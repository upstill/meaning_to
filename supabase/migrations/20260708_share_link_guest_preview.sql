-- Let a guest (anon, no session) preview the pursuits a share link grants,
-- read-only. RLS limits anon to the guest UUID's own categories/tasks, so these
-- SECURITY DEFINER functions expose ONLY the given link's contents to anon.

-- The link's categories, each with the owner's display name (never their email).
CREATE OR REPLACE FUNCTION public.get_share_link_pursuits(p_link uuid)
 RETURNS TABLE(category jsonb, owner_name text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT to_jsonb(c),
         COALESCE(
           NULLIF(u.raw_user_meta_data->>'full_name', ''),
           NULLIF(u.raw_user_meta_data->>'name', ''),
           split_part(u.email, '@', 1)
         )
  FROM share_link_categories slc
  JOIN "Categories" c ON c.id = slc.category_id
  JOIN auth.users   u ON u.id = c.owner_id
  WHERE slc.link_id = p_link;
$function$;

GRANT EXECUTE ON FUNCTION public.get_share_link_pursuits(uuid) TO anon, authenticated;

-- The shared (non-private) tasks of one category, only if it's in the link.
CREATE OR REPLACE FUNCTION public.get_share_link_tasks(p_link uuid, p_category bigint)
 RETURNS SETOF "Tasks"
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT t.*
  FROM "Tasks" t
  WHERE t.category_id = p_category
    AND t.shared = true
    AND EXISTS (
      SELECT 1 FROM share_link_categories slc
      WHERE slc.link_id = p_link AND slc.category_id = p_category
    );
$function$;

GRANT EXECUTE ON FUNCTION public.get_share_link_tasks(uuid, bigint) TO anon, authenticated;
