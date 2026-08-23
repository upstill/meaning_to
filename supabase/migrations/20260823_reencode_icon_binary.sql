-- Re-encode the "Icons".data column from its corrupt stringified form to real
-- image bytes.
--
-- BUG: DomainIcon.saveToDatabase used to send a raw Uint8List as the `data`
-- value. The Supabase/PostgREST client serialized it to a JSON int array, so
-- Postgres stored the LITERAL TEXT "[255,216,255,...]" into the bytea column
-- instead of the JPEG bytes. Image.memory could never decode it, so cached
-- favicons rendered blank (most visible on web, where the network fallback URL
-- is the CORS-blocked img.logo.dev). The client write path is fixed in
-- lib/models/icon.dart (DomainIcon.encodeBytea → `\x`-hex bytea literal); this
-- migration repairs the ~40 rows already written the old way.
--
-- Idempotent: only touches rows whose first byte is ASCII '[' (0x5B = 91), i.e.
-- still in the stringified form. Rows already holding real image bytes (which
-- start with a JPEG/PNG magic byte, never '[') are left untouched, so this is
-- safe to run more than once.

UPDATE "Icons" i
SET data = sub.newdata
FROM (
  SELECT domain,
    decode(string_agg(lpad(to_hex(x::int), 2, '0'), ''), 'hex') AS newdata
  FROM "Icons",
       LATERAL unnest(
         string_to_array(
           regexp_replace(convert_from(data, 'UTF8'), '[\[\]\s]', '', 'g'),
           ','
         )
       ) AS x
  WHERE get_byte(data, 0) = 91  -- ASCII '[' : only the corrupt stringified rows
  GROUP BY domain
) sub
WHERE i.domain = sub.domain
  AND get_byte(i.data, 0) = 91;

-- Verify (expects real image magic bytes, e.g. ffd8 for JPEG / 8950 for PNG,
-- and zero remaining rows that still start with '['):
--   SELECT count(*) FILTER (WHERE get_byte(data,0) = 91) AS still_corrupt,
--          count(*) AS total
--   FROM "Icons";
