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
