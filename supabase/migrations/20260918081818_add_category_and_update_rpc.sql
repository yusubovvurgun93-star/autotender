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
