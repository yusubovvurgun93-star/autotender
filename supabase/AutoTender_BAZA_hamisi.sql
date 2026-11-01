
-- ======================================================================
-- 20260917094622_autotender_schema.sql
-- ======================================================================
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

-- ======================================================================
-- 20260917094954_storage_policies.sql
-- ======================================================================
/*
# Storage policies for part-images bucket

1. Security
- Public read access for part-images bucket (anyone can view uploaded part photos)
- Anon upload access for image files (jpeg, png, webp, gif)
*/

DROP POLICY IF EXISTS "anon_read_part_images" ON storage.objects;
CREATE POLICY "anon_read_part_images"
ON storage.objects FOR SELECT
TO anon, authenticated
USING (bucket_id = 'part-images');

DROP POLICY IF EXISTS "anon_upload_part_images" ON storage.objects;
CREATE POLICY "anon_upload_part_images"
ON storage.objects FOR INSERT
TO anon, authenticated
WITH CHECK (bucket_id = 'part-images');

-- ======================================================================
-- 20260917095014_fix_views_security_invoker.sql
-- ======================================================================
/*
# Fix views to use SECURITY INVOKER instead of SECURITY DEFINER

The views were created with SECURITY DEFINER (default), which bypasses RLS.
This migration recreates them with SECURITY INVOKER so RLS policies apply to the querying user.
*/

CREATE OR REPLACE VIEW seller_requests_feed
WITH (security_invoker = true) AS
SELECT
  r.id, r.buyer_tag, r.brand, r.model, r.year, r.vin, r.part_name,
  r.part_images, r.urgency, r.budget_azn, r.status, r.expires_at, r.created_at,
  (SELECT count(*) FROM bids b WHERE b.request_id = r.id) AS bid_count,
  (SELECT count(*) FROM bids b WHERE b.request_id = r.id) >= 5 AS slots_full
FROM requests r
WHERE r.status = 'active';

CREATE OR REPLACE VIEW seller_lost_bids_feedback
WITH (security_invoker = true) AS
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

CREATE OR REPLACE VIEW admin_dashboard_stats
WITH (security_invoker = true) AS
SELECT
  (SELECT count(*) FROM stores) AS total_stores,
  (SELECT count(*) FROM requests) AS total_requests,
  (SELECT count(*) FROM requests WHERE status = 'active') AS active_requests,
  (SELECT count(*) FROM bids) AS total_bids,
  (SELECT COALESCE(sum(30 - coin_balance), 0) FROM stores) AS coins_spent,
  (SELECT COALESCE(sum(GREATEST(coin_balance - 30, 0)), 0) FROM stores) AS bonus_coins_given;

-- ======================================================================
-- 20260917095536_deal_protection.sql
-- ======================================================================
/*
# Deal Protection: Add deal_status column and runner-up selection support

## Overview
After a buyer accepts a bid, they can confirm the deal ("Razılaşdıq") or report
it failed ("Razılaşma Alınmadı"). If failed, the accepted bid is cancelled,
the store's +5 bonus is revoked, the bid is marked rejected, and the buyer
can select another bid.

## Changes
1. New column: `requests.deal_status` (text, nullable)
   - null = no deal yet
   - 'confirmed' = buyer confirmed the deal
   - 'failed' = deal fell through, buyer can re-select
2. New column: `bids.deal_status` (text, nullable) — tracks per-bid deal outcome
3. Modified trigger `on_request_accepted` — also sets deal_status = null on request
4. New function `cancel_accepted_bid` — revokes bonus coins, marks bid rejected,
   clears accepted_bid_id, sets deal_status='failed', reopens request
5. New function `confirm_deal` — sets deal_status='confirmed' on request and bid
*/

-- Add deal_status to requests
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'requests' AND column_name = 'deal_status') THEN
    ALTER TABLE requests ADD COLUMN deal_status text;
  END IF;
END $$;

-- Add deal_status to bids
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bids' AND column_name = 'deal_status') THEN
    ALTER TABLE bids ADD COLUMN deal_status text;
  END IF;
END $$;

-- Function to cancel an accepted bid (deal fell through)
-- Revokes +5 bonus coins from the store, marks bid as rejected,
-- clears accepted_bid_id, sets deal_status='failed', reopens request
CREATE OR REPLACE FUNCTION cancel_accepted_bid(p_request_id uuid)
RETURNS void AS $$
DECLARE
  v_accepted_bid_id uuid;
  v_store_id uuid;
BEGIN
  SELECT accepted_bid_id INTO v_accepted_bid_id FROM requests WHERE id = p_request_id;
  IF v_accepted_bid_id IS NULL THEN
    RAISE EXCEPTION 'Bu sorğuda qəbul edilmiş təklif yoxdur.';
  END IF;

  SELECT store_id INTO v_store_id FROM bids WHERE id = v_accepted_bid_id;

  -- Revoke +5 bonus coins from the store
  UPDATE stores SET coin_balance = GREATEST(coin_balance - 5, 0)
    WHERE id = v_store_id;

  -- Mark the accepted bid as rejected with deal_status failed
  UPDATE bids SET status = 'rejected', deal_status = 'failed'
    WHERE id = v_accepted_bid_id;

  -- Clear accepted_bid_id, set deal_status failed, reopen request
  UPDATE requests
    SET accepted_bid_id = NULL,
        deal_status = 'failed',
        status = 'active'
    WHERE id = p_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Function to confirm a deal
CREATE OR REPLACE FUNCTION confirm_deal(p_request_id uuid)
RETURNS void AS $$
DECLARE
  v_accepted_bid_id uuid;
BEGIN
  SELECT accepted_bid_id INTO v_accepted_bid_id FROM requests WHERE id = p_request_id;
  IF v_accepted_bid_id IS NULL THEN
    RAISE EXCEPTION 'Bu sorğuda qəbul edilmiş təklif yoxdur.';
  END IF;

  UPDATE requests SET deal_status = 'confirmed' WHERE id = p_request_id;
  UPDATE bids SET deal_status = 'confirmed' WHERE id = v_accepted_bid_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- ======================================================================
-- 20260918081818_add_category_and_update_rpc.sql
-- ======================================================================
/*
# Add category column to requests and update cancel_accepted_bid RPC

## Changes
1. New column: `requests.category` (text, nullable) — stores the part category
2. Updated RPC: `cancel_accepted_bid` now accepts both p_request_id and p_bid_id
3. Recreate views with DROP + CREATE to include new columns cleanly
*/

-- Add category column to requests
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'requests' AND column_name = 'category') THEN
    ALTER TABLE requests ADD COLUMN category text;
  END IF;
END $$;

-- Update cancel_accepted_bid to accept bid_id parameter
CREATE OR REPLACE FUNCTION cancel_accepted_bid(p_request_id uuid, p_bid_id uuid)
RETURNS void AS $$
DECLARE
  v_store_id uuid;
BEGIN
  SELECT store_id INTO v_store_id FROM bids WHERE id = p_bid_id;
  IF v_store_id IS NULL THEN
    RAISE EXCEPTION 'Təklif tapılmadı.';
  END IF;

  UPDATE stores SET coin_balance = GREATEST(coin_balance - 5, 0)
    WHERE id = v_store_id;

  UPDATE bids SET status = 'rejected', deal_status = 'failed'
    WHERE id = p_bid_id;

  UPDATE requests
    SET accepted_bid_id = NULL,
        deal_status = 'failed',
        status = 'active'
    WHERE id = p_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Drop and recreate views to include category column
DROP VIEW IF EXISTS seller_requests_feed;
CREATE VIEW seller_requests_feed
WITH (security_invoker = true) AS
SELECT
  r.id, r.buyer_tag, r.brand, r.model, r.year, r.vin, r.part_name,
  r.part_images, r.urgency, r.budget_azn, r.status, r.deal_status,
  r.expires_at, r.created_at, r.category,
  (SELECT count(*) FROM bids b WHERE b.request_id = r.id) AS bid_count,
  (SELECT count(*) FROM bids b WHERE b.request_id = r.id) >= 5 AS slots_full
FROM requests r
WHERE r.status = 'active';

DROP VIEW IF EXISTS seller_lost_bids_feedback;
CREATE VIEW seller_lost_bids_feedback
WITH (security_invoker = true) AS
SELECT
  b.id AS bid_id, b.store_id, b.request_id, b.price_azn AS my_price,
  b.condition AS my_condition, b.warranty AS my_warranty, b.status AS bid_status,
  b.deal_status,
  r.brand, r.model, r.year, r.part_name, r.category,
  wb.price_azn AS winning_price, wb.warranty AS winning_warranty,
  ws.name AS winning_store,
  (b.price_azn - wb.price_azn) AS price_difference
FROM bids b
JOIN requests r ON r.id = b.request_id
LEFT JOIN bids wb ON wb.id = r.accepted_bid_id AND wb.id <> b.id
LEFT JOIN stores ws ON ws.id = wb.store_id
WHERE b.status = 'rejected'
ORDER BY b.created_at DESC;

-- ======================================================================
-- 20260921112831_20260921000001_fix_statuses_and_admin_security.sql.sql
-- ======================================================================
/*
# Fix Status Case Mismatches + Admin Security

## Overview
1. Normalize all existing uppercase request statuses to canonical lowercase values.
   The database schema, triggers, and views all use lowercase statuses ('active',
   'completed', 'expired', 'pending', 'accepted', 'rejected'). Some rows were
   incorrectly inserted with uppercase 'ACTIVE' by the frontend. This migration
   normalizes those rows.
2. Lock down the `stores` table UPDATE/DELETE to authenticated admin users only.
   Previously anyone with the anon key could modify store coin balances.
3. Create an `admins` table that maps auth.users IDs to admin privileges.
   The RLS policy on `stores` checks membership in this table.
4. Restrict coin-balance column updates: only admin users can change coin_balance.
5. Revoke stores UPDATE/DELETE from anon role so anonymous requests are denied.

## Data Changes
- `requests.status`: 'ACTIVE' → 'active' (only uppercase values are touched)
- Existing 'completed', 'expired' rows are left unchanged

## Security Changes
- `stores` UPDATE policy: only authenticated users listed in `admins` table
- `stores` DELETE policy: only authenticated users listed in `admins` table
- `stores` SELECT/INSERT remain open to anon (stores list is public, registration is open)
- New `admins` table with RLS (admin-only read, self-insert blocked)
- Revoke UPDATE/DELETE on `stores` from `anon` role
*/

-- ===================== 1. NORMALIZE STATUSES =====================
UPDATE requests SET status = 'active' WHERE status = 'ACTIVE';
UPDATE requests SET status = 'completed' WHERE status = 'COMPLETED';
UPDATE requests SET status = 'expired' WHERE status = 'EXPIRED';
UPDATE bids SET status = 'pending' WHERE status = 'PENDING';
UPDATE bids SET status = 'accepted' WHERE status = 'ACCEPTED';
UPDATE bids SET status = 'rejected' WHERE status = 'REJECTED';

-- ===================== 2. ADMINS TABLE =====================
CREATE TABLE IF NOT EXISTS admins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  email text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE admins ENABLE ROW LEVEL SECURITY;

-- Admins can read the admin list; anon cannot
DROP POLICY IF EXISTS "admins_select_own" ON admins;
CREATE POLICY "admins_select_own" ON admins FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

-- Prevent direct inserts by anon/authenticated (admin seeds must be done via SQL)
DROP POLICY IF EXISTS "admins_insert_blocked" ON admins;
CREATE POLICY "admins_insert_blocked" ON admins FOR INSERT
  TO authenticated WITH CHECK (false);

DROP POLICY IF EXISTS "admins_delete_own" ON admins;
CREATE POLICY "admins_delete_own" ON admins FOR DELETE
  TO authenticated USING (auth.uid() = user_id);

-- ===================== 3. LOCK DOWN STORES UPDATE/DELETE =====================
-- Revoke direct UPDATE/DELETE from anon so anonymous requests are denied at the GRANT level
REVOKE UPDATE, DELETE ON stores FROM anon;

-- Replace the open UPDATE policy with an admin-only one
DROP POLICY IF EXISTS "anon_update_stores" ON stores;
CREATE POLICY "admin_update_stores" ON stores FOR UPDATE
  TO authenticated
  USING (EXISTS (SELECT 1 FROM admins WHERE admins.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM admins WHERE admins.user_id = auth.uid()));

-- Replace the open DELETE policy with an admin-only one
DROP POLICY IF EXISTS "anon_delete_stores" ON stores;
CREATE POLICY "admin_delete_stores" ON stores FOR DELETE
  TO authenticated
  USING (EXISTS (SELECT 1 FROM admins WHERE admins.user_id = auth.uid()));

-- ===================== 4. LOCK DOWN BIDS/REQUESTS STATUS COLUMNS =====================
-- Restrict bids.status updates to only happen via triggers (not direct frontend updates)
-- The buyer should accept bids by updating requests.accepted_bid_id, not bids.status
-- We revoke UPDATE on bids from anon entirely; authenticated is not needed for the current flow
REVOKE UPDATE ON bids FROM anon;

-- Keep bids SELECT/INSERT open (sellers need to insert bids, everyone reads)
-- Keep requests SELECT/INSERT/UPDATE open (buyers create and accept bids via accepted_bid_id)
-- Requests UPDATE is needed by the frontend to set accepted_bid_id and by the expiry sweep

-- ======================================================================
-- 20261029120000_secure_rewrite.sql
-- ======================================================================
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

-- ======================================================================
-- 20261101120000_billing_plans.sql
-- ======================================================================
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

-- ======================================================================
-- 20261102120000_safety_privacy.sql
-- ======================================================================
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

-- ======================================================================
-- 20261103120000_services_ratings.sql
-- ======================================================================
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
