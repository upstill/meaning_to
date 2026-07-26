-- share_channel_status: drives the checkbox/advisory in the share-accept dialog.
-- For a redeemed link, returns the creator plus whether the link carries any
-- invite emails and whether the caller's account email is among them. Lets the
-- client show "also accept future shares from <name>" only on an email match,
-- and otherwise advise that the sender should invite THIS email.
--
-- Apply via the Supabase SQL editor.

CREATE OR REPLACE FUNCTION public.share_channel_status(p_link uuid)
  RETURNS TABLE(creator_id uuid, creator_name text,
                has_invites boolean, email_matches boolean)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_email   TEXT;
  v_creator UUID;
BEGIN
  SELECT lower(email) INTO v_email FROM auth.users WHERE id = auth.uid();
  SELECT sl.created_by INTO v_creator FROM share_links sl WHERE sl.id = p_link;

  -- No row → not applicable (unknown link, or the caller is the creator).
  IF v_creator IS NULL OR v_creator = auth.uid() THEN
    RETURN;
  END IF;

  RETURN QUERY
    SELECT
      v_creator,
      COALESCE((SELECT COALESCE(u.raw_user_meta_data->>'full_name',
                                u.raw_user_meta_data->>'name', '(unnamed user)')
                  FROM auth.users u WHERE u.id = v_creator), '(unnamed user)'),
      EXISTS(SELECT 1 FROM share_link_invites i WHERE i.link_id = p_link),
      EXISTS(SELECT 1 FROM share_link_invites i
              WHERE i.link_id = p_link AND lower(i.email) = v_email);
END;
$$;
GRANT EXECUTE ON FUNCTION public.share_channel_status(uuid) TO authenticated;
