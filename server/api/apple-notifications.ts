// apple-notifications (Vercel Node serverless function)
//
// App Store Server Notifications V2 webhook'u. Apple -> bu endpoint ->
// signedPayload (JWS) kriptografik olarak doğrulanır -> (ve SADECE
// geçerliyse) ilgili kullanıcının "profiles" satırı SERVICE ROLE ile
// güncellenir. Kullanıcı, verify-purchase'ın yazdığı
// subscription_original_transaction_id ile eşleştirilir.
//
// Idempotency: profil durumu bildirimin sayaç/sırasından değil, Apple'ın
// imzalı transaction'ındaki (expiresDate / revocationDate) değerlerden
// DETERMİNİSTİK olarak türetilir. Aynı bildirim iki kez gelirse aynı satıra
// aynı değerler yazılır. Gecikmiş/sırasız gelen eski bir yenileme
// bildirimi, DB'deki daha ileri bir expires_at'i geri almaz.
//
// Gerekli env (verify-purchase ile AYNI, yeni env yok):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, APPLE_APP_APPLE_ID (Production için)

import type { VercelRequest, VercelResponse } from '@vercel/node';
import { createClient } from '@supabase/supabase-js';
import { SignedDataVerifier, Environment } from '@apple/app-store-server-library';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const BUNDLE_ID = 'com.kaan.lifeadmin';
const MONTHLY_PRODUCT_ID = 'lifeadmin_premium_monthly';
const YEARLY_PRODUCT_ID = 'lifeadmin_premium_yearly';

const ENABLE_ONLINE_CHECKS = false;

const REQUIRED_ROOT_CERT_FILES = [
  'AppleIncRoot.cer',
  'AppleRootCA-G2.cer',
  'AppleRootCA-G3.cer',
];

// Desteklenen notificationType'lar.
//  - ENTITLEMENT: transaction'dan durum türetilir (aktif/süresi dolmuş).
//  - TERMINATE: premium hemen kapatılır.
//  - LOG_ONLY: DB'ye dokunulmaz.
const ENTITLEMENT_TYPES = new Set([
  'SUBSCRIBED',
  'DID_RENEW',
  'DID_CHANGE_RENEWAL_STATUS',
  'OFFER_REDEEMED',
  'DID_FAIL_TO_RENEW',
  'EXPIRED',
  'GRACE_PERIOD_EXPIRED',
]);
const TERMINATE_TYPES = new Set(['REVOKE', 'REFUND']);
const LOG_ONLY_TYPES = new Set(['REFUND_DECLINED']);

// Süresi geçmiş olması beklenen tipler — "stale" koruması bunlara uygulanmaz
// (EXPIRED zaten expiresDate geçmişte olduğu için free'ye döner).
const STALE_GUARD_EXEMPT = new Set(['EXPIRED', 'GRACE_PERIOD_EXPIRED']);

class ConfigError extends Error {}

let cachedRootCertificates: Buffer[] | null = null;

function loadAppleRootCertificates(): Buffer[] {
  if (cachedRootCertificates) return cachedRootCertificates;

  const certs: Buffer[] = [];
  const missing: string[] = [];

  for (const fileName of REQUIRED_ROOT_CERT_FILES) {
    try {
      certs.push(readFileSync(join(__dirname, '..', 'certs', fileName)));
    } catch (_error) {
      missing.push(fileName);
    }
  }

  if (missing.length > 0) {
    throw new ConfigError(`Apple kök sertifikaları eksik: ${missing.join(', ')}.`);
  }

  cachedRootCertificates = certs;
  return certs;
}

function parseAppAppleId(): number | null {
  const raw = process.env.APPLE_APP_APPLE_ID;
  if (!raw) return null;

  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0) return null;

  return parsed;
}

interface DecodedNotification {
  notificationType: string;
  subtype?: string;
  notificationUUID?: string;
  data?: {
    environment?: string;
    bundleId?: string;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
}

interface DecodedTransaction {
  bundleId?: string;
  productId?: string;
  originalTransactionId?: string;
  expiresDate?: number;
  revocationDate?: number;
}

interface DecodedRenewal {
  autoRenewStatus?: number;
}

interface VerifiedNotification {
  verifier: SignedDataVerifier;
  environmentLabel: 'production' | 'sandbox';
  notification: DecodedNotification;
}

// Production önce, olmazsa Sandbox. Kütüphane, bildirimin kendi
// environment'ını verifier'ın environment'ı ile karşılaştırır (ve Production
// için bundleId + appAppleId'yi de zorlar) — yanlış environment reddedilir.
async function verifyNotification(
  signedPayload: string,
): Promise<VerifiedNotification | null> {
  const roots = loadAppleRootCertificates();

  const attempts: Array<{ label: 'production' | 'sandbox'; environment: Environment }> = [
    { label: 'production', environment: Environment.PRODUCTION },
    { label: 'sandbox', environment: Environment.SANDBOX },
  ];

  let productionConfigMissing = false;

  for (const attempt of attempts) {
    let appAppleId: number | undefined;

    if (attempt.environment === Environment.PRODUCTION) {
      const parsed = parseAppAppleId();

      if (parsed === null) {
        productionConfigMissing = true;
        continue;
      }

      appAppleId = parsed;
    }

    try {
      const verifier = new SignedDataVerifier(
        roots,
        ENABLE_ONLINE_CHECKS,
        attempt.environment,
        BUNDLE_ID,
        appAppleId,
      );

      const notification = (await verifier.verifyAndDecodeNotification(
        signedPayload,
      )) as unknown as DecodedNotification;

      return { verifier, environmentLabel: attempt.label, notification };
    } catch (error) {
      const err = error as {
        constructor?: { name?: string };
        status?: number;
        cause?: { message?: string; name?: string };
      };

      console.error(
        JSON.stringify({
          event: 'apple-notification-verification-attempt-error',
          environment: attempt.label,
          errorConstructorName: err?.constructor?.name,
          errorMessage: error instanceof Error ? error.message : String(error),
          status: err?.status,
          causeName: err?.cause?.name,
          at: new Date().toISOString(),
        }),
      );
    }
  }

  if (productionConfigMissing) {
    throw new ConfigError(
      'APPLE_APP_APPLE_ID env değişkeni ayarlanmamış veya geçersiz — ' +
        'Production bildirimleri doğrulanamıyor.',
    );
  }

  return null;
}

function maskId(value: string | undefined): string | undefined {
  if (!value) return undefined;
  return value.length <= 4 ? '****' : `***${value.slice(-4)}`;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') {
    res.status(405).json({ success: false, reason: 'Method not allowed.' });
    return;
  }

  try {
    const supabaseUrl = process.env.SUPABASE_URL;
    const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseUrl || !supabaseServiceRoleKey) {
      console.error('apple-notifications config error: missing Supabase env vars');
      res.status(500).json({ success: false, reason: 'Sunucu yapılandırması eksik.' });
      return;
    }

    const body = (req.body ?? {}) as Record<string, unknown>;
    const signedPayload = body.signedPayload;

    if (typeof signedPayload !== 'string' || signedPayload.length === 0) {
      res.status(400).json({ success: false, reason: 'signedPayload eksik.' });
      return;
    }

    // JWS doğrulanmadan hiçbir DB işlemi yapılmaz.
    const verified = await verifyNotification(signedPayload);

    if (!verified) {
      res.status(401).json({ success: false, reason: 'Bildirim doğrulanamadı.' });
      return;
    }

    const { verifier, environmentLabel, notification } = verified;
    const notificationType = notification.notificationType;
    const subtype = notification.subtype;
    const logBase = {
      notificationType,
      subtype,
      notificationUUID: notification.notificationUUID,
      environment: environmentLabel,
    };

    if (LOG_ONLY_TYPES.has(notificationType)) {
      console.log(JSON.stringify({ event: 'apple-notification-log-only', ...logBase }));
      res.status(200).json({ success: true, handled: false });
      return;
    }

    const isTerminate = TERMINATE_TYPES.has(notificationType);

    if (!isTerminate && !ENTITLEMENT_TYPES.has(notificationType)) {
      console.log(JSON.stringify({ event: 'apple-notification-ignored', ...logBase }));
      res.status(200).json({ success: true, handled: false });
      return;
    }

    const signedTransactionInfo = notification.data?.signedTransactionInfo;

    if (!signedTransactionInfo) {
      console.warn(JSON.stringify({ event: 'apple-notification-no-transaction', ...logBase }));
      res.status(200).json({ success: true, handled: false });
      return;
    }

    const transaction = (await verifier.verifyAndDecodeTransaction(
      signedTransactionInfo,
    )) as unknown as DecodedTransaction;

    let autoRenewStatus: number | undefined;
    const signedRenewalInfo = notification.data?.signedRenewalInfo;

    if (signedRenewalInfo) {
      const renewal = (await verifier.verifyAndDecodeRenewalInfo(
        signedRenewalInfo,
      )) as unknown as DecodedRenewal;
      autoRenewStatus = renewal.autoRenewStatus;
    }

    const originalTransactionId = transaction.originalTransactionId;

    if (!originalTransactionId) {
      console.warn(
        JSON.stringify({ event: 'apple-notification-missing-original-transaction-id', ...logBase }),
      );
      res.status(200).json({ success: true, handled: false });
      return;
    }

    if (transaction.bundleId !== BUNDLE_ID) {
      console.error(JSON.stringify({ event: 'apple-notification-bundle-mismatch', ...logBase }));
      res.status(400).json({ success: false, reason: 'Bundle ID uyuşmuyor.' });
      return;
    }

    if (
      transaction.productId !== MONTHLY_PRODUCT_ID &&
      transaction.productId !== YEARLY_PRODUCT_ID
    ) {
      console.error(JSON.stringify({ event: 'apple-notification-unknown-product', ...logBase }));
      res.status(400).json({ success: false, reason: 'Ürün ID uyuşmuyor.' });
      return;
    }

    const expiresAt = transaction.expiresDate ? new Date(transaction.expiresDate) : null;
    const isRevoked = isTerminate || transaction.revocationDate != null;
    const isActive = !isRevoked && expiresAt !== null && expiresAt.getTime() > Date.now();

    let subscriptionStatus: string;
    if (notificationType === 'REFUND') {
      subscriptionStatus = 'refunded';
    } else if (isRevoked) {
      subscriptionStatus = 'revoked';
    } else {
      subscriptionStatus = isActive ? 'active' : 'expired';
    }

    const admin = createClient(supabaseUrl, supabaseServiceRoleKey);

    const { data: profiles, error: findError } = await admin
      .from('profiles')
      .select('id, subscription_expires_at, subscription_status')
      .eq('subscription_original_transaction_id', originalTransactionId);

    if (findError) {
      console.error(
        JSON.stringify({ event: 'apple-notification-profile-lookup-error', ...logBase }),
        findError,
      );
      res.status(500).json({ success: false, reason: 'Profil sorgulanamadı.' });
      return;
    }

    if (!profiles || profiles.length === 0) {
      // verify-purchase henüz çalışmamış olabilir; o akış aynı durumu
      // kendisi yazacağı için Apple'ı tekrar denemeye zorlamıyoruz.
      console.warn(
        JSON.stringify({
          event: 'apple-notification-no-matching-profile',
          originalTransactionId: maskId(originalTransactionId),
          ...logBase,
        }),
      );
      res.status(200).json({ success: true, handled: false });
      return;
    }

    const newExpiresMs = expiresAt?.getTime() ?? 0;
    const applyTo: string[] = [];

    for (const profile of profiles as Array<{
      id: string;
      subscription_expires_at: string | null;
      subscription_status: string | null;
    }>) {
      if (!isTerminate && !STALE_GUARD_EXEMPT.has(notificationType)) {
        const existingMs = profile.subscription_expires_at
          ? new Date(profile.subscription_expires_at).getTime()
          : 0;
        const wasRevoked =
          profile.subscription_status === 'revoked' ||
          profile.subscription_status === 'refunded';

        // Eski/sırasız gelmiş bildirim, daha yeni bir durumu geri almasın.
        if (newExpiresMs < existingMs || (wasRevoked && newExpiresMs <= existingMs)) {
          console.log(
            JSON.stringify({
              event: 'apple-notification-stale-skipped',
              profileId: profile.id,
              ...logBase,
            }),
          );
          continue;
        }
      }

      applyTo.push(profile.id);
    }

    if (applyTo.length > 0) {
      // subscription_original_transaction_id bilerek DEĞİŞTİRİLMİYOR.
      const { error: updateError } = await admin
        .from('profiles')
        .update({
          plan: isActive ? 'premium' : 'free',
          subscription_status: subscriptionStatus,
          subscription_product_id: transaction.productId,
          subscription_expires_at: expiresAt?.toISOString() ?? null,
          subscription_platform: 'ios',
        })
        .in('id', applyTo);

      if (updateError) {
        console.error(
          JSON.stringify({ event: 'apple-notification-profile-update-error', ...logBase }),
          updateError,
        );
        res.status(500).json({ success: false, reason: 'Profil güncellenemedi.' });
        return;
      }
    }

    console.log(
      JSON.stringify({
        event: 'apple-notification-processed',
        originalTransactionId: maskId(originalTransactionId),
        plan: isActive ? 'premium' : 'free',
        subscriptionStatus,
        autoRenewStatus,
        profilesMatched: profiles.length,
        profilesUpdated: applyTo.length,
        ...logBase,
      }),
    );

    res.status(200).json({ success: true, handled: true });
  } catch (error) {
    if (error instanceof ConfigError) {
      console.error('apple-notifications config error:', error.message);
      res.status(500).json({ success: false, reason: 'Sunucu yapılandırması eksik.' });
      return;
    }

    console.error('apple-notifications error', error);
    res.status(500).json({ success: false, reason: 'Beklenmeyen bir hata oluştu.' });
  }
}
