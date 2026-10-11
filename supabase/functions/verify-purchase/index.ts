// verify-purchase
//
// Flutter (PurchaseService._verifyAndComplete) -> bu fonksiyon -> Apple'ın
// StoreKit 2 "signed transaction" (JWS) doğrulaması -> (ve SADECE
// geçerliyse) profiles tablosunu SERVICE ROLE ile günceller. Flutter
// tarafı hiçbir zaman "profiles.plan = premium" yazmıyor — sistemdeki TEK
// yetkili, güvenli yer burasıdır.
//
// KÖK NEDEN (önceki implementasyonun kırık olmasının sebebi):
// `in_app_purchase` paketi iOS'ta artık StoreKit 2 kullanıyor.
// `purchase.verificationData.serverVerificationData` bu durumda eski
// base64 App Store "receipt" DEĞİL, Apple tarafından imzalanmış bir JWS
// (JSON Web Signature) transaction string'i. Eski implementasyon bunu
// `https://[sandbox.]itunes.apple.com/verifyReceipt`'e (klasik receipt
// doğrulama) gönderiyordu — Apple bunu geçersiz/parse edilemez bir receipt
// olarak reddediyor, fonksiyon `success:false` dönüyor, Flutter da
// "Satın alma sunucuda doğrulanamadı" gösteriyordu. Apple onay sesinin
// gelmesi StoreKit'in kendi satın alma akışının (client-side) başarılı
// olduğunu gösteriyor — sorun hep bizim server-side doğrulamamızdaydı.
//
// ÇÖZÜM: Apple'ın resmi "App Store Server Library"sini (@apple/app-store-
// server-library) kullanarak JWS transaction'ı KRİPTOGRAFİK olarak
// doğruluyoruz (imza zinciri Apple'ın kök sertifikasına kadar kontrol
// edilir) ve imza geçerliyse decode edilmiş, GÜVENİLİR transaction
// verisini (bundleId, productId, expiresDate, environment, revocationDate
// vb.) kullanıyoruz.
//
// === DEPLOY ETMEDEN ÖNCE YAPMAN GEREKEN EK ADIMLAR ===
// 1) Apple PKI'daki ÜÇ kök sertifikayı indirip bu fonksiyonun yanına koy
//    (bunlar PUBLIC sertifikalardır, secret DEĞİL — repoya commit edilebilir).
//    Detay ve indirme linkleri: certs/README.md
// 2) Production'da doğrulama yapılacaksa APPLE_APP_APPLE_ID secret'ını set et
//    (Sandbox bu olmadan da çalışır — aşağıya bak).
// Sertifikalardan biri eksikse veya Production denenirken APPLE_APP_APPLE_ID
// geçersizse fonksiyon, satın almayı yanlış yorumlamak yerine net bir hata
// ile durur.
//
// Deploy:
//   supabase functions deploy verify-purchase
//   supabase secrets set APPLE_APP_APPLE_ID=123456789
//
// App Store Server API KULLANILMIYOR — Issuer ID/Key ID/.p8 GEREKMİYOR; JWS
// doğrudan Apple'ın public kök sertifikalarına karşı doğrulanıyor.
// SUPABASE_URL/SUPABASE_ANON_KEY/SUPABASE_SERVICE_ROLE_KEY runtime'a
// otomatik enjekte edilir; service role Flutter'a hiçbir zaman gönderilmez.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  SignedDataVerifier,
  Environment,
} from 'npm:@apple/app-store-server-library@^1';

const BUNDLE_ID = 'com.kaan.lifeadmin';
const MONTHLY_PRODUCT_ID = 'lifeadmin_premium_monthly';
const YEARLY_PRODUCT_ID = 'lifeadmin_premium_yearly';

// KAPALI tutuluyor (Production VE Sandbox'ta) — Supabase Edge Runtime'da
// bu kütüphanenin enableOnlineChecks=true iken yaptığı OCSP response
// parsing adımı "BER error" ile patlıyor. Kapatmak, aşağıdaki OFFLINE
// kriptografik kontrollerden HİÇBİRİNİ devre dışı bırakmaz — sadece
// Apple'a ek bir online revocation sorgusu ATILMAZ: 3 Apple root
// sertifikasına karşı zincir doğrulaması, sertifika OID kontrolleri, JWS
// imza doğrulaması, bundleId/environment/productId/revocationDate/
// expiresDate kontrolleri hepsi aynen çalışmaya devam ediyor.
const ENABLE_ONLINE_CHECKS = false;

// Production ortamında SignedDataVerifier, transaction'ın gerçekten BU
// uygulamaya ait olduğunu doğrulamak için appAppleId'ye İHTİYAÇ DUYAR —
// bu yüzden Production denemesi başlamadan önce (Apple'a hiç istek
// atmadan) geçerli bir sayıya parse edilip edilemediğini kontrol ediyoruz.
// Geçersizse/eksikse Production denemesi "config error" olarak atlanır;
// Sandbox denemesi buna ihtiyaç duymadığı için etkilenmez.
function parseAppAppleId(): number | null {
  const raw = Deno.env.get('APPLE_APP_APPLE_ID');
  if (!raw) return null;

  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0) return null;

  return parsed;
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');

    if (!authHeader) {
      return jsonResponse({ success: false, reason: 'Yetkilendirme eksik.' }, 401);
    }

    // Çağıranın kimliğini KENDİ JWT'sinden doğruluyoruz — client'ın
    // gönderdiği herhangi bir user id alanına ASLA güvenmiyoruz. Flutter
    // tarafı ayrıca bir "userId" alanı da göndermiyor; kimlik SADECE bu
    // Authorization header'ından (functions.invoke'un otomatik eklediği
    // oturum JWT'si) türetiliyor.
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: userData, error: userError } = await userClient.auth.getUser();

    if (userError || !userData?.user) {
      return jsonResponse({ success: false, reason: 'Kullanıcı doğrulanamadı.' }, 401);
    }

    const userId = userData.user.id;
    const body = await req.json();
    const productId = body?.productId as string | undefined;
    // `receiptData` alan adı tarihsel — Flutter tarafı (purchase_service.dart)
    // buraya artık bir StoreKit 2 JWS transaction string'i koyuyor, eski bir
    // base64 receipt değil. Satın alma akışına dokunmamak için alan adını
    // DEĞİŞTİRMEDİM, sadece içeriğini doğru yorumluyorum.
    const signedTransaction = body?.receiptData as string | undefined;

    if (!productId || !signedTransaction) {
      return jsonResponse({ success: false, reason: 'Eksik satın alma verisi.' }, 400);
    }

    if (productId !== MONTHLY_PRODUCT_ID && productId !== YEARLY_PRODUCT_ID) {
      logSafe('unknown-product', { productId });
      return jsonResponse({ success: false, reason: 'Bilinmeyen ürün.' }, 400);
    }

    const verification = await verifyTransaction(signedTransaction);

    if (!verification.valid) {
      logSafe('verification-failed', {
        productId,
        reason: verification.reason,
        environmentTried: verification.environmentTried,
        maskedTransactionId: verification.maskedTransactionId,
      });
      return jsonResponse({ success: false, reason: verification.reason }, 200);
    }

    const payload = verification.payload!;

    // Bütünlük kontrolleri — imza geçerli olsa bile içerik beklediğimiz
    // uygulama/ürüne ait değilse ASLA premium açmıyoruz.
    if (payload.bundleId !== BUNDLE_ID) {
      logSafe('bundle-id-mismatch', { got: payload.bundleId });
      return jsonResponse({ success: false, reason: 'Bundle ID uyuşmuyor.' }, 200);
    }

    if (payload.productId !== MONTHLY_PRODUCT_ID && payload.productId !== YEARLY_PRODUCT_ID) {
      logSafe('product-id-mismatch', { got: payload.productId });
      return jsonResponse({ success: false, reason: 'Ürün ID uyuşmuyor.' }, 200);
    }

    const isRevoked = payload.revocationDate != null;
    const expiresAt = payload.expiresDate ? new Date(payload.expiresDate) : null;
    const isActive = !isRevoked && expiresAt !== null && expiresAt.getTime() > Date.now();

    logSafe('verified', {
      productId: payload.productId,
      environment: payload.environment,
      maskedTransactionId: maskId(payload.transactionId),
      isActive,
      isRevoked,
    });

    // Service role — SADECE burada, sunucu tarafında. Flutter'a hiçbir
    // zaman gönderilmez.
    const adminClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { error: updateError } = await adminClient
      .from('profiles')
      .update({
        plan: isActive ? 'premium' : 'free',
        subscription_product_id: payload.productId,
        subscription_expires_at: expiresAt?.toISOString() ?? null,
        subscription_platform: 'ios',
        subscription_status: isRevoked ? 'revoked' : isActive ? 'active' : 'expired',
      })
      .eq('id', userId);

    if (updateError) {
      console.error('profiles update error', updateError);
      return jsonResponse({ success: false, reason: 'Profil güncellenemedi.' }, 500);
    }

    return jsonResponse({
      success: true,
      plan: isActive ? 'premium' : 'free',
      expiresAt: expiresAt?.toISOString() ?? null,
    });
  } catch (error) {
    console.error('verify-purchase error', error);
    return jsonResponse({ success: false, reason: 'Beklenmeyen bir hata oluştu.' }, 500);
  }
});

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// Güvenli, maskelenmiş log — ASLA ham JWS/token/secret yazmıyor.
function logSafe(event: string, details: Record<string, unknown>) {
  console.log(JSON.stringify({ event, ...details, at: new Date().toISOString() }));
}

function maskId(id: string | undefined): string | undefined {
  if (!id || id.length <= 8) return id ? '***' : undefined;
  return `${id.slice(0, 4)}***${id.slice(-4)}`;
}

// App Store Server Library'nin VerificationStatus sayısal kodları — Apple
// kütüphanesi hatayı status numarası olarak veriyor, isme çevirmiyor.
const VERIFICATION_STATUS_NAMES: Record<number, string> = {
  0: 'OK',
  1: 'VERIFICATION_FAILURE',
  2: 'RETRYABLE_VERIFICATION_FAILURE',
  3: 'INVALID_APP_IDENTIFIER',
  4: 'INVALID_ENVIRONMENT',
  5: 'INVALID_CHAIN_LENGTH',
  6: 'INVALID_CERTIFICATE',
  7: 'FAILURE',
};

interface VerifiedPayload {
  bundleId: string;
  productId: string;
  transactionId: string;
  expiresDate?: number;
  revocationDate?: number;
  environment: string;
}

interface TransactionVerification {
  valid: boolean;
  payload?: VerifiedPayload;
  reason?: string;
  environmentTried?: string;
  maskedTransactionId?: string;
}

// Apple PKI'daki resmi kök sertifika zinciri — App Store Server Library
// örneklerinde dokümante edildiği gibi ÜÇÜ de array olarak veriliyor
// (hangi transaction'ın hangi köke zincirlendiği imzaya göre değişebilir).
// Biri bile eksikse fail-fast: receipt'i yanlış/eksik doğrulamak yerine
// fonksiyon hiç başlamıyor.
const REQUIRED_ROOT_CERT_FILES = [
  'AppleIncRoot.cer',
  'AppleRootCA-G2.cer',
  'AppleRootCA-G3.cer',
];

let cachedRootCertificates: Uint8Array[] | null = null;

async function loadAppleRootCertificates(): Promise<Uint8Array[]> {
  if (cachedRootCertificates) return cachedRootCertificates;

  const certs: Uint8Array[] = [];
  const missing: string[] = [];

  for (const fileName of REQUIRED_ROOT_CERT_FILES) {
    try {
      const certUrl = new URL(`./certs/${fileName}`, import.meta.url);
      certs.push(await Deno.readFile(certUrl));
    } catch (_error) {
      missing.push(fileName);
    }
  }

  if (missing.length > 0) {
    throw new Error(
      `Apple kök sertifikaları eksik: ${missing.join(', ')}. ` +
        'certs/README.md dosyasındaki linklerden indirip ' +
        'supabase/functions/verify-purchase/certs/ içine ekleyip tekrar deploy et.',
    );
  }

  cachedRootCertificates = certs;
  return certs;
}

interface VerificationAttemptOutcome {
  ok: boolean;
  decoded?: Record<string, unknown>;
  error?: string;
  isConfigError?: boolean;
}

async function attemptVerification(
  roots: Uint8Array[],
  environment: Environment,
  signedTransaction: string,
): Promise<VerificationAttemptOutcome> {
  let appAppleId: number | undefined;

  if (environment === Environment.PRODUCTION) {
    const parsed = parseAppAppleId();

    if (parsed === null) {
      // Apple'a hiç istek atılmadı — bu bilinçli bir config hatası, bir
      // doğrulama BAŞARISIZLIĞI değil.
      return {
        ok: false,
        isConfigError: true,
        error:
          'APPLE_APP_APPLE_ID secret\'ı ayarlanmamış veya geçerli bir pozitif ' +
          'tam sayı değil — Production doğrulaması bu olmadan başlatılamaz.',
      };
    }

    appAppleId = parsed;
  }

  try {
    const verifier = new SignedDataVerifier(
      roots,
      ENABLE_ONLINE_CHECKS,
      environment,
      BUNDLE_ID,
      appAppleId, // Sandbox'ta undefined kalır — SignedDataVerifier bunu kabul eder
    );

    const decoded = await verifier.verifyAndDecodeTransaction(signedTransaction);
    return { ok: true, decoded: decoded as Record<string, unknown> };
  } catch (error) {
    // Apple'ın VerificationException'ı genelde boş/jenerik bir `message`
    // taşır — gerçek bilgi `status` (VerificationStatus kodu) ve
    // `cause` (altta yatan kriptografik/parse hatası) alanlarındadır.
    // Burada SADECE güvenli, yapılandırılmış metadata logluyoruz —
    // ham JWS/imza/secret ASLA loglanmıyor.
    const err = error as {
      constructor?: { name?: string };
      status?: number;
      cause?: { message?: string; name?: string };
      message?: string;
    };

    const jwsInfo = decodeJwsUnsafe(signedTransaction);
    const statusName =
      typeof err?.status === 'number'
        ? (VERIFICATION_STATUS_NAMES[err.status] ?? `UNKNOWN(${err.status})`)
        : undefined;

    console.error(
      JSON.stringify({
        event: 'apple-verification-attempt-error',
        environment: environment === Environment.PRODUCTION ? 'production' : 'sandbox',
        onlineChecks: ENABLE_ONLINE_CHECKS,
        errorConstructorName: err?.constructor?.name,
        errorMessage: error instanceof Error ? error.message : String(error),
        status: err?.status,
        statusName,
        causeName: err?.cause?.name,
        causeMessage: err?.cause?.message,
        jwsPartsCount: jwsInfo.partsCount,
        jwsAlg: jwsInfo.alg,
        jwsX5cLength: jwsInfo.x5cLength,
        // Doğrulanmamış (imza kontrolünden GEÇMEMİŞ) değerler — sadece
        // "gönderilen veri bizim beklediğimize benziyor mu?" teşhisi için.
        unverifiedBundleId: jwsInfo.bundleId,
        unverifiedProductId: jwsInfo.productId,
        maskedTransactionId: jwsInfo.maskedTransactionId,
        at: new Date().toISOString(),
      }),
    );

    return {
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

// Client'tan gelen signed transaction'ı önce PRODUCTION ortamına karşı
// doğrulamayı dener (APPLE_APP_APPLE_ID set ve geçerliyse); başarısız
// olursa veya config eksikse (tıpkı eski verifyReceipt'in 21007 durumunda
// sandbox'a düşmesi gibi) SANDBOX ortamına karşı tekrar dener — Sandbox,
// appAppleId olmadan da çalışır. Hangi ortamın doğruladığı, decode edilen
// payload'ın kendi `environment` alanından da teyit edilir.
async function verifyTransaction(
  signedTransaction: string,
): Promise<TransactionVerification> {
  const roots = await loadAppleRootCertificates();

  const attempts: Array<{ label: string; environment: Environment }> = [
    { label: 'production', environment: Environment.PRODUCTION },
    { label: 'sandbox', environment: Environment.SANDBOX },
  ];

  let lastLabel = '';
  let lastErrorMessage = '';

  for (const attempt of attempts) {
    lastLabel = attempt.label;

    const outcome = await attemptVerification(
      roots,
      attempt.environment,
      signedTransaction,
    );

    if (outcome.ok && outcome.decoded) {
      const decoded = outcome.decoded;

      return {
        valid: true,
        payload: {
          bundleId: decoded.bundleId as string,
          productId: decoded.productId as string,
          transactionId: decoded.transactionId as string,
          expiresDate: decoded.expiresDate as number | undefined,
          revocationDate: decoded.revocationDate as number | undefined,
          environment: String(decoded.environment ?? attempt.label),
        },
        environmentTried: attempt.label,
      };
    }

    lastErrorMessage = outcome.error ?? 'bilinmeyen hata';

    // Gerçek kütüphane/config hatasını logluyoruz (ör. "certificate chain
    // invalid", "APPLE_APP_APPLE_ID ayarlanmamış") — bu mesajlar HAM
    // JWS/imza/secret İÇERMEZ, sadece açıklayıcı metindir.
    console.error(
      JSON.stringify({
        event: outcome.isConfigError
          ? 'apple-verification-config-error'
          : 'apple-verification-error',
        environmentTried: attempt.label,
        error: lastErrorMessage,
        maskedTransactionId: decodeJwsUnsafe(signedTransaction).maskedTransactionId,
        at: new Date().toISOString(),
      }),
    );
  }

  return {
    valid: false,
    reason: `Apple imza doğrulaması başarısız (${lastLabel}).`,
    environmentTried: lastLabel,
    maskedTransactionId: decodeJwsUnsafe(signedTransaction).maskedTransactionId,
  };
}

function base64UrlDecode(segment: string): string {
  const normalized = segment.replaceAll('-', '+').replaceAll('_', '/');
  const padded = normalized.padEnd(
    normalized.length + ((4 - (normalized.length % 4)) % 4),
    '=',
  );
  return atob(padded);
}

interface UnsafeJwsInfo {
  partsCount: number;
  alg?: string;
  x5cLength?: number;
  bundleId?: string;
  productId?: string;
  maskedTransactionId?: string;
}

// SADECE teşhis/log amaçlı — İMZASI HENÜZ DOĞRULANMAMIŞ JWS'nin header ve
// payload segmentlerini okur (header/payload base64url ile kodlanmış ama
// şifreli DEĞİL, bu yüzden teşhis için okumak güvenlidir — imza/secret
// açığa çıkmaz). Buradan dönen hiçbir değer ASLA bir güven/yetkilendirme
// kararında kullanılmaz; sadece "neden doğrulanamadı?" sorusuna log'da
// cevap vermek için var. Signature segmentine (3. parça) hiç dokunulmuyor.
function decodeJwsUnsafe(signedTransaction: string): UnsafeJwsInfo {
  const parts = signedTransaction.split('.');
  const info: UnsafeJwsInfo = { partsCount: parts.length };

  try {
    if (parts[0]) {
      const header = JSON.parse(base64UrlDecode(parts[0])) as Record<string, unknown>;
      info.alg = header.alg as string | undefined;
      const x5c = header.x5c as unknown[] | undefined;
      info.x5cLength = Array.isArray(x5c) ? x5c.length : undefined;
    }
  } catch (_error) {
    // Header okunamadı — sadece teşhis bilgisi eksik kalır, fonksiyon durmaz.
  }

  try {
    if (parts[1]) {
      const payload = JSON.parse(base64UrlDecode(parts[1])) as Record<string, unknown>;
      info.bundleId = payload.bundleId as string | undefined;
      info.productId = payload.productId as string | undefined;
      info.maskedTransactionId = maskId(payload.transactionId as string | undefined);
    }
  } catch (_error) {
    // Payload okunamadı — sadece teşhis bilgisi eksik kalır, fonksiyon durmaz.
  }

  return info;
}
