-- 0009: force PostgREST schema-cache reload (create_ride returned
-- transient 404s after the 0008 replace; DDL below validates cleanly).
notify pgrst, 'reload schema';
