-- Fix find_tasks_by_link_url: the RETURNS TABLE(...) column list declared
-- id/category_id/original_id as `integer` and owner_id as `text`, and listed
-- columns in an order that didn't match `SELECT t.*`. The real "Tasks" columns
-- are bigint / uuid, so every call threw:
--   "structure of query does not match function result type ...
--    Returned type bigint does not match expected type integer in column 1."
-- That forced the client (IncomingLinkProcessor.findAllDuplicates) into a
-- full-table fallback scan, which was itself capped at 1000 rows — so URL-based
-- duplicate detection silently missed older tasks.
--
-- Redefine with explicit, correctly-typed columns selected in a fixed order
-- (never rely on `t.*` matching a declared TABLE signature). The return type
-- changes, so CREATE OR REPLACE is rejected ("cannot change return type of
-- existing function") — drop first.

DROP FUNCTION IF EXISTS public.find_tasks_by_link_url(text);

CREATE FUNCTION public.find_tasks_by_link_url(search_url_pattern text)
RETURNS TABLE(
  id bigint,
  created_at timestamptz,
  suggestible_at timestamptz,
  triggers_at timestamptz,
  category_id bigint,
  headline text,
  notes text,
  owner_id uuid,
  deferral integer,
  links text[],
  finished boolean,
  original_id bigint,
  shared boolean,
  priority smallint,
  synopsis text
)
LANGUAGE sql
STABLE
AS $function$
  SELECT t.id, t.created_at, t.suggestible_at, t.triggers_at, t.category_id,
         t.headline, t.notes, t.owner_id, t.deferral, t.links, t.finished,
         t.original_id, t.shared, t.priority, t.synopsis
  FROM "Tasks" t
  WHERE EXISTS (
    SELECT 1 FROM unnest(t.links) AS link
    WHERE link LIKE search_url_pattern
  )
  ORDER BY t.created_at DESC;
$function$;
