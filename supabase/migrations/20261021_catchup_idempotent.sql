-- Life Admin — TOPLU, TEKRAR ÇALIŞTIRILABİLİR (idempotent) migration.
--
-- Amaç: Bugüne kadarki tüm şema gereksinimlerini tek dosyada, güvenle
-- tamamlamak. Her adım "yoksa ekle" mantığındadır: zaten uygulanmış
-- migration'ların üzerine tekrar çalıştırmak HATA VERMEZ ve hiçbir kullanıcı
-- verisini silmez/değiştirmez. Supabase SQL Editor'de çalıştır.
--
-- NOT: Bu dosya, önceki migration'ların (20260916, 20260921, 20260924,
-- 20261012, 20261020) yerine geçmez; hiçbirini çalıştırmadıysan bu tek dosya
-- hepsini kapsar. profiles / events TABLOLARININ kendisi bu repoda hiç
-- tanımlanmadı (dashboard'da oluşturulmuş); bu dosya onları OLUŞTURMAZ, yalnızca
-- kodun beklediği kolonları ekler.
--
-- NOT: profiles tablosunun istemci yazmalarına kapatılması bu dosyanın
-- kapsamında DEĞİLDİR; bunun için ayrıca
-- 20261023_lock_profiles_client_writes.sql çalıştırılmalıdır.

-- ---------------------------------------------------------------------------
-- 1) events: kodun kullandığı kolonlar
-- ---------------------------------------------------------------------------
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS note text,
  ADD COLUMN IF NOT EXISTS duration_minutes integer,
  ADD COLUMN IF NOT EXISTS reminder_enabled boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS reminder_minutes_before integer,
  ADD COLUMN IF NOT EXISTS source text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- Kısıt ADA göre değil tanımına göre aranır: duration_minutes için bir CHECK
-- zaten varsa (başka adla bile) ikincisi eklenmez.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.events'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%duration_minutes%'
  ) THEN
    ALTER TABLE public.events
      ADD CONSTRAINT events_duration_minutes_check
      CHECK (duration_minutes IS NULL OR duration_minutes BETWEEN 1 AND 1440);
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2) profiles: abonelik / Premium kolonları
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS subscription_product_id text,
  ADD COLUMN IF NOT EXISTS subscription_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS subscription_platform text,
  ADD COLUMN IF NOT EXISTS subscription_status text,
  ADD COLUMN IF NOT EXISTS subscription_original_transaction_id text;

-- App Store Server Notifications webhook'u kullanıcıyı bu kolonla bulur.
CREATE INDEX IF NOT EXISTS profiles_subscription_original_transaction_id_idx
  ON public.profiles (subscription_original_transaction_id)
  WHERE subscription_original_transaction_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 3) apple_auth_tokens: Apple token revoke (yalnızca service-role erişir)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.apple_auth_tokens (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  refresh_token text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.apple_auth_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.apple_auth_tokens FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) countdowns ve journal_entries (+ RLS politikaları, yalnızca eksikse)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.countdowns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  title text NOT NULL,
  target_date date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.journal_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  entry_date date NOT NULL,
  content text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, entry_date)
);

ALTER TABLE public.countdowns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;

-- Politikalar AD'a göre değil (tablo + komut) bazında kontrol edilir: canlı
-- veritabanında aynı işi yapan politikalar farklı adlarla ("Users can create
-- own countdowns" gibi) zaten olabilir; o durumda ÇOĞALTILMAZ. Mevcut hiçbir
-- politika silinmez veya değiştirilmez.
DO $$
DECLARE
  spec record;
BEGIN
  FOR spec IN
    SELECT * FROM (VALUES
      ('countdowns',      'Users can view their own countdowns',        'SELECT', 'auth.uid() = user_id', NULL),
      ('countdowns',      'Users can insert their own countdowns',      'INSERT', NULL, 'auth.uid() = user_id'),
      ('countdowns',      'Users can update their own countdowns',      'UPDATE', 'auth.uid() = user_id', NULL),
      ('countdowns',      'Users can delete their own countdowns',      'DELETE', 'auth.uid() = user_id', NULL),
      ('journal_entries', 'Users can view their own journal entries',   'SELECT', 'auth.uid() = user_id', NULL),
      ('journal_entries', 'Users can insert their own journal entries', 'INSERT', NULL, 'auth.uid() = user_id'),
      ('journal_entries', 'Users can update their own journal entries', 'UPDATE', 'auth.uid() = user_id', NULL),
      ('journal_entries', 'Users can delete their own journal entries', 'DELETE', 'auth.uid() = user_id', NULL)
    ) AS t(tbl, pol, cmd, using_expr, check_expr)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = spec.tbl
        AND cmd = spec.cmd
    ) THEN
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR %s%s%s',
        spec.pol,
        spec.tbl,
        spec.cmd,
        CASE WHEN spec.using_expr IS NOT NULL THEN ' USING (' || spec.using_expr || ')' ELSE '' END,
        CASE WHEN spec.check_expr IS NOT NULL THEN ' WITH CHECK (' || spec.check_expr || ')' ELSE '' END
      );
    END IF;
  END LOOP;
END $$;
