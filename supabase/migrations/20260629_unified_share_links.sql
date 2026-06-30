-- Unified share links: one reusable link grants a SET of pursuits.
-- Replaces the per-category single-use / open_to_all invitation model.
-- Apply via the Supabase SQL Editor (MCP access is read-only).

-- ── 1. Schema ────────────────────────────────────────────────────────────────

-- A share link = a token owned by its creator.
CREATE TABLE IF NOT EXISTS share_links (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by  UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- The set of categories a link grants.
CREATE TABLE IF NOT EXISTS share_link_categories (
  link_id     UUID    NOT NULL REFERENCES share_links(id)  ON DELETE CASCADE,
  category_id INTEGER NOT NULL REFERENCES "Categories"(id) ON DELETE CASCADE,
  PRIMARY KEY (link_id, category_id)
);

ALTER TABLE share_links           ENABLE ROW LEVEL SECURITY;
ALTER TABLE share_link_categories ENABLE ROW LEVEL SECURITY;

-- Creators manage only their own links.
DROP POLICY IF EXISTS "share_links_owner" ON share_links;
CREATE POLICY "share_links_owner"
  ON share_links FOR ALL
  USING  (auth.uid() = created_by)
  WITH CHECK (auth.uid() = created_by);

-- Link items are visible/manageable to the link's creator. Redeem reads them via
-- a SECURITY DEFINER RPC, so recipients need no direct SELECT policy here.
DROP POLICY IF EXISTS "share_link_categories_owner" ON share_link_categories;
CREATE POLICY "share_link_categories_owner"
  ON share_link_categories FOR ALL
  USING (
    EXISTS (SELECT 1 FROM share_links sl
             WHERE sl.id = link_id AND sl.created_by = auth.uid())
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM share_links sl
             WHERE sl.id = link_id AND sl.created_by = auth.uid())
  );

-- Track which shared-with-me rows the recipient hasn't seen yet (NULL = new).
ALTER TABLE shared_categories
  ADD COLUMN IF NOT EXISTS seen_at TIMESTAMPTZ;

-- ── 2. create_share_link ─────────────────────────────────────────────────────
-- Verifies the caller owns every category, creates a link granting all of them,
-- and returns the new link token.
CREATE OR REPLACE FUNCTION public.create_share_link(p_category_ids INTEGER[])
  RETURNS UUID
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_link  UUID;
  v_count INTEGER;
BEGIN
  IF p_category_ids IS NULL OR array_length(p_category_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'No categories supplied';
  END IF;

  -- Every supplied category must exist and be owned by the caller.
  SELECT count(*) INTO v_count
    FROM "Categories"
   WHERE id = ANY(p_category_ids)
     AND owner_id = auth.uid();

  IF v_count <> array_length(p_category_ids, 1) THEN
    RAISE EXCEPTION 'Not authorized to share one or more of these categories';
  END IF;

  INSERT INTO share_links(created_by) VALUES (auth.uid())
    RETURNING id INTO v_link;

  INSERT INTO share_link_categories(link_id, category_id)
    SELECT v_link, unnest(p_category_ids);

  RETURN v_link;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_share_link(INTEGER[]) TO authenticated;

-- ── 3. redeem_share_link ─────────────────────────────────────────────────────
-- Subscribes the caller to every category in the link (idempotent), marking each
-- new subscription unseen. Skips categories the caller already owns. Returns the
-- category id + headline for each granted pursuit (for the recipient notification).
CREATE OR REPLACE FUNCTION public.redeem_share_link(p_link UUID)
  RETURNS TABLE(category_id INTEGER, headline TEXT)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_subscriber_name TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM share_links WHERE id = p_link) THEN
    RAISE EXCEPTION 'Share link not found';
  END IF;

  -- Resolve the caller's display name once.
  SELECT COALESCE(
           raw_user_meta_data->>'full_name',
           raw_user_meta_data->>'name',
           email
         )
    INTO v_subscriber_name
    FROM auth.users
   WHERE id = auth.uid();

  -- Subscribe to every category in the link that the caller does not own.
  INSERT INTO shared_categories(user_id, category_id, owner_name, subscriber_name,
                                available, seen_at)
  SELECT
    auth.uid(),
    c.id,
    COALESCE(u.raw_user_meta_data->>'full_name',
             u.raw_user_meta_data->>'name',
             u.email),
    v_subscriber_name,
    false,   -- new shares are not borrowed onto the home list until opted in
    NULL     -- unseen
  FROM share_link_categories slc
  JOIN "Categories" c ON c.id = slc.category_id
  JOIN auth.users   u ON u.id = c.owner_id
  WHERE slc.link_id = p_link
    AND c.owner_id <> auth.uid()
  ON CONFLICT (user_id, category_id) DO NOTHING;

  -- Return the full granted set (regardless of whether newly inserted) so the
  -- caller can show "these were shared with you".
  RETURN QUERY
    SELECT c.id, c.headline
      FROM share_link_categories slc
      JOIN "Categories" c ON c.id = slc.category_id
     WHERE slc.link_id = p_link
       AND c.owner_id <> auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.redeem_share_link(UUID) TO authenticated;
