-- Drop the now-unused Categories.private column.
--
-- The whole-category `private`/isPrivate flag was removed from all app code in
-- v1.0.0+69 (2026-08-29): the column is no longer read or written. Verified no
-- DB dependencies reference it (no RLS policy, function, or view uses a bare
-- `private` — only `tasks_are_private`, which is a DIFFERENT column and stays).
--
-- Irreversible (drops the per-row boolean values), but they were inert.
-- Apply via the Supabase dashboard SQL editor (MCP is read-only).

ALTER TABLE "Categories" DROP COLUMN IF EXISTS private;
