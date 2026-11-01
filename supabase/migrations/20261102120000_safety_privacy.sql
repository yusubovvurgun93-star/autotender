/* =====================================================================
   AutoTender — 3-cü migration: şikayətlər, mağaza dayandırma, məlumatların ixracı və hesabın silinməsi
   ƏVVƏL 1-ci və 2-ci migration işləməlidir. Təkrar işlətmək təhlükəsizdir.
   ===================================================================== */

alter table public.stores add column if not exists suspended boolean not null default false;
alter table public.stores add column if not exists suspended_reason text;

-- =====================================================================
-- 1. Şikayətlər
-- =====================================================================
create table if not exists public.reports (
  id            uuid primary key default gen_random_uuid(),
  reporter_id   uuid references auth.users(id) on delete set null,
  reporter_role text not null check (reporter_role in ('buyer', 'seller')),
  kind          text not null check (kind in ('store', 'request')),
  store_id      uuid references public.stores(id) on delete set null,
  request_id    uuid references public.requests(id) on delete set null,
  reason        text not null check (reason in
    ('wrong_price', 'bad_part', 'no_response', 'rude', 'bypass', 'spam', 'fake', 'other')),
  details       text check (details is null or length(details) <= 500),
  status        text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  admin_note    text,
  created_at    timestamptz not null default now(),
  handled_at    timestamptz,
  handled_by    uuid
);
create index if not exists reports_status_idx on public.reports (status, created_at desc);
create index if not exists reports_store_idx  on public.reports (store_id);
create unique index if not exists reports_one_open_per_target
  on public.reports (reporter_id, kind, coalesce(store_id, request_id)) where status = 'open';
alter table public.reports enable row level security;
revoke all on public.reports from anon, authenticated;

create or replace function public.submit_report(
  p_kind text, p_store uuid, p_request uuid, p_reason text, p_details text default null)
returns void language plpgsql security definer set search_path = public as $fn$
declare
  u uuid := auth.uid();
  v_anon boolean := coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
  v_details text := nullif(btrim(coalesce(p_details, '')), '');
  v_target_name text; a record;
begin
  if u is null then raise exception 'Sessiya tapılmadı.'; end if;
  if p_reason is null or p_reason not in ('wrong_price','bad_part','no_response','rude','bypass','spam','fake','other') then
    raise exception 'Səbəbi seçin.';
  end if;
  if v_details is not null and length(v_details) > 500 then raise exception 'Qeyd 500 simvolu keçməməlidir.'; end if;
  if p_reason = 'other' and (v_details is null or length(v_details) < 5) then
    raise exception 'Qısa izah yazın.';
  end if;
  if (select count(*) from reports where reporter_id = u and created_at > now() - interval '24 hours') >= 5 then
    raise exception 'Gündəlik şikayət limitinə çatdınız.';
  end if;

  if p_kind = 'store' then
    if not v_anon then raise exception 'Mağaza haqqında yalnız alıcı şikayət edə bilər.'; end if;
    if p_reason in ('spam', 'fake') then raise exception 'Səbəb bu şikayət növünə uyğun deyil.'; end if;
    if not exists (select 1 from bids b join requests r on r.id = b.request_id
                   where r.owner_id = u and b.store_id = p_store) then
      raise exception 'Yalnız sorğunuza təklif vermiş mağazanı şikayət edə bilərsiniz.';
    end if;
    select name into v_target_name from stores where id = p_store;
    insert into reports (reporter_id, reporter_role, kind, store_id, request_id, reason, details)
    values (u, 'buyer', 'store', p_store, p_request, p_reason, v_details);
  elsif p_kind = 'request' then
    if v_anon or my_store_id() is null then raise exception 'Sorğunu yalnız satıcı şikayət edə bilər.'; end if;
    if p_reason not in ('spam', 'fake', 'rude', 'other') then raise exception 'Səbəb bu şikayət növünə uyğun deyil.'; end if;
    if not exists (select 1 from requests where id = p_request and owner_id is distinct from u) then
      raise exception 'Sorğu tapılmadı.';
    end if;
    select brand || ' ' || coalesce(model, '') || ' — ' || part_name into v_target_name from requests where id = p_request;
    insert into reports (reporter_id, reporter_role, kind, store_id, request_id, reason, details)
    values (u, 'seller', 'request', null, p_request, p_reason, v_details);
  else
    raise exception 'Şikayət növü düzgün deyil.';
  end if;

  for a in select user_id from admins loop
    perform _notify(a.user_id, 'admin', 'report', 'Yeni şikayət', coalesce(v_target_name, '') || ' — ' || p_reason, p_request);
  end loop;
exception when unique_violation then
  raise exception 'Bu şikayəti artıq göndərmisiniz. Baxılması gözlənilir.';
end
$fn$;

create or replace function public.admin_list_reports(p_status text default 'open')
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
    select rp.id, rp.kind, rp.reason, rp.details, rp.status, rp.admin_note, rp.reporter_role, rp.created_at,
           rp.store_id, s.name as store_name, s.phone as store_phone, s.suspended as store_suspended,
           (select count(*) from reports r2 where r2.store_id = rp.store_id) as store_total_reports,
           rp.request_id, (rq.brand || ' ' || coalesce(rq.model, '') || ' — ' || rq.part_name) as request_title,
           rq.status as request_status
    from reports rp
    left join stores s on s.id = rp.store_id
    left join requests rq on rq.id = rp.request_id
    where p_status is null or rp.status = p_status
    order by rp.created_at desc limit 100) x), '[]'::jsonb);
end
$fn$;

create or replace function public.admin_resolve_report(p_report uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $fn$
declare rp reports%rowtype;
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  if p_status not in ('resolved', 'dismissed') then raise exception 'Status düzgün deyil.'; end if;
  select * into rp from reports where id = p_report for update;
  if not found then raise exception 'Şikayət tapılmadı.'; end if;
  update reports set status = p_status, admin_note = left(nullif(btrim(coalesce(p_note, '')), ''), 300),
         handled_at = now(), handled_by = auth.uid()
   where id = p_report;
  perform _notify(rp.reporter_id, rp.reporter_role, 'report_update', 'Şikayətinizə baxıldı',
    case p_status when 'resolved' then 'Təşəkkür edirik, tədbir görüldü.' else 'Yoxlanıldı, bu dəfə tədbir görülmədi.' end, rp.request_id);
end
$fn$;

-- Mağazanı dayandır / bərpa et. Dayandırılanda aktiv təklifləri bağlanır və coin qaytarılır
create or replace function public.admin_set_suspended(p_store uuid, p_suspended boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $fn$
declare b record; v_owner uuid;
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  select owner_id into v_owner from stores where id = p_store;
  if not found then raise exception 'Mağaza tapılmadı.'; end if;
  update stores set suspended = coalesce(p_suspended, false),
         suspended_reason = case when p_suspended then left(nullif(btrim(coalesce(p_reason, '')), ''), 200) else null end
   where id = p_store;
  if p_suspended then
    for b in select bd.id, bd.fee_paid from bids bd join requests r on r.id = bd.request_id
             where bd.store_id = p_store and bd.status = 'pending' and r.status = 'active' loop
      perform _coin_move(p_store, coalesce(b.fee_paid, cfg('bid_fee', 1)), 'REFUND', null, b.id, 'Mağaza dayandırıldı');
      update bids set status = 'expired' where id = b.id;
    end loop;
    perform _notify(v_owner, 'seller', 'suspended', 'Hesabınız müvəqqəti dayandırıldı',
      'Təklif vermək mümkün deyil. Dəstək ilə əlaqə saxlayın.', null);
  else
    perform _notify(v_owner, 'seller', 'unsuspended', 'Hesabınız bərpa olundu', 'Yenidən təklif verə bilərsiniz.', null);
  end if;
end
$fn$;

create or replace function public.admin_cancel_request(p_request uuid)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if not is_admin() then raise exception 'İcazə yoxdur.'; end if;
  if not exists (select 1 from requests where id = p_request and status = 'active') then
    raise exception 'Sorğu tapılmadı və ya artıq bağlanıb.';
  end if;
  perform _close_request(p_request, 'cancelled');
end
$fn$;

-- =====================================================================
-- 2. Məlumatların ixracı və hesabın silinməsi
-- =====================================================================
create or replace function public.export_my_data()
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare u uuid := auth.uid(); v_store uuid;
begin
  if u is null then raise exception 'Sessiya tapılmadı.'; end if;
  select id into v_store from stores where owner_id = u;
  return jsonb_build_object(
    'user_id', u,
    'exported_at', now(),
    'requests', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'brand', r.brand, 'model', r.model, 'year', r.year, 'vin', r.vin, 'part_name', r.part_name,
        'category', r.category, 'budget_azn', r.budget_azn, 'status', r.status, 'created_at', r.created_at,
        'bids', coalesce((select jsonb_agg(jsonb_build_object(
            'store', (select name from stores where id = b.store_id), 'price_azn', b.price_azn,
            'condition', b.condition, 'warranty', b.warranty, 'status', b.status, 'created_at', b.created_at))
          from bids b where b.request_id = r.id), '[]'::jsonb)) order by r.created_at desc)
      from requests r where r.owner_id = u), '[]'::jsonb),
    'store', (select to_jsonb(s) - 'owner_id' from stores s where s.id = v_store),
    'bids', coalesce((select jsonb_agg(to_jsonb(b) order by b.created_at desc) from bids b where b.store_id = v_store), '[]'::jsonb),
    'coin_ledger', coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from coin_ledger l where l.store_id = v_store), '[]'::jsonb),
    'orders', coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at desc) from payment_orders o where o.store_id = v_store), '[]'::jsonb));
end
$fn$;

create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $fn$
declare u uuid := auth.uid(); v_store stores%rowtype; r record;
begin
  if u is null then raise exception 'Sessiya tapılmadı.'; end if;
  if is_admin() then raise exception 'Admin hesabı buradan silinə bilməz.'; end if;

  select * into v_store from stores where owner_id = u for update;
  if found then
    if exists (select 1 from bids b join requests rq on rq.id = b.request_id
               where b.store_id = v_store.id and b.status = 'pending' and rq.status = 'active' and rq.expires_at > now()) then
      raise exception 'Aktiv təkliflərinizin vaxtı bitənə qədər gözləyin, sonra hesabı silə bilərsiniz.';
    end if;
    update payment_orders set status = 'cancelled' where store_id = v_store.id and status = 'pending';
    if v_store.coin_balance > 0 then
      perform _coin_move(v_store.id, -v_store.coin_balance, 'ACCOUNT_DELETED', null, null, 'Hesab silindi');
    end if;
    -- Maliyyə qeydləri və keçmiş razılaşmalar qalır, şəxsi məlumat silinir
    update stores set name = 'Silinmiş mağaza', phone = 'deleted-' || left(id::text, 8), voen = null, address = null,
           supported_brands = '{}', categories = '{}', verified = false, plan = 'free', plan_until = null,
           suspended = true, suspended_reason = 'Hesab silinib', owner_id = null
     where id = v_store.id;
  end if;

  for r in select id from requests where owner_id = u and status = 'active' loop
    perform _close_request(r.id, 'cancelled');
  end loop;
  update requests set vin = null, part_images = '{}', owner_id = null where owner_id = u;

  delete from auth.users where id = u;
end
$fn$;

-- =====================================================================
-- 3. Dayandırılmış mağaza təklif verə bilmir və bildiriş almır
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
  v_fee numeric;
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
    and brand_matches(s.supported_brands, p_brand)
    and (cardinality(s.categories) = 0 or p_category is null or p_category = any (s.categories));

  return v_id;
end
$fn$;

-- =====================================================================
-- 4. Icazələr
-- =====================================================================
do $c$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any (array[
      'submit_report', 'admin_list_reports', 'admin_resolve_report', 'admin_set_suspended',
      'admin_cancel_request', 'export_my_data', 'delete_my_account', 'submit_bid', 'create_request'])
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end
$c$;
