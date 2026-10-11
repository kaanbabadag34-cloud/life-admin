// delete-account (Vercel Node serverless function)
//
// POST /api/delete-account
// Header: Authorization: Bearer <Supabase access token>
//
// Kullanıcı kimliği SADECE doğrulanmış access token'dan çıkarılır; body'deki
// hiçbir alana güvenilmez. Silme sırası (repodaki gerçek şemaya göre):
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
// Gerekli env: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
// (verify-purchase ile aynı; yeni env yok). Service role key SADECE burada.
// Token, kullanıcı id'si veya kişisel veri LOGLANMAZ.

import type { VercelRequest, VercelResponse } from '@vercel/node';
import { createClient } from '@supabase/supabase-js';

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
    console.error(
      'delete-account error',
      error instanceof Error ? error.message : 'unknown',
    );
    res.status(500).json({ success: false, reason: 'Beklenmeyen bir hata oluştu.' });
  }
}
