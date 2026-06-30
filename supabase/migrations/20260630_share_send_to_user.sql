-- In-app "Send To User": search for a user and grant them a set of pursuits
-- directly (no link round-trip). Apply via the Supabase SQL Editor (MCP is read-only).

-- ── 1. search_users ──────────────────────────────────────────────────────────
-- Matches other users by name OR email substring, but returns only a display
-- NAME — never the email. So a full email you already know finds the person,
-- while partial matches never reveal anyone's address.
CREATE OR REPLACE FUNCTION public.search_users(p_query TEXT)
  RETURNS TABLE(id UUID, name TEXT)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
BEGIN
  IF p_query IS NULL OR length(trim(p_query)) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
    SELECT u.id,
           COALESCE(u.raw_user_meta_data->>'full_name',
                    u.raw_user_meta_data->>'name',
                    '(unnamed user)') AS name
      FROM auth.users u
     WHERE u.id <> auth.uid()
       AND (
         u.raw_user_meta_data->>'full_name' ILIKE '%' || p_query || '%'
         OR u.raw_user_meta_data->>'name'   ILIKE '%' || p_query || '%'
         OR u.email                          ILIKE '%' || p_query || '%'
       )
     ORDER BY name
     LIMIT 25;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_users(TEXT) TO authenticated;

-- ── 2. send_share_to_user ────────────────────────────────────────────────────
-- Grants every pursuit in p_category_ids (all owned by the caller) directly to
-- p_recipient, marking each new subscription unseen so the recipient's
-- new-shares notification fires. Returns the number of pursuits granted.
CREATE OR REPLACE FUNCTION public.send_share_to_user(
    p_category_ids INTEGER[], p_recipient UUID)
  RETURNS INTEGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_count           INTEGER;
  v_granted         INTEGER;
  v_subscriber_name TEXT;
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

  -- Resolve the recipient's display name once.
  SELECT COALESCE(raw_user_meta_data->>'full_name',
                  raw_user_meta_data->>'name',
                  email)
    INTO v_subscriber_name
    FROM auth.users
   WHERE id = p_recipient;

  WITH inserted AS (
    INSERT INTO shared_categories(user_id, category_id, owner_name,
                                  subscriber_name, available, seen_at)
    SELECT
      p_recipient,
      c.id,
      COALESCE(u.raw_user_meta_data->>'full_name',
               u.raw_user_meta_data->>'name',
               u.email),
      v_subscriber_name,
      false,
      NULL
    FROM "Categories" c
    JOIN auth.users u ON u.id = c.owner_id
    WHERE c.id = ANY(p_category_ids)
      AND c.owner_id <> p_recipient
    ON CONFLICT (user_id, category_id) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_granted FROM inserted;

  RETURN v_granted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_share_to_user(INTEGER[], UUID) TO authenticated;
