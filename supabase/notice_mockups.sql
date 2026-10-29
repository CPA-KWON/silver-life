-- N01–N05/A12–A13. Apply after neighborhood_media.sql and
-- institution_access_requests.sql. Additive; keeps existing notices and roles.
begin;
alter table public.institution_notices add column if not exists institution_kind text not null default '기타' check(institution_kind in('복지관','주민센터','보건소','경로당','기타'));
alter table public.institution_notices add column if not exists contact_phone text;
alter table public.institution_notices add column if not exists image_paths text[] not null default '{}';
alter table public.institution_notices add column if not exists linked_programs uuid[] not null default '{}';
create table if not exists public.institution_notice_readers (
 notice_id uuid not null references public.institution_notices(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 read_at timestamptz not null default now(),primary key(notice_id,user_id)
);
alter table public.institution_notice_readers enable row level security;
revoke all on public.institution_notice_readers from public,anon,authenticated;
-- Do not expose future scheduled or expired notices through direct table reads
-- or signed storage URLs. Staff can still preview their own unpublished work.
drop policy if exists institution_notices_read on public.institution_notices;
create policy institution_notices_read on public.institution_notices for select to authenticated using(
 public.activity_is_member(org_id) or (published and (publish_at is null or publish_at<=now())
  and (expires_at is null or expires_at>now()) and exists(select 1 from public.activity_organizations o where o.id=org_id and o.approved)));
grant select(important,pinned,publish_at,linked_program,institution_kind,contact_phone,image_paths,linked_programs) on public.institution_notices to authenticated;
create or replace function public.institution_notice_data(n public.institution_notices) returns jsonb
language sql stable security definer set search_path='' as $$
 select (to_jsonb(n)-'created_by')||jsonb_build_object('org_name',o.name,'summary',left(n.body,140),
  'telephone',coalesce(nullif(n.contact_phone,''),f.telephone),
  'facility',case when f.id is null then null else jsonb_build_object('id',f.id,'name',f.name,'address',f.address,'lat',f.lat,'lng',f.lng,'telephone',f.telephone) end,
  'reader_count',(select count(*) from public.institution_notice_readers r where r.notice_id=n.id),
  'programs',coalesce((select jsonb_agg(public.activity_program_data(p)) from public.activity_programs p
    where (p.id=any(n.linked_programs) or p.id=n.linked_program) and p.org_id=n.org_id and not p.draft),'[]'::jsonb))
 from public.activity_organizations o left join public.facilities f on f.id=o.facility_id where o.id=n.org_id
$$;
create or replace function public.institution_notice_feed() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid();begin
 if u is null then raise exception '로그인이 필요해요.' using errcode='42501';end if;
 return coalesce((select jsonb_agg(x.data order by x.pinned desc,x.important desc,x.published_at desc,x.id) from(
  select n.id,n.pinned,n.important,n.published_at,public.institution_notice_data(n)-'body' data
  from public.institution_notices n join public.activity_organizations o on o.id=n.org_id and o.approved
  join public.profiles p on p.id=u and p.region_sido=n.region_sido and p.region_sigungu=n.region_sigungu
  where n.published and (n.publish_at is null or n.publish_at<=now()) and (n.expires_at is null or n.expires_at>now())
  order by n.pinned desc,n.important desc,n.published_at desc,n.id limit 50
 )x),'[]'::jsonb);
end $$;
create or replace function public.institution_notice_detail(p_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare u uuid:=auth.uid();n public.institution_notices;begin
 if u is null then raise exception '로그인이 필요해요.' using errcode='42501';end if;
 select note.* into n from public.institution_notices note join public.activity_organizations o on o.id=note.org_id
 where note.id=p_id and (public.activity_is_member(note.org_id) or (o.approved and note.published
  and (note.publish_at is null or note.publish_at<=now()) and (note.expires_at is null or note.expires_at>now())));
 if not found then raise exception '게시가 종료됐거나 볼 수 없는 공지예요.';end if;
 if not public.activity_is_member(n.org_id) then
  insert into public.institution_notice_readers(notice_id,user_id) values(n.id,u) on conflict do nothing;
 end if;
 return public.institution_notice_data(n);
end $$;
create or replace function public.institution_notice_list() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception '로그인이 필요해요.' using errcode='42501';end if;
 return coalesce((select jsonb_agg(public.institution_notice_data(n) order by n.updated_at desc,n.id)
 from public.institution_notices n where public.activity_is_member(n.org_id)),'[]'::jsonb);
end $$;
create or replace function public.institution_notice_save_v2(p_data jsonb,p_id uuid default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();v_org uuid:=(p_data->>'org_id')::uuid;old public.institution_notices;result uuid:=coalesce(p_id,(p_data->>'client_request_id')::uuid,gen_random_uuid());
v_end timestamptz:=(p_data->>'expires_at')::timestamptz;v_start timestamptz:=(p_data->>'publish_at')::timestamptz;
paths text[]:=array(select jsonb_array_elements_text(coalesce(p_data->'image_paths','[]'::jsonb)));
programs uuid[]:=array(select distinct value::uuid from jsonb_array_elements_text(coalesce(p_data->'linked_programs','[]'::jsonb)));
begin
 if u is null or not public.activity_is_member(v_org) then raise exception '승인된 기관 담당자 권한이 필요해요.' using errcode='42501';end if;
 if v_end is not null and (v_end<=now() or v_end<=v_start) then raise exception '게시 종료일은 게시 시작일 이후로 선택해 주세요.';end if;
 if cardinality(paths)>5 or exists(select 1 from unnest(paths) p where p not like v_org::text||'/notices/%' or not exists(select 1 from storage.objects s where s.bucket_id='neighborhood-media' and s.name=p)) then raise exception '우리 기관의 첨부 사진을 골라 주세요.';end if;
 if cardinality(programs)>10 or exists(select 1 from unnest(programs) id where not exists(select 1 from public.activity_programs p where p.id=id and p.org_id=v_org and not p.draft)) then raise exception '우리 기관이 등록한 프로그램만 연결할 수 있어요.';end if;
 if nullif(p_data->>'contact_phone','') is not null and p_data->>'contact_phone' !~ '^[+0-9() -]{7,30}$' then raise exception '문의 전화번호를 확인해 주세요.';end if;
 select * into old from public.institution_notices where id=result for update;
 if found then
  if old.org_id<>v_org then raise exception '우리 기관 공지만 수정할 수 있어요.' using errcode='42501';end if;
  update public.institution_notices set title=trim(p_data->>'title'),body=trim(p_data->>'body'),region_sido=p_data->>'region_sido',region_sigungu=p_data->>'region_sigungu',source_url=nullif(trim(p_data->>'source_url'),''),expires_at=v_end,
   publish_at=v_start,important=coalesce((p_data->>'important')::boolean,false),pinned=coalesce((p_data->>'pinned')::boolean,false),institution_kind=coalesce(p_data->>'institution_kind','기타'),contact_phone=nullif(trim(p_data->>'contact_phone'),''),image_paths=paths,linked_programs=programs,linked_program=programs[1],updated_at=now() where id=result;
 else
  insert into public.institution_notices(id,org_id,title,body,region_sido,region_sigungu,source_url,expires_at,created_by,publish_at,important,pinned,institution_kind,contact_phone,image_paths,linked_programs,linked_program)
  values(result,v_org,trim(p_data->>'title'),trim(p_data->>'body'),p_data->>'region_sido',p_data->>'region_sigungu',nullif(trim(p_data->>'source_url'),''),v_end,u,v_start,coalesce((p_data->>'important')::boolean,false),coalesce((p_data->>'pinned')::boolean,false),coalesce(p_data->>'institution_kind','기타'),nullif(trim(p_data->>'contact_phone'),''),paths,programs,programs[1]);
 end if;
 return result;
end $$;
create or replace function public.institution_notice_publish(p_id uuid,p_published boolean) returns void
language plpgsql security definer set search_path='' as $$
declare old public.institution_notices;begin
 select * into old from public.institution_notices where id=p_id for update;
 if auth.uid() is null or not found or not public.activity_is_member(old.org_id) then raise exception '우리 기관 공지만 게시할 수 있어요.' using errcode='42501';end if;
 if p_published is null then raise exception '게시 상태를 선택해 주세요.';end if;
 if p_published and old.expires_at<=now() then raise exception '종료일을 수정한 뒤 게시해 주세요.';end if;
 update public.institution_notices set published=p_published,published_at=case when p_published then coalesce(publish_at,now()) else published_at end,updated_at=now() where id=p_id;
end $$;
create or replace function public.neighborhood_media_org_member(object_name text) returns boolean
language sql stable set search_path='' as $$
 select case when split_part(object_name,'/',1) ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
 then public.activity_is_member(split_part(object_name,'/',1)::uuid) else false end
$$;
revoke all on function public.neighborhood_media_org_member(text) from public,anon;
grant execute on function public.neighborhood_media_org_member(text) to authenticated;
-- Institution attachments are stored under org UUIDs and remain with the
-- institution if an individual staff account is deleted.
drop policy if exists neighborhood_media_upload on storage.objects;
create policy neighborhood_media_upload on storage.objects for insert to authenticated with check(bucket_id='neighborhood-media' and (
 ((storage.foldername(name))[1]=auth.uid()::text and (storage.foldername(name))[2] in('posts','avatars','org-proofs')) or
 ((storage.foldername(name))[2]='notices' and public.neighborhood_media_org_member(name))));
drop policy if exists neighborhood_media_read on storage.objects;
create policy neighborhood_media_read on storage.objects for select to authenticated using(bucket_id='neighborhood-media' and (
 ((storage.foldername(name))[1]=auth.uid()::text and (storage.foldername(name))[2] in('posts','avatars','org-proofs')) or
 (storage.foldername(name))[2]='avatars' or
 ((storage.foldername(name))[2]='posts' and exists(select 1 from public.posts p where name=any(p.image_paths))) or
 ((storage.foldername(name))[2]='notices' and (public.neighborhood_media_org_member(name) or exists(select 1 from public.institution_notices n where name=any(n.image_paths))))));
drop policy if exists neighborhood_media_remove on storage.objects;
create policy neighborhood_media_remove on storage.objects for delete to authenticated using(bucket_id='neighborhood-media' and (
 ((storage.foldername(name))[1]=auth.uid()::text and (storage.foldername(name))[2] in('posts','avatars','org-proofs')) or
 ((storage.foldername(name))[2]='notices' and public.neighborhood_media_org_member(name))));
revoke all on function public.institution_notice_data(public.institution_notices) from public,anon,authenticated;
revoke all on function public.institution_notice_save_v2(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.institution_notice_save_v2(jsonb,uuid) to authenticated;
commit;
notify pgrst,'reload schema';
