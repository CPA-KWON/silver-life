-- 기관 공지: 기존 활동 기관/회원/지역 설정을 재사용. 기존 정책/표는 변경하지 않음.
begin;
create table if not exists public.institution_notices (
 id uuid primary key default gen_random_uuid(),org_id uuid not null references public.activity_organizations,
 title text not null check(char_length(btrim(title)) between 1 and 100),
 body text not null check(char_length(btrim(body)) between 1 and 5000),
 region_sido text not null check(region_sido in('서울특별시','부산광역시','인천광역시','대구광역시','광주광역시','대전광역시','울산광역시','세종특별자치시','경기도','강원특별자치도','충청북도','충청남도','경상북도','경상남도','전북특별자치도','전라남도','제주특별자치도')),
 region_sigungu text not null check(char_length(btrim(region_sigungu)) between 1 and 50),
 source_url text check(source_url is null or (char_length(source_url)<=2048 and source_url ~ '^https://[A-Za-z0-9.-]+([/?#][^[:space:]]*)?$')),
 published boolean not null default false,published_at timestamptz,expires_at timestamptz,
 created_by uuid not null references auth.users,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table public.institution_notices enable row level security;
revoke all on public.institution_notices from public,anon,authenticated;
-- 작성자 개인 UUID는 공개하지 않음. 쓰기는 기관 권한 검사 RPC만 사용.
grant select(id,org_id,title,body,region_sido,region_sigungu,source_url,published,published_at,expires_at,created_at,updated_at) on public.institution_notices to authenticated;
drop policy if exists institution_notices_read on public.institution_notices;
create policy institution_notices_read on public.institution_notices for select to authenticated using(
 public.activity_is_member(org_id) or (published and (expires_at is null or expires_at>now()) and exists(select 1 from public.activity_organizations o where o.id=org_id and o.approved))
);
create index if not exists institution_notices_feed on public.institution_notices(region_sido,region_sigungu,published_at desc) where published;

create or replace function public.institution_notice_feed() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid();begin
 if u is null then raise exception '로그인이 필요해요.' using errcode='42501';end if;
 return coalesce((select jsonb_agg(x.data order by x.published_at desc,x.id) from(
  select n.id,n.published_at,(to_jsonb(n)-'created_by'-'body')||jsonb_build_object('org_name',o.name) data
  from public.institution_notices n join public.activity_organizations o on o.id=n.org_id and o.approved
  join public.profiles p on p.id=u and p.region_sido=n.region_sido and p.region_sigungu=n.region_sigungu
  where n.published and (n.expires_at is null or n.expires_at>now()) order by n.published_at desc,n.id limit 30
 )x),'[]'::jsonb);
end $$;
create or replace function public.institution_notice_detail(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid();result jsonb;begin
 if u is null then raise exception '로그인이 필요해요.' using errcode='42501';end if;
 select (to_jsonb(n)-'created_by')||jsonb_build_object('org_name',o.name) into result
 from public.institution_notices n join public.activity_organizations o on o.id=n.org_id
 where n.id=p_id and (public.activity_is_member(n.org_id) or (o.approved and n.published and (n.expires_at is null or n.expires_at>now())));
 if result is null then raise exception '게시가 종료됐거나 볼 수 없는 공지예요.';end if;
 return result;
end $$;
create or replace function public.institution_notice_list() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception '로그인이 필요해요.' using errcode='42501';end if;
 return coalesce((select jsonb_agg((to_jsonb(n)-'created_by')||jsonb_build_object('org_name',o.name) order by n.updated_at desc,n.id)
 from public.institution_notices n join public.activity_organizations o on o.id=n.org_id where public.activity_is_member(n.org_id)),'[]'::jsonb);
end $$;
create or replace function public.institution_notice_save(p_data jsonb,p_id uuid default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();v_org uuid:=(p_data->>'org_id')::uuid;old public.institution_notices;result uuid;v_end timestamptz:=(p_data->>'expires_at')::timestamptz;
begin
 if u is null or not public.activity_is_member(v_org) then raise exception '승인된 기관 담당자만 공지를 등록할 수 있어요.' using errcode='42501';end if;
 if v_end is not null and v_end<=now() then raise exception '게시 종료일은 오늘 이후로 선택해주세요.';end if;
 if p_id is null then
  insert into public.institution_notices(org_id,title,body,region_sido,region_sigungu,source_url,expires_at,created_by)
  values(v_org,btrim(p_data->>'title'),btrim(p_data->>'body'),p_data->>'region_sido',p_data->>'region_sigungu',nullif(btrim(p_data->>'source_url'),''),v_end,u) returning id into result;
 else
  select * into old from public.institution_notices where id=p_id for update;
  if not found or old.org_id<>v_org or not public.activity_is_member(old.org_id) then raise exception '우리 기관 공지만 수정할 수 있어요.' using errcode='42501';end if;
  update public.institution_notices set title=btrim(p_data->>'title'),body=btrim(p_data->>'body'),region_sido=p_data->>'region_sido',region_sigungu=p_data->>'region_sigungu',source_url=nullif(btrim(p_data->>'source_url'),''),expires_at=v_end,updated_at=now() where id=p_id returning id into result;
 end if;
 return result;
end $$;
create or replace function public.institution_notice_publish(p_id uuid,p_published boolean) returns void
language plpgsql security definer set search_path='' as $$
declare old public.institution_notices;begin
 select * into old from public.institution_notices where id=p_id for update;
 if auth.uid() is null or not found or not public.activity_is_member(old.org_id) then raise exception '우리 기관 공지만 게시할 수 있어요.' using errcode='42501';end if;
 if p_published is null then raise exception '게시 상태를 선택해주세요.';end if;
 if p_published and old.expires_at<=now() then raise exception '종료일을 수정한 뒤 게시해주세요.';end if;
 update public.institution_notices set published=p_published,published_at=case when p_published then coalesce(published_at,now()) else published_at end,updated_at=now() where id=p_id;
end $$;
revoke all on function public.institution_notice_feed(),public.institution_notice_detail(uuid),public.institution_notice_list(),public.institution_notice_save(jsonb,uuid),public.institution_notice_publish(uuid,boolean) from public,anon,authenticated;
grant execute on function public.institution_notice_feed(),public.institution_notice_detail(uuid),public.institution_notice_list(),public.institution_notice_save(jsonb,uuid),public.institution_notice_publish(uuid,boolean) to authenticated;
commit;
