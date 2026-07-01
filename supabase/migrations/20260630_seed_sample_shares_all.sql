-- Onboarding seed: subscribe a new user to ALL of the sample owner's Pursuits.
-- Replaces the previous redeem_sample_shares, which only granted the owner's
-- open_to_all share-invitations — a model that was retired, so new users got
-- nothing. Now it grants every category owned by p_owner_email.
-- Apply via the Supabase SQL Editor (MCP access is read-only).

CREATE OR REPLACE FUNCTION public.redeem_sample_shares(
  p_owner_email text,
  p_available   boolean DEFAULT true
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id        uuid;
  v_owner_name      text;
  v_subscriber_id   uuid;
  v_subscriber_name text;
  v_category_id     integer;
  v_count           integer := 0;
BEGIN
  -- Resolve the sample-share owner.
  SELECT id,
         COALESCE(raw_user_meta_data->>'full_name', email)
  INTO   v_owner_id, v_owner_name
  FROM   auth.users
  WHERE  email = p_owner_email
  LIMIT  1;

  IF v_owner_id IS NULL THEN
    RETURN 0;
  END IF;

  -- Calling user.
  v_subscriber_id := auth.uid();
  IF v_subscriber_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Never subscribe the owner to their own categories.
  IF v_subscriber_id = v_owner_id THEN
    RETURN 0;
  END IF;

  -- Subscriber display name.
  SELECT COALESCE(raw_user_meta_data->>'full_name', email)
  INTO   v_subscriber_name
  FROM   auth.users
  WHERE  id = v_subscriber_id;

  -- Subscribe to EVERY category owned by the sample owner.
  FOR v_category_id IN
    SELECT c.id
    FROM   "Categories" c
    WHERE  c.owner_id = v_owner_id
  LOOP
    -- seen_at = now() so onboarding seeds don't also trigger the "New Pursuits
    -- shared with you" notification (the welcome dialog already greets them).
    INSERT INTO shared_categories
      (category_id, user_id, available, owner_name, subscriber_name,
       shared_at, seen_at)
    VALUES
      (v_category_id, v_subscriber_id, p_available,
       v_owner_name, v_subscriber_name, now(), now())
    ON CONFLICT (user_id, category_id) DO NOTHING;

    IF FOUND THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.redeem_sample_shares(text, boolean) TO authenticated;
