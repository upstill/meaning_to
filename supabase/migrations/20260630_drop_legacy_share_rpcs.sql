-- Drop RPCs orphaned by the 2026-06-29 unified-share-link overhaul.
-- Apply via the Supabase SQL Editor (MCP access is read-only).
--
-- KEPT intentionally:
--   redeem_invitation(uuid), get_invitation_info(uuid) — legacy ?invite=<token>
--     links issued before the overhaul still redeem through these.
--   redeem_sample_shares(text, boolean) — still called by the app.
--   create_share_link(int[]), redeem_share_link(uuid) — the new mechanism.
-- The share_invitations table is also retained (legacy redemption + account
-- deletion cleanup still reference it).

DROP FUNCTION IF EXISTS public.create_share_invitation(integer);
DROP FUNCTION IF EXISTS public.get_category_subscribers(integer);
DROP FUNCTION IF EXISTS public.revoke_subscriber(integer, uuid);
