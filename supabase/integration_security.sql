-- Apply after the existing main schema (including reports.sql / region_split.sql).
-- Transactional and repeatable. Review/back up the live database before applying.
begin;

-- Never broaden access to private profiles to fix author nickname joins.
-- Restrictive policies also protect installations that added a broad policy.
drop policy if exists profiles_private_read on public.profiles;
create policy profiles_private_read on public.profiles as restrictive
for select to authenticated using (id = auth.uid());

create or replace view public.public_profiles
with (security_barrier = true, security_invoker = false) as
select id, nickname, region_sido, region_sigungu
from public.profiles where auth.uid() is not null;
revoke all on public.public_profiles from public, anon, authenticated;
grant select on public.public_profiles to authenticated;

-- Computed relationships override PostgREST's original profiles join, keeping
-- profiles!inner(...) and its region filters compatible with current clients.
create or replace function public.profiles(public.posts)
returns setof public.public_profiles rows 1
language sql stable security definer set search_path = '' as $$
  select p.* from public.public_profiles p
  where p.id = $1.author_id and auth.uid() is not null;
$$;
create or replace function public.profiles(public.comments)
returns setof public.public_profiles rows 1
language sql stable security definer set search_path = '' as $$
  select p.* from public.public_profiles p
  where p.id = $1.author_id and auth.uid() is not null;
$$;
revoke all on function public.profiles(public.posts) from public, anon;
revoke all on function public.profiles(public.comments) from public, anon;
grant execute on function public.profiles(public.posts) to authenticated;
grant execute on function public.profiles(public.comments) to authenticated;

-- Shared facility data may be created, but not rewritten by arbitrary visitors.
drop policy if exists "Signed-in users can update facilities" on public.facilities;
revoke update, delete on public.facilities from anon, authenticated;
drop policy if exists facilities_no_client_update on public.facilities;
create policy facilities_no_client_update on public.facilities as restrictive
for update to authenticated using (false) with check (false);
drop policy if exists facilities_no_client_delete on public.facilities;
create policy facilities_no_client_delete on public.facilities as restrictive
for delete to authenticated using (false);

create or replace function public.ensure_facility(data jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare result uuid; latitude double precision; longitude double precision;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다'; end if;
  latitude := (data->>'lat')::double precision;
  longitude := (data->>'lng')::double precision;
  if nullif(btrim(data->>'name'),'') is null
    or nullif(btrim(data->>'address'),'') is null
    or length(data->>'name') > 200 or length(data->>'address') > 500
    or latitude is null or longitude is null
    or not (latitude between -90 and 90)
    or not (longitude between -180 and 180)
  then raise exception '올바른 시설 정보가 필요합니다'; end if;
  insert into public.facilities(name,address,lat,lng,category,telephone,region_sido,region_sigungu)
  values(btrim(data->>'name'),btrim(data->>'address'),latitude,longitude,
    data->>'category',data->>'telephone',data->>'region_sido',data->>'region_sigungu')
  on conflict (name,address) do nothing returning id into result;
  if result is null then
    select id into result from public.facilities
    where name=btrim(data->>'name') and address=btrim(data->>'address');
  end if;
  return result;
end;
$$;
revoke all on function public.ensure_facility(jsonb) from public, anon;
grant execute on function public.ensure_facility(jsonb) to authenticated;

-- Only count is public within the signed-in app, never other users' locations.
drop policy if exists checkins_private_read on public.checkins;
create policy checkins_private_read on public.checkins as restrictive
for select to authenticated using(user_id = auth.uid());
create or replace function public.facility_presence(target_facility uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다'; end if;
  return (
    select jsonb_build_object('count',count(*),
      'checked_in',coalesce(bool_or(user_id=auth.uid()),false))
    from public.checkins
    where facility_id=target_facility
      and checked_in_at >= now()-interval '3 hours'
      and checked_in_at <= now()
  );
end;
$$;
revoke all on function public.facility_presence(uuid) from public, anon;
grant execute on function public.facility_presence(uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
