// verify-purchase (Vercel Node serverless function)
//
// Flutter (PurchaseService._verifyAndComplete) -> bu endpoint -> Apple'ın
// StoreKit 2 "signed transaction" (JWS) doğrulaması -> (ve SADECE
// geçerliyse) Supabase "profiles" tablosunu SERVICE ROLE ile günceller.
// Flutter tarafı hiçbir zaman "profiles.plan = premium" yazmıyor —
// sistemdeki TEK yetkili, güvenli yer burasıdır.
//
// NEDEN BURADA (Supabase Edge Function'dan taşındı): @apple/app-store-
// server-library Node.js runtime hedefliyor. Supabase Edge Functions
// Deno üzerinde çalışıyor ve kütüphanenin sertifika/imza doğrulama
// adımlarında Deno'ya özgü bir uyumsuzluktan kaynaklanan "BER error"
// (enableOnlineChecks kapalıyken bile devam eden) ile karşılaşıldı. Aynı
// doğrulama mantığı, kütüphanenin hedeflediği gerçek Node.js runtime'ında
// (Vercel Node Serverless Function) çalıştırılıyor.
//
// Korunan güvenlik kontrolleri (hiçbiri kaldırılmadı/bypass edilmedi):
// - Apple'ın 3 kök sertifikasına karşı zincir doğrulaması
// - JWS kriptografik imza doğrulaması
// - bundleId === com.kaan.lifeadmin
// - productId allowlist (sadece lifeadmin_premium_monthly/yearly)
// - Sandbox/Production environment ayrımı (Production önce denenir,
//   olmazsa Sandbox'a düşer)
// - revocationDate (iade/iptal) kontrolü
// - expiresDate (aktif abonelik) kontrolü
// - Production'da appAppleId zorunluluğu (config eksikse Apple'a hiç
//   istek atılmadan net bir hata ile durur)
//
// Deploy (bu klasörden):
//   cd server
//   vercel link        (ilk seferde — Vercel hesabına/projene bağlar)
//   vercel deploy --prod
//
// Gerekli Vercel env secret'ları (Vercel Dashboard > Project > Settings >
// Environment Variables, ya da `vercel env add <AD>`):
//   SUPABASE_URL                 (main.dart'taki Supabase URL'in aynısı)
//   SUPABASE_ANON_KEY             (main.dart'taki publishableKey'in aynısı)
//   SUPABASE_SERVICE_ROLE_KEY     (Supabase Dashboard > Project Settings >
//                                  API > service_role — GİZLİ, SADECE buraya)
//   APPLE_APP_APPLE_ID             (opsiyonel — Sandbox testinde gerekmez;
//                                  Production doğrulaması için zorunlu)
//
// Service role key bu dosyada/koda hiçbir zaman YAZILMIYOR — sadece
// process.env üzerinden okunuyor ve Flutter'a asla gönderilmiyor.

import type { VercelRequest, VercelResponse } from '@vercel/node';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { SignedDataVerifier, Environment } from '@apple/app-store-server-library';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  isClaimReference,
  isUuid,
  normalizeEnvironment,
  ownershipConflictBody,
  tokenMatchesUser,
  type LoginProvider,
} from '../lib/ownership';

const BUNDLE_ID = 'com.kaan.lifeadmin';
const MONTHLY_PRODUCT_ID = 'lifeadmin_premium_monthly';
const YEARLY_PRODUCT_ID = 'lifeadmin_premium_yearly';

// Node.js (gerçek runtime, Deno uyumluluk sorunu yok) üzerinde online
// OCSP kontrollerini açmak mümkün, ama kapsamı Deno'daki davranışla
// birebir aynı tutmak için KAPALI bırakıldı. Offline kriptografik
// kontrollerin (yukarıdaki liste) hiçbirini etkilemiyor.
const ENABLE_ONLINE_CHECKS = false;

const REQUIRED_ROOT_CERT_FILES = [
  'AppleIncRoot.cer',
  'AppleRootCA-G2.cer',
  'AppleRootCA-G3.cer',
];

function parseAppAppleId(): number | null {
  const raw = process.env.APPLE_APP_APPLE_ID;
  if (!raw) return null;

  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0) return null;

  return parsed;
}

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
    throw new Error(`Apple kök sertifikaları eksik: ${missing.join(', ')}.`);
  }

  cachedRootCertificates = certs;
  return certs;
}

interface VerifiedPayload {
  bundleId: string;
  productId: string;
  transactionId: string;
  originalTransactionId?: string;
  appAccountToken?: string;
  expiresDate?: number;
  revocationDate?: number;
  environment: string;
}

interface AttemptOutcome {
  ok: boolean;
  decoded?: Record<string, unknown>;
  error?: string;
  isConfigError?: boolean;
}

async function attemptVerification(
  roots: Buffer[],
  environment: Environment,
  signedTransaction: string,
): Promise<AttemptOutcome> {
  let appAppleId: number | undefined;

  if (environment === Environment.PRODUCTION) {
    const parsed = parseAppAppleId();

    if (parsed === null) {
      return {
        ok: false,
        isConfigError: true,
        error:
          'APPLE_APP_APPLE_ID env değişkeni ayarlanmamış veya geçerli bir ' +
          'pozitif tam sayı değil — Production doğrulaması bu olmadan ' +
          'başlatılamaz.',
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
      appAppleId, // Sandbox'ta undefined kalır
    );

    const decoded = await verifier.verifyAndDecodeTransaction(signedTransaction);
    return { ok: true, decoded: decoded as Record<string, unknown> };
  } catch (error) {
    const err = error as {
      constructor?: { name?: string };
      status?: number;
      cause?: { message?: string; name?: string };
    };

    console.error(
      JSON.stringify({
        event: 'apple-verification-attempt-error',
        environment: environment === Environment.PRODUCTION ? 'production' : 'sandbox',
        onlineChecks: ENABLE_ONLINE_CHECKS,
        errorConstructorName: err?.constructor?.name,
        errorMessage: error instanceof Error ? error.message : String(error),
        status: err?.status,
        causeName: err?.cause?.name,
        causeMessage: err?.cause?.message,
        at: new Date().toISOString(),
      }),
    );

    return {
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

async function verifyTransaction(signedTransaction: string): Promise<{
  valid: boolean;
  payload?: VerifiedPayload;
  reason?: string;
}> {
  const roots = loadAppleRootCertificates();

  const attempts: Array<{ label: string; environment: Environment }> = [
    { label: 'production', environment: Environment.PRODUCTION },
    { label: 'sandbox', environment: Environment.SANDBOX },
  ];

  let lastLabel = '';

  for (const attempt of attempts) {
    lastLabel = attempt.label;

    const outcome = await attemptVerification(roots, attempt.environment, signedTransaction);

    if (outcome.ok && outcome.decoded) {
      const decoded = outcome.decoded;

      return {
        valid: true,
        payload: {
          bundleId: decoded.bundleId as string,
          productId: decoded.productId as string,
          transactionId: decoded.transactionId as string,
          originalTransactionId: decoded.originalTransactionId as string | undefined,
          appAccountToken: decoded.appAccountToken as string | undefined,
          expiresDate: decoded.expiresDate as number | undefined,
          revocationDate: decoded.revocationDate as number | undefined,
          environment: String(decoded.environment ?? attempt.label),
        },
      };
    }
  }

  return {
    valid: false,
    reason: `Apple imza doğrulaması başarısız (${lastLabel}).`,
  };
}

async function ownerProvider(
  adminClient: SupabaseClient,
  ownerId: string,
): Promise<LoginProvider | null> {
  try {
    const { data } = await adminClient.auth.admin.getUserById(ownerId);
    const provider = data?.user?.app_metadata?.provider;
    return provider === 'apple' || provider === 'google' || provider === 'email'
      ? provider
      : null;
  } catch (_error) {
    return null;
  }
}

function setCors(res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  setCors(res);

  if (req.method === 'OPTIONS') {
    res.status(200).end();
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ success: false, reason: 'Method not allowed.' });
    return;
  }

  try {
    const authHeader = req.headers.authorization;

    if (!authHeader) {
      res.status(401).json({ success: false, reason: 'Yetkilendirme eksik.' });
      return;
    }

    const supabaseUrl = process.env.SUPABASE_URL;
    const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;
    const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
      console.error('verify-purchase config error: missing Supabase env vars');
      res.status(500).json({ success: false, reason: 'Sunucu yapılandırması eksik.' });
      return;
    }

    // Çağıranın kimliğini KENDİ erişim token'ından doğruluyoruz — client'ın
    // gönderdiği herhangi bir user id alanına ASLA güvenmiyoruz.
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userError } = await userClient.auth.getUser();

    if (userError || !userData?.user) {
      res.status(401).json({ success: false, reason: 'Kullanıcı doğrulanamadı.' });
      return;
    }

    const userId = userData.user.id;
    const body = (req.body ?? {}) as Record<string, unknown>;
    const productId = body.productId as string | undefined;
    // `receiptData` alan adı Flutter tarafındaki (purchase_service.dart)
    // mevcut isimle AYNI tutuldu — içeriği bir StoreKit 2 JWS transaction
    // string'i.
    const signedTransaction = body.receiptData as string | undefined;

    if (!productId || !signedTransaction) {
      res.status(400).json({ success: false, reason: 'Eksik satın alma verisi.' });
      return;
    }

    if (productId !== MONTHLY_PRODUCT_ID && productId !== YEARLY_PRODUCT_ID) {
      res.status(400).json({ success: false, reason: 'Bilinmeyen ürün.' });
      return;
    }

    const verification = await verifyTransaction(signedTransaction);

    if (!verification.valid || !verification.payload) {
      res.status(200).json({ success: false, reason: verification.reason });
      return;
    }

    const payload = verification.payload;

    // Bütünlük kontrolleri — imza geçerli olsa bile içerik beklediğimiz
    // uygulama/ürüne ait değilse ASLA premium açmıyoruz.
    if (payload.bundleId !== BUNDLE_ID) {
      res.status(200).json({ success: false, reason: 'Bundle ID uyuşmuyor.' });
      return;
    }

    if (payload.productId !== MONTHLY_PRODUCT_ID && payload.productId !== YEARLY_PRODUCT_ID) {
      res.status(200).json({ success: false, reason: 'Ürün ID uyuşmuyor.' });
      return;
    }

    const isRevoked = payload.revocationDate != null;
    const expiresAt = payload.expiresDate ? new Date(payload.expiresDate) : null;
    const isActive = !isRevoked && expiresAt !== null && expiresAt.getTime() > Date.now();

    // Service role — SADECE burada, sunucu tarafında (Vercel env secret).
    // Flutter'a hiçbir zaman gönderilmez.
    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);

    const plan = isActive ? 'premium' : 'free';
    const status = isRevoked ? 'revoked' : isActive ? 'active' : 'expired';

    if (!payload.originalTransactionId) {
      // Abonelik kimliği olmadan hangi hesaba ait olduğuna karar verilemez:
      // hak AÇILMAZ (eskiden profil yine de güncelleniyordu).
      console.warn(
        JSON.stringify({
          event: 'verify-purchase-missing-original-transaction-id',
          productId: payload.productId,
          environment: payload.environment,
          at: new Date().toISOString(),
        }),
      );
      res.status(200).json({ success: false, reason: 'Satın alma kaydı eksik.' });
      return;
    }

    // Abonelik en fazla BİR Life Admin hesabına bağlanır; karar tek bir kilitli
    // SQL işleminde verilir (migrations/20261031100300_subscription_ownership.sql).
    // "Geri Yükle" aboneliği başka hesaba TAŞIMAZ. Yalnızca satın alma Apple
    // imzalı appAccountToken ile BU hesapta başlatıldıysa ve
    // SUBSCRIPTION_TOKEN_TRANSFER=on ise taşınır (kullanıcı onayı bekleyen karar).
    const { data: claim, error: claimError } = await adminClient
      .rpc('claim_subscription', {
        p_user_id: userId,
        p_original_transaction_id: payload.originalTransactionId,
        p_app_account_token: isUuid(payload.appAccountToken) ? payload.appAccountToken : null,
        p_allow_token_transfer: process.env.SUBSCRIPTION_TOKEN_TRANSFER === 'on',
        p_product_id: payload.productId,
        p_expires_at: expiresAt?.toISOString() ?? null,
        p_status: status,
        p_plan: plan,
      })
      .single<{ result: string; previous_owner: string | null }>();

    if (claimError || !claim) {
      console.error(
        JSON.stringify({
          event: 'verify-purchase-claim-error',
          code: claimError?.code,
          at: new Date().toISOString(),
        }),
      );
      res.status(500).json({ success: false, reason: 'Profil güncellenemedi.' });
      return;
    }

    if (claim.result === 'owned_by_other') {
      // Kurtarma ipucu: yalnızca bağlı hesabın GİRİŞ TÜRÜ söylenir (e-posta
      // veya kimlik paylaşılmaz). Abonelik ASLA otomatik taşınmaz.
      const provider = claim.previous_owner
        ? await ownerProvider(adminClient, claim.previous_owner)
        : null;

      // Satın alma Apple imzalı appAccountToken ile BU hesapta başlatıldıysa
      // kullanıcı gerçekten bu hesapta ödeme yaptı: destek kaydı açılır ve
      // referans verilir. Kayıt açılamazsa yine de "bağlı başka hesap" yanıtı
      // döner (kesin sonuç; uygulama tekrar denemez).
      let reference: string | null = null;
      // İade edilmiş (revoked) işlem için kayıt AÇILMAZ.
      if (
        !isRevoked &&
        tokenMatchesUser(payload.appAccountToken, userId) &&
        payload.transactionId
      ) {
        const { data: claimRef, error: recordError } = await adminClient.rpc(
          'record_subscription_claim',
          {
            p_user_id: userId,
            p_original_transaction_id: payload.originalTransactionId,
            p_transaction_id: payload.transactionId,
            p_product_id: payload.productId,
            p_environment: normalizeEnvironment(payload.environment),
            p_expires_at: expiresAt?.toISOString() ?? null,
            p_token_matches: true,
          },
        );
        if (recordError || !isClaimReference(claimRef)) {
          console.error(
            JSON.stringify({
              event: 'verify-purchase-claim-record-error',
              code: recordError?.code,
              at: new Date().toISOString(),
            }),
          );
        } else {
          reference = claimRef;
          console.warn(
            JSON.stringify({
              event: 'verify-purchase-claim-recorded',
              reference,
              environment: normalizeEnvironment(payload.environment),
              at: new Date().toISOString(),
            }),
          );
        }
      }

      res.status(200).json(ownershipConflictBody(provider, reference));
      return;
    }

    res.status(200).json({
      success: true,
      plan,
      expiresAt: expiresAt?.toISOString() ?? null,
    });
  } catch (error) {
    console.error('verify-purchase error', error);
    res.status(500).json({ success: false, reason: 'Beklenmeyen bir hata oluştu.' });
  }
}
