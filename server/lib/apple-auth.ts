// Sign in with Apple için ortak server helper'ları (apple-auth-token ve
// delete-account endpoint'leri kullanır). Apple secret'ları SADECE Vercel
// env'den okunur: APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (.p8),
// APPLE_CLIENT_ID. Private key, client secret JWT, authorization code ve
// refresh token HİÇBİR ZAMAN loglanmaz.

import { sign as cryptoSign, verify as cryptoVerify, createPrivateKey, createPublicKey } from 'node:crypto';
import { request } from 'node:https';

const APPLE_AUDIENCE = 'https://appleid.apple.com';
const APPLE_TOKEN_URL = 'https://appleid.apple.com/auth/token';
const APPLE_REVOKE_URL = 'https://appleid.apple.com/auth/revoke';

// Apple client secret en fazla 6 ay geçerli olabilir; her istekte üretip
// birkaç dakika geçerli tutuyoruz.
const CLIENT_SECRET_TTL_SECONDS = 300;

export class AppleConfigError extends Error {}

export class AppleRequestError extends Error {
  // Apple'ın döndüğü güvenli hata kodu (örn. invalid_grant); token içermez.
  readonly appleError?: string;
  readonly status: number;

  constructor(message: string, status: number, appleError?: string) {
    super(message);
    this.status = status;
    this.appleError = appleError;
  }
}

function base64Url(input: Buffer | string): string {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

// Env'de key hem gerçek newline'lı hem de "\n" (iki karakter) kaçışlı
// gelebilir; ayrıca baş/son tırnak veya CRLF olabilir.
export function normalizePrivateKey(raw: string): string {
  let key = raw.trim();

  if (
    (key.startsWith('"') && key.endsWith('"')) ||
    (key.startsWith("'") && key.endsWith("'"))
  ) {
    key = key.slice(1, -1);
  }

  key = key.replace(/\\r\\n/g, '\n').replace(/\\n/g, '\n').replace(/\r\n/g, '\n');

  // Satır sonları boşluğa dönüşmüş (tek satırlık) PEM'leri de onar:
  // gövdeyi alıp boşlukları atar, 64 karakterlik satırlara böler;
  // BEGIN/END satırları korunur.
  const pem = key.match(/-----BEGIN PRIVATE KEY-----([\s\S]*?)-----END PRIVATE KEY-----/);

  if (pem) {
    const body = pem[1].replace(/\s+/g, '');
    const lines = body.match(/.{1,64}/g) ?? [];

    return ['-----BEGIN PRIVATE KEY-----', ...lines, '-----END PRIVATE KEY-----'].join('\n');
  }

  return key.trim();
}

// Vercel env değerlerinde sık görülen sorun: değerin sonunda/başında
// görünmez boşluk, "\n" veya sarmalayan tırnak. Team ID / Key ID / Client ID
// bu yüzden JWT'de bir karakter farklı olur ve Apple "invalid_client" döner.
function cleanEnvValue(raw: string | undefined): string | undefined {
  if (raw === undefined) return undefined;

  let value = raw.trim();

  if (
    value.length >= 2 &&
    ((value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'")))
  ) {
    value = value.slice(1, -1).trim();
  }

  return value;
}

function requireAppleEnv(): {
  teamId: string;
  keyId: string;
  privateKey: string;
  clientId: string;
} {
  const teamId = cleanEnvValue(process.env.APPLE_TEAM_ID);
  const keyId = cleanEnvValue(process.env.APPLE_KEY_ID);
  const rawKey = process.env.APPLE_PRIVATE_KEY;
  const clientId = cleanEnvValue(process.env.APPLE_CLIENT_ID);

  const missing = [
    ['APPLE_TEAM_ID', teamId],
    ['APPLE_KEY_ID', keyId],
    ['APPLE_PRIVATE_KEY', rawKey],
    ['APPLE_CLIENT_ID', clientId],
  ]
    .filter(([, value]) => !value)
    .map(([name]) => name);

  if (missing.length > 0) {
    throw new AppleConfigError(`Eksik Apple env değişkenleri: ${missing.join(', ')}.`);
  }

  return {
    teamId: teamId as string,
    keyId: keyId as string,
    privateKey: normalizePrivateKey(rawKey as string),
    clientId: clientId as string,
  };
}

// Apple Team ID ve Key ID: tam 10 karakter, büyük harf/rakam.
const APPLE_ID_PATTERN = /^[A-Z0-9]{10}$/;

// Hata ayıklama için GÜVENLİ özet: env değerlerini (clientId hariç),
// private key'i, JWT'yi veya imzayı İÇERMEZ — yalnızca var/yok, uzunluk,
// format ve key tipi bilgisi.
export function describeAppleCredentials(): Record<string, unknown> {
  const rawTeamId = process.env.APPLE_TEAM_ID;
  const rawKeyId = process.env.APPLE_KEY_ID;
  const rawClientId = process.env.APPLE_CLIENT_ID;
  const rawKey = process.env.APPLE_PRIVATE_KEY;

  const teamId = cleanEnvValue(rawTeamId);
  const keyId = cleanEnvValue(rawKeyId);
  const clientId = cleanEnvValue(rawClientId);

  const diagnostics: Record<string, unknown> = {
    hasTeamId: !!teamId,
    hasKeyId: !!keyId,
    hasPrivateKey: !!rawKey,
    clientId,
    clientIdIsExpectedBundleId: clientId === 'com.kaan.lifeadmin',
    teamIdLooksValid: teamId ? APPLE_ID_PATTERN.test(teamId) : false,
    keyIdLooksValid: keyId ? APPLE_ID_PATTERN.test(keyId) : false,
    teamIdHadSurroundingWhitespace: rawTeamId !== undefined && rawTeamId !== rawTeamId.trim(),
    keyIdHadSurroundingWhitespace: rawKeyId !== undefined && rawKeyId !== rawKeyId.trim(),
    clientIdHadSurroundingWhitespace:
      rawClientId !== undefined && rawClientId !== rawClientId.trim(),
    jwtHeaderClaims: ['alg', 'kid', 'typ'],
    jwtPayloadClaims: ['iss', 'iat', 'exp', 'aud', 'sub'],
    jwtAudience: APPLE_AUDIENCE,
    jwtTtlSeconds: CLIENT_SECRET_TTL_SECONDS,
    serverUnixTime: Math.floor(Date.now() / 1000),
  };

  if (rawKey) {
    const normalized = normalizePrivateKey(rawKey);

    diagnostics.privateKeyHasBeginMarker = normalized.includes('-----BEGIN PRIVATE KEY-----');
    diagnostics.privateKeyHasEndMarker = normalized.includes('-----END PRIVATE KEY-----');
    diagnostics.privateKeyLineCount = normalized.split('\n').length;

    try {
      const keyObject = createPrivateKey(normalized);
      const details = keyObject.asymmetricKeyDetails as { namedCurve?: string } | undefined;

      diagnostics.privateKeyParses = true;
      diagnostics.privateKeyType = keyObject.asymmetricKeyType;
      diagnostics.privateKeyCurve = details?.namedCurve;

      // İmza formatı kendi kendine doğrulanıyor: ürettiğimiz 64-byte R||S
      // imzası, aynı key'in public kısmıyla geçerli mi?
      const probe = Buffer.from('apple-auth-self-check');
      const signature = cryptoSign('sha256', probe, {
        key: keyObject,
        dsaEncoding: 'ieee-p1363',
      });

      diagnostics.signatureLengthBytes = signature.length;
      diagnostics.signatureSelfVerifies = cryptoVerify(
        'sha256',
        probe,
        { key: createPublicKey(keyObject), dsaEncoding: 'ieee-p1363' },
        signature,
      );
    } catch (_error) {
      diagnostics.privateKeyParses = false;
    }
  }

  return diagnostics;
}

function logAppleFailureDiagnostics(operation: string, status: number, appleError?: string) {
  console.error(
    JSON.stringify({
      event: 'apple-credentials-diagnostics',
      operation,
      appleStatus: status,
      appleError,
      ...describeAppleCredentials(),
      at: new Date().toISOString(),
    }),
  );
}

export function getAppleClientId(): string {
  return requireAppleEnv().clientId;
}

// ES256 client secret JWT'si (Apple'ın "client_secret" formatı).
export function createAppleClientSecret(): string {
  const { teamId, keyId, privateKey, clientId } = requireAppleEnv();

  const now = Math.floor(Date.now() / 1000);

  const header = { alg: 'ES256', kid: keyId, typ: 'JWT' };
  const payload = {
    iss: teamId,
    iat: now,
    exp: now + CLIENT_SECRET_TTL_SECONDS,
    aud: APPLE_AUDIENCE,
    sub: clientId,
  };

  const signingInput = `${base64Url(JSON.stringify(header))}.${base64Url(
    JSON.stringify(payload),
  )}`;

  let signature: Buffer;

  try {
    // JWS ES256, DER değil ham (r||s, IEEE P1363) imza ister.
    signature = cryptoSign('sha256', Buffer.from(signingInput), {
      key: createPrivateKey(privateKey),
      dsaEncoding: 'ieee-p1363',
    });
  } catch (_error) {
    throw new AppleConfigError('APPLE_PRIVATE_KEY okunamadı veya geçersiz.');
  }

  return `${signingInput}.${base64Url(signature)}`;
}

interface HttpResult {
  status: number;
  body: string;
}

function postForm(url: string, form: Record<string, string>): Promise<HttpResult> {
  const payload = new URLSearchParams(form).toString();
  const target = new URL(url);

  return new Promise((resolve, reject) => {
    const req = request(
      {
        method: 'POST',
        hostname: target.hostname,
        path: target.pathname,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(payload),
        },
        timeout: 10000,
      },
      (res) => {
        const chunks: Buffer[] = [];
        res.on('data', (chunk: Buffer) => chunks.push(chunk));
        res.on('end', () =>
          resolve({
            status: res.statusCode ?? 0,
            body: Buffer.concat(chunks).toString('utf8'),
          }),
        );
      },
    );

    req.on('timeout', () => req.destroy(new Error('Apple isteği zaman aşımına uğradı.')));
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

function safeAppleError(body: string): string | undefined {
  try {
    const parsed = JSON.parse(body) as { error?: unknown };
    return typeof parsed.error === 'string' ? parsed.error : undefined;
  } catch (_error) {
    return undefined;
  }
}

// authorizationCode -> Apple refresh_token
export async function exchangeAuthorizationCode(authorizationCode: string): Promise<string> {
  const clientId = getAppleClientId();
  const clientSecret = createAppleClientSecret();

  const result = await postForm(APPLE_TOKEN_URL, {
    client_id: clientId,
    client_secret: clientSecret,
    code: authorizationCode,
    grant_type: 'authorization_code',
  });

  if (result.status !== 200) {
    const appleError = safeAppleError(result.body);
    logAppleFailureDiagnostics('token-exchange', result.status, appleError);

    throw new AppleRequestError('Apple token değişimi başarısız.', result.status, appleError);
  }

  let refreshToken: unknown;

  try {
    refreshToken = (JSON.parse(result.body) as { refresh_token?: unknown }).refresh_token;
  } catch (_error) {
    refreshToken = undefined;
  }

  if (typeof refreshToken !== 'string' || refreshToken.length === 0) {
    throw new AppleRequestError('Apple yanıtında refresh_token yok.', result.status);
  }

  return refreshToken;
}

export async function revokeRefreshToken(refreshToken: string): Promise<void> {
  const clientId = getAppleClientId();
  const clientSecret = createAppleClientSecret();

  const result = await postForm(APPLE_REVOKE_URL, {
    client_id: clientId,
    client_secret: clientSecret,
    token: refreshToken,
    token_type_hint: 'refresh_token',
  });

  if (result.status !== 200) {
    const appleError = safeAppleError(result.body);
    logAppleFailureDiagnostics('token-revoke', result.status, appleError);

    throw new AppleRequestError('Apple token revoke başarısız.', result.status, appleError);
  }
}

interface UserWithIdentities {
  identities?: Array<{ provider?: string }> | null;
}

export function hasAppleIdentity(user: UserWithIdentities | null | undefined): boolean {
  return (user?.identities ?? []).some((identity) => identity.provider === 'apple');
}
