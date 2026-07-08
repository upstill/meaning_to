-- Reuse an existing share link when the caller already has one granting exactly
-- the same set of pursuits, instead of minting a redundant new link every time.
-- (Share links are permanent and reusable by design, so returning the existing
-- one is correct and keeps the "your share links" list free of duplicates.)
--
-- Matching is by exact category SET (order/duplicate-insensitive). A different
-- set — even a subset or superset — still creates a new link.

CREATE OR REPLACE FUNCTION public.create_share_link(p_category_ids integer[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_link  UUID;
  v_count INTEGER;
  v_want  INTEGER[];   -- normalized (distinct, sorted) requested set
BEGIN
  IF p_category_ids IS NULL OR array_length(p_category_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'No categories supplied';
  END IF;

  SELECT array_agg(DISTINCT x ORDER BY x) INTO v_want
    FROM unnest(p_category_ids) AS x;

  -- Every supplied category must exist and be owned by the caller.
  SELECT count(DISTINCT id) INTO v_count
    FROM "Categories"
   WHERE id = ANY(v_want)
     AND owner_id = auth.uid();

  IF v_count <> array_length(v_want, 1) THEN
    RAISE EXCEPTION 'Not authorized to share one or more of these categories';
  END IF;

  -- Reuse the caller's existing link with exactly this set, if any.
  SELECT sl.id INTO v_link
    FROM share_links sl
   WHERE sl.created_by = auth.uid()
     AND (SELECT array_agg(DISTINCT slc.category_id ORDER BY slc.category_id)
            FROM share_link_categories slc
           WHERE slc.link_id = sl.id) = v_want
   ORDER BY sl.created_at
   LIMIT 1;

  IF v_link IS NOT NULL THEN
    RETURN v_link;
  END IF;

  INSERT INTO share_links(created_by) VALUES (auth.uid())
    RETURNING id INTO v_link;

  INSERT INTO share_link_categories(link_id, category_id)
    SELECT v_link, unnest(v_want);

  RETURN v_link;
END;
$function$;
