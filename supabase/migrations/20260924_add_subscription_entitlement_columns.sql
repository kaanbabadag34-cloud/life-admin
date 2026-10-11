-- Life Admin Premium satın alma sistemi — verify-purchase Edge Function
-- bu kolonları güncelliyor. Mevcut "plan"/"ai_usage"/"ai_usage_reset_at"
-- kolonlarına DOKUNULMUYOR, sadece abonelik meta verisi için 4 yeni
-- kolon ekleniyor. Bu migration'ı Supabase SQL Editor'de çalıştır.
--
-- Not (manuel test premium'u gerçek satın almadan ayırmak için): gerçek,
-- doğrulanmış bir satın alma HER ZAMAN subscription_platform +
-- subscription_status alanlarını doldurur. Bir satırda plan='premium'
-- ama subscription_platform NULL ise, bu satın alma değil elle (test
-- amaçlı) verilmiş bir premium demektir.

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS subscription_product_id text,
ADD COLUMN IF NOT EXISTS subscription_expires_at timestamptz,
ADD COLUMN IF NOT EXISTS subscription_platform text,
ADD COLUMN IF NOT EXISTS subscription_status text;
