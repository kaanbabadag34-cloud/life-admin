-- Sign in with Apple refresh token'ları (hesap silerken Apple revoke için).
-- Bu tabloya SADECE service-role backend (Vercel /api/apple-auth-token ve
-- /api/delete-account) erişir. RLS açık ve BİLEREK hiçbir policy yok:
-- anon/authenticated roller bu tabloyu hiçbir şekilde okuyamaz/yazamaz.
-- Bu migration'ı Supabase SQL Editor'de çalıştır.

CREATE TABLE IF NOT EXISTS public.apple_auth_tokens (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  refresh_token text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.apple_auth_tokens ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.apple_auth_tokens FROM anon, authenticated;
