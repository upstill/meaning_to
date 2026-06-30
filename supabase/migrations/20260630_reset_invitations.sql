-- ONE-TIME reset of the invitation/sharing state for a fresh start.
-- Clears all issued links and invitations, and all UN-borrowed shares, while
-- leaving borrowed pursuits (shared_categories.available = true) intact.
-- Apply via the Supabase SQL Editor (MCP access is read-only).
--
-- This is a data cleanup, not a schema change — safe to run once, harmless if
-- re-run (it just deletes already-empty sets).

BEGIN;

-- Issued share links and their category mappings.
DELETE FROM share_link_categories;
DELETE FROM share_links;

-- Legacy single-category invitations.
DELETE FROM share_invitations;

-- Un-borrowed Shared-With-Me rows only; keep what recipients actually borrowed
-- onto their home lists (available = true).
DELETE FROM shared_categories WHERE available IS NOT TRUE;

-- Clear the "new/unseen" flag on the surviving borrowed rows so the reset
-- doesn't leave a stale "New Pursuits shared with you" notification.
-- (Remove this statement if you'd rather keep their unseen state.)
UPDATE shared_categories SET seen_at = now() WHERE seen_at IS NULL;

COMMIT;
