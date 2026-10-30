-- Add public provenance to the existing read-only welfare catalog.
-- Does not create partner organizations, enrollment, missions or reward rights.
-- Existing source/source_id keys, 85 records, favorites and RLS remain intact.
begin;
alter table public.welfare_programs
 add column if not exists source_url text,
 add column if not exists source_verified_at timestamptz,
 add column if not exists source_status text,
 add column if not exists registration_starts_on date,
 add column if not exists registration_ends_on date,
 add column if not exists program_ends_on date,
 add column if not exists contact_phone text,
 add column if not exists preparations text,
 add column if not exists location_is_offsite boolean;
notify pgrst, 'reload schema';
commit;
