-- Flutter tarafı (Plan.note / EventService) `events.note` kolonunu bekliyor
-- ama Supabase şemasında bu kolon henüz yok. Bu migration'ı Supabase SQL
-- Editor'de çalıştır.

ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS note text;
