-- Make account deletion complete: also remove the auth.users row.
--
-- The old delete_user() only ran `DELETE FROM auth.users`, relying on the client
-- to have first deleted the user's Categories/Tasks (which reference auth.users
-- with ON DELETE NO ACTION). If those weren't fully cleared (e.g. RLS blocked the
-- client delete), the auth.users delete failed the FK check and — because the
-- client swallows the RPC error — the account row silently survived.
--
-- Do the whole thing server-side as the definer (postgres, which CAN delete from
-- auth.users and bypasses RLS): clear the two NO ACTION blockers, then delete the
-- auth user. Everything else — shared_categories, share_links, share_invitations,
-- and all auth-internal tables (identities, sessions, …) — is ON DELETE CASCADE.

CREATE OR REPLACE FUNCTION public.delete_user()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Clear the NO ACTION foreign keys to auth.users. Deleting a Category cascades
  -- its dependents (share_link_categories, shared_categories for it, etc.).
  DELETE FROM "Tasks"      WHERE owner_id = v_uid;
  DELETE FROM "Categories" WHERE owner_id = v_uid;

  -- Remove the auth user. Remaining references cascade automatically.
  DELETE FROM auth.users WHERE id = v_uid;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.delete_user() TO PUBLIC;
