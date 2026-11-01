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
