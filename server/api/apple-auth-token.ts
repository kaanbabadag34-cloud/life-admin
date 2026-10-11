// apple-auth-token (Vercel Node serverless function)
//
// POST /api/apple-auth-token
// Header: Authorization: Bearer <Supabase access token>
// Body:   { "authorizationCode": "<Sign in with Apple authorization code>" }
//
// Native Sign in with Apple girişinden sonra Flutter, Apple'ın verdiği tek
// kullanımlık authorization code'u buraya gönderir. Burada Apple'a
// (appleid.apple.com/auth/token) refresh token'a çevrilir ve
// `apple_auth_tokens` tablosuna (SADECE service role erişebilir) UPSERT
// edilir. Hesap silerken bu refresh token ile Apple authorization revoke
// edilir (bkz. delete-account.ts). userId body'den ALINMAZ; doğrulanmış
// Supabase access token'dan çıkarılır.
//
// Authorization code, refresh token, client secret JWT ve private key
// HİÇBİR ZAMAN loglanmaz.

import type { VercelRequest, VercelResponse } from '@vercel/node';
import { createClient } from '@supabase/supabase-js';
import {
  AppleConfigError,
  AppleRequestError,
  exchangeAuthorizationCode,
  hasAppleIdentity,
} from '../lib/apple-auth';

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
      console.error('apple-auth-token config error: missing Supabase env vars');
      res.status(500).json({ success: false, reason: 'Sunucu yapılandırması eksik.' });
      return;
    }

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userError } = await userClient.auth.getUser();

    if (userError || !userData?.user) {
      res.status(401).json({ success: false, reason: 'Kullanıcı doğrulanamadı.' });
      return;
    }

    const user = userData.user;

    // Apple ile giriş yapmamış (Google/e-posta) bir kullanıcı için Apple
    // refresh token saklamıyoruz.
    if (!hasAppleIdentity(user)) {
      res.status(400).json({ success: false, reason: 'Apple kimliği bulunamadı.' });
      return;
    }

    const body = (req.body ?? {}) as Record<string, unknown>;
    const authorizationCode = body.authorizationCode;

    if (
      typeof authorizationCode !== 'string' ||
      authorizationCode.length === 0 ||
      authorizationCode.length > 2048
    ) {
      res.status(400).json({ success: false, reason: 'authorizationCode eksik.' });
      return;
    }

    const refreshToken = await exchangeAuthorizationCode(authorizationCode);

    const admin = createClient(supabaseUrl, supabaseServiceRoleKey);

    const { error: upsertError } = await admin.from('apple_auth_tokens').upsert(
      {
        user_id: user.id,
        refresh_token: refreshToken,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'user_id' },
    );

    if (upsertError) {
      console.error(
        JSON.stringify({
          event: 'apple-auth-token-store-error',
          code: upsertError.code,
          at: new Date().toISOString(),
        }),
      );
      res.status(500).json({ success: false, reason: 'Token kaydedilemedi.' });
      return;
    }

    res.status(200).json({ success: true });
  } catch (error) {
    if (error instanceof AppleConfigError) {
      console.error(
        JSON.stringify({
          event: 'apple-auth-token-config-error',
          message: error.message,
          at: new Date().toISOString(),
        }),
      );
      res.status(500).json({ success: false, reason: 'Sunucu yapılandırması eksik.' });
      return;
    }

    if (error instanceof AppleRequestError) {
      console.error(
        JSON.stringify({
          event: 'apple-auth-token-exchange-error',
          appleStatus: error.status,
          appleError: error.appleError,
          at: new Date().toISOString(),
        }),
      );
      res.status(502).json({ success: false, reason: 'Apple doğrulaması başarısız.' });
      return;
    }

    console.error(
      'apple-auth-token error',
      error instanceof Error ? error.message : 'unknown',
    );
    res.status(500).json({ success: false, reason: 'Beklenmeyen bir hata oluştu.' });
  }
}
