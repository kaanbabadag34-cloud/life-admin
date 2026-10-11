-- Flutter tarafındaki CountdownPage (Sayaç) ve JournalPage (Günlük)
-- `countdowns` ve `journal_entries` tablolarını bekliyor ama Supabase
-- şemasında bu tablolar henüz yok — bu yüzden her istek başarısız oluyor
-- ve ekranlar sonsuz loading/hata durumunda kalıyor. Bu migration'ı
-- Supabase SQL Editor'de çalıştır.

CREATE TABLE IF NOT EXISTS public.countdowns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  title text NOT NULL,
  target_date date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.countdowns ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own countdowns"
  ON public.countdowns FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own countdowns"
  ON public.countdowns FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own countdowns"
  ON public.countdowns FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own countdowns"
  ON public.countdowns FOR DELETE
  USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.journal_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  entry_date date NOT NULL,
  content text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, entry_date)
);

ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own journal entries"
  ON public.journal_entries FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own journal entries"
  ON public.journal_entries FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own journal entries"
  ON public.journal_entries FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own journal entries"
  ON public.journal_entries FOR DELETE
  USING (auth.uid() = user_id);
