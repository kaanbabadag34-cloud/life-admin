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
import { createClient } from '@supabase/supabase-js';
import { SignedDataVerifier, Environment } from '@apple/app-store-server-library';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

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

    const profileUpdate: Record<string, unknown> = {
      plan: isActive ? 'premium' : 'free',
      subscription_product_id: payload.productId,
      subscription_expires_at: expiresAt?.toISOString() ?? null,
      subscription_platform: 'ios',
      subscription_status: isRevoked ? 'revoked' : isActive ? 'active' : 'expired',
    };

    // originalTransactionId, yalnızca Apple doğrulaması başarılı olduktan
    // sonra, doğrulanmış payload'dan gelir. Yoksa mevcut alan EZİLMEZ
    // (alan update'e hiç eklenmez) ve premium akışı bozulmaz.
    if (payload.originalTransactionId) {
      profileUpdate.subscription_original_transaction_id = payload.originalTransactionId;
    } else {
      console.warn(
        JSON.stringify({
          event: 'verify-purchase-missing-original-transaction-id',
          userId,
          productId: payload.productId,
          environment: payload.environment,
          at: new Date().toISOString(),
        }),
      );
    }

    const { error: updateError } = await adminClient
      .from('profiles')
      .update(profileUpdate)
      .eq('id', userId);

    if (updateError) {
      console.error('profiles update error', updateError);
      res.status(500).json({ success: false, reason: 'Profil güncellenemedi.' });
      return;
    }

    res.status(200).json({
      success: true,
      plan: isActive ? 'premium' : 'free',
      expiresAt: expiresAt?.toISOString() ?? null,
    });
  } catch (error) {
    console.error('verify-purchase error', error);
    res.status(500).json({ success: false, reason: 'Beklenmeyen bir hata oluştu.' });
  }
}
