// delete-account (Vercel Node serverless function)
//
// POST /api/delete-account
// Header: Authorization: Bearer <Supabase access token>
//
// Kullanıcı kimliği SADECE doğrulanmış access token'dan çıkarılır; body'deki
// hiçbir alana güvenilmez. Silme sırası (repodaki gerçek şemaya göre):
//   0. (SADECE Apple ile giriş yapmış kullanıcılar) Apple token revoke:
//        apple_auth_tokens.refresh_token -> appleid.apple.com/auth/revoke.
//        Revoke başarılı OLMADAN hiçbir şey silinmez. Refresh token kaydı
//        yoksa 409 + code "APPLE_REAUTH_REQUIRED" döner (Flutter kullanıcıyı
//        Apple ile yeniden doğrulatıp /api/apple-auth-token ile token'ı
//        yakalar, sonra silmeyi tekrar dener). Revoke sonrası
//        apple_auth_tokens satırı silinir. Google/e-posta kullanıcılarında
//        Apple'a hiç istek atılmaz.
//   1. journal_entries   (user_id)  -- auth.users'a ON DELETE CASCADE
//   2. countdowns        (user_id)  -- auth.users'a ON DELETE CASCADE
//   3. events            (user_id)  -- dashboard'da oluşturulmuş; FK/cascade
//                                      repoda yok, bu yüzden AÇIKÇA siliniyor
//   4. profiles          (id)       -- dashboard'da oluşturulmuş; açıkça siliniyor
//   5. auth.users        (admin API) -- EN SON
// Herhangi bir adım başarısız olursa işlem orada durur ve auth kullanıcısı
// SİLİNMEZ (kullanıcı tekrar deneyebilir; adımlar idempotent).
//
// Apple aboneliği iptal edilmeye ÇALIŞILMAZ — kullanıcı aboneliği App Store
// ayarlarından kendisi yönetir. Storage: uygulama hiçbir bucket kullanmıyor
// (lib/ altında storage çağrısı yok), bu yüzden dosya silme adımı yok.
//
// Gerekli env: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY ve
// (Apple kullanıcıları için) APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY,
// APPLE_CLIENT_ID. Service role key SADECE burada.
// Token, kullanıcı id'si veya kişisel veri LOGLANMAZ.

import type { VercelRequest, VercelResponse } from '@vercel/node';
import { createClient } from '@supabase/supabase-js';
import {
  AppleConfigError,
  hasAppleIdentity,
  revokeRefreshToken,
} from '../lib/apple-auth';

// [tablo, kullanıcıyı gösteren kolon] — sıra önemli.
const USER_TABLES: Array<[string, string]> = [
  ['journal_entries', 'user_id'],
  ['countdowns', 'user_id'],
  ['events', 'user_id'],
  ['profiles', 'id'],
];

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
      console.error('delete-account config error: missing Supabase env vars');
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

    const userId = userData.user.id;
    const admin = createClient(supabaseUrl, supabaseServiceRoleKey);
    const deletedCounts: Record<string, number | null> = {};

    // Apple kimliği, istemciye değil gerçek Supabase auth kullanıcısına
    // bakılarak belirlenir.
    const { data: adminUserData, error: adminUserError } =
      await admin.auth.admin.getUserById(userId);

    if (adminUserError || !adminUserData?.user) {
      console.error(
        JSON.stringify({
          event: 'delete-account-user-lookup-error',
          status: adminUserError?.status,
          at: new Date().toISOString(),
        }),
      );
      res.status(500).json({ success: false, reason: 'Kullanıcı bilgisi alınamadı.' });
      return;
    }

    if (hasAppleIdentity(adminUserData.user)) {
      const { data: tokenRow, error: tokenError } = await admin
        .from('apple_auth_tokens')
        .select('refresh_token')
        .eq('user_id', userId)
        .maybeSingle();

      if (tokenError) {
        console.error(
          JSON.stringify({
            event: 'delete-account-apple-token-lookup-error',
            code: tokenError.code,
            at: new Date().toISOString(),
          }),
        );
        res.status(500).json({ success: false, reason: 'Apple bilgisi okunamadı.' });
        return;
      }

      if (!tokenRow?.refresh_token) {
        console.warn(
          JSON.stringify({
            event: 'delete-account-apple-reauth-required',
            at: new Date().toISOString(),
          }),
        );
        res.status(409).json({
          success: false,
          code: 'APPLE_REAUTH_REQUIRED',
          reason: 'Apple ile yeniden doğrulama gerekiyor.',
        });
        return;
      }

      try {
        await revokeRefreshToken(tokenRow.refresh_token as string);
      } catch (error) {
        if (error instanceof AppleConfigError) throw error;

        const appleError = error as { status?: number; appleError?: string };
        console.error(
          JSON.stringify({
            event: 'delete-account-apple-revoke-error',
            appleStatus: appleError.status,
            appleError: appleError.appleError,
            at: new Date().toISOString(),
          }),
        );
        res.status(502).json({
          success: false,
          code: 'APPLE_REVOKE_FAILED',
          reason: 'Apple yetkilendirmesi kaldırılamadı.',
        });
        return;
      }

      const { error: tokenDeleteError } = await admin
        .from('apple_auth_tokens')
        .delete()
        .eq('user_id', userId);

      if (tokenDeleteError) {
        console.error(
          JSON.stringify({
            event: 'delete-account-apple-token-delete-error',
            code: tokenDeleteError.code,
            at: new Date().toISOString(),
          }),
        );
        res.status(500).json({ success: false, reason: 'Hesap verileri silinemedi.' });
        return;
      }
    }

    for (const [table, column] of USER_TABLES) {
      const { error, count } = await admin
        .from(table)
        .delete({ count: 'exact' })
        .eq(column, userId);

      if (error) {
        console.error(
          JSON.stringify({
            event: 'delete-account-table-error',
            table,
            code: error.code,
            message: error.message,
            at: new Date().toISOString(),
          }),
        );
        res.status(500).json({ success: false, reason: 'Hesap verileri silinemedi.' });
        return;
      }

      deletedCounts[table] = count;
    }

    const { error: authDeleteError } = await admin.auth.admin.deleteUser(userId);

    if (authDeleteError) {
      console.error(
        JSON.stringify({
          event: 'delete-account-auth-error',
          status: authDeleteError.status,
          message: authDeleteError.message,
          at: new Date().toISOString(),
        }),
      );
      res.status(500).json({ success: false, reason: 'Kullanıcı hesabı silinemedi.' });
      return;
    }

    console.log(
      JSON.stringify({
        event: 'delete-account-success',
        deletedCounts,
        at: new Date().toISOString(),
      }),
    );

    res.status(200).json({ success: true });
  } catch (error) {
    if (error instanceof AppleConfigError) {
      console.error(
        JSON.stringify({
          event: 'delete-account-apple-config-error',
          message: error.message,
          at: new Date().toISOString(),
        }),
      );
      res.status(500).json({ success: false, reason: 'Sunucu yapılandırması eksik.' });
      return;
    }

    console.error(
      'delete-account error',
      error instanceof Error ? error.message : 'unknown',
    );
    res.status(500).json({ success: false, reason: 'Beklenmeyen bir hata oluştu.' });
  }
}
