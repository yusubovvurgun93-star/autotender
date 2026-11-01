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
