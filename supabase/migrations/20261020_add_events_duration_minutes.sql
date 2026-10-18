-- AI'nın algıladığı etkinlik süresi (ör. "2 saat sürecek"). Apple Takvim
-- bitiş saatini hesaplamak için kullanılır. NULL = süre belirtilmemiş
-- (varsayılan 60 dakika uygulanır); mevcut kayıtlar etkilenmez.
-- Bu migration'ı Supabase SQL Editor'de çalıştır.

ALTER TABLE public.events
ADD COLUMN IF NOT EXISTS duration_minutes integer
CHECK (duration_minutes IS NULL OR duration_minutes BETWEEN 1 AND 1440);
