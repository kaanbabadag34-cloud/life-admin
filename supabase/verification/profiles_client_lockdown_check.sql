-- SALT OKUNUR doğrulama: public.profiles tablosunda istemci rolleri (anon,
-- authenticated) hiçbir kolonu güncelleyemiyor mu? Hiçbir veriyi okumaz veya
-- değiştirmez; yalnızca yetki ve katalog bilgilerine bakar.
-- Supabase SQL Editor'de çalıştır. BEKLENEN: tüm satırlarda ok = true.
-- (ok = false satırları önce listelenir.)

with roles as (
  select unnest(array['anon', 'authenticated']) as role_name
),
cols as (
  select column_name
  from information_schema.columns
  where table_schema = 'public' and table_name = 'profiles'
),
checks as (
  -- Her kolon için UPDATE (plan, ai_usage, subscription_* dahil HEPSİ)
  select 'kolon UPDATE: ' || r.role_name || ' -> ' || c.column_name as check_name,
         false as expected,
         has_column_privilege(r.role_name, 'public.profiles', c.column_name, 'UPDATE') as actual
  from roles r cross join cols c

  union all

  -- Tablo düzeyi yazma / yapı yetkileri
  select 'tablo ' || p || ': ' || r.role_name,
         false,
         has_table_privilege(r.role_name, 'public.profiles', p)
  from roles r
  cross join unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'TRIGGER', 'REFERENCES']) as p

  union all

  -- Kendi profilini okuyabilmeli (uygulama bunu kullanıyor)
  select 'tablo SELECT: authenticated', true,
         has_table_privilege('authenticated', 'public.profiles', 'SELECT')

  union all

  -- Sunucu tarafı (Vercel / parse-plan) hâlâ yazabilmeli
  select 'service_role UPDATE', true,
         has_table_privilege('service_role', 'public.profiles', 'UPDATE')

  union all

  select 'RLS açık', true,
         (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass)

  union all

  -- Derinlemesine savunma trigger'ı (yetki yeniden verilirse korur)
  select 'trigger protect_profile_entitlements var', true,
         exists (
           select 1 from pg_trigger
           where tgrelid = 'public.profiles'::regclass
             and tgname = 'protect_profile_entitlements'
             and not tgisinternal
         )

  union all

  -- Yeni kullanıcı profili trigger fonksiyonu SECURITY DEFINER olmalı
  select 'handle_new_user SECURITY DEFINER', true,
         coalesce((
           select prosecdef from pg_proc
           where oid = to_regprocedure('public.handle_new_user()')
         ), false)
)
select check_name, expected, actual, (expected = actual) as ok
from checks
order by ok, check_name;
