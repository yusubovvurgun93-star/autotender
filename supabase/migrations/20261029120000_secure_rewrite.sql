/*
# AutoTender v2 — Təhlükəsizlik və biznes məntiqinin serverə köçürülməsi

## Niyə
Əvvəlki sxemdə bütün cədvəllər anon açarla tam açıq idi və coin / qəbul / bonus məntiqi
brauzerdən idarə olunurdu. Nəticə: istənilən şəxs coin yarada, başqasının sorğusunu bağlaya,
bütün mağazaların telefonunu oxuya və rəqiblərin qiymətlərini görə bilirdi.

## Əsas qərarlar
1. Alıcı QEYDİYYATSIZDIR: Supabase "anonymous sign-in" ilə real `auth.uid()` alır.
   Sorğular bu id-yə bağlanır (owner_id). Heç kim başqasının sorğusunu görmür.
2. Satıcı e-poçt + parol ilə daxil olur. Hər hesab = bir mağaza (stores.owner_id).
3. Cədvəllərə birbaşa yazı BAĞLANIR. Bütün yazılar RPC funksiyaları ilə gedir
   (submit_bid, accept_bid, report_deal_failed, confirm_deal, register_store ...).
   Coin yalnız serverdə hərəkət edir və hər hərəkət `coin_ledger`-də qeyd olunur.
4. Təkliflər "qapalı"dır: satıcı yalnız öz təklifini görür; alıcı yalnız öz sorğusunun təkliflərini.
5. Satıcının telefonu yalnız alıcı təklifi QƏBUL edəndən sonra açılır (get_deal_contact / accept_bid).
6. Statuslar vahid kiçik hərflidir: requests: active|completed|expired|cancelled,
   bids: pending|accepted|rejected|expired.
7. Vaxtı bitən sorğular `expire_requests()` ilə bağlanır, mağazalara coin qaytarılır
   (pg_cron varsa hər dəqiqə, yoxdursa tətbiq özü çağırır).

## Əvvəlcədən Supabase Dashboard-da (Authentication)
- Sign In / Providers → "Allow anonymous sign-ins" = ON (alıcılar üçün)
- Sign In / Providers → Email → "Confirm email" = OFF (satıcı dərhal başlasın; ON qalsa da tətbiq işləyir)

## Admin yaratmaq (bir dəfə, SQL Editor-da)
  insert into public.admins (user_id, email)
  select id, email from auth.users where email = '<ADMIN_EMAIL>';
*/

-- =====================================================================
-- 0. KONFİQURASİYA
-- =====================================================================
create table if not exists public.app_config (
  key   text primary key,
  value integer not null
);
alter table public.app_config enable row level security;

insert into public.app_config (key, value) values
  ('signup_coins', 30),
  ('bid_limit', 5),
  ('bid_fee', 1),
  ('sale_bonus', 5),
  ('bonus_daily_cap', 3),
  ('max_active_requests', 5),
  ('requests_per_day', 15),
  ('reopen_hours', 6)
on conflict (key) do nothing;

-- =====================================================================
-- 1. SXEM DƏYİŞİKLİKLƏRİ
-- =====================================================================
alter table public.stores add column if not exists owner_id uuid references auth.users(id) on delete set null;
alter table public.stores add column if not exists categories text[] not null default '{}';
alter table public.stores add column if not exists review_count integer not null default 0;
alter table public.stores add column if not exists failed_deals integer not null default 0;

alter table public.requests add column if not exists owner_id uuid references auth.users(id) on delete set null;
alter table public.requests add column if not exists accepted_bid_id uuid;
alter table public.requests add column if not exists deal_status text;
alter table public.requests add column if not exists category text;
alter table public.bids add column if not exists deal_status text;

create unique index if not exists stores_owner_id_key on public.stores (owner_id) where owner_id is not null;
create index if not exists requests_owner_idx on public.requests (owner_id, created_at desc);
create index if not exists requests_status_exp_idx on public.requests (status, expires_at);

-- Statusları vahid formata gətir
update public.requests set status = lower(status) where status <> lower(status);
update public.bids     set status = lower(status) where status <> lower(status);
update public.requests set status = 'expired'
  where status not in ('active', 'completed', 'expired', 'cancelled');
update public.bids set status = 'expired'
  where status not in ('pending', 'accepted', 'rejected', 'expired');

-- Kateqoriyaları açar-sözlərə gətir (köhnə mətn → açar)
update public.requests set category = case
  when category ilike 'Yağ%'      then 'oil'
  when category ilike 'Aqreqat%'  then 'aggregate'
  when category ilike 'Kuzov%'    then 'body'
  when category ilike 'Elektrik%' then 'electrical'
  when category ilike 'Təkər%'    then 'wheel'
  when category ilike 'Aksesuar%' then 'accessory'
  else category end
where category is not null
  and category not in ('oil', 'aggregate', 'body', 'electrical', 'wheel', 'accessory');

-- Məhdudiyyətlər (mövcud data uyğun gəlmirsə xəbərdarlıq verib keçir)
do $c$
begin
  begin
    alter table public.requests add constraint requests_status_chk
      check (status in ('active', 'completed', 'expired', 'cancelled'));
  exception when duplicate_object then null;
           when others then raise notice 'requests_status_chk əlavə olunmadı: %', sqlerrm;
  end;
  begin
    alter table public.requests add constraint requests_urgency_chk
      check (urgency in ('express', 'standard', 'wide'));
  exception when duplicate_object then null;
           when others then raise notice 'requests_urgency_chk əlavə olunmadı: %', sqlerrm;
  end;
  begin
    alter table public.bids add constraint bids_status_chk
      check (status in ('pending', 'accepted', 'rejected', 'expired'));
  exception when duplicate_object then null;
           when others then raise notice 'bids_status_chk əlavə olunmadı: %', sqlerrm;
  end;
  begin
    alter table public.bids add constraint bids_condition_chk
      check (condition in ('original', 'analog', 'used'));
  exception when duplicate_object then null;
           when others then raise notice 'bids_condition_chk əlavə olunmadı: %', sqlerrm;
  end;
  begin
    create unique index bids_one_per_store_key on public.bids (request_id, store_id);
  exception when duplicate_table then null;
           when others then raise notice 'bids_one_per_store_key yaradılmadı (təkrar təkliflər var): %', sqlerrm;
  end;
  begin
    create unique index stores_voen_key on public.stores (voen) where voen is not null and voen <> '';
  exception when duplicate_table then null;
           when others then raise notice 'stores_voen_key yaradılmadı (təkrar VÖEN var): %', sqlerrm;
  end;
end
$c$;

-- =====================================================================
-- 2. TƏMİZ FUNKSİYALAR (yan təsirsiz)
-- =====================================================================

-- Telefonu beynəlxalq formata gətirir: 0501234567 / 50 123 45 67 / +994501234567 → 994501234567
create or replace function public.normalize_az_phone(p text)
returns text language plpgsql immutable set search_path = public as $fn$
declare d text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
begin
  if length(d) = 12 and d like '994%' then return d; end if;
  if length(d) = 10 and d like '0%'   then return '994' || substr(d, 2); end if;
  if length(d) = 9                    then return '994' || d; end if;
  return null;
end
$fn$;

-- Təklif qeydində telefon / mesajlaşma yönləndirməsi varmı?
-- Detal (OEM) nömrələrini bloklamır; yalnız mobil nömrə nümunələrini və əlaqə sözlərini tutur.
create or replace function public.bid_note_is_clean(p text)
returns boolean language plpgsql immutable set search_path = public as $fn$
declare
  t text := lower(btrim(coalesce(p, '')));
  squeezed text;
begin
  if t = '' then return true; end if;
  squeezed := regexp_replace(t, '[\s\.\-\(\)_/]', '', 'g');
  if squeezed ~ '(^|[^0-9])(\+?994|0)?(10|50|51|55|60|70|77|99)[0-9]{7}([^0-9]|$)' then
    return false;
  end if;
  if t ~ '(^|[^[:alnum:]])(wp|wa|whatsapp|watsap|vatsap|vatsapp|telegram|tg|insta|instagram|call)([^[:alnum:]]|$)' then
    return false;
  end if;
  if t ~ '(zəng|zeng|əlaqə|elaqe|@)' then
    return false;
  end if;
  return true;
end
$fn$;

-- Mağazanın markaları sorğunun markasına uyğundurmu? (köhnə "Hyundai / Kia" kimi qruplar da dəstəklənir)
create or replace function public.brand_matches(p_supported text[], p_brand text)
returns boolean language sql immutable set search_path = public as $fn$
  select p_supported is null
      or cardinality(p_supported) = 0
      or exists (
        select 1 from unnest(p_supported) s
        where s = 'Bütün markalar'
           or lower(s) = lower(p_brand)
           or lower(p_brand) = any (regexp_split_to_array(lower(s), '\s*[/(),]\s*'))
      )
$fn$;

create or replace function public.cfg(p_key text, p_default integer)
returns integer language sql stable security definer set search_path = public as $fn$
  select coalesce((select value from public.app_config where key = p_key), p_default)
$fn$;

create or replace function public._clean_text_array(p_arr text[], p_max_items integer, p_max_len integer)
returns text[] language sql immutable set search_path = public as $fn$
  select coalesce(array(
    select distinct left(btrim(x), p_max_len)
    from unnest(coalesce(p_arr, '{}')) x
    where btrim(x) <> ''
    limit p_max_items
  ), '{}')
$fn$;

-- =====================================================================
-- 3. RLS ÜÇÜN YARDIMÇILAR
-- =====================================================================
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $fn$
  select exists (select 1 from public.admins where user_id = auth.uid())
$fn$;

create or replace function public.my_store_id()
returns uuid language sql stable security definer set search_path = public as $fn$
  select id from public.stores where owner_id = auth.uid() limit 1
$fn$;

create or replace function public.owns_request(p_request uuid)
returns boolean language sql stable security definer set search_path = public as $fn$
  select exists (select 1 from public.requests where id = p_request and owner_id = auth.uid())
$fn$;

-- =====================================================================
-- 4. YENİ CƏDVƏLLƏR
-- =====================================================================
create table if not exists public.coin_ledger (
  id         uuid primary key default gen_random_uuid(),
  store_id   uuid not null references public.stores(id) on delete cascade,
  amount     integer not null,
  type       text not null,
  request_id uuid references public.requests(id) on delete set null,
  bid_id     uuid references public.bids(id) on delete set null,
  note       text,
  created_at timestamptz not null default now()
);
create index if not exists coin_ledger_store_idx on public.coin_ledger (store_id, created_at desc);
create index if not exists coin_ledger_bid_idx on public.coin_ledger (bid_id, type);
alter table public.coin_ledger enable row level security;

create table if not exists public.store_reviews (
  id         uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.requests(id) on delete cascade,
  store_id   uuid not null references public.stores(id) on delete cascade,
  buyer_tag  text,
  stars      integer not null check (stars between 1 and 5),
  comment    text check (comment is null or length(comment) <= 300),
  created_at timestamptz not null default now()
);
create index if not exists store_reviews_store_idx on public.store_reviews (store_id, created_at desc);
alter table public.store_reviews enable row level security;

alter table public.in_app_notifications add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.in_app_notifications add column if not exists kind text;
alter table public.in_app_notifications add column if not exists request_id uuid;
alter table public.in_app_notifications add column if not exists is_read boolean not null default false;
create index if not exists notifications_user_idx on public.in_app_notifications (user_id, created_at desc);

-- =====================================================================
-- 5. KÖHNƏ TRIGGER / FUNKSİYA / VIEW / POLICY-LƏRİN SİLİNMƏSİ
-- =====================================================================
drop trigger if exists trg_deduct_coin  on public.bids;
drop trigger if exists trg_slot_limit   on public.bids;
drop trigger if exists trg_validate_note on public.bids;
drop trigger if exists trg_on_accepted  on public.requests;
drop trigger if exists trg_auto_refund  on public.requests;

drop function if exists public.deduct_coin_on_bid();
drop function if exists public.enforce_bid_slot_limit();
drop function if exists public.validate_bid_note();
drop function if exists public.on_request_accepted();
drop function if exists public.auto_refund_expired();
drop function if exists public.cancel_accepted_bid(uuid);
drop function if exists public.cancel_accepted_bid(uuid, uuid);
drop function if exists public.confirm_deal(uuid);

drop view if exists public.seller_requests_feed;
drop view if exists public.seller_lost_bids_feedback;
drop view if exists public.admin_dashboard_stats;

do $c$
declare pol record;
begin
  for pol in
    select policyname, tablename from pg_policies
    where schemaname = 'public'
      and tablename in ('stores', 'requests', 'bids', 'in_app_notifications', 'car_brands', 'admins',
                        'coin_ledger', 'store_reviews', 'app_config')
  loop
    execute format('drop policy %I on public.%I', pol.policyname, pol.tablename);
  end loop;
end
$c$;

-- =====================================================================
-- 6. İMTİYAZLAR (GRANT) VƏ RLS POLICY-LƏRİ
-- =====================================================================
alter table public.stores               enable row level security;
alter table public.requests             enable row level security;
alter table public.bids                 enable row level security;
alter table public.in_app_notifications enable row level security;
alter table public.car_brands           enable row level security;
alter table public.admins               enable row level security;

revoke all on public.stores, public.requests, public.bids, public.in_app_notifications,
              public.car_brands, public.admins, public.coin_ledger, public.store_reviews,
              public.app_config
  from anon, authenticated;

-- stores: yalnız açıq sütunlar (telefon, VÖEN, ünvan, coin gizlidir)
grant select (id, name, grade, rating, review_count, verified, supported_brands, created_at)
  on public.stores to anon, authenticated;
grant select on public.car_brands to anon, authenticated;
grant insert, update, delete on public.car_brands to authenticated;      -- policy ilə yalnız admin
grant select on public.requests, public.bids to authenticated;
grant select on public.coin_ledger, public.store_reviews to authenticated;
grant select on public.in_app_notifications to authenticated;
grant update (is_read) on public.in_app_notifications to authenticated;

create policy brands_read on public.car_brands
  for select to anon, authenticated using (true);
create policy brands_admin_write on public.car_brands
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy stores_public_read on public.stores
  for select to anon, authenticated using (true);

create policy requests_owner_read on public.requests
  for select to authenticated using (owner_id = (select auth.uid()));
create policy requests_seller_read on public.requests
  for select to authenticated
  using (status = 'active' and expires_at > now() and public.my_store_id() is not null);
create policy requests_admin_read on public.requests
  for select to authenticated using (public.is_admin());

create policy bids_owner_read on public.bids
  for select to authenticated using (public.owns_request(request_id));
create policy bids_store_read on public.bids
  for select to authenticated using (store_id = public.my_store_id());
create policy bids_admin_read on public.bids
  for select to authenticated using (public.is_admin());

create policy notifications_own_read on public.in_app_notifications
  for select to authenticated using (user_id = (select auth.uid()));
create policy notifications_own_update on public.in_app_notifications
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy ledger_store_read on public.coin_ledger
  for select to authenticated using (store_id = public.my_store_id() or public.is_admin());

create policy reviews_read on public.store_reviews
  for select to authenticated using (true);

-- =====================================================================
-- 7. DAXİLİ FUNKSİYALAR (API-dən çağırıla bilməz)
-- =====================================================================
create or replace function public._coin_move(
  p_store uuid, p_amount integer, p_type text,
  p_request uuid default null, p_bid uuid default null, p_note text default null)
returns integer language plpgsql security definer set search_path = public as $fn$
declare v_old integer; v_new integer;
begin
  select coin_balance into v_old from stores where id = p_store for update;
  if not found then return 0; end if;
  v_new := greatest(v_old + p_amount, 0);
  update stores set coin_balance = v_new where id = p_store;
  if v_new <> v_old then
    insert into coin_ledger (store_id, amount, type, request_id, bid_id, note)
    values (p_store, v_new - v_old, p_type, p_request, p_bid, p_note);
  end if;
  return v_new - v_old;
end
$fn$;

create or replace function public._notify(
  p_user uuid, p_target text, p_kind text, p_title text, p_body text, p_request uuid default null)
returns void language sql security definer set search_path = public as $fn$
  insert into public.in_app_notifications (target_type, target_id, user_id, kind, title, body, request_id)
  select p_target, p_user, p_user, p_kind, p_title, p_body, p_request
  where p_user is not null
$fn$;

create or replace function public._recompute_store_rating(p_store uuid)
returns void language plpgsql security definer set search_path = public as $fn$
declare v_avg numeric; v_cnt integer;
begin
  select avg(stars), count(*) into v_avg, v_cnt from store_reviews where store_id = p_store;
  update stores set
    rating = case when v_cnt = 0 then 5.0 else round(v_avg, 1) end,
    review_count = v_cnt,
    grade = case
      when v_cnt >= 5 and v_avg >= 4.7 then 'A+'
      when v_cnt >= 3 and v_avg < 4.0  then 'B'
      else 'A' end
  where id = p_store;
end
$fn$;

-- Sorğunu bağlayır: gözləyən təkliflər 'expired' olur, mağazalara coin qaytarılır
create or replace function public._close_request(p_request uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $fn$
declare r record; b record; v_owner uuid; v_n integer := 0;
begin
  select owner_id, brand, model, part_name into r from requests where id = p_request;
  for b in select id, store_id from bids where request_id = p_request and status = 'pending' loop
    perform _coin_move(b.store_id, cfg('bid_fee', 1), 'REFUND', p_request, b.id, 'Sorğu bağlandı');
    update bids set status = 'expired' where id = b.id;
    select owner_id into v_owner from stores where id = b.store_id;
    perform _notify(v_owner, 'seller', 'refund',
      case p_status when 'cancelled' then 'Sorğu ləğv edildi' else 'Sorğunun vaxtı bitdi' end,
      trim(coalesce(r.brand, '') || ' ' || coalesce(r.model, '')) || ' — ' || coalesce(r.part_name, '') || '. Coininiz qaytarıldı.',
      p_request);
    v_n := v_n + 1;
  end loop;
  update requests set status = p_status where id = p_request;
  if p_status = 'expired' and v_n > 0 then
    perform _notify(r.owner_id, 'buyer', 'request_expired', 'Sorğunuzun vaxtı bitdi',
      trim(coalesce(r.brand, '') || ' ' || coalesce(r.model, '')) || ' — ' || coalesce(r.part_name, '') ||
      '. ' || v_n || ' təklif seçilməmiş qaldı.', p_request);
  end if;
end
$fn$;

-- =====================================================================
-- 8. İSTİFADƏÇİ / MAĞAZA RPC-ləri
-- =====================================================================
create or replace function public.get_my_role()
returns jsonb language sql stable security definer set search_path = public as $fn$
  select jsonb_build_object(
    'user_id', auth.uid(),
    'is_anonymous', coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false),
    'is_admin', public.is_admin(),
    'store_id', public.my_store_id())
$fn$;

create or replace function public.get_my_store()
returns setof public.stores language sql stable security definer set search_path = public as $fn$
  select * from public.stores where owner_id = auth.uid()
$fn$;

create or replace function public.register_store(
  p_name text, p_voen text, p_phone text, p_address text,
  p_brands text[], p_categories text[])
returns uuid language plpgsql security definer set search_path = public as $fn$
declare
  u uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_phone text := normalize_az_phone(p_phone);
  v_voen text := nullif(btrim(coalesce(p_voen, '')), '');
  v_brands text[] := _clean_text_array(p_brands, 40, 40);
  v_cats text[] := _clean_text_array(p_categories, 10, 20);
  v_id uuid;
begin
  if u is null then raise exception 'Daxil olmaq lazımdır.'; end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Mağaza açmaq üçün e-poçt ilə qeydiyyat lazımdır.';
  end if;
  if exists (select 1 from stores where owner_id = u) then
    raise exception 'Bu hesabın artıq mağazası var.';
  end if;
  if length(v_name) < 2 or length(v_name) > 60 then
    raise exception 'Mağaza adı 2–60 simvol olmalıdır.';
  end if;
  if v_phone is null then
    raise exception 'Telefon nömrəsi düzgün deyil (məs: 050 123 45 67).';
  end if;
  if exists (select 1 from stores where normalize_az_phone(phone) = v_phone) then
    raise exception 'Bu nömrə ilə mağaza artıq mövcuddur.';
  end if;
  if v_voen is not null and v_voen !~ '^[0-9]{10}$' then
    raise exception 'VÖEN 10 rəqəmdən ibarət olmalıdır.';
  end if;
  if v_voen is not null and exists (select 1 from stores where voen = v_voen) then
    raise exception 'Bu VÖEN ilə mağaza artıq mövcuddur.';
  end if;
  if cardinality(v_brands) = 0 then v_brands := array['Bütün markalar']; end if;

  insert into stores (name, voen, phone, address, supported_brands, categories,
                      coin_balance, grade, rating, review_count, verified, owner_id)
  values (v_name, v_voen, v_phone, left(btrim(coalesce(nullif(p_address, ''), 'Bakı')), 120),
          v_brands, v_cats, cfg('signup_coins', 30), 'A', 5.0, 0, false, u)
  returning id into v_id;

  insert into coin_ledger (store_id, amount, type, note)
  values (v_id, cfg('signup_coins', 30), 'SIGNUP', 'Qeydiyyat bonusu');
  return v_id;
end
$fn$;

create or replace function public.update_my_store(
  p_name text, p_address text, p_brands text[], p_categories text[])
returns void language plpgsql security definer set search_path = public as $fn$
declare
  v_name text := btrim(coalesce(p_name, ''));
  v_brands text[] := _clean_text_array(p_brands, 40, 40);
begin
  if auth.uid() is null then raise exception 'Daxil olmaq lazımdır.'; end if;
  if length(v_name) < 2 or length(v_name) > 60 then
    raise exception 'Mağaza adı 2–60 simvol olmalıdır.';
  end if;
  if cardinality(v_brands) = 0 then v_brands := array['Bütün markalar']; end if;
  update stores set
    name = v_name,
    address = left(btrim(coalesce(nullif(p_address, ''), address, 'Bakı')), 120),
    supported_brands = v_brands,
    categories = _clean_text_array(p_categories, 10, 20)
  where owner_id = auth.uid();
  if not found then raise exception 'Mağaza profili tapılmadı.'; end if;
end
$fn$;

-- =====================================================================
-- 9. ALICI RPC-ləri
-- =====================================================================
create or replace function public.create_request(
  p_brand text, p_model text, p_year integer, p_vin text, p_part_name text,
  p_category text, p_urgency text, p_budget numeric, p_images text[] default '{}')
returns uuid language plpgsql security definer set search_path = public as $fn$
declare
  u uuid := auth.uid();
  v_model text := btrim(coalesce(p_model, ''));
  v_part text := btrim(coalesce(p_part_name, ''));
  v_vin text := nullif(upper(regexp_replace(coalesce(p_vin, ''), '\s', '', 'g')), '');
  v_hours integer;
  v_imgs text[] := coalesce(p_images, '{}');
  v_id uuid;
  i integer;
begin
  if u is null then raise exception 'Sessiya tapılmadı. Səhifəni yeniləyin.'; end if;
  if not exists (select 1 from car_brands where name = p_brand) then
    raise exception 'Avtomobilin markasını seçin.';
  end if;
  if length(v_model) < 1 or length(v_model) > 40 then raise exception 'Modeli qeyd edin.'; end if;
  if length(v_part) < 2 or length(v_part) > 120 then raise exception 'Detalın adını qeyd edin.'; end if;
  if p_year is not null and (p_year < 1950 or p_year > extract(year from now())::int + 1) then
    raise exception 'İl düzgün deyil.';
  end if;
  if v_vin is not null and v_vin !~ '^[A-Z0-9]{5,17}$' then
    raise exception 'VIN yalnız hərf və rəqəmlərdən ibarət olmalıdır (maks. 17).';
  end if;
  if p_category is not null and p_category not in ('oil', 'aggregate', 'body', 'electrical', 'wheel', 'accessory') then
    raise exception 'Kateqoriya düzgün deyil.';
  end if;
  v_hours := case p_urgency when 'express' then 1 when 'standard' then 6 when 'wide' then 24 else null end;
  if v_hours is null then raise exception 'Müddət düzgün deyil.'; end if;
  if p_budget is not null and (p_budget <= 0 or p_budget > 1000000) then
    raise exception 'Büdcə düzgün deyil.';
  end if;
  if cardinality(v_imgs) > 3 then raise exception 'Ən çox 3 şəkil əlavə etmək olar.'; end if;
  for i in 1 .. coalesce(cardinality(v_imgs), 0) loop
    if v_imgs[i] !~ '^https://' or length(v_imgs[i]) > 500 or position(u::text in v_imgs[i]) = 0 then
      raise exception 'Şəkil ünvanı düzgün deyil.';
    end if;
  end loop;

  if (select count(*) from requests where owner_id = u and status = 'active' and expires_at > now())
       >= cfg('max_active_requests', 5) then
    raise exception 'Eyni vaxtda ən çox % aktiv sorğunuz ola bilər.', cfg('max_active_requests', 5);
  end if;
  if (select count(*) from requests where owner_id = u and created_at > now() - interval '24 hours')
       >= cfg('requests_per_day', 15) then
    raise exception 'Gündəlik sorğu limitinə çatdınız.';
  end if;

  insert into requests (owner_id, buyer_tag, brand, model, year, vin, part_name, part_images,
                        category, urgency, budget_azn, status, expires_at)
  values (u, 'Sürücü #' || (floor(random() * 9000) + 1000)::int, p_brand, v_model, p_year, v_vin, v_part,
          v_imgs, p_category, p_urgency, p_budget, 'active', now() + v_hours * interval '1 hour')
  returning id into v_id;

  -- Uyğun satıcılara bildiriş
  insert into in_app_notifications (target_type, target_id, user_id, kind, title, body, request_id)
  select 'seller', s.owner_id, s.owner_id, 'new_request',
         'Yeni sorğu: ' || p_brand || ' ' || v_model, v_part, v_id
  from stores s
  where s.owner_id is not null
    and s.owner_id <> u
    and s.coin_balance >= cfg('bid_fee', 1)
    and brand_matches(s.supported_brands, p_brand)
    and (cardinality(s.categories) = 0 or p_category is null or p_category = any (s.categories));

  return v_id;
end
$fn$;

create or replace function public.cancel_request(p_request_id uuid)
returns void language plpgsql security definer set search_path = public as $fn$
declare r requests%rowtype;
begin
  select * into r from requests where id = p_request_id for update;
  if not found or r.owner_id is distinct from auth.uid() then
    raise exception 'Bu əməliyyat üçün icazəniz yoxdur.';
  end if;
  if r.status <> 'active' then raise exception 'Yalnız aktiv sorğunu ləğv etmək olar.'; end if;
  perform _close_request(r.id, 'cancelled');
end
$fn$;

create or replace function public.accept_bid(p_bid_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare
  u uuid := auth.uid();
  b bids%rowtype;
  r requests%rowtype;
  s stores%rowtype;
  v_today integer;
begin
  if u is null then raise exception 'Sessiya tapılmadı.'; end if;
  select request_id into r.id from bids where id = p_bid_id;
  if r.id is null then raise exception 'Təklif tapılmadı.'; end if;
  select * into r from requests where id = r.id for update;
  if r.owner_id is distinct from u then raise exception 'Bu əməliyyat üçün icazəniz yoxdur.'; end if;
  if r.status <> 'active' or r.expires_at <= now() then raise exception 'Bu sorğu artıq bağlanıb.'; end if;
  select * into b from bids where id = p_bid_id;
  if b.status <> 'pending' then raise exception 'Bu təklif artıq aktiv deyil.'; end if;

  update bids set status = 'accepted' where id = b.id;
  update bids set status = 'rejected'
    where request_id = r.id and id <> b.id and status = 'pending';
  update requests set status = 'completed', accepted_bid_id = b.id, deal_status = null where id = r.id;

  select * into s from stores where id = b.store_id;
  select count(*) into v_today from coin_ledger
    where store_id = s.id and type = 'SALE_BONUS' and created_at > now() - interval '24 hours';
  if v_today < cfg('bonus_daily_cap', 3) then
    perform _coin_move(s.id, cfg('sale_bonus', 5), 'SALE_BONUS', r.id, b.id, null);
  end if;

  perform _notify(s.owner_id, 'seller', 'bid_accepted', 'Təklifiniz qəbul edildi',
    trim(coalesce(r.brand, '') || ' ' || coalesce(r.model, '')) || ' — ' || r.part_name ||
    '. Alıcı sizinlə WhatsApp-da əlaqə saxlayacaq.', r.id);

  insert into in_app_notifications (target_type, target_id, user_id, kind, title, body, request_id)
  select 'seller', s2.owner_id, s2.owner_id, 'bid_lost', 'Təklif seçilmədi',
         trim(coalesce(r.brand, '') || ' ' || coalesce(r.model, '')) || ' — ' || r.part_name ||
         '. Qalib qiymət: ' || b.price_azn::numeric(12, 0) || ' AZN, sizin: ' || ob.price_azn::numeric(12, 0) || ' AZN.',
         r.id
  from bids ob join stores s2 on s2.id = ob.store_id
  where ob.request_id = r.id and ob.id <> b.id and ob.status = 'rejected'
    and ob.deal_status is distinct from 'failed' and s2.owner_id is not null;

  return jsonb_build_object('store_name', s.name, 'phone', s.phone, 'price', b.price_azn);
end
$fn$;

create or replace function public.get_deal_contact(p_request_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare r requests%rowtype; s stores%rowtype; b bids%rowtype;
begin
  select * into r from requests where id = p_request_id;
  if not found or r.owner_id is distinct from auth.uid() then
    raise exception 'Bu əməliyyat üçün icazəniz yoxdur.';
  end if;
  if r.status <> 'completed' or r.accepted_bid_id is null then
    raise exception 'Bu sorğuda qəbul edilmiş təklif yoxdur.';
  end if;
  select * into b from bids where id = r.accepted_bid_id;
  select * into s from stores where id = b.store_id;
  return jsonb_build_object(
    'store_name', s.name, 'phone', s.phone, 'price', b.price_azn,
    'deal_status', r.deal_status,
    'reviewed', exists (select 1 from store_reviews where request_id = r.id));
end
$fn$;

create or replace function public.report_deal_failed(p_request_id uuid)
returns void language plpgsql security definer set search_path = public as $fn$
declare r requests%rowtype; b bids%rowtype; v_owner uuid; v_bonus integer;
begin
  select * into r from requests where id = p_request_id for update;
  if not found or r.owner_id is distinct from auth.uid() then
    raise exception 'Bu əməliyyat üçün icazəniz yoxdur.';
  end if;
  if r.status <> 'completed' or r.accepted_bid_id is null or r.deal_status is not null then
    raise exception 'Bu razılaşmanı ləğv etmək mümkün deyil.';
  end if;
  select * into b from bids where id = r.accepted_bid_id;

  select amount into v_bonus from coin_ledger
    where bid_id = b.id and type = 'SALE_BONUS' order by created_at desc limit 1;
  if coalesce(v_bonus, 0) > 0 then
    perform _coin_move(b.store_id, -v_bonus, 'BONUS_REVOKED', r.id, b.id, 'Razılaşma alınmadı');
  end if;

  update bids set status = 'rejected', deal_status = 'failed' where id = b.id;
  update bids set status = 'pending'
    where request_id = r.id and id <> b.id and status = 'rejected' and deal_status is distinct from 'failed';
  update stores set failed_deals = failed_deals + 1 where id = b.store_id;
  update requests set status = 'active', accepted_bid_id = null, deal_status = 'failed',
         expires_at = now() + cfg('reopen_hours', 6) * interval '1 hour'
    where id = r.id;

  select owner_id into v_owner from stores where id = b.store_id;
  perform _notify(v_owner, 'seller', 'deal_failed', 'Razılaşma alınmadı',
    trim(coalesce(r.brand, '') || ' ' || coalesce(r.model, '')) || ' — ' || r.part_name ||
    '. Sorğu alıcı üçün yenidən açıldı.', r.id);
end
$fn$;

create or replace function public.confirm_deal(
  p_request_id uuid, p_stars integer default null, p_comment text default null)
returns void language plpgsql security definer set search_path = public as $fn$
declare r requests%rowtype; v_store uuid;
begin
  select * into r from requests where id = p_request_id for update;
  if not found or r.owner_id is distinct from auth.uid() then
    raise exception 'Bu əməliyyat üçün icazəniz yoxdur.';
  end if;
  if r.status <> 'completed' or r.accepted_bid_id is null then
    raise exception 'Bu sorğuda qəbul edilmiş təklif yoxdur.';
  end if;
  if p_stars is not null and (p_stars < 1 or p_stars > 5) then
    raise exception 'Qiymət 1–5 arasında olmalıdır.';
  end if;
  if p_comment is not null and length(p_comment) > 300 then
    raise exception 'Rəy 300 simvolu keçməməlidir.';
  end if;

  if r.deal_status is distinct from 'confirmed' then
    update requests set deal_status = 'confirmed' where id = r.id;
    update bids set deal_status = 'confirmed' where id = r.accepted_bid_id;
  end if;

  if p_stars is not null then
    select store_id into v_store from bids where id = r.accepted_bid_id;
    insert into store_reviews (request_id, store_id, buyer_tag, stars, comment)
    values (r.id, v_store, r.buyer_tag, p_stars, nullif(btrim(coalesce(p_comment, '')), ''))
    on conflict (request_id) do nothing;
    perform _recompute_store_rating(v_store);
  end if;
end
$fn$;

-- =====================================================================
-- 10. SATICI RPC-ləri
-- =====================================================================
create or replace function public.submit_bid(
  p_request_id uuid, p_price numeric, p_condition text, p_warranty text, p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $fn$
declare
  u uuid := auth.uid();
  v_sid uuid;
  v_store stores%rowtype;
  r requests%rowtype;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_warranty text := btrim(coalesce(p_warranty, ''));
  v_bid uuid;
begin
  if u is null then raise exception 'Daxil olmaq lazımdır.'; end if;
  select id into v_sid from stores where owner_id = u;
  if v_sid is null then raise exception 'Təklif vermək üçün mağaza profili lazımdır.'; end if;

  select * into r from requests where id = p_request_id for update;
  if not found then raise exception 'Sorğu tapılmadı.'; end if;
  select * into v_store from stores where id = v_sid for update;

  if r.owner_id = u then raise exception 'Öz sorğunuza təklif verə bilməzsiniz.'; end if;
  if r.status <> 'active' or r.expires_at <= now() then raise exception 'Bu sorğu artıq bağlanıb.'; end if;
  if not brand_matches(v_store.supported_brands, r.brand) then
    raise exception 'Bu marka mağazanızın profilinə daxil deyil.';
  end if;
  if p_price is null or p_price <= 0 or p_price > 1000000 then
    raise exception 'Qiyməti düzgün qeyd edin.';
  end if;
  if p_condition is null or p_condition not in ('original', 'analog', 'used') then
    raise exception 'Detalın vəziyyətini seçin.';
  end if;
  if v_warranty = '' then v_warranty := 'Zəmanətsiz'; end if;
  if length(v_warranty) > 40 then raise exception 'Zəmanət mətni çox uzundur.'; end if;
  if v_note is not null and length(v_note) > 300 then raise exception 'Qeyd 300 simvolu keçməməlidir.'; end if;
  if v_note is not null and not bid_note_is_clean(v_note) then
    raise exception 'Qeydə telefon nömrəsi və ya əlaqə yönləndirməsi yazmaq olmaz. Əlaqə məlumatları təklif qəbul ediləndən sonra açılır.';
  end if;
  if exists (select 1 from bids where request_id = r.id and store_id = v_store.id) then
    raise exception 'Bu sorğuya artıq təklif göndərmisiniz.';
  end if;
  if (select count(*) from bids where request_id = r.id) >= cfg('bid_limit', 5) then
    raise exception 'Bu sorğu üçün təklif limiti dolub.';
  end if;
  if v_store.coin_balance < cfg('bid_fee', 1) then
    raise exception 'Kifayət qədər coin yoxdur.';
  end if;

  insert into bids (request_id, store_id, price_azn, condition, warranty, note, status)
  values (r.id, v_store.id, p_price, p_condition, v_warranty, v_note, 'pending')
  returning id into v_bid;

  perform _coin_move(v_store.id, -cfg('bid_fee', 1), 'BID_FEE', r.id, v_bid, null);

  perform _notify(r.owner_id, 'buyer', 'new_bid', 'Yeni təklif gəldi',
    trim(coalesce(r.brand, '') || ' ' || coalesce(r.model, '')) || ' — ' || r.part_name ||
    ': ' || p_price::numeric(12, 0) || ' AZN', r.id);
  return v_bid;
end
$fn$;

-- Açıq sorğular: markaya uyğun, vaxtı bitməmiş, limit dolmamış (və ya artıq təklif verdiyim)
drop function if exists public.seller_feed();
create or replace function public.seller_feed()
returns table (
  id uuid, buyer_tag text, brand text, model text, year integer, vin text, part_name text,
  part_images text[], category text, urgency text, budget_azn numeric,
  expires_at timestamptz, created_at timestamptz,
  bid_count integer, slots_full boolean, my_bid_id uuid)
language sql stable security definer set search_path = public as $fn$
  with s as (select * from public.stores where owner_id = auth.uid()),
  x as (
    select r.*,
      (select count(*) from public.bids b where b.request_id = r.id)::integer as n,
      (select b.id from public.bids b where b.request_id = r.id and b.store_id = s.id) as mine
    from public.requests r, s
    where r.status = 'active' and r.expires_at > now()
      and r.owner_id is distinct from auth.uid()
      and public.brand_matches(s.supported_brands, r.brand)
  )
  select x.id, x.buyer_tag, x.brand, x.model, x.year, x.vin, x.part_name, x.part_images,
         x.category, x.urgency, x.budget_azn, x.expires_at, x.created_at,
         x.n, x.n >= public.cfg('bid_limit', 5), x.mine
  from x
  where x.n < public.cfg('bid_limit', 5) or x.mine is not null
  order by x.created_at desc
  limit 100
$fn$;

-- Arxiv: son 7 gündə bağlanmış / limiti dolmuş sorğular (bazar məlumatı; alıcı kimliyi və VIN yoxdur)
drop function if exists public.seller_closed_feed();
create or replace function public.seller_closed_feed()
returns table (
  id uuid, brand text, model text, year integer, part_name text, category text, urgency text,
  budget_azn numeric, status text, created_at timestamptz, expires_at timestamptz,
  bid_count integer, i_bid boolean, accepted_price numeric)
language sql stable security definer set search_path = public as $fn$
  with s as (select * from public.stores where owner_id = auth.uid()),
  x as (
    select r.*,
      (select count(*) from public.bids b where b.request_id = r.id)::integer as n,
      exists (select 1 from public.bids b where b.request_id = r.id and b.store_id = s.id) as mine
    from public.requests r, s
    where r.created_at > now() - interval '7 days'
      and r.owner_id is distinct from auth.uid()
      and public.brand_matches(s.supported_brands, r.brand)
  )
  select x.id, x.brand, x.model, x.year, x.part_name, x.category, x.urgency, x.budget_azn,
         x.status, x.created_at, x.expires_at, x.n, x.mine,
         (select b.price_azn from public.bids b where b.id = x.accepted_bid_id and x.status = 'completed')
  from x
  where x.status in ('expired', 'completed', 'cancelled')
     or (x.status = 'active' and (x.expires_at <= now() or x.n >= public.cfg('bid_limit', 5)))
  order by x.created_at desc
  limit 100
$fn$;

-- Mənim təkliflərim + uduzduqda qalib qiymət (bazar analitikası)
drop function if exists public.seller_my_bids();
create or replace function public.seller_my_bids()
returns table (
  bid_id uuid, request_id uuid, price_azn numeric, condition text, warranty text, note text,
  bid_status text, deal_status text, bid_created_at timestamptz,
  brand text, model text, year integer, part_name text, category text,
  request_status text, request_expires_at timestamptz,
  winning_price numeric, winning_warranty text, price_difference numeric)
language sql stable security definer set search_path = public as $fn$
  with s as (select * from public.stores where owner_id = auth.uid())
  select b.id, b.request_id, b.price_azn, b.condition, b.warranty, b.note,
         b.status, b.deal_status, b.created_at,
         r.brand, r.model, r.year, r.part_name, r.category,
         r.status, r.expires_at,
         wb.price_azn, wb.warranty, (b.price_azn - wb.price_azn)
  from s
  join public.bids b on b.store_id = s.id
  join public.requests r on r.id = b.request_id
  left join public.bids wb on wb.id = r.accepted_bid_id and wb.id <> b.id and r.status = 'completed'
  order by b.created_at desc
  limit 200
$fn$;

-- =====================================================================
-- 11. VAXT BİTMƏSİ
-- =====================================================================
create or replace function public.expire_requests()
returns integer language plpgsql security definer set search_path = public as $fn$
declare r record; n integer := 0;
begin
  for r in
    select id from requests
    where status = 'active' and expires_at <= now()
    order by expires_at limit 200
    for update skip locked
  loop
    perform _close_request(r.id, 'expired');
    n := n + 1;
  end loop;
  return n;
end
$fn$;

-- =====================================================================
-- 12. ADMİN RPC-ləri
-- =====================================================================
create or replace function public.admin_dashboard()
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  return jsonb_build_object(
    'total_stores',       (select count(*) from stores),
    'verified_stores',    (select count(*) from stores where verified),
    'total_requests',     (select count(*) from requests),
    'active_requests',    (select count(*) from requests where status = 'active' and expires_at > now()),
    'completed_requests', (select count(*) from requests where status = 'completed'),
    'expired_requests',   (select count(*) from requests where status = 'expired'),
    'requests_7d',        (select count(*) from requests where created_at > now() - interval '7 days'),
    'total_bids',         (select count(*) from bids),
    'coins_spent',        (select coalesce(-sum(amount), 0) from coin_ledger where type = 'BID_FEE'),
    'coins_refunded',     (select coalesce(sum(amount), 0) from coin_ledger where type = 'REFUND'),
    'bonus_coins_given',  (select coalesce(sum(amount), 0) from coin_ledger where type = 'SALE_BONUS'),
    'failed_deals',       (select coalesce(sum(failed_deals), 0) from stores));
end
$fn$;

create or replace function public.admin_list_stores()
returns setof public.stores language plpgsql stable security definer set search_path = public as $fn$
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  return query select * from stores order by created_at desc;
end
$fn$;

create or replace function public.admin_adjust_coins(p_store uuid, p_delta integer, p_note text default null)
returns integer language plpgsql security definer set search_path = public as $fn$
declare v_moved integer;
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  if p_delta is null or p_delta = 0 or abs(p_delta) > 1000 then raise exception 'Məbləğ düzgün deyil.'; end if;
  v_moved := _coin_move(p_store, p_delta, 'ADMIN_ADJUST', null, null, left(p_note, 200));
  return (select coin_balance from stores where id = p_store);
end
$fn$;

create or replace function public.admin_set_verified(p_store uuid, p_verified boolean)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  update stores set verified = coalesce(p_verified, false) where id = p_store;
end
$fn$;

-- Köhnə (sahibsiz) mağazanı e-poçtu ilə qeydiyyatdan keçmiş istifadəçiyə bağlayır
create or replace function public.admin_assign_store_owner(p_store uuid, p_email text)
returns void language plpgsql security definer set search_path = public as $fn$
declare v_user uuid;
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  select id into v_user from auth.users where lower(email) = lower(btrim(p_email));
  if v_user is null then raise exception 'Bu e-poçt ilə istifadəçi tapılmadı.'; end if;
  if exists (select 1 from stores where owner_id = v_user) then
    raise exception 'Bu istifadəçinin artıq mağazası var.';
  end if;
  update stores set owner_id = v_user where id = p_store and owner_id is null;
  if not found then raise exception 'Mağaza tapılmadı və ya artıq sahibi var.'; end if;
end
$fn$;

-- =====================================================================
-- 13. FUNKSİYA İCAZƏLƏRİ
-- =====================================================================
do $c$
declare f record;
begin
  -- Yalnız daxil olmuş istifadəçilər (anonim alıcı da "authenticated"dır)
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any (array[
      'get_my_role', 'get_my_store', 'register_store', 'update_my_store',
      'create_request', 'cancel_request', 'accept_bid', 'get_deal_contact',
      'report_deal_failed', 'confirm_deal',
      'submit_bid', 'seller_feed', 'seller_closed_feed', 'seller_my_bids',
      'expire_requests',
      'admin_dashboard', 'admin_list_stores', 'admin_adjust_coins',
      'admin_set_verified', 'admin_assign_store_owner',
      'is_admin', 'my_store_id', 'owns_request'])
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;

  -- Daxili funksiyalar: API-dən heç kim çağıra bilməz
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any (array[
      '_coin_move', '_notify', '_recompute_store_rating', '_close_request',
      '_clean_text_array', 'cfg', 'normalize_az_phone', 'bid_note_is_clean', 'brand_matches'])
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end
$c$;

-- =====================================================================
-- 14. MARKALAR, REALTIME, STORAGE, CRON
-- =====================================================================
insert into public.car_brands (name) values
  ('Chery'), ('BYD'), ('Geely'), ('Haval'), ('Changan'), ('JAC'), ('Suzuki'), ('Mini')
on conflict (name) do nothing;

-- Köhnə telefonları vahid formata gətir (wa.me linkləri işləsin)
update public.stores set phone = public.normalize_az_phone(phone)
  where public.normalize_az_phone(phone) is not null and phone <> public.normalize_az_phone(phone);

do $c$
begin
  begin alter publication supabase_realtime add table public.in_app_notifications;
  exception when others then null; end;
  begin alter publication supabase_realtime add table public.requests;
  exception when others then null; end;
  begin alter publication supabase_realtime add table public.bids;
  exception when others then null; end;
end
$c$;

-- Şəkil yükləmə: yalnız daxil olmuş istifadəçi, öz qovluğuna; yalnız şəkil faylları, maks. 3 MB
do $c$
begin
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('part-images', 'part-images', true, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do update set
    public = true,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

  drop policy if exists "anon_read_part_images" on storage.objects;
  drop policy if exists "anon_upload_part_images" on storage.objects;
  drop policy if exists part_images_upload on storage.objects;
  drop policy if exists part_images_delete on storage.objects;

  create policy part_images_upload on storage.objects
    for insert to authenticated
    with check (bucket_id = 'part-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
  create policy part_images_delete on storage.objects
    for delete to authenticated
    using (bucket_id = 'part-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
exception when others then
  raise notice 'Storage siyasətləri qurulmadı: %', sqlerrm;
end
$c$;

-- Vaxt bitməsi: pg_cron varsa hər dəqiqə (yoxdursa tətbiq expire_requests()-i özü çağırır)
do $c$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('autotender-expire-requests', '* * * * *', 'select public.expire_requests()');
exception when others then
  raise notice 'pg_cron aktiv deyil, tətbiq özü expire_requests() çağıracaq: %', sqlerrm;
end
$c$;
