-- Consent-gated direct sharing (email-matched channels).
--
-- Replaces the old stranger-contact vector (all-user search_users +
-- unconditional send_share_to_user) with a consent channel that can only form
-- between people who already know each other's email. Share links stay
-- broadcast-safe (anyone who opens one gets the read-only pursuits); the
-- "allow direct sends" channel only opens for a redeemer whose account email
-- matches an email the sender attached to the link.
--
-- Apply via the Supabase SQL editor (MCP is read-only).

-- ── 1. Tables ────────────────────────────────────────────────────────────────

-- Optional per-link target emails (normalized lowercase). Not client-readable:
-- RLS on with no policies → only SECURITY DEFINER functions (owned by postgres)
-- can touch it. This is the gate; it never leaks whether an email is a user.
CREATE TABLE IF NOT EXISTS public.share_link_invites (
  link_id UUID NOT NULL REFERENCES public.share_links(id) ON DELETE CASCADE,
  email   TEXT NOT NULL,
  PRIMARY KEY (link_id, email)
);
ALTER TABLE public.share_link_invites ENABLE ROW LEVEL SECURITY;

-- Granted channels: recipient allows sender to send them pursuits directly.
CREATE TABLE IF NOT EXISTS public.allowed_senders (
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (recipient_id, sender_id)
);
ALTER TABLE public.allowed_senders ENABLE ROW LEVEL SECURITY;

-- Either party may see the relationship; only the recipient may revoke it.
-- (Inserts happen only via accept_share_channel, SECURITY DEFINER.)
DROP POLICY IF EXISTS allowed_senders_select ON public.allowed_senders;
CREATE POLICY allowed_senders_select ON public.allowed_senders
  FOR SELECT TO authenticated
  USING (auth.uid() IN (recipient_id, sender_id));

DROP POLICY IF EXISTS allowed_senders_delete ON public.allowed_senders;
CREATE POLICY allowed_senders_delete ON public.allowed_senders
  FOR DELETE TO authenticated
  USING (auth.uid() = recipient_id);

-- ── 2. create_share_link(int[], text[]) ─────────────────────────────────────
-- Same reusable-link behavior as before, plus optional target emails attached
-- as invites. Drop the 1-arg version so callers always pass emails ('{}' = none).
DROP FUNCTION IF EXISTS public.create_share_link(integer[]);
DROP FUNCTION IF EXISTS public.create_share_link(integer[], text[]);

CREATE OR REPLACE FUNCTION public.create_share_link(
    p_category_ids integer[], p_emails text[])
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_link  UUID;
  v_count INTEGER;
  v_want  INTEGER[];
BEGIN
  IF p_category_ids IS NULL OR array_length(p_category_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'No categories supplied';
  END IF;

  SELECT array_agg(DISTINCT x ORDER BY x) INTO v_want
    FROM unnest(p_category_ids) AS x;

  SELECT count(DISTINCT id) INTO v_count
    FROM "Categories"
   WHERE id = ANY(v_want)
     AND owner_id = auth.uid();

  IF v_count <> array_length(v_want, 1) THEN
    RAISE EXCEPTION 'Not authorized to share one or more of these categories';
  END IF;

  -- Reuse the caller's existing link with exactly this category set, if any.
  SELECT sl.id INTO v_link
    FROM share_links sl
   WHERE sl.created_by = auth.uid()
     AND (SELECT array_agg(DISTINCT slc.category_id ORDER BY slc.category_id)
            FROM share_link_categories slc
           WHERE slc.link_id = sl.id) = v_want
   ORDER BY sl.created_at
   LIMIT 1;

  IF v_link IS NULL THEN
    INSERT INTO share_links(created_by) VALUES (auth.uid())
      RETURNING id INTO v_link;
    INSERT INTO share_link_categories(link_id, category_id)
      SELECT v_link, unnest(v_want);
  END IF;

  -- Attach any target emails (normalized). Accumulates across reuse.
  IF p_emails IS NOT NULL THEN
    INSERT INTO share_link_invites(link_id, email)
      SELECT v_link, lower(trim(e))
        FROM unnest(p_emails) AS e
       WHERE trim(e) <> ''
      ON CONFLICT (link_id, email) DO NOTHING;
  END IF;

  RETURN v_link;
END;
$$;
GRANT EXECUTE ON FUNCTION public.create_share_link(integer[], text[]) TO authenticated;

-- ── 3. share_channel_offer(uuid) ─────────────────────────────────────────────
-- If the caller's account email matches an invite on this link, return the link
-- creator (id, name) so the client can offer "allow <name> to send you Pursuits
-- directly". Otherwise return nothing. Never reveals invites to anyone else.
CREATE OR REPLACE FUNCTION public.share_channel_offer(p_link uuid)
  RETURNS TABLE(id uuid, name text)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_email   TEXT;
  v_creator UUID;
BEGIN
  SELECT lower(email) INTO v_email FROM auth.users WHERE id = auth.uid();
  IF v_email IS NULL THEN RETURN; END IF;

  SELECT sl.created_by INTO v_creator FROM share_links sl WHERE sl.id = p_link;
  IF v_creator IS NULL OR v_creator = auth.uid() THEN RETURN; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM share_link_invites i
     WHERE i.link_id = p_link AND lower(i.email) = v_email
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
    SELECT u.id,
           COALESCE(u.raw_user_meta_data->>'full_name',
                    u.raw_user_meta_data->>'name', '(unnamed user)')
      FROM auth.users u
     WHERE u.id = v_creator;
END;
$$;
GRANT EXECUTE ON FUNCTION public.share_channel_offer(uuid) TO authenticated;

-- ── 4. accept_share_channel(uuid) ────────────────────────────────────────────
-- Grants the link creator a channel to the caller, only if the email gate passes.
CREATE OR REPLACE FUNCTION public.accept_share_channel(p_link uuid)
  RETURNS void
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

  IF v_creator IS NULL OR v_creator = auth.uid() OR v_email IS NULL THEN
    RAISE EXCEPTION 'Not eligible to open this channel';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM share_link_invites i
     WHERE i.link_id = p_link AND lower(i.email) = v_email
  ) THEN
    RAISE EXCEPTION 'Not eligible to open this channel';
  END IF;

  INSERT INTO allowed_senders(recipient_id, sender_id)
    VALUES (auth.uid(), v_creator)
  ON CONFLICT (recipient_id, sender_id) DO NOTHING;
END;
$$;
GRANT EXECUTE ON FUNCTION public.accept_share_channel(uuid) TO authenticated;

-- ── 5. search_users(text) — RESCOPED to the caller's recipients ──────────────
-- No longer searches all users or emails. Returns people who have granted the
-- caller a channel (allowed_senders where sender = caller), by name. An empty/
-- short query returns the full recipient list so it doubles as the picker.
CREATE OR REPLACE FUNCTION public.search_users(p_query text)
  RETURNS TABLE(id uuid, name text)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    SELECT u.id,
           COALESCE(u.raw_user_meta_data->>'full_name',
                    u.raw_user_meta_data->>'name', '(unnamed user)') AS name
      FROM allowed_senders a
      JOIN auth.users u ON u.id = a.recipient_id
     WHERE a.sender_id = auth.uid()
       AND (
         p_query IS NULL OR length(trim(p_query)) < 2
         OR u.raw_user_meta_data->>'full_name' ILIKE '%' || p_query || '%'
         OR u.raw_user_meta_data->>'name'      ILIKE '%' || p_query || '%'
       )
     ORDER BY name
     LIMIT 50;
END;
$$;
GRANT EXECUTE ON FUNCTION public.search_users(text) TO authenticated;

-- ── 6. list_allowed_senders() — people who can send to me (manage/unfriend) ──
CREATE OR REPLACE FUNCTION public.list_allowed_senders()
  RETURNS TABLE(id uuid, name text)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    SELECT u.id,
           COALESCE(u.raw_user_meta_data->>'full_name',
                    u.raw_user_meta_data->>'name', '(unnamed user)') AS name
      FROM allowed_senders a
      JOIN auth.users u ON u.id = a.sender_id
     WHERE a.recipient_id = auth.uid()
     ORDER BY name;
END;
$$;
GRANT EXECUTE ON FUNCTION public.list_allowed_senders() TO authenticated;

-- ── 7. revoke_allowed_sender(uuid) — unfriend / block future direct sends ────
CREATE OR REPLACE FUNCTION public.revoke_allowed_sender(p_sender uuid)
  RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path = public
AS $$
  DELETE FROM allowed_senders
   WHERE recipient_id = auth.uid() AND sender_id = p_sender;
$$;
GRANT EXECUTE ON FUNCTION public.revoke_allowed_sender(uuid) TO authenticated;

-- ── 8. send_share_to_user(int[], uuid) — now gated by an allowed_senders row ─
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

  -- Consent gate: recipient must have granted the caller a channel.
  IF NOT EXISTS (
    SELECT 1 FROM allowed_senders
     WHERE recipient_id = p_recipient AND sender_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Recipient has not allowed you to send them Pursuits';
  END IF;

  SELECT count(*) INTO v_count
    FROM "Categories"
   WHERE id = ANY(p_category_ids)
     AND owner_id = auth.uid();

  IF v_count <> array_length(p_category_ids, 1) THEN
    RAISE EXCEPTION 'Not authorized to share one or more of these categories';
  END IF;

  SELECT COALESCE(raw_user_meta_data->>'full_name',
                  raw_user_meta_data->>'name', email)
    INTO v_subscriber_name
    FROM auth.users
   WHERE id = p_recipient;

  WITH inserted AS (
    INSERT INTO shared_categories(user_id, category_id, owner_name,
                                  subscriber_name, available, seen_at)
    SELECT
      p_recipient, c.id,
      COALESCE(u.raw_user_meta_data->>'full_name',
               u.raw_user_meta_data->>'name', u.email),
      v_subscriber_name, false, NULL
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
