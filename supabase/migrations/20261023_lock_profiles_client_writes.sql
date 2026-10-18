-- Life Admin — profiles tablosunu istemci yazmalarına KAPATMA (güvenlik).
--
-- Sorun: `authenticated` rolü public.profiles üzerinde tüm kolonlara UPDATE
-- yapabiliyordu; bu, bir kullanıcının kendi `plan`, `ai_usage` ve
-- `subscription_*` alanlarını değiştirebilmesi demekti.
--
-- Çözüm: Flutter uygulaması `profiles`'ı yalnızca OKUR. Yazanlar service_role
-- ile çalışan sunucu tarafıdır (Vercel: verify-purchase, apple-notifications,
-- delete-account; Supabase Edge Function: parse-plan). service_role bu
-- değişiklikten etkilenmez.
--
-- Bu migration TEKRAR ÇALIŞTIRILABİLİR: yetkileri kaldırmak zaten olmayan bir
-- yetki için hata vermez; fonksiyon/trigger yeniden oluşturulur. Hiçbir
-- kullanıcı verisi okunmaz, değiştirilmez veya silinmez. Canlı veritabanında
-- bu değişikliklerin yetki kısmı daha önce elle uygulandı; bu dosya kaydını ve
-- (varsa eksik) trigger'ı tamamlar.
--
-- Doğrulama: supabase/verification/profiles_client_lockdown_check.sql

-- 1) İstemci rollerinin profiles üzerindeki yazma/yapı yetkilerini kaldır.
--    (SELECT korunur: uygulama kendi profilini okur; RLS yalnızca kendi
--    satırını gösterir.)
REVOKE UPDATE, INSERT, DELETE, TRUNCATE, TRIGGER, REFERENCES
  ON public.profiles FROM anon, authenticated;

-- 2) Derinlemesine savunma: biri ileride UPDATE yetkisini yeniden verirse
--    bile, istemci rolü korunan alanları değiştiremesin. service_role ve
--    postgres (Dashboard) etkilenmez.
CREATE OR REPLACE FUNCTION public.protect_profile_entitlements()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon') THEN
    IF NEW.id                                   IS DISTINCT FROM OLD.id
    OR NEW.plan                                 IS DISTINCT FROM OLD.plan
    OR NEW.ai_usage                             IS DISTINCT FROM OLD.ai_usage
    OR NEW.ai_usage_reset_at                    IS DISTINCT FROM OLD.ai_usage_reset_at
    OR NEW.created_at                           IS DISTINCT FROM OLD.created_at
    OR NEW.subscription_status                  IS DISTINCT FROM OLD.subscription_status
    OR NEW.subscription_platform                IS DISTINCT FROM OLD.subscription_platform
    OR NEW.subscription_product_id              IS DISTINCT FROM OLD.subscription_product_id
    OR NEW.subscription_expires_at              IS DISTINCT FROM OLD.subscription_expires_at
    OR NEW.subscription_original_transaction_id IS DISTINCT FROM OLD.subscription_original_transaction_id
    THEN
      RAISE EXCEPTION 'Bu alanlar yalnızca sunucu tarafından değiştirilebilir.'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_profile_entitlements ON public.profiles;

CREATE TRIGGER protect_profile_entitlements
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.protect_profile_entitlements();

-- İSTEĞE BAĞLI (bugün gerekmiyor; uygulama adı auth metadata'da tutuyor):
-- İstemcinin yalnızca kendi görünen adını güncelleyebilmesi için SÜTUN BAZLI
-- yetki. Mevcut "Users can update own profile" RLS politikası yalnızca kendi
-- satırına izin verir.
-- GRANT UPDATE (full_name) ON public.profiles TO authenticated;
