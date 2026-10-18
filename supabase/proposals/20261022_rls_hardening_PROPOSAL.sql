-- ============================================================================
-- ÖNERİ (PROPOSAL) — OTOMATİK UYGULANMAZ, ONAY + ÖN KONTROL GEREKİR
-- ============================================================================
-- Bu dosya BİLEREK `migrations/` klasöründe DEĞİL: Supabase CLI onu otomatik
-- uygulamasın. Tamamını yapıştırıp çalıştırırsan ilk komut hata verip durur.
--
-- Amaç: Premium (plan, subscription_*) ve AI kullanım (ai_usage*) alanlarının,
-- ve görev verilerinin, istemci (anon / authenticated JWT) tarafından yetkisiz
-- değiştirilememesi. Flutter uygulaması `profiles` tablosunu YALNIZCA okur
-- (iki select); yazanlar sunucu tarafı (Vercel service role) ve `parse-plan`
-- Edge Function'dır.
-- ============================================================================

DO $$
BEGIN
  RAISE EXCEPTION
    'ÖNERİ DOSYASI: önce BÖLÜM 1 (salt okunur kontroller) çıktısını incele, sonra BÖLÜM 2''yi adım adım çalıştır.';
END $$;

-- ============================================================================
-- BÖLÜM 1 — SALT OKUNUR KONTROLLER (veriyi değiştirmez; önce bunları çalıştır)
-- ============================================================================

-- 1a) RLS açık mı?
-- select relname, relrowsecurity as rls_acik
-- from pg_class
-- where relnamespace = 'public'::regnamespace
--   and relname in ('profiles','events','countdowns','journal_entries','apple_auth_tokens');

-- 1b) Mevcut politikalar (özellikle profiles için UPDATE/INSERT var mı?)
-- select tablename, policyname, cmd, roles, qual, with_check
-- from pg_policies where schemaname = 'public' order by tablename, cmd;

-- 1c) İstemci rollerinin tablo yetkileri
-- select table_name, grantee, privilege_type
-- from information_schema.role_table_grants
-- where table_schema = 'public'
--   and grantee in ('anon','authenticated')
--   and table_name in ('profiles','events','apple_auth_tokens')
-- order by table_name, grantee, privilege_type;

-- 1d) auth.users üzerindeki trigger'lar ve SECURITY DEFINER olup olmadıkları.
--     (profiles satırını yeni kullanıcı için oluşturan trigger varsa
--     prosecdef = true OLMALI; değilse BÖLÜM 2 / adım 3 kayıt olmayı bozar.)
-- select t.tgname, p.proname, p.prosecdef
-- from pg_trigger t join pg_proc p on p.oid = t.tgfoid
-- where t.tgrelid = 'auth.users'::regclass and not t.tgisinternal;

-- 1e) parse-plan Edge Function ai_usage'ı service role ile mi güncelliyor?
--     (Supabase Dashboard > Edge Functions > parse-plan > kaynak.) Kullanıcının
--     JWT'siyle güncelliyorsa BÖLÜM 2 / adım 3 AI kotasını bozar.

-- ============================================================================
-- BÖLÜM 2 — UYGULAMA ADIMLARI (yalnızca Bölüm 1 uygunsa, tek tek)
-- ============================================================================

-- Adım 1: profiles için RLS aç ve yalnızca KENDİ satırını okumaya izin ver.
-- alter table public.profiles enable row level security;
--
-- do $$
-- begin
--   if not exists (select 1 from pg_policies
--                  where schemaname='public' and tablename='profiles'
--                    and policyname='profiles_select_own') then
--     create policy profiles_select_own on public.profiles
--       for select to authenticated using (auth.uid() = id);
--   end if;
-- end $$;

-- Adım 2: events için kullanıcı yalnızca KENDİ satırlarını görsün/yazsın;
-- user_id başkasına çevrilemesin (WITH CHECK).
-- alter table public.events enable row level security;
--
-- do $$
-- declare spec record;
-- begin
--   for spec in select * from (values
--     ('events_select_own','select','auth.uid() = user_id', null),
--     ('events_insert_own','insert', null, 'auth.uid() = user_id'),
--     ('events_update_own','update','auth.uid() = user_id', 'auth.uid() = user_id'),
--     ('events_delete_own','delete','auth.uid() = user_id', null)
--   ) as t(pol, cmd, using_expr, check_expr)
--   loop
--     if not exists (select 1 from pg_policies
--                    where schemaname='public' and tablename='events'
--                      and policyname = spec.pol) then
--       execute format('create policy %I on public.events for %s to authenticated%s%s',
--         spec.pol, spec.cmd,
--         case when spec.using_expr is not null then ' using (' || spec.using_expr || ')' else '' end,
--         case when spec.check_expr is not null then ' with check (' || spec.check_expr || ')' else '' end);
--     end if;
--   end loop;
-- end $$;

-- Adım 3 (SADECE 1d ve 1e uygunsa): istemci rollerinin profiles yazma yetkisini
-- tamamen kaldır. Böylece kullanıcı kendi plan / subscription_* / ai_usage
-- alanlarını PostgREST üzerinden değiştiremez. service role etkilenmez.
-- revoke insert, update, delete on public.profiles from anon, authenticated;
