-- Fix links column: Set NULL and malformed JSON strings to empty PostgreSQL arrays
-- Run this in your Supabase SQL editor

-- First, let's see the current state
SELECT 
  COUNT(*) as total_tasks,
  COUNT(CASE WHEN links IS NULL THEN 1 END) as null_links,
  COUNT(CASE WHEN links = '[]'::text[] THEN 1 END) as empty_array_links,
  COUNT(CASE WHEN links::text = '[]' THEN 1 END) as malformed_json_strings,
  COUNT(CASE WHEN links IS NOT NULL AND links != '[]'::text[] AND links::text != '[]' THEN 1 END) as valid_links
FROM "Tasks";

-- Update tasks with NULL links to empty arrays
UPDATE "Tasks" 
SET links = '{}'::text[] 
WHERE links IS NULL;

-- Update tasks with malformed JSON strings to empty arrays
UPDATE "Tasks" 
SET links = '{}'::text[] 
WHERE links::text = '[]' OR links::text = '{}' OR links::text = '';

-- Verify the fix
SELECT 
  COUNT(*) as total_tasks,
  COUNT(CASE WHEN links IS NULL THEN 1 END) as still_null_links,
  COUNT(CASE WHEN links::text = '[]' THEN 1 END) as still_malformed_strings,
  COUNT(CASE WHEN links IS NOT NULL AND links::text != '[]' THEN 1 END) as correct_arrays
FROM "Tasks";

-- Show a sample of the results
SELECT id, headline, links, pg_typeof(links) as links_type
FROM "Tasks" 
ORDER BY id 
LIMIT 10; 