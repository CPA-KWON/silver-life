-- F01–F11. Keeps facilities, favorites and presence reads. Apply after
-- institution_access_requests.sql and notice_mockups.sql.
begin;
create table if not exists public.facility_guides(
 facility_id uuid primary key references public.facilities(id) on delete cascade,
 org_id uuid not null references public.activity_organizations(id),
 opening_hours text not null default '' check(length(opening_hours)<=2000),
 floor_guide text not null default '' check(length(floor_guide)<=2000),
 accessibility text not null default '' check(length(accessibility)<=2000),
 contact_phone text check(contact_phone is null or contact_phone ~ '^[+0-9() -]{7,30}$'),
 elevator boolean,entry_steps integer check(entry_steps between 0 and 200),resting_seats boolean,
 image_paths text[] not null default '{}' check(cardinality(image_paths)<=5),
 updated_at timestamptz not null default now(),updated_by uuid references auth.users(id) on delete set null
);
alter table public.facility_guides enable row level security;
revoke all on public.facility_guides from public,anon,authenticated;
grant select(facility_id,org_id,opening_hours,floor_guide,accessibility,contact_phone,elevator,entry_steps,resting_seats,image_paths,updated_at) on public.facility_guides to authenticated;
drop policy if exists facility_guides_read on public.facility_guides;
create policy facility_guides_read on public.facility_guides for select to authenticated using(exists(select 1 from public.activity_organizations o where o.id=org_id and o.approved and o.facility_id=public.facility_guides.facility_id));
create or replace function public.facility_guide(target_facility uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;begin
 if auth.uid() is null then raise exception '로그인이 필요해요' using errcode='42501';end if;
 select (to_jsonb(g)-'updated_by')||jsonb_build_object('org_name',o.name) into result
 from public.facility_guides g join public.activity_organizations o on o.id=g.org_id and o.approved and o.facility_id=g.facility_id where g.facility_id=target_facility;
 return coalesce(result,'{}'::jsonb);
end $$;
create or replace function public.facility_guide_save(target_org uuid,details jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare o public.activity_organizations;paths text[]:=array(select jsonb_array_elements_text(coalesce(details->'image_paths','[]'::jsonb)));
begin
 select * into o from public.activity_organizations where id=target_org;
 if auth.uid() is null or not found or not public.activity_is_member(o.id) or o.facility_id is null then raise exception '인증된 기관과 연결된 시설만 수정할 수 있어요' using errcode='42501';end if;
 if cardinality(paths)>5 or exists(select 1 from unnest(paths) p where p not like o.id::text||'/notices/%' or not exists(select 1 from storage.objects s where s.bucket_id='neighborhood-media' and s.name=p)) then raise exception '우리 기관의 안내 이미지를 골라 주세요';end if;
 insert into public.facility_guides(facility_id,org_id,opening_hours,floor_guide,accessibility,contact_phone,elevator,entry_steps,resting_seats,image_paths,updated_by)
 values(o.facility_id,o.id,trim(coalesce(details->>'opening_hours','')),trim(coalesce(details->>'floor_guide','')),trim(coalesce(details->>'accessibility','')),nullif(trim(details->>'contact_phone'),''),(details->>'elevator')::boolean,(details->>'entry_steps')::integer,(details->>'resting_seats')::boolean,paths,auth.uid())
 on conflict(facility_id) do update set org_id=excluded.org_id,opening_hours=excluded.opening_hours,floor_guide=excluded.floor_guide,accessibility=excluded.accessibility,contact_phone=excluded.contact_phone,elevator=excluded.elevator,entry_steps=excluded.entry_steps,resting_seats=excluded.resting_seats,image_paths=excluded.image_paths,updated_at=now(),updated_by=auth.uid();
end $$;
-- A check-in represents a nearby device fix, not a program attendance reward.
-- GPS spoofing cannot be ruled out by client-provided coordinates; no points
-- or institutional completion are issued by this function.
create or replace function public.facility_check_in(target_facility uuid,latitude double precision,longitude double precision,accuracy double precision,captured_at timestamptz) returns void
language plpgsql security definer set search_path='' as $$
declare f public.facilities;u uuid:=auth.uid();begin
 if u is null then raise exception '로그인이 필요해요' using errcode='42501';end if;
 if latitude is null or longitude is null or accuracy is null or captured_at is null
  or not(latitude between -90 and 90) or not(longitude between -180 and 180)
  or not(accuracy between 0 and 100) or captured_at<now()-interval '2 minutes' or captured_at>now()+interval '10 seconds' then raise exception '정확한 현재 위치를 다시 확인해 주세요';end if;
 select * into f from public.facilities where id=target_facility;
 if not found then raise exception '시설을 찾을 수 없어요';end if;
 if f.lat is null or f.lng is null or not(f.lat between -90 and 90) or not(f.lng between -180 and 180) then raise exception '시설 위치를 확인하지 못했어요';end if;
 if public.activity_distance(latitude,longitude,f.lat,f.lng)>.2 then raise exception '시설 200m 안에 도착한 뒤 체크인해 주세요';end if;
 insert into public.checkins(user_id,facility_id,checked_in_at) values(u,f.id,now())
 on conflict(user_id,facility_id) do update set checked_in_at=now();
end $$;
revoke insert,update on public.checkins from public,anon,authenticated;
revoke all on function public.facility_guide(uuid),public.facility_guide_save(uuid,jsonb),public.facility_check_in(uuid,double precision,double precision,double precision,timestamptz) from public,anon,authenticated;
grant execute on function public.facility_guide(uuid),public.facility_guide_save(uuid,jsonb),public.facility_check_in(uuid,double precision,double precision,double precision,timestamptz) to authenticated;
-- Extend institutional image reads to the approved facility guide.
drop policy if exists neighborhood_media_read on storage.objects;
create policy neighborhood_media_read on storage.objects for select to authenticated using(bucket_id='neighborhood-media' and (
 ((storage.foldername(name))[1]=auth.uid()::text and (storage.foldername(name))[2] in('posts','avatars','org-proofs')) or
 (storage.foldername(name))[2]='avatars' or
 ((storage.foldername(name))[2]='posts' and exists(select 1 from public.posts p where name=any(p.image_paths))) or
 ((storage.foldername(name))[2]='notices' and (public.neighborhood_media_org_member(name) or exists(select 1 from public.institution_notices n where name=any(n.image_paths)) or exists(select 1 from public.facility_guides g where name=any(g.image_paths))))));
commit;
notify pgrst,'reload schema';
