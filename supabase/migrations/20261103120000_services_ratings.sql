/* =====================================================================
   AutoTender — 4-cü migration: Usta / servis xidməti və mağaza reytinqi
   ƏVVƏL 1, 2 və 3-cü migration işləməlidir. Təkrar işlətmək təhlükəsizdir.

   - Sorğu iki növ olur: 'part' (ehtiyat hissəsi) və 'service' (usta / servis xidməti).
   - Xidmət təchizatçısı: 'shop' (mağaza), 'service_center' (servis), 'master' (usta).
   - Xidmət sorğusu: kateqoriya, şəhər/rayon, "yerində gəlsin", "servis / usta / fərqi yoxdur".
   - Təchizatçı yalnız öz kateqoriya, şəhər, marka və növünə uyğun sorğuları görür.
   - Hər "razılaşma alınmadı" mağaza reytinqini aşağı salır (yarım çəkili 1 ulduz).
   ===================================================================== */

-- =====================================================================
-- 1. Sxem
-- =====================================================================
alter table public.stores add column if not exists provider_type text not null default 'shop';
alter table public.stores add column if not exists offerings text[] not null default '{parts}';
alter table public.stores add column if not exists service_categories text[] not null default '{}';
alter table public.stores add column if not exists cities text[] not null default '{}';
alter table public.stores add column if not exists mobile_service boolean not null default false;

alter table public.requests add column if not exists request_type text not null default 'part';
alter table public.requests add column if not exists city text;
alter table public.requests add column if not exists area text;
alter table public.requests add column if not exists on_site boolean not null default false;
alter table public.requests add column if not exists provider_pref text not null default 'any';

alter table public.bids add column if not exists eta_hours integer;
alter table public.bids add column if not exists images text[] not null default '{}';
alter table public.bids add column if not exists price_type text not null default 'fixed';

do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'stores_provider_type_chk') then
    alter table public.stores add constraint stores_provider_type_chk check (provider_type in ('shop', 'service_center', 'master'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'requests_type_chk') then
    alter table public.requests add constraint requests_type_chk check (request_type in ('part', 'service'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'requests_pref_chk') then
    alter table public.requests add constraint requests_pref_chk check (provider_pref in ('any', 'service_center', 'master'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bids_price_type_chk') then
    alter table public.bids add constraint bids_price_type_chk check (price_type in ('fixed', 'from'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bids_eta_chk') then
    alter table public.bids add constraint bids_eta_chk check (eta_hours is null or eta_hours between 1 and 2000);
  end if;
  -- xidmət təklifi üçün 'service' vəziyyəti
  alter table public.bids drop constraint if exists bids_condition_chk;
  alter table public.bids add constraint bids_condition_chk check (condition in ('original', 'analog', 'used', 'service'));
end
$c$;

create index if not exists requests_type_idx on public.requests (request_type, status, expires_at);

-- Alıcıya mağaza kartında göstərilən yeni açıq sütunlar
grant select (provider_type, mobile_service) on public.stores to anon, authenticated;

-- =====================================================================
-- 2. Sabitlər və uyğunluq qaydası
-- =====================================================================
create or replace function public.valid_service_categories()
returns text[] language sql immutable as $fn$
  select array['diagnostics', 'engine', 'chassis', 'electrical', 'body', 'ac', 'tires', 'maintenance', 'detailing', 'towing']
$fn$;

create or replace function public.valid_cities()
returns text[] language sql immutable as $fn$
  select array['Bakı', 'Sumqayıt', 'Gəncə', 'Mingəçevir', 'Lənkəran', 'Şəki', 'Naxçıvan', 'Digər']
$fn$;

-- Sorğu bu təchizatçıya aid edilirmi? (lent, arxiv və bildirişlər üçün vahid qayda)
create or replace function public.request_matches_store(p_request uuid, p_store uuid)
returns boolean language sql stable security definer set search_path = public as $fn$
  select coalesce((
    select case
      when r.request_type = 'part' then
        'parts' = any (s.offerings) and brand_matches(s.supported_brands, r.brand)
      else
        'service' = any (s.offerings)
        and brand_matches(s.supported_brands, r.brand)
        and r.category = any (s.service_categories)
        and r.city = any (s.cities)
        and (r.provider_pref = 'any'
             or (r.provider_pref = 'master' and s.provider_type = 'master')
             or (r.provider_pref = 'service_center' and s.provider_type in ('service_center', 'shop')))
        and (not r.on_site or s.mobile_service)
      end
    from requests r, stores s
    where r.id = p_request and s.id = p_store), false)
$fn$;

-- Şəkil ünvanlarını yoxlayır: https, öz qovluğu (<user_id>/...), maks. p_max ədəd
create or replace function public._check_images(p_imgs text[], p_uid uuid, p_max integer)
returns text[] language plpgsql immutable as $fn$
declare v text[] := coalesce(p_imgs, '{}'); i integer;
begin
  if cardinality(v) > p_max then raise exception 'Ən çox % şəkil əlavə etmək olar.', p_max; end if;
  for i in 1 .. coalesce(cardinality(v), 0) loop
    if v[i] !~ '^https://' or length(v[i]) > 500 or position(p_uid::text in v[i]) = 0 then
      raise exception 'Şəkil ünvanı düzgün deyil.';
    end if;
  end loop;
  return v;
end
$fn$;

-- =====================================================================
-- 3. Təchizatçı profili
-- =====================================================================
create or replace function public.update_provider_profile(
  p_provider_type text, p_offerings text[], p_service_categories text[], p_cities text[], p_mobile boolean)
returns void language plpgsql security definer set search_path = public as $fn$
declare
  v_off text[] := _clean_text_array(p_offerings, 2, 10);
  v_cat text[] := _clean_text_array(p_service_categories, 12, 20);
  v_cit text[] := _clean_text_array(p_cities, 10, 20);
begin
  if auth.uid() is null then raise exception 'Daxil olmaq lazımdır.'; end if;
  if p_provider_type is null or p_provider_type not in ('shop', 'service_center', 'master') then
    raise exception 'Təchizatçı növünü seçin (mağaza / servis / usta).';
  end if;
  if cardinality(v_off) = 0 or not (v_off <@ array['parts', 'service']) then
    raise exception 'Nə təklif etdiyinizi seçin (ehtiyat hissəsi və/ya xidmət).';
  end if;
  if 'service' = any (v_off) then
    if cardinality(v_cat) = 0 or not (v_cat <@ valid_service_categories()) then
      raise exception 'Xidmət kateqoriyalarını seçin.';
    end if;
    if cardinality(v_cit) = 0 or not (v_cit <@ valid_cities()) then
      raise exception 'Xidmət göstərdiyiniz şəhər(lər)i seçin.';
    end if;
  else
    v_cat := '{}'; v_cit := '{}';
  end if;
  update stores set provider_type = p_provider_type, offerings = v_off,
         service_categories = v_cat, cities = v_cit,
         mobile_service = coalesce(p_mobile, false) and 'service' = any (v_off)
   where owner_id = auth.uid();
  if not found then raise exception 'Mağaza profili tapılmadı.'; end if;
end
$fn$;

-- =====================================================================
-- 4. Xidmət sorğusu (alıcı)
-- =====================================================================
create or replace function public.create_service_request(
  p_category text, p_title text, p_brand text, p_model text, p_year integer,
  p_city text, p_area text, p_on_site boolean, p_provider_pref text,
  p_urgency text, p_budget numeric, p_images text[] default '{}')
returns uuid language plpgsql security definer set search_path = public as $fn$
declare
  u uuid := auth.uid();
  v_title text := btrim(coalesce(p_title, ''));
  v_model text := btrim(coalesce(p_model, ''));
  v_area text := nullif(btrim(coalesce(p_area, '')), '');
  v_hours integer;
  v_imgs text[] := coalesce(p_images, '{}');
  v_id uuid;
  i integer;
begin
  if u is null then raise exception 'Sessiya tapılmadı. Səhifəni yeniləyin.'; end if;
  if p_category is null or not (p_category = any (valid_service_categories())) then
    raise exception 'Xidmət növünü seçin.';
  end if;
  if length(v_title) < 3 or length(v_title) > 120 then raise exception 'Nə lazım olduğunu qısa yazın.'; end if;
  if not exists (select 1 from car_brands where name = p_brand) then raise exception 'Avtomobilin markasını seçin.'; end if;
  if length(v_model) < 1 or length(v_model) > 40 then raise exception 'Modeli qeyd edin.'; end if;
  if p_year is not null and (p_year < 1950 or p_year > extract(year from now())::int + 1) then
    raise exception 'İl düzgün deyil.';
  end if;
  if p_city is null or not (p_city = any (valid_cities())) then raise exception 'Şəhəri seçin.'; end if;
  if v_area is not null and length(v_area) > 40 then raise exception 'Rayon/ərazi çox uzundur.'; end if;
  if p_provider_pref is null or p_provider_pref not in ('any', 'service_center', 'master') then
    raise exception 'Servis və ya usta seçimi düzgün deyil.';
  end if;
  v_hours := case p_urgency when 'express' then 1 when 'standard' then 6 when 'wide' then 24 else null end;
  if v_hours is null then raise exception 'Müddət düzgün deyil.'; end if;
  if p_budget is not null and (p_budget <= 0 or p_budget > 1000000) then raise exception 'Büdcə düzgün deyil.'; end if;
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

  insert into requests (owner_id, buyer_tag, request_type, brand, model, year, part_name, part_images,
                        category, urgency, budget_azn, status, expires_at, city, area, on_site, provider_pref)
  values (u, 'Sürücü #' || (floor(random() * 9000) + 1000)::int, 'service', p_brand, v_model, p_year, v_title,
          v_imgs, p_category, p_urgency, p_budget, 'active', now() + v_hours * interval '1 hour',
          p_city, v_area, coalesce(p_on_site, false), p_provider_pref)
  returning id into v_id;

  insert into in_app_notifications (target_type, target_id, user_id, kind, title, body, request_id)
  select 'seller', s.owner_id, s.owner_id, 'new_request',
         'Yeni xidmət sorğusu: ' || p_brand || ' ' || v_model, v_title || ' · ' || p_city, v_id
  from stores s
  where s.owner_id is not null and s.owner_id <> u and not s.suspended
    and s.coin_balance >= bid_fee_for(s.id)
    and request_matches_store(v_id, s.id);

  return v_id;
end
$fn$;

-- =====================================================================
-- 5. Xidmət təklifi (usta / servis)
-- =====================================================================
drop function if exists public.submit_service_bid(uuid, numeric, text, integer, text, text);
create or replace function public.submit_service_bid(
  p_request_id uuid, p_price numeric, p_price_type text, p_eta_hours integer,
  p_warranty text, p_note text default null, p_images text[] default '{}')
returns uuid language plpgsql security definer set search_path = public as $fn$
declare
  u uuid := auth.uid();
  v_imgs text[];
  v_store stores%rowtype;
  r requests%rowtype;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_warranty text := btrim(coalesce(p_warranty, ''));
  v_bid uuid;
  v_fee numeric;
begin
  if u is null then raise exception 'Daxil olmaq lazımdır.'; end if;
  select * into v_store from stores where owner_id = u for update;
  if not found then raise exception 'Təklif vermək üçün profil lazımdır.'; end if;
  if v_store.suspended then raise exception 'Hesabınız müvəqqəti dayandırılıb. Dəstək ilə əlaqə saxlayın.'; end if;

  select * into r from requests where id = p_request_id for update;
  if not found then raise exception 'Sorğu tapılmadı.'; end if;
  if r.request_type <> 'service' then raise exception 'Bu ehtiyat hissəsi sorğusudur.'; end if;
  if r.owner_id = u then raise exception 'Öz sorğunuza təklif verə bilməzsiniz.'; end if;
  if r.status <> 'active' or r.expires_at <= now() then raise exception 'Bu sorğu artıq bağlanıb.'; end if;
  if not request_matches_store(r.id, v_store.id) then
    raise exception 'Bu sorğu profilinizə uyğun deyil (kateqoriya, şəhər və ya növ).';
  end if;
  if p_price is null or p_price <= 0 or p_price > 1000000 then raise exception 'Qiyməti düzgün qeyd edin.'; end if;
  if p_price_type is null or p_price_type not in ('fixed', 'from') then raise exception 'Qiymət növünü seçin.'; end if;
  if p_eta_hours is null or p_eta_hours < 1 or p_eta_hours > 2000 then raise exception 'İş müddətini seçin.'; end if;
  if v_warranty = '' then v_warranty := 'Zəmanətsiz'; end if;
  if length(v_warranty) > 40 then raise exception 'Zəmanət mətni çox uzundur.'; end if;
  if v_note is not null and length(v_note) > 300 then raise exception 'Qeyd 300 simvolu keçməməlidir.'; end if;
  if v_note is not null and not bid_note_is_clean(v_note) then
    raise exception 'Qeydə telefon nömrəsi və ya əlaqə yönləndirməsi yazmaq olmaz. Əlaqə məlumatları təklif qəbul ediləndən sonra açılır.';
  end if;
  v_imgs := _check_images(p_images, u, 3);
  if exists (select 1 from bids where request_id = r.id and store_id = v_store.id) then
    raise exception 'Bu sorğuya artıq təklif göndərmisiniz.';
  end if;
  if (select count(*) from bids where request_id = r.id) >= cfg('bid_limit', 5) then
    raise exception 'Bu sorğu üçün təklif limiti dolub.';
  end if;
  v_fee := bid_fee_for(v_store.id);
  if v_store.coin_balance < v_fee then
    raise exception 'Kifayət qədər coin yoxdur. "Hesab" bölməsindən coin ala bilərsiniz.';
  end if;

  insert into bids (request_id, store_id, price_azn, condition, warranty, note, status, fee_paid, price_type, eta_hours, images)
  values (r.id, v_store.id, p_price, 'service', v_warranty, v_note, 'pending', v_fee, p_price_type, p_eta_hours, v_imgs)
  returning id into v_bid;
  perform _coin_move(v_store.id, -v_fee, 'BID_FEE', r.id, v_bid, null);

  perform _notify(r.owner_id, 'buyer', 'new_bid', 'Yeni təklif gəldi',
    trim(coalesce(r.brand, '') || ' ' || coalesce(r.model, '')) || ' — ' || r.part_name ||
    ': ' || case when p_price_type = 'from' then 'dən ' else '' end || p_price::numeric(12, 0) || ' AZN', r.id);
  return v_bid;
end
$fn$;

-- =====================================================================
-- 6. Lent, arxiv, təkliflərim (hər iki növ)
-- =====================================================================
drop function if exists public.seller_feed();
create or replace function public.seller_feed()
returns table (
  id uuid, request_type text, buyer_tag text, brand text, model text, year integer, vin text, part_name text,
  part_images text[], category text, urgency text, budget_azn numeric,
  city text, area text, on_site boolean, provider_pref text,
  expires_at timestamptz, created_at timestamptz,
  bid_count integer, slots_full boolean, my_bid_id uuid)
language sql stable security definer set search_path = public as $fn$
  with s as (select * from public.stores where owner_id = auth.uid() and not suspended),
  x as (
    select r.*,
      (select count(*) from public.bids b where b.request_id = r.id)::integer as n,
      (select b.id from public.bids b where b.request_id = r.id and b.store_id = s.id) as mine
    from public.requests r, s
    where r.status = 'active' and r.expires_at > now()
      and r.owner_id is distinct from auth.uid()
      and public.request_matches_store(r.id, s.id)
  )
  select x.id, x.request_type, x.buyer_tag, x.brand, x.model, x.year, x.vin, x.part_name, x.part_images,
         x.category, x.urgency, x.budget_azn, x.city, x.area, x.on_site, x.provider_pref,
         x.expires_at, x.created_at,
         x.n, x.n >= public.cfg('bid_limit', 5), x.mine
  from x
  where x.n < public.cfg('bid_limit', 5) or x.mine is not null
  order by x.created_at desc
  limit 100
$fn$;

drop function if exists public.seller_closed_feed();
create or replace function public.seller_closed_feed()
returns table (
  id uuid, request_type text, brand text, model text, year integer, part_name text, category text, urgency text,
  budget_azn numeric, city text, status text, created_at timestamptz, expires_at timestamptz,
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
      and public.request_matches_store(r.id, s.id)
  )
  select x.id, x.request_type, x.brand, x.model, x.year, x.part_name, x.category, x.urgency, x.budget_azn, x.city,
         x.status, x.created_at, x.expires_at, x.n, x.mine,
         (select b.price_azn from public.bids b where b.id = x.accepted_bid_id and x.status = 'completed')
  from x
  where x.status in ('expired', 'completed', 'cancelled')
     or (x.status = 'active' and (x.expires_at <= now() or x.n >= public.cfg('bid_limit', 5)))
  order by x.created_at desc
  limit 100
$fn$;

drop function if exists public.seller_my_bids();
create or replace function public.seller_my_bids()
returns table (
  bid_id uuid, request_id uuid, request_type text, price_azn numeric, price_type text, eta_hours integer,
  condition text, warranty text, note text,
  bid_status text, deal_status text, bid_created_at timestamptz,
  brand text, model text, year integer, part_name text, category text, city text,
  request_status text, request_expires_at timestamptz,
  winning_price numeric, winning_warranty text, price_difference numeric)
language sql stable security definer set search_path = public as $fn$
  with s as (select * from public.stores where owner_id = auth.uid())
  select b.id, b.request_id, r.request_type, b.price_azn, b.price_type, b.eta_hours,
         b.condition, b.warranty, b.note,
         b.status, b.deal_status, b.created_at,
         r.brand, r.model, r.year, r.part_name, r.category, r.city,
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
-- 7. Reytinq: "razılaşma alınmadı" reytinqi aşağı salır
-- =====================================================================
create or replace function public._recompute_store_rating(p_store uuid)
returns void language plpgsql security definer set search_path = public as $fn$
declare v_sum numeric; v_cnt integer; v_failed integer; v_avg numeric;
begin
  select coalesce(sum(stars), 0), count(*) into v_sum, v_cnt from store_reviews where store_id = p_store;
  select failed_deals into v_failed from stores where id = p_store;
  v_failed := coalesce(v_failed, 0);
  if v_failed = 0 then
    v_avg := case when v_cnt = 0 then 5.0 else round(v_sum / v_cnt, 1) end;
  else
    -- Hər uğursuz razılaşma yarım çəkili 1 ulduz sayılır; yeni mağaza bir şikayətlə
    -- çökməsin deyə hesaba 2 neytral (5 ulduz) başlanğıc rəy əlavə olunur.
    v_avg := round((v_sum + 5.0 * 2 + 0.5 * v_failed) / (v_cnt + 2 + 0.5 * v_failed), 1);
  end if;
  update stores set
    rating = v_avg,
    review_count = v_cnt,
    grade = case
      when v_cnt >= 5 and v_avg >= 4.7 then 'A+'
      when v_cnt + v_failed >= 3 and v_avg < 4.0 then 'B'
      else 'A' end
  where id = p_store;
end
$fn$;

create or replace function public.admin_set_failed_deals(p_store uuid, p_count integer)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  if p_count is null or p_count < 0 or p_count > 1000 then raise exception 'Say düzgün deyil.'; end if;
  update stores set failed_deals = p_count where id = p_store;
  if not found then raise exception 'Mağaza tapılmadı.'; end if;
  perform _recompute_store_rating(p_store);
end
$fn$;

-- =====================================================================
-- 8. Ehtiyat hissəsi təklifi / sorğusu (növ yoxlaması + şəkil) və uğursuz razılaşma
-- =====================================================================
drop function if exists public.submit_bid(uuid, numeric, text, text, text);
create or replace function public.submit_bid(
  p_request_id uuid, p_price numeric, p_condition text, p_warranty text, p_note text default null, p_images text[] default '{}')
returns uuid language plpgsql security definer set search_path = public as $fn$
declare
  u uuid := auth.uid();
  v_sid uuid;
  v_store stores%rowtype;
  r requests%rowtype;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_warranty text := btrim(coalesce(p_warranty, ''));
  v_bid uuid;
  v_fee numeric;
  v_imgs text[];
begin
  if u is null then raise exception 'Daxil olmaq lazımdır.'; end if;
  select id into v_sid from stores where owner_id = u;
  if v_sid is null then raise exception 'Təklif vermək üçün mağaza profili lazımdır.'; end if;

  select * into r from requests where id = p_request_id for update;
  if not found then raise exception 'Sorğu tapılmadı.'; end if;
  select * into v_store from stores where id = v_sid for update;
  if v_store.suspended then
    raise exception 'Hesabınız müvəqqəti dayandırılıb. Dəstək ilə əlaqə saxlayın.';
  end if;

  if r.owner_id = u then raise exception 'Öz sorğunuza təklif verə bilməzsiniz.'; end if;
  if r.status <> 'active' or r.expires_at <= now() then raise exception 'Bu sorğu artıq bağlanıb.'; end if;
  if r.request_type <> 'part' then raise exception 'Bu xidmət sorğusudur. Xidmət təklifi formasından istifadə edin.'; end if;
  if not ('parts' = any (v_store.offerings)) then
    raise exception 'Profilinizdə ehtiyat hissəsi satışı seçilməyib.';
  end if;
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
  v_imgs := _check_images(p_images, u, 3);
  if exists (select 1 from bids where request_id = r.id and store_id = v_store.id) then
    raise exception 'Bu sorğuya artıq təklif göndərmisiniz.';
  end if;
  if (select count(*) from bids where request_id = r.id) >= cfg('bid_limit', 5) then
    raise exception 'Bu sorğu üçün təklif limiti dolub.';
  end if;
  v_fee := bid_fee_for(v_store.id);
  if v_store.coin_balance < v_fee then
    raise exception 'Kifayət qədər coin yoxdur. "Hesab" bölməsindən coin ala bilərsiniz.';
  end if;

  insert into bids (request_id, store_id, price_azn, condition, warranty, note, status, fee_paid, images)
  values (r.id, v_store.id, p_price, p_condition, v_warranty, v_note, 'pending', v_fee, v_imgs)
  returning id into v_bid;

  perform _coin_move(v_store.id, -v_fee, 'BID_FEE', r.id, v_bid, null);

  perform _notify(r.owner_id, 'buyer', 'new_bid', 'Yeni təklif gəldi',
    trim(coalesce(r.brand, '') || ' ' || coalesce(r.model, '')) || ' — ' || r.part_name ||
    ': ' || p_price::numeric(12, 0) || ' AZN', r.id);
  return v_bid;
end
$fn$;

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
    and not s.suspended
    and s.coin_balance >= bid_fee_for(s.id)
    and 'parts' = any (s.offerings)
    and brand_matches(s.supported_brands, p_brand)
    and (cardinality(s.categories) = 0 or p_category is null or p_category = any (s.categories));

  return v_id;
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
  perform _recompute_store_rating(b.store_id);
  update requests set status = 'active', accepted_bid_id = null, deal_status = 'failed',
         expires_at = now() + cfg('reopen_hours', 6) * interval '1 hour'
    where id = r.id;

  select owner_id into v_owner from stores where id = b.store_id;
  perform _notify(v_owner, 'seller', 'deal_failed', 'Razılaşma alınmadı',
    trim(coalesce(r.brand, '') || ' ' || coalesce(r.model, '')) || ' — ' || r.part_name ||
    '. Sorğu alıcı üçün yenidən açıldı.', r.id);
end
$fn$;

-- =====================================================================
-- 9. Bazar analizi yalnız ehtiyat hissəsi sorğularını sayır
-- =====================================================================
create or replace function public.seller_insights()
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare
  s stores%rowtype;
  v_plan text; v_level integer;
  v_since timestamptz := now() - interval '30 days';
  v_out jsonb; v_market jsonb; v_pro jsonb;
  v_cat jsonb; v_brand jsonb; v_parts jsonb; v_hours jsonb; v_price jsonb; v_gap jsonb; v_opp jsonb; v_speed jsonb;
begin
  select * into s from stores where owner_id = auth.uid();
  if not found then raise exception 'Mağaza profili tapılmadı.'; end if;
  v_plan := effective_plan(s.id);
  v_level := plan_rank(v_plan);

  v_out := jsonb_build_object(
    'plan', v_plan, 'level', v_level,
    'teaser', jsonb_build_object(
      'requests_30d', (select count(*) from requests r
                        where r.created_at >= v_since and r.owner_id is distinct from s.owner_id
                          and r.request_type = 'part' and brand_matches(s.supported_brands, r.brand)),
      'completed_30d', (select count(*) from requests r
                         where r.created_at >= v_since and r.status = 'completed' and r.owner_id is distinct from s.owner_id
                           and r.request_type = 'part' and brand_matches(s.supported_brands, r.brand))));

  if v_level >= 1 then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.requests desc), '[]'::jsonb) into v_cat from (
      select coalesce(r.category, 'other') as category,
             count(*)::integer as requests,
             round(avg(nb.n)::numeric, 1) as avg_bids,
             case when count(wb.id) >= 3 then round(avg(wb.price_azn), 0) end as avg_win_price,
             (count(*) filter (where nb.n = 0))::integer as no_bid_requests,
             count(mb.id)::integer as my_bids,
             (count(*) filter (where wb.store_id = s.id))::integer as my_wins
      from requests r
      left join lateral (select count(*) as n from bids b where b.request_id = r.id) nb on true
      left join bids wb on wb.id = r.accepted_bid_id and r.status = 'completed'
      left join bids mb on mb.request_id = r.id and mb.store_id = s.id
      where r.created_at >= v_since and r.owner_id is distinct from s.owner_id
        and r.request_type = 'part' and brand_matches(s.supported_brands, r.brand)
      group by 1) t;

    select coalesce(jsonb_agg(to_jsonb(t) order by t.requests desc), '[]'::jsonb) into v_brand from (
      select r.brand,
             count(*)::integer as requests,
             case when count(wb.id) >= 3 then round(avg(wb.price_azn), 0) end as avg_win_price,
             count(mb.id)::integer as my_bids
      from requests r
      left join bids wb on wb.id = r.accepted_bid_id and r.status = 'completed'
      left join bids mb on mb.request_id = r.id and mb.store_id = s.id
      where r.created_at >= v_since and r.owner_id is distinct from s.owner_id
        and r.request_type = 'part' and brand_matches(s.supported_brands, r.brand)
      group by r.brand order by count(*) desc limit 8) t;

    v_market := jsonb_build_object('by_category', v_cat, 'by_brand', v_brand);
    v_out := v_out || jsonb_build_object('market', v_market);
  end if;

  if v_level >= 2 then
    select coalesce(jsonb_agg(to_jsonb(t) order by t.requests desc), '[]'::jsonb) into v_parts from (
      select lower(btrim(r.part_name)) as part,
             count(*)::integer as requests,
             case when count(wb.id) >= 3 then round(avg(wb.price_azn), 0) end as avg_win_price,
             case when count(wb.id) >= 3 then round(min(wb.price_azn), 0) end as min_win_price,
             case when count(wb.id) >= 3 then round(max(wb.price_azn), 0) end as max_win_price
      from requests r
      left join bids wb on wb.id = r.accepted_bid_id and r.status = 'completed'
      where r.created_at >= v_since and r.owner_id is distinct from s.owner_id
        and r.request_type = 'part' and brand_matches(s.supported_brands, r.brand)
      group by 1 having count(*) >= 2
      order by count(*) desc limit 10) t;

    select coalesce(jsonb_agg(coalesce(c.n, 0) order by h), '[]'::jsonb) into v_hours
    from generate_series(0, 23) h
    left join (
      select extract(hour from r.created_at at time zone 'Asia/Baku')::integer as hr, count(*)::integer as n
      from requests r
      where r.created_at >= v_since and r.owner_id is distinct from s.owner_id
        and r.request_type = 'part' and brand_matches(s.supported_brands, r.brand)
      group by 1) c on c.hr = h;

    -- Mənim qiymət mövqeyim (yalnız öz təkliflərim və qalibin qiyməti)
    select jsonb_build_object(
        'wins', count(*) filter (where mb.status = 'accepted'),
        'losses', count(*) filter (where mb.status = 'rejected' and wb.id is not null),
        'avg_gap_azn', round(avg(mb.price_azn - wb.price_azn) filter (where mb.status = 'rejected' and wb.id is not null), 1),
        'avg_gap_pct', round(avg((mb.price_azn / wb.price_azn - 1) * 100) filter (where mb.status = 'rejected' and wb.id is not null), 0))
      into v_price
    from bids mb
    join requests r on r.id = mb.request_id
    left join bids wb on wb.id = r.accepted_bid_id and wb.id <> mb.id and r.status = 'completed'
    where mb.store_id = s.id and mb.created_at >= v_since;

    select coalesce(jsonb_agg(to_jsonb(t) order by t.losses desc), '[]'::jsonb) into v_gap from (
      select coalesce(r.category, 'other') as category,
             (count(*) filter (where mb.status = 'accepted'))::integer as wins,
             (count(*) filter (where mb.status = 'rejected' and wb.id is not null))::integer as losses,
             round(avg((mb.price_azn / wb.price_azn - 1) * 100)
                   filter (where mb.status = 'rejected' and wb.id is not null), 0) as avg_gap_pct
      from bids mb
      join requests r on r.id = mb.request_id
      left join bids wb on wb.id = r.accepted_bid_id and wb.id <> mb.id and r.status = 'completed'
      where mb.store_id = s.id and mb.created_at >= v_since
      group by 1) t;

    -- Cavabsız qalan tələb (fürsət): son 7 gün, mənim markalarım, 0 təklif
    select coalesce(jsonb_agg(to_jsonb(t) order by t.requests desc), '[]'::jsonb) into v_opp from (
      select r.brand, count(*)::integer as requests
      from requests r
      where r.created_at >= now() - interval '7 days' and r.owner_id is distinct from s.owner_id
        and r.status in ('expired', 'active') and r.expires_at <= now()
        and not exists (select 1 from bids b where b.request_id = r.id)
        and r.request_type = 'part' and brand_matches(s.supported_brands, r.brand)
      group by r.brand order by count(*) desc limit 5) t;

    -- Cavab sürəti: mənim median vaxtım vs. qalib təkliflərin median vaxtı (dəqiqə)
    select jsonb_build_object(
        'my_median_min', (select round((percentile_cont(0.5) within group (order by extract(epoch from (mb.created_at - r.created_at)) / 60))::numeric, 0)
                          from bids mb join requests r on r.id = mb.request_id
                          where mb.store_id = s.id and mb.created_at >= v_since),
        'winner_median_min', (select case when count(*) >= 5 then
                                round((percentile_cont(0.5) within group (order by extract(epoch from (wb.created_at - r.created_at)) / 60))::numeric, 0) end
                              from requests r join bids wb on wb.id = r.accepted_bid_id
                              where r.status = 'completed' and r.created_at >= v_since
                                and r.request_type = 'part' and brand_matches(s.supported_brands, r.brand)))
      into v_speed;

    v_pro := jsonb_build_object(
      'top_parts', v_parts, 'hourly', v_hours, 'price_position', v_price,
      'by_category_position', v_gap, 'unanswered_7d', v_opp, 'response_speed', v_speed);
    v_out := v_out || jsonb_build_object('pro', v_pro);
  end if;

  return v_out;
end
$fn$;

-- =====================================================================
-- 10. İcazələr
-- =====================================================================
do $c$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any (array[
      'update_provider_profile', 'create_service_request', 'submit_service_bid', 'submit_bid',
      'create_request', 'seller_feed', 'seller_closed_feed', 'seller_my_bids', 'seller_insights',
      'admin_set_failed_deals', 'report_deal_failed'])
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any (array[
      '_check_images', 'request_matches_store', 'valid_service_categories', 'valid_cities',
      '_recompute_store_rating'])
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end
$c$;

-- Mövcud mağazalar üçün reytinqi yenidən hesabla (uğursuz razılaşmalar nəzərə alınsın)
do $c$
declare s record;
begin
  for s in select id from stores loop
    perform _recompute_store_rating(s.id);
  end loop;
end
$c$;
