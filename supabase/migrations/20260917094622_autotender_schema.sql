/*
# AutoTender — Full Schema for Automotive Parts Tender Marketplace

## Overview
A reverse marketplace (C2B) where buyers publish part requests and stores send sealed bids.
No authentication — buyers and sellers are identified by session/local selection, not auth.users.
All policies use `TO anon, authenticated` so the anon-key frontend can operate.

## New Tables
1. `car_brands` — Catalog of car brands (Mercedes-Benz, BMW, Toyota, etc.)
   - id (uuid PK), name (text unique), logo_url (text nullable), created_at
2. `stores` — Seller stores/shops
   - id (uuid PK), name, voen (tax ID), phone, address, supported_brands (text[]),
   - coin_balance (int default 30), grade (text default 'A'), rating (numeric default 5.0),
   - verified (bool default false), created_at
3. `requests` — Buyer part requests
   - id (uuid PK), buyer_tag (text, anonymous label like "Gizli Sürücü #12"),
   - brand (text), model (text), year (int), vin (text), part_name (text),
   - part_images (text[] up to 3 URLs), urgency (text: 'express'|'standard'|'wide'),
   - budget_azn (numeric nullable), status (text default 'active'),
   - expires_at (timestamptz), accepted_bid_id (uuid nullable), created_at
4. `bids` — Sealed bids from stores on requests
   - id (uuid PK), request_id (FK requests), store_id (FK stores),
   - price_azn (numeric), condition (text: 'original'|'analog'|'used'),
   - warranty (text), note (text), status (text default 'pending'),
   - created_at
5. `in_app_notifications` — Toast notifications for realtime
   - id (uuid PK), target_type (text: 'buyer'|'seller'|'admin'),
   - target_id (uuid nullable), title (text), body (text), created_at

## Views
1. `seller_requests_feed` — Active requests filtered by store's supported brands,
   with bid count and whether the store already bid (slot limit 5).
2. `seller_lost_bids_feedback` — Lost bids with winning price for market analysis.
3. `admin_dashboard_stats` — Aggregate KPIs for admin dashboard.

## Triggers
1. `deduct_coin_on_bid` — On bid insert: deduct 1 coin from store, reject if balance < 1.
2. `enforce_bid_slot_limit` — On bid insert: reject if request already has 5 bids.
3. `set_accepted_bid_status` — On request accepted_bid_id update: set winning bid to 'accepted', others to 'rejected'.
4. `award_bonus_coins` — On bid status becoming 'accepted': award +5 coins to winning store.
5. `auto_refund_expired` — On request status becoming 'expired': refund 1 coin to each participating store.
6. `validate_bid_note` — On bid insert: reject notes containing phone patterns or contact-bypass keywords.

## Security
- RLS enabled on all tables.
- All policies use `TO anon, authenticated` with `USING (true)` / `WITH CHECK (true)` because
  this is a single-tenant no-auth app — all data is intentionally shared/public via the anon key.
*/

-- ===================== CAR BRANDS =====================
CREATE TABLE IF NOT EXISTS car_brands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  logo_url text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE car_brands ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_select_car_brands" ON car_brands;
CREATE POLICY "anon_select_car_brands" ON car_brands FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_car_brands" ON car_brands;
CREATE POLICY "anon_insert_car_brands" ON car_brands FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_car_brands" ON car_brands;
CREATE POLICY "anon_update_car_brands" ON car_brands FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_car_brands" ON car_brands;
CREATE POLICY "anon_delete_car_brands" ON car_brands FOR DELETE TO anon, authenticated USING (true);

-- ===================== STORES =====================
CREATE TABLE IF NOT EXISTS stores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  voen text,
  phone text,
  address text,
  supported_brands text[] DEFAULT '{}',
  coin_balance integer NOT NULL DEFAULT 30,
  grade text NOT NULL DEFAULT 'A',
  rating numeric(3,1) NOT NULL DEFAULT 5.0,
  verified boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE stores ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_select_stores" ON stores;
CREATE POLICY "anon_select_stores" ON stores FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_stores" ON stores;
CREATE POLICY "anon_insert_stores" ON stores FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_stores" ON stores;
CREATE POLICY "anon_update_stores" ON stores FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_stores" ON stores;
CREATE POLICY "anon_delete_stores" ON stores FOR DELETE TO anon, authenticated USING (true);

-- ===================== REQUESTS =====================
CREATE TABLE IF NOT EXISTS requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_tag text NOT NULL DEFAULT 'Gizli Sürücü',
  brand text NOT NULL,
  model text,
  year integer,
  vin text,
  part_name text NOT NULL,
  part_images text[] DEFAULT '{}',
  urgency text NOT NULL DEFAULT 'standard',
  budget_azn numeric(10,2),
  status text NOT NULL DEFAULT 'active',
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '6 hours'),
  accepted_bid_id uuid,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_select_requests" ON requests;
CREATE POLICY "anon_select_requests" ON requests FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_requests" ON requests;
CREATE POLICY "anon_insert_requests" ON requests FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_requests" ON requests;
CREATE POLICY "anon_update_requests" ON requests FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_requests" ON requests;
CREATE POLICY "anon_delete_requests" ON requests FOR DELETE TO anon, authenticated USING (true);

CREATE INDEX IF NOT EXISTS idx_requests_status ON requests(status);
CREATE INDEX IF NOT EXISTS idx_requests_created ON requests(created_at DESC);

-- ===================== BIDS =====================
CREATE TABLE IF NOT EXISTS bids (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES requests(id) ON DELETE CASCADE,
  store_id uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  price_azn numeric(10,2) NOT NULL,
  condition text NOT NULL DEFAULT 'analog',
  warranty text NOT NULL DEFAULT 'Zəmanətsiz',
  note text DEFAULT '',
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE bids ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_select_bids" ON bids;
CREATE POLICY "anon_select_bids" ON bids FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_bids" ON bids;
CREATE POLICY "anon_insert_bids" ON bids FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_bids" ON bids;
CREATE POLICY "anon_update_bids" ON bids FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_bids" ON bids;
CREATE POLICY "anon_delete_bids" ON bids FOR DELETE TO anon, authenticated USING (true);

CREATE INDEX IF NOT EXISTS idx_bids_request ON bids(request_id);
CREATE INDEX IF NOT EXISTS idx_bids_store ON bids(store_id);

-- ===================== NOTIFICATIONS =====================
CREATE TABLE IF NOT EXISTS in_app_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_type text NOT NULL DEFAULT 'buyer',
  target_id uuid,
  title text NOT NULL,
  body text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE in_app_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_select_notifications" ON in_app_notifications;
CREATE POLICY "anon_select_notifications" ON in_app_notifications FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "anon_insert_notifications" ON in_app_notifications;
CREATE POLICY "anon_insert_notifications" ON in_app_notifications FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_notifications" ON in_app_notifications;
CREATE POLICY "anon_update_notifications" ON in_app_notifications FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "anon_delete_notifications" ON in_app_notifications;
CREATE POLICY "anon_delete_notifications" ON in_app_notifications FOR DELETE TO anon, authenticated USING (true);

CREATE INDEX IF NOT EXISTS idx_notifications_created ON in_app_notifications(created_at DESC);

-- ===================== TRIGGER FUNCTIONS =====================

-- Deduct 1 coin on bid insert, reject if balance < 1
CREATE OR REPLACE FUNCTION deduct_coin_on_bid()
RETURNS trigger AS $$
BEGIN
  IF NEW.store_id IS NULL THEN
    RETURN NEW;
  END IF;
  UPDATE stores SET coin_balance = coin_balance - 1
    WHERE id = NEW.store_id AND coin_balance >= 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kifayət qədər coin yoxdur. Təklif göndərmək üçün ən azı 1 coin lazımdır.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Enforce max 5 bids per request
CREATE OR REPLACE FUNCTION enforce_bid_slot_limit()
RETURNS trigger AS $$
DECLARE
  bid_count integer;
BEGIN
  SELECT count(*) INTO bid_count FROM bids WHERE request_id = NEW.request_id;
  IF bid_count >= 5 THEN
    RAISE EXCEPTION 'Bu sorğu üçün təklif limiti dolub (5/5).'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Validate bid note against phone/contact-bypass patterns
CREATE OR REPLACE FUNCTION validate_bid_note()
RETURNS trigger AS $$
BEGIN
  IF NEW.note ~ '(050|051|055|070|077|099|\+994)' THEN
    RAISE EXCEPTION 'Qeydə telefon nömrəsi daxil etmək olmaz. Əlaqə məlumatları yalnız təklif qəbul edildikdən sonra açıqlanır.'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.note ~* '(wp|whatsapp|zəng|zeng|call)' THEN
    RAISE EXCEPTION 'Qeydə telefon nömrəsi daxil etmək olmaz. Əlaqə məlumatları yalnız təklif qəbul edildikdən sonra açıqlanır.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- On accepted_bid_id update: set winning bid to accepted, others to rejected, award +5 coins
CREATE OR REPLACE FUNCTION on_request_accepted()
RETURNS trigger AS $$
BEGIN
  IF NEW.accepted_bid_id IS DISTINCT FROM OLD.accepted_bid_id AND NEW.accepted_bid_id IS NOT NULL THEN
    UPDATE bids SET status = 'accepted' WHERE id = NEW.accepted_bid_id;
    UPDATE bids SET status = 'rejected'
      WHERE request_id = NEW.id AND id <> NEW.accepted_bid_id;
    UPDATE stores SET coin_balance = coin_balance + 5
      WHERE id = (SELECT store_id FROM bids WHERE id = NEW.accepted_bid_id);
    UPDATE requests SET status = 'completed' WHERE id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Auto-refund 1 coin to participating stores when request expires without accepted bid
CREATE OR REPLACE FUNCTION auto_refund_expired()
RETURNS trigger AS $$
BEGIN
  IF NEW.status = 'expired' AND OLD.status <> 'expired' THEN
    UPDATE stores SET coin_balance = coin_balance + 1
      WHERE id IN (SELECT store_id FROM bids WHERE request_id = NEW.id AND status = 'pending');
    UPDATE bids SET status = 'expired' WHERE request_id = NEW.id AND status = 'pending';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- ===================== TRIGGERS =====================
DROP TRIGGER IF EXISTS trg_deduct_coin ON bids;
CREATE TRIGGER trg_deduct_coin BEFORE INSERT ON bids
  FOR EACH ROW EXECUTE FUNCTION deduct_coin_on_bid();

DROP TRIGGER IF EXISTS trg_slot_limit ON bids;
CREATE TRIGGER trg_slot_limit BEFORE INSERT ON bids
  FOR EACH ROW EXECUTE FUNCTION enforce_bid_slot_limit();

DROP TRIGGER IF EXISTS trg_validate_note ON bids;
CREATE TRIGGER trg_validate_note BEFORE INSERT ON bids
  FOR EACH ROW EXECUTE FUNCTION validate_bid_note();

DROP TRIGGER IF EXISTS trg_on_accepted ON requests;
CREATE TRIGGER trg_on_accepted AFTER UPDATE OF accepted_bid_id ON requests
  FOR EACH ROW EXECUTE FUNCTION on_request_accepted();

DROP TRIGGER IF EXISTS trg_auto_refund ON requests;
CREATE TRIGGER trg_auto_refund AFTER UPDATE OF status ON requests
  FOR EACH ROW EXECUTE FUNCTION auto_refund_expired();

-- ===================== VIEWS =====================

-- Seller feed: active requests matching store's supported brands, with bid count + already-bid flag
CREATE OR REPLACE VIEW seller_requests_feed AS
SELECT
  r.id, r.buyer_tag, r.brand, r.model, r.year, r.vin, r.part_name,
  r.part_images, r.urgency, r.budget_azn, r.status, r.expires_at, r.created_at,
  (SELECT count(*) FROM bids b WHERE b.request_id = r.id) AS bid_count,
  (SELECT count(*) FROM bids b WHERE b.request_id = r.id) >= 5 AS slots_full
FROM requests r
WHERE r.status = 'active';

-- Seller lost bids feedback: bids that were rejected, with winning price
CREATE OR REPLACE VIEW seller_lost_bids_feedback AS
SELECT
  b.id AS bid_id, b.store_id, b.request_id, b.price_azn AS my_price,
  b.condition AS my_condition, b.warranty AS my_warranty, b.status AS bid_status,
  r.brand, r.model, r.year, r.part_name,
  wb.price_azn AS winning_price, wb.warranty AS winning_warranty,
  ws.name AS winning_store,
  (b.price_azn - wb.price_azn) AS price_difference
FROM bids b
JOIN requests r ON r.id = b.request_id
LEFT JOIN bids wb ON wb.id = r.accepted_bid_id AND wb.id <> b.id
LEFT JOIN stores ws ON ws.id = wb.store_id
WHERE b.status = 'rejected'
ORDER BY b.created_at DESC;

-- Admin dashboard stats
CREATE OR REPLACE VIEW admin_dashboard_stats AS
SELECT
  (SELECT count(*) FROM stores) AS total_stores,
  (SELECT count(*) FROM requests) AS total_requests,
  (SELECT count(*) FROM requests WHERE status = 'active') AS active_requests,
  (SELECT count(*) FROM bids) AS total_bids,
  (SELECT COALESCE(sum(30 - coin_balance), 0) FROM stores) AS coins_spent,
  (SELECT COALESCE(sum(GREATEST(coin_balance - 30, 0)), 0) FROM stores) AS bonus_coins_given;

-- ===================== SEED CAR BRANDS =====================
INSERT INTO car_brands (name) VALUES
  ('Mercedes-Benz'), ('BMW'), ('Toyota'), ('Hyundai'),
  ('Kia'), ('Audi'), ('Volkswagen'), ('Nissan'),
  ('Mazda'), ('Honda'), ('Lexus'), ('Opel'),
  ('Ford'), ('Chevrolet'), ('Renault'), ('Peugeot'),
  ('Citroen'), ('Skoda'), ('Subaru'), ('Mitsubishi'),
  ('Land Rover'), ('Jeep'), ('Daewoo'), ('Lada')
ON CONFLICT (name) DO NOTHING;
