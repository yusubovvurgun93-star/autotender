/* =====================================================================
   AutoTender — 2-ci migration: coin paketləri, Plus/Pro planları, analiz, Telegram
   ---------------------------------------------------------------------
   ƏVVƏL 20261029120000_secure_rewrite.sql işləməlidir. Bu fayl onun üstünə qurulur.
   Təkrar işlətmək təhlükəsizdir.

   Nə edir:
   - Coin yarım hissəli olur (Plus planı təklif haqqını 50% endirir: 0.5 coin).
   - bids.fee_paid: hər təklif üçün real ödənilən haqq saxlanır, vaxt bitəndə məhz o qaytarılır.
   - stores.plan / plan_until: 'free' | 'plus' | 'pro' (vaxtı bitəndə avtomatik 'free').
   - billing_catalog: coin paketləri və planlar (qiymətləri SQL ilə dəyişmək olar).
   - payment_orders: sifariş → satıcı köçürür → admin təsdiqləyir → coin/plan avtomatik verilir.
   - app_texts: ödəniş təlimatı, dəstək WhatsApp nömrəsi, Telegram bot adı (admin paneldən dəyişir).
   - seller_insights(): Plus və Pro üçün bazar analizi (serverdə plan yoxlanır).
   - telegram_links: satıcı/admin Telegram bildirişləri.
   ===================================================================== */

-- =====================================================================
-- 0. Konfiqurasiya
-- =====================================================================
insert into public.app_config (key, value) values
  ('plus_fee_pct', 50),   -- Plus: təklif haqqı bu faiz qədərdir (50 → yarısı)
  ('pro_fee_pct', 0)      -- Pro: təklif pulsuzdur
on conflict (key) do nothing;

-- =====================================================================
-- 1. Sxem: yarım coin, plan, ödənilən haqq
-- =====================================================================
alter table public.stores alter column coin_balance type numeric(10,1) using coin_balance::numeric;
alter table public.coin_ledger alter column amount type numeric(10,1) using amount::numeric;

alter table public.stores add column if not exists plan text not null default 'free';
alter table public.stores add column if not exists plan_until timestamptz;
alter table public.bids add column if not exists fee_paid numeric(10,1);

do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'stores_plan_check') then
    alter table public.stores add constraint stores_plan_check check (plan in ('free', 'plus', 'pro'));
  end if;
end
$c$;

-- =====================================================================
-- 2. Daxili funksiyalar
-- =====================================================================
drop function if exists public._coin_move(uuid, integer, text, uuid, uuid, text);
create or replace function public._coin_move(
  p_store uuid, p_amount numeric, p_type text,
  p_request uuid default null, p_bid uuid default null, p_note text default null)
returns numeric language plpgsql security definer set search_path = public as $fn$
declare v_old numeric; v_new numeric;
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

create or replace function public.effective_plan(p_store uuid)
returns text language sql stable security definer set search_path = public as $fn$
  select coalesce((select case when plan <> 'free' and plan_until is not null and plan_until > now()
                               then plan else 'free' end
                   from stores where id = p_store), 'free')
$fn$;

create or replace function public.plan_rank(p_plan text)
returns integer language sql immutable as $fn$
  select case p_plan when 'pro' then 2 when 'plus' then 1 else 0 end
$fn$;

create or replace function public.bid_fee_for(p_store uuid)
returns numeric language sql stable security definer set search_path = public as $fn$
  select round(cfg('bid_fee', 1)::numeric *
         case effective_plan(p_store)
           when 'pro'  then cfg('pro_fee_pct', 0)
           when 'plus' then cfg('plus_fee_pct', 50)
           else 100 end / 100.0, 1)
$fn$;

-- =====================================================================
-- 3. Dəyişdirilmiş funksiyalar (plan endirimi, faktiki haqqın qaytarılması)
-- =====================================================================
-- Sorğunu bağlayır: gözləyən təkliflər 'expired' olur, ödənilən haqq mağazalara qaytarılır
create or replace function public._close_request(p_request uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $fn$
declare r record; b record; v_owner uuid; v_n integer := 0;
begin
  select owner_id, brand, model, part_name into r from requests where id = p_request;
  for b in select id, store_id, fee_paid from bids where request_id = p_request and status = 'pending' loop
    perform _coin_move(b.store_id, coalesce(b.fee_paid, cfg('bid_fee', 1)), 'REFUND', p_request, b.id, 'Sorğu bağlandı');
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
    and s.coin_balance >= bid_fee_for(s.id)
    and brand_matches(s.supported_brands, p_brand)
    and (cardinality(s.categories) = 0 or p_category is null or p_category = any (s.categories));

  return v_id;
end
$fn$;

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
  v_fee numeric;
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
  v_fee := bid_fee_for(v_store.id);
  if v_store.coin_balance < v_fee then
    raise exception 'Kifayət qədər coin yoxdur. "Hesab" bölməsindən coin ala bilərsiniz.';
  end if;

  insert into bids (request_id, store_id, price_azn, condition, warranty, note, status, fee_paid)
  values (r.id, v_store.id, p_price, p_condition, v_warranty, v_note, 'pending', v_fee)
  returning id into v_bid;

  perform _coin_move(v_store.id, -v_fee, 'BID_FEE', r.id, v_bid, null);

  perform _notify(r.owner_id, 'buyer', 'new_bid', 'Yeni təklif gəldi',
    trim(coalesce(r.brand, '') || ' ' || coalesce(r.model, '')) || ' — ' || r.part_name ||
    ': ' || p_price::numeric(12, 0) || ' AZN', r.id);
  return v_bid;
end
$fn$;

drop function if exists public.admin_adjust_coins(uuid, integer, text);
create or replace function public.admin_adjust_coins(p_store uuid, p_delta numeric, p_note text default null)
returns numeric language plpgsql security definer set search_path = public as $fn$
declare v_moved numeric;
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  if p_delta is null or p_delta = 0 or abs(p_delta) > 1000 then raise exception 'Məbləğ düzgün deyil.'; end if;
  v_moved := _coin_move(p_store, p_delta, 'ADMIN_ADJUST', null, null, left(p_note, 200));
  return (select coin_balance from stores where id = p_store);
end
$fn$;

-- =====================================================================
-- 4. Katalog, mətnlər, sifarişlər
-- =====================================================================
create table if not exists public.billing_catalog (
  key       text primary key,
  kind      text not null check (kind in ('coins', 'plan')),
  title     text not null,
  price_azn numeric(10, 2) not null check (price_azn > 0),
  coins     numeric(10, 1),
  plan      text check (plan in ('plus', 'pro')),
  days      integer,
  active    boolean not null default true,
  sort      integer not null default 0,
  check ((kind = 'coins' and coins > 0) or (kind = 'plan' and plan is not null and days > 0))
);
alter table public.billing_catalog enable row level security;

-- Qiymətlər başlanğıc təklifdir — SQL ilə (update billing_catalog set price_azn = ... where key = ...) dəyişin
insert into public.billing_catalog (key, kind, title, price_azn, coins, plan, days, sort) values
  ('coins_20',     'coins', '20 coin',        10, 20,   null,   null, 10),
  ('coins_50',     'coins', '50 coin',        20, 50,   null,   null, 20),
  ('coins_150',    'coins', '150 coin',       50, 150,  null,   null, 30),
  ('plan_plus_30', 'plan',  'Plus — 30 gün',  19, null, 'plus', 30,   40),
  ('plan_pro_30',  'plan',  'Pro — 30 gün',   49, null, 'pro',  30,   50)
on conflict (key) do nothing;

create table if not exists public.app_texts (
  key   text primary key,
  value text not null default ''
);
alter table public.app_texts enable row level security;
insert into public.app_texts (key, value) values
  ('payment_instructions', 'Sifarişi yaradın, göstərilən kodu ödənişin izahına yazın və dəstəyə WhatsApp-da xəbər verin. Ödəniş təsdiqlənən kimi coin/plan hesabınıza əlavə olunur.'),
  ('support_whatsapp', ''),
  ('telegram_bot_username', '')
on conflict (key) do nothing;

create table if not exists public.payment_orders (
  id           uuid primary key default gen_random_uuid(),
  store_id     uuid not null references public.stores(id) on delete cascade,
  item_key     text not null references public.billing_catalog(key),
  kind         text not null,
  title        text not null,
  amount_azn   numeric(10, 2) not null,
  coins        numeric(10, 1),
  plan         text,
  days         integer,
  reference    text not null unique,
  status       text not null default 'pending' check (status in ('pending', 'paid', 'cancelled')),
  created_at   timestamptz not null default now(),
  paid_at      timestamptz,
  confirmed_by uuid
);
create index if not exists payment_orders_store_idx  on public.payment_orders (store_id, created_at desc);
create index if not exists payment_orders_status_idx on public.payment_orders (status, created_at desc);
alter table public.payment_orders enable row level security;

create table if not exists public.telegram_links (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  chat_id      bigint unique,
  link_code    text unique,
  code_expires timestamptz,
  linked_at    timestamptz,
  created_at   timestamptz not null default now()
);
alter table public.telegram_links enable row level security;

-- Bu cədvəllərə birbaşa giriş yoxdur: yalnız aşağıdakı RPC-lər
revoke all on public.billing_catalog, public.app_texts, public.payment_orders, public.telegram_links
  from anon, authenticated;

do $c$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant select, update on public.telegram_links to service_role;
  end if;
end
$c$;

-- =====================================================================
-- 5. Hesab / ödəniş RPC-ləri (satıcı)
-- =====================================================================
create or replace function public.get_app_texts()
returns jsonb language sql stable security definer set search_path = public as $fn$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from app_texts
$fn$;

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
    'catalog', coalesce((select jsonb_agg(jsonb_build_object(
        'key', key, 'kind', kind, 'title', title, 'price_azn', price_azn,
        'coins', coins, 'plan', plan, 'days', days) order by sort)
      from billing_catalog where active), '[]'::jsonb),
    'orders', coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at desc) from (
        select id, item_key, kind, title, amount_azn, reference, status, created_at, paid_at
        from payment_orders where store_id = s.id order by created_at desc limit 10) o), '[]'::jsonb));
end
$fn$;

create or replace function public.create_payment_order(p_item text)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare
  s stores%rowtype; c billing_catalog%rowtype; v_ref text; v_id uuid; a record; n integer := 0;
begin
  select * into s from stores where owner_id = auth.uid();
  if not found then raise exception 'Mağaza profili tapılmadı.'; end if;
  select * into c from billing_catalog where key = p_item and active;
  if not found then raise exception 'Paket tapılmadı.'; end if;
  if (select count(*) from payment_orders where store_id = s.id and status = 'pending') >= 3 then
    raise exception 'Gözləyən 3 sifarişiniz var. Əvvəlcə onları ödəyin və ya ləğv edin.';
  end if;
  if c.kind = 'plan' and plan_rank(effective_plan(s.id)) > plan_rank(c.plan) then
    raise exception 'Hazırda daha yüksək plan aktivdir.';
  end if;

  loop
    v_ref := 'AT-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from payment_orders where reference = v_ref);
    n := n + 1;
    if n > 10 then raise exception 'Kod yaradıla bilmədi, yenidən cəhd edin.'; end if;
  end loop;

  insert into payment_orders (store_id, item_key, kind, title, amount_azn, coins, plan, days, reference)
  values (s.id, c.key, c.kind, c.title, c.price_azn, c.coins, c.plan, c.days, v_ref)
  returning id into v_id;

  for a in select user_id from admins loop
    perform _notify(a.user_id, 'admin', 'payment_order', 'Yeni ödəniş sifarişi',
      s.name || ' — ' || c.title || ' (' || c.price_azn::numeric(10, 0) || ' AZN), kod: ' || v_ref, null);
  end loop;

  return jsonb_build_object('id', v_id, 'reference', v_ref, 'amount_azn', c.price_azn, 'title', c.title);
end
$fn$;

create or replace function public.cancel_payment_order(p_order uuid)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  update payment_orders set status = 'cancelled'
   where id = p_order and status = 'pending' and store_id = my_store_id();
  if not found then raise exception 'Sifariş tapılmadı və ya artıq bağlanıb.'; end if;
end
$fn$;

-- =====================================================================
-- 6. Admin: sifarişlər, plan, mətnlər
-- =====================================================================
create or replace function public.admin_list_orders(p_status text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  return coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at desc) from (
    select po.id, po.reference, po.title, po.kind, po.amount_azn, po.status, po.created_at, po.paid_at,
           s.id as store_id, s.name as store_name, s.phone as store_phone
    from payment_orders po join stores s on s.id = po.store_id
    where p_status is null or po.status = p_status
    order by po.created_at desc limit 100) o), '[]'::jsonb);
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

  update payment_orders set status = 'paid', paid_at = now(), confirmed_by = auth.uid() where id = o.id;
  perform _notify(s.owner_id, 'seller', 'payment_confirmed', 'Ödəniş təsdiqləndi',
    o.title || ' hesabınıza əlavə olundu. Təşəkkürlər!', null);
end
$fn$;

create or replace function public.admin_cancel_order(p_order uuid)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  update payment_orders set status = 'cancelled' where id = p_order and status = 'pending';
  if not found then raise exception 'Sifariş tapılmadı və ya artıq bağlanıb.'; end if;
end
$fn$;

-- Əllə plan vermək (pilot mağazalar üçün). p_plan = 'free' planı sıfırlayır
create or replace function public.admin_set_plan(p_store uuid, p_plan text, p_days integer default 30)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  if p_plan not in ('free', 'plus', 'pro') then raise exception 'Plan düzgün deyil.'; end if;
  if p_plan <> 'free' and (p_days is null or p_days < 1 or p_days > 366) then
    raise exception 'Gün sayı 1–366 olmalıdır.';
  end if;
  update stores set
    plan = p_plan,
    plan_until = case when p_plan = 'free' then null else now() + p_days * interval '1 day' end
  where id = p_store;
  if not found then raise exception 'Mağaza tapılmadı.'; end if;
end
$fn$;

create or replace function public.admin_set_text(p_key text, p_value text)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  if p_key not in ('payment_instructions', 'support_whatsapp', 'telegram_bot_username') then
    raise exception 'Naməlum açar.';
  end if;
  if length(coalesce(p_value, '')) > 800 then raise exception 'Mətn çox uzundur.'; end if;
  insert into app_texts (key, value) values (p_key, btrim(coalesce(p_value, '')))
  on conflict (key) do update set value = excluded.value;
end
$fn$;

create or replace function public.admin_set_catalog_price(p_key text, p_price numeric)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  if p_price is null or p_price <= 0 or p_price > 100000 then raise exception 'Qiymət düzgün deyil.'; end if;
  update billing_catalog set price_azn = p_price where key = p_key;
  if not found then raise exception 'Paket tapılmadı.'; end if;
end
$fn$;

create or replace function public.admin_billing_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  return jsonb_build_object(
    'pending_orders', (select count(*) from payment_orders where status = 'pending'),
    'revenue_total',  (select coalesce(sum(amount_azn), 0) from payment_orders where status = 'paid'),
    'revenue_30d',    (select coalesce(sum(amount_azn), 0) from payment_orders
                        where status = 'paid' and paid_at > now() - interval '30 days'),
    'active_plus',    (select count(*) from stores where plan = 'plus' and plan_until > now()),
    'active_pro',     (select count(*) from stores where plan = 'pro' and plan_until > now()),
    'catalog', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'title', title, 'price_azn', price_azn) order by sort)
                         from billing_catalog where active), '[]'::jsonb),
    'texts', get_app_texts());
end
$fn$;

-- =====================================================================
-- 7. Bazar analizi (Plus: bazar qiymətləri; Pro: dərin analiz)
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
                          and brand_matches(s.supported_brands, r.brand)),
      'completed_30d', (select count(*) from requests r
                         where r.created_at >= v_since and r.status = 'completed' and r.owner_id is distinct from s.owner_id
                           and brand_matches(s.supported_brands, r.brand))));

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
        and brand_matches(s.supported_brands, r.brand)
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
        and brand_matches(s.supported_brands, r.brand)
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
        and brand_matches(s.supported_brands, r.brand)
      group by 1 having count(*) >= 2
      order by count(*) desc limit 10) t;

    select coalesce(jsonb_agg(coalesce(c.n, 0) order by h), '[]'::jsonb) into v_hours
    from generate_series(0, 23) h
    left join (
      select extract(hour from r.created_at at time zone 'Asia/Baku')::integer as hr, count(*)::integer as n
      from requests r
      where r.created_at >= v_since and r.owner_id is distinct from s.owner_id
        and brand_matches(s.supported_brands, r.brand)
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
        and brand_matches(s.supported_brands, r.brand)
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
                                and brand_matches(s.supported_brands, r.brand)))
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
-- 8. Telegram bildirişləri
-- =====================================================================
create or replace function public.telegram_status()
returns jsonb language sql stable security definer set search_path = public as $fn$
  select jsonb_build_object('linked', coalesce((select chat_id is not null from telegram_links where user_id = auth.uid()), false))
$fn$;

create or replace function public.telegram_create_code()
returns text language plpgsql security definer set search_path = public as $fn$
declare v_code text; u uuid := auth.uid();
begin
  if u is null then raise exception 'Daxil olmaq lazımdır.'; end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Telegram yalnız satıcı və admin hesabları üçündür.';
  end if;
  v_code := upper(substr(md5(random()::text || clock_timestamp()::text || u::text), 1, 10));
  insert into telegram_links (user_id, link_code, code_expires)
  values (u, v_code, now() + interval '15 minutes')
  on conflict (user_id) do update set link_code = excluded.link_code, code_expires = excluded.code_expires;
  return v_code;
end
$fn$;

create or replace function public.telegram_unlink()
returns void language sql security definer set search_path = public as $fn$
  update telegram_links set chat_id = null, linked_at = null, link_code = null, code_expires = null
  where user_id = auth.uid()
$fn$;

-- Yalnız service_role (Edge Function) çağırır
create or replace function public.telegram_complete_link(p_code text, p_chat_id bigint)
returns boolean language plpgsql security definer set search_path = public as $fn$
declare v_user uuid;
begin
  select user_id into v_user from telegram_links
   where link_code = upper(btrim(p_code)) and code_expires > now();
  if v_user is null then return false; end if;
  update telegram_links set chat_id = null, linked_at = null where chat_id = p_chat_id and user_id <> v_user;
  update telegram_links set chat_id = p_chat_id, linked_at = now(), link_code = null, code_expires = null
   where user_id = v_user;
  return true;
end
$fn$;

-- =====================================================================
-- 9. Funksiya icazələri (Supabase standartı yeni funksiyalara hamıya icazə verir — bağlayırıq)
-- =====================================================================
do $c$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any (array[
      'get_app_texts', 'billing_overview', 'create_payment_order', 'cancel_payment_order',
      'admin_list_orders', 'admin_confirm_order', 'admin_cancel_order', 'admin_set_plan',
      'admin_set_text', 'admin_set_catalog_price', 'admin_billing_stats',
      'seller_insights', 'telegram_status', 'telegram_create_code', 'telegram_unlink',
      'submit_bid', 'create_request', 'admin_adjust_coins'])
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;

  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any (array[
      '_coin_move', '_close_request', 'effective_plan', 'plan_rank', 'bid_fee_for', 'telegram_complete_link'])
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;

  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.telegram_complete_link(text, bigint) to service_role';
  end if;
end
$c$;
