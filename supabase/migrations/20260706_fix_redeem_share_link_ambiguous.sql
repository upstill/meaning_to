-- Fix: redeem_share_link raised "column reference category_id is ambiguous".
--
-- The function's RETURNS TABLE(category_id integer, headline text) puts an OUT
-- variable named `category_id` in scope for the whole body. In the
-- INSERT ... ON CONFLICT (user_id, category_id) the unqualified `category_id`
-- could mean either that OUT variable or the shared_categories column, and with
-- plpgsql's default variable_conflict = error Postgres refused to run it. So
-- redeeming a share link failed in every path (surfaced as a snackbar when the
-- recipient was already logged in, swallowed silently after sign-in/sign-up).
--
-- Adding `#variable_conflict use_column` makes ambiguous identifiers resolve to
-- the table column, which is what every reference here intends.
--
-- Also fixes a second latent bug that this one had been masking: the RETURN
-- QUERY selects "Categories".id (bigint), but the function declared the result
-- column as integer, so it failed with "Returned type bigint does not match
-- expected type integer". The result column is now bigint to match. (Dart reads
-- it as an int either way, so no client change.)
--
-- Changing the result column type requires dropping the function first
-- (CREATE OR REPLACE cannot change a function's OUT/result row type).

DROP FUNCTION IF EXISTS public.redeem_share_link(uuid);

CREATE OR REPLACE FUNCTION public.redeem_share_link(p_link uuid)
 RETURNS TABLE(category_id bigint, headline text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
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
$function$;

-- DROP wiped the previous grant; restore EXECUTE for callers.
GRANT EXECUTE ON FUNCTION public.redeem_share_link(uuid) TO PUBLIC;
