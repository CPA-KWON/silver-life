-- O01–O10. Requests do not grant membership. Only a trusted operator with a
-- server service role (or SQL Editor) can run institution_review_access.
begin;
alter table public.activity_organizations add column if not exists facility_id uuid references public.facilities(id);
create unique index if not exists activity_organizations_facility on public.activity_organizations(facility_id) where facility_id is not null;
create table if not exists public.institution_access_requests (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 facility_id uuid not null references public.facilities(id),
 institution_name text not null, institution_kind text not null check(institution_kind in('복지관','주민센터','경로당','보건소','기타')),
 contact_name text not null check(length(contact_name) between 1 and 50),
 department text not null check(length(department)<=100),
 duties text[] not null check(cardinality(duties) between 1 and 4 and duties <@ array['프로그램 운영','신청자 관리','공지 작성','경험 나눔 모집']),
 contact_phone text not null check(length(contact_phone) between 8 and 50 and length(regexp_replace(contact_phone,'[^0-9]','','g'))>=8),
 proof_paths text[] not null default '{}' check(cardinality(proof_paths)<=3),
 consented_at timestamptz not null default now(),
 status text not null default 'pending' check(status in('pending','approved','rejected','cancelled')),
 rejection_reason text,org_id uuid references public.activity_organizations(id),
 created_at timestamptz not null default now(),reviewed_at timestamptz
);
create unique index if not exists institution_access_one_pending on public.institution_access_requests(user_id) where status='pending';
alter table public.institution_access_requests enable row level security;
revoke all on public.institution_access_requests from public,anon,authenticated;
grant select on public.institution_access_requests to authenticated;
drop policy if exists institution_access_own on public.institution_access_requests;
create policy institution_access_own on public.institution_access_requests for select to authenticated using(user_id=auth.uid());
create or replace function public.institution_request_access(request_id uuid, details jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); facility public.facilities; r public.institution_access_requests;
 proofs text[]; requested_duties text[];
begin
 if u is null then raise exception '로그인이 필요해요' using errcode='42501';end if;
 -- Serialize submissions from one user, including uncertain-response retries.
 perform 1 from auth.users where id=u for update;
 select * into r from public.institution_access_requests where id=request_id and user_id=u;
 if found then return to_jsonb(r);end if;
 if exists(select 1 from public.institution_access_requests where user_id=u and status='pending') then raise exception '이미 심사 중인 요청이 있어요';end if;
 if exists(select 1 from public.activity_org_members m join public.activity_organizations o on o.id=m.org_id where m.user_id=u and o.approved) then raise exception '이미 기관 담당자로 연결되어 있어요';end if;
 if (details->>'consent') is distinct from 'true' then raise exception '기관 정보 확인·이용에 동의해 주세요';end if;
 select * into facility from public.facilities where id=(details->>'facility_id')::uuid;
 if not found then raise exception '기관을 다시 골라 주세요';end if;
 proofs:=array(select jsonb_array_elements_text(coalesce(details->'proof_paths','[]'::jsonb)));
 requested_duties:=array(select jsonb_array_elements_text(coalesce(details->'duties','[]'::jsonb)));
 if exists(select 1 from unnest(proofs) p where p not like u::text||'/org-proofs/%' or not exists(select 1 from storage.objects o where o.bucket_id='neighborhood-media' and o.name=p)) then raise exception '재직 확인 자료를 확인해 주세요';end if;
 insert into public.institution_access_requests(id,user_id,facility_id,institution_name,institution_kind,contact_name,department,duties,contact_phone,proof_paths)
 values(request_id,u,facility.id,facility.name,details->>'institution_kind',trim(details->>'contact_name'),trim(coalesce(details->>'department','')),requested_duties,trim(details->>'contact_phone'),proofs) returning * into r;
 return to_jsonb(r);
end $$;
create or replace function public.institution_cancel_access(request_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception '로그인이 필요해요' using errcode='42501';end if;
 update public.institution_access_requests set status='cancelled',reviewed_at=now() where id=request_id and user_id=auth.uid() and status='pending';
 if not found then raise exception '취소할 심사 요청을 찾을 수 없어요';end if;
end $$;
create or replace function public.institution_review_access(request_id uuid, approve boolean, target_org uuid default null, reason text default null) returns void
language plpgsql security definer set search_path='' as $$
declare r public.institution_access_requests; org public.activity_organizations; selected_org uuid;
begin
 select * into r from public.institution_access_requests where id=request_id for update;
 if not found or r.status<>'pending' then raise exception '심사 중인 요청만 처리할 수 있어요';end if;
 if approve then
  if target_org is null then
   if exists(select 1 from public.activity_organizations where facility_id=r.facility_id) then raise exception '이 기관은 이미 등록되어 있어요. 기존 기관을 지정해 주세요';end if;
   insert into public.activity_organizations(name,approved,facility_id) values(r.institution_name,true,r.facility_id) returning id into selected_org;
  else
   select * into org from public.activity_organizations where id=target_org for update;
   if not found or not org.approved or org.name<>r.institution_name or (org.facility_id is not null and org.facility_id<>r.facility_id) then raise exception '요청한 시설과 승인할 기관을 확인해 주세요';end if;
   update public.activity_organizations set facility_id=r.facility_id where id=org.id;
   selected_org:=org.id;
  end if;
  insert into public.activity_org_members(org_id,user_id) values(selected_org,r.user_id) on conflict do nothing;
  update public.institution_access_requests set status='approved',org_id=selected_org,reviewed_at=now(),rejection_reason=null where id=request_id;
 else
  if length(trim(coalesce(reason,''))) not between 5 and 1000 then raise exception '반려 이유를 5~1000자로 적어 주세요';end if;
  update public.institution_access_requests set status='rejected',rejection_reason=trim(reason),reviewed_at=now() where id=request_id;
 end if;
end $$;
revoke all on function public.institution_request_access(uuid,jsonb),public.institution_cancel_access(uuid),public.institution_review_access(uuid,boolean,uuid,text) from public,anon,authenticated;
grant execute on function public.institution_request_access(uuid,jsonb),public.institution_cancel_access(uuid) to authenticated;
grant execute on function public.institution_review_access(uuid,boolean,uuid,text) to service_role;
-- Proofs have no public read policy. Staff review uses a trusted server.
drop policy if exists neighborhood_media_upload on storage.objects;
create policy neighborhood_media_upload on storage.objects for insert to authenticated with check(bucket_id='neighborhood-media' and (storage.foldername(name))[1]=auth.uid()::text and (storage.foldername(name))[2] in('posts','avatars','org-proofs'));
commit;
notify pgrst,'reload schema';
