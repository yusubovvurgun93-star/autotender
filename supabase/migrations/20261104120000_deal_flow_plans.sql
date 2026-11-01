/* =====================================================================
   AutoTender — 5-ci migration: razılaşma alınmayanda yeni qayda, plan hədiyyə coin, bonus 2 coin
   ƏVVƏL 1, 2, 3 və 4-cü migration işləməlidir. Təkrar işlətmək təhlükəsizdir.

   - Tender qalibi bonusu 2 coin olur.
   - Plus: hər aylıq alışda 30 hədiyyə coin (billing_catalog.coins). Pro: 39 AZN.
   - "Razılaşma alınmadı": başqa təklif qalıbsa sorğu satıcılara bağlı qalır (sealed),
     alıcı yalnız əvvəl təklif vermiş mağazalardan seçir. Qalmayıbsa sorğu yenidən hamıya açılır.
   - Son 30 gündə 3 və daha çox uğursuz razılaşma olan mağaza barədə admin bildiriş alır.
   ===================================================================== */

insert into public.app_config (key, value) values ('rechoose_hours', 24)
on conflict (key) do nothing;
update public.app_config set value = 2 where key = 'sale_bonus';

update public.billing_catalog set coins = 30 where key = 'plan_plus_30';
update public.billing_catalog set price_azn = 39 where key = 'plan_pro_30';

alter table public.requests add column if not exists sealed boolean not null default false;
alter table public.bids add column if not exists deal_failed_at timestamptz;
create index if not exists bids_failed_idx on public.bids (store_id, deal_failed_at) where deal_failed_at is not null;

-- =====================================================================
-- Razılaşma alınmadı
-- =====================================================================
create or replace function public.report_deal_failed(p_request_id uuid)
returns void language plpgsql security definer set search_path = public as $fn$
declare
  r requests%rowtype; b bids%rowtype; v_owner uuid; v_bonus numeric; v_left integer; v_recent integer;
  v_store_name text; a record;
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

  update bids set status = 'rejected', deal_status = 'failed', deal_failed_at = now() where id = b.id;
  update bids set status = 'pending'
    where request_id = r.id and id <> b.id and status = 'rejected' and deal_status is distinct from 'failed';
  update stores set failed_deals = failed_deals + 1 where id = b.store_id;
  perform _recompute_store_rating(b.store_id);

  select count(*) into v_left from bids where request_id = r.id and status = 'pending';
  if v_left > 0 then
    -- Əvvəl təklif vermiş mağazalar qalıb: sorğu hamıya açılmır, alıcı onlardan seçir
    update requests set status = 'active', accepted_bid_id = null, deal_status = 'failed', sealed = true,
           expires_at = now() + cfg('rechoose_hours', 24) * interval '1 hour'
     where id = r.id;
  else
    -- Başqa təklif yoxdur: sorğu yenidən hamıya açılır
    update requests set status = 'active', accepted_bid_id = null, deal_status = 'failed', sealed = false,
           expires_at = now() + cfg('reopen_hours', 6) * interval '1 hour'
     where id = r.id;
    insert into in_app_notifications (target_type, target_id, user_id, kind, title, body, request_id)
    select 'seller', s.owner_id, s.owner_id, 'new_request',
           'Sorğu yenidən açıldı: ' || coalesce(r.brand, '') || ' ' || coalesce(r.model, ''), r.part_name, r.id
    from stores s
    where s.owner_id is not null and s.owner_id <> r.owner_id and not s.suspended
      and s.coin_balance >= bid_fee_for(s.id)
      and not exists (select 1 from bids x where x.request_id = r.id and x.store_id = s.id)
      and request_matches_store(r.id, s.id);
  end if;

  select owner_id, name into v_owner, v_store_name from stores where id = b.store_id;
  perform _notify(v_owner, 'seller', 'deal_failed', 'Razılaşma alınmadı',
    trim(coalesce(r.brand, '') || ' ' || coalesce(r.model, '')) || ' — ' || r.part_name ||
    '. Reytinqiniz aşağı düşdü, satış bonusu geri alındı.', r.id);

  select count(*) into v_recent from bids
    where store_id = b.store_id and deal_failed_at > now() - interval '30 days';
  if v_recent >= 3 then
    for a in select user_id from admins loop
      perform _notify(a.user_id, 'admin', 'report', 'Mağaza tez-tez razılaşmanı pozur',
        v_store_name || ' — son 30 gündə ' || v_recent || ' uğursuz razılaşma. Yoxlayın.', null);
    end loop;
  end if;
end
$fn$;

-- =====================================================================
-- Lent və təkliflər bağlı sorğuya getmir
-- =====================================================================
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
    where r.status = 'active' and r.expires_at > now() and not r.sealed
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
  if r.sealed then raise exception 'Bu sorğu yeni təkliflər qəbul etmir.'; end if;
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
  if r.sealed then raise exception 'Bu sorğu yeni təkliflər qəbul etmir.'; end if;
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
-- Plan hədiyyə coin və hesab icmalı
-- =====================================================================
create or replace function public.billing_overview()
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare s stores%rowtype;
begin
  select * into s from stores where owner_id = auth.uid();
  if not found then raise exception 'Mağaza profili tapılmadı.'; end if;
  return jsonb_build_object(
    'plan', effective_plan(s.id),
    'plan_until', case when effective_plan(s.id) = 'free' then null else s.plan_until end,
    'coin_balance', s.coin_balance,
    'bid_fee', bid_fee_for(s.id),
    'base_bid_fee', cfg('bid_fee', 1),
    'sale_bonus', cfg('sale_bonus', 2),
    'catalog', coalesce((select jsonb_agg(jsonb_build_object(
        'key', key, 'kind', kind, 'title', title, 'price_azn', price_azn,
        'coins', coins, 'plan', plan, 'days', days) order by sort)
      from billing_catalog where active), '[]'::jsonb),
    'orders', coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at desc) from (
        select id, item_key, kind, title, amount_azn, reference, status, created_at, paid_at
        from payment_orders where store_id = s.id order by created_at desc limit 10) o), '[]'::jsonb));
end
$fn$;

create or replace function public.admin_confirm_order(p_order uuid)
returns void language plpgsql security definer set search_path = public as $fn$
declare o payment_orders%rowtype; s stores%rowtype; v_cur text;
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  select * into o from payment_orders where id = p_order for update;
  if not found then raise exception 'Sifariş tapılmadı.'; end if;
  if o.status = 'paid' then raise exception 'Bu sifariş artıq təsdiqlənib.'; end if;
  select * into s from stores where id = o.store_id for update;

  if o.kind = 'coins' then
    perform _coin_move(s.id, o.coins, 'PURCHASE', null, null, o.title || ' (' || o.reference || ')');
  else
    v_cur := effective_plan(s.id);
    if plan_rank(v_cur) > plan_rank(o.plan) then
      raise exception 'Mağazada daha yüksək plan aktivdir.';
    elsif v_cur = o.plan then
      update stores set plan_until = plan_until + o.days * interval '1 day' where id = s.id;
    else
      update stores set plan = o.plan, plan_until = now() + o.days * interval '1 day' where id = s.id;
    end if;
  end if;

  if o.kind = 'plan' and coalesce(o.coins, 0) > 0 then
    perform _coin_move(s.id, o.coins, 'PLAN_BONUS', null, null, o.title || ' — aylıq hədiyyə coin (' || o.reference || ')');
  end if;

  update payment_orders set status = 'paid', paid_at = now(), confirmed_by = auth.uid() where id = o.id;
  perform _notify(s.owner_id, 'seller', 'payment_confirmed', 'Ödəniş təsdiqləndi',
    o.title || ' hesabınıza əlavə olundu. Təşəkkürlər!', null);
end
$fn$;

-- =====================================================================
-- İcazələr
-- =====================================================================
do $c$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any (array[
      'report_deal_failed', 'seller_feed', 'submit_bid', 'submit_service_bid',
      'billing_overview', 'admin_confirm_order'])
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end
$c$;
