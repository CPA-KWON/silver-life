-- Run once in the SQL Editor, after facilities_schema.sql, so check-in
-- counts update live without a manual refresh.
alter publication supabase_realtime add table public.checkins;
