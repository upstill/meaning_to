-- Returns all categories that have an open-to-all share invitation.
-- SECURITY DEFINER bypasses RLS so any authenticated user can discover them.
CREATE OR REPLACE FUNCTION get_discoverable_categories()
RETURNS SETOF "Categories"
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT ON (c.id) c.*
  FROM "Categories" c
  INNER JOIN share_invitations si ON si.category_id = c.id
  WHERE si.open_to_all = true;
$$;
