-- Show, per share link owned by the caller, the display names of users who
-- currently hold any of the link's pursuits (i.e. took it up).
--
-- Why a function: RLS on shared_categories is (auth.uid() = user_id), so a link
-- owner cannot read who ELSE subscribes to their shared pursuits. This SECURITY
-- DEFINER function reads it on their behalf, scoped to their own links only.
-- No new table / tracking — it just joins existing tables.
--
-- Names come from the taker's LIVE auth.users display name (full_name → name),
-- never their email address; the fallback for a user with no display name is the
-- email local-part. (The denormalized shared_categories.subscriber_name is stale
-- — it froze whatever name existed at redemption time, often the email.)
--
-- Attribution is by category overlap (approximate): links can share a pursuit,
-- so the same person may appear on more than one link.

CREATE OR REPLACE FUNCTION public.get_share_link_takers()
 RETURNS TABLE(link_id uuid, taker text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT slc.link_id,
    COALESCE(
      NULLIF(u.raw_user_meta_data->>'full_name', ''),
      NULLIF(u.raw_user_meta_data->>'name', ''),
      split_part(u.email, '@', 1)
    )
  FROM share_links sl
  JOIN share_link_categories slc ON slc.link_id = sl.id
  JOIN shared_categories sc      ON sc.category_id = slc.category_id
  JOIN auth.users u              ON u.id = sc.user_id
  WHERE sl.created_by = auth.uid()
    AND sc.user_id <> sl.created_by;
$function$;

GRANT EXECUTE ON FUNCTION public.get_share_link_takers() TO PUBLIC;
