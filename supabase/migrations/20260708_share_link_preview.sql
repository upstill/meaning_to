-- Preview a share link before signing in: who's inviting, and how many pursuits.
-- Callable by anon (a logged-out invite-follower has no session), so it's a
-- SECURITY DEFINER function reading share_links + auth.users, exposing only the
-- inviter's display name (never their email) and a count.

CREATE OR REPLACE FUNCTION public.get_share_link_preview(p_link uuid)
 RETURNS TABLE(inviter_name text, num_pursuits int)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    COALESCE(
      NULLIF(u.raw_user_meta_data->>'full_name', ''),
      NULLIF(u.raw_user_meta_data->>'name', ''),
      split_part(u.email, '@', 1)
    ),
    (SELECT count(*)::int
       FROM share_link_categories slc
      WHERE slc.link_id = sl.id)
  FROM share_links sl
  JOIN auth.users u ON u.id = sl.created_by
  WHERE sl.id = p_link;
$function$;

GRANT EXECUTE ON FUNCTION public.get_share_link_preview(uuid) TO anon, authenticated;
