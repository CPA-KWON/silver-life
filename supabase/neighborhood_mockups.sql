-- Additional mockups: additive schema. Run after existing integration/activity SQL.
begin;
alter table public.posts add column if not exists meetup_topic text not null default '산책·운동';
alter table public.posts add column if not exists meetup_capacity integer not null default 10 check(meetup_capacity between 2 and 100);
alter table public.posts add column if not exists duration_minutes integer not null default 60 check(duration_minutes between 15 and 1440);
alter table public.posts add column if not exists meetup_cancelled boolean not null default false;
alter table public.posts add column if not exists image_paths text[] not null default '{}';
alter table public.profiles add column if not exists avatar_path text;
-- Preserve all existing categories; add the question category shown in K11.
alter table public.posts drop constraint if exists posts_category_check;
alter table public.posts add constraint posts_category_check check(category in('자유게시판','동네모임','건강정보','나눔·도움요청','질문'));
create table if not exists public.user_blocks (
 user_id uuid not null references auth.users on delete cascade,
 blocked_id uuid not null references auth.users on delete cascade,
 created_at timestamptz not null default now(),primary key(user_id,blocked_id),check(user_id<>blocked_id));
create table if not exists public.post_likes (
 user_id uuid not null references auth.users on delete cascade,
 post_id uuid not null references public.posts on delete cascade,
 created_at timestamptz not null default now(),primary key(user_id,post_id));
create table if not exists public.meetup_members (
 user_id uuid not null references auth.users on delete cascade,
 post_id uuid not null references public.posts on delete cascade,
 joined_at timestamptz not null default now(), active boolean not null default true,
 primary key(user_id,post_id));
create index if not exists meetup_members_post on public.meetup_members(post_id) where active;
alter table public.user_blocks enable row level security;
alter table public.post_likes enable row level security;
alter table public.meetup_members enable row level security;
drop policy if exists user_blocks_own on public.user_blocks;
create policy user_blocks_own on public.user_blocks for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists post_likes_own on public.post_likes;
create policy post_likes_own on public.post_likes for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid() and exists(select 1 from public.posts p where p.id=post_id));
drop policy if exists meetup_members_own on public.meetup_members;
create policy meetup_members_own on public.meetup_members for select to authenticated using(user_id=auth.uid());
grant select,insert,delete on public.user_blocks,public.post_likes to authenticated;
grant select on public.meetup_members to authenticated;
revoke insert,update,delete on public.meetup_members from anon,authenticated;
-- A restrictive policy composes with, and never widens, the existing report policies.
drop policy if exists posts_blocked_authors on public.posts;
create policy posts_blocked_authors on public.posts as restrictive for select to authenticated
 using(not exists(select 1 from public.user_blocks b where b.user_id=auth.uid() and b.blocked_id=author_id));
drop policy if exists comments_blocked_authors on public.comments;
create policy comments_blocked_authors on public.comments as restrictive for select to authenticated
 using(not exists(select 1 from public.user_blocks b where b.user_id=auth.uid() and b.blocked_id=author_id));

create or replace function public.neighborhood_state(post_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=auth.uid(); result jsonb;
begin
 if uid is null then raise exception '로그인이 필요해요' using errcode='42501'; end if;
 if cardinality(post_ids)>500 then raise exception '요청이 너무 많아요'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'liked',exists(select 1 from public.post_likes l where l.post_id=p.id and l.user_id=uid),
 'likes',(select count(*) from public.post_likes l where l.post_id=p.id),
 'joined',p.author_id=uid or exists(select 1 from public.meetup_members m where m.post_id=p.id and m.user_id=uid and m.active),
 'member_count',1+(select count(*) from public.meetup_members m where m.post_id=p.id and m.user_id<>p.author_id and m.active),
 'participants',coalesce((select jsonb_agg(jsonb_build_object('nickname',r.nickname)) from public.public_profiles r where
 (r.id=p.author_id or exists(select 1 from public.meetup_members m where m.post_id=p.id and m.user_id=r.id and m.active))
 and not exists(select 1 from public.user_blocks b where b.user_id=uid and b.blocked_id=r.id)),'[]'::jsonb)
 )),'[]'::jsonb) into result from public.posts p
 where p.id=any(post_ids) and (p.author_id=uid or not public.post_is_hidden(p.id))
 and not exists(select 1 from public.user_blocks b where b.user_id=uid and b.blocked_id=p.author_id);
 return result;
end $$;
create or replace function public.meetup_participate(target uuid,participating boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); p public.posts; n integer;
begin
 if uid is null then raise exception '로그인이 필요해요' using errcode='42501'; end if;
 select * into p from public.posts where id=target for update;
 if p.id is null or p.category<>'동네모임' or public.post_is_hidden(target)
 or exists(select 1 from public.user_blocks b where b.user_id=uid and b.blocked_id=p.author_id) then raise exception '모임을 확인할 수 없어요'; end if;
 if p.meetup_cancelled or p.event_at<=now() then raise exception '끝나거나 취소된 모임은 참여 상태를 바꿀 수 없어요'; end if;
 if p.author_id=uid then
  if not participating then raise exception '개설자는 모임 수정에서 모임을 취소해 주세요'; end if;
 else
  if participating then
   select 1+count(*) into n from public.meetup_members where post_id=target and active and user_id<>p.author_id;
   if n>=p.meetup_capacity and not exists(select 1 from public.meetup_members where post_id=target and user_id=uid and active) then raise exception '모집 정원이 찼어요'; end if;
   insert into public.meetup_members(user_id,post_id) values(uid,target) on conflict(user_id,post_id) do update set active=true,joined_at=now();
  else update public.meetup_members set active=false where user_id=uid and post_id=target; end if;
 end if;
 return public.neighborhood_state(array[target]);
end $$;
-- Lock the post during edits too; cannot shrink capacity below actual attendees.
create or replace function public.neighborhood_validate_post() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.category='동네모임' then
  if new.meetup_topic not in('산책·운동','바둑·장기','노래·취미','배움','봉사') then raise exception '모임 분야를 확인해 주세요'; end if;
  if new.meetup_capacity < (select 1+count(*) from public.meetup_members where post_id=new.id and active and user_id<>new.author_id) then raise exception '참여 인원보다 정원을 줄일 수 없어요'; end if;
 end if;
 if cardinality(new.image_paths)>5 or exists(select 1 from unnest(new.image_paths) path where path not like new.author_id::text||'/posts/%') then raise exception '사진 경로를 확인해 주세요'; end if;
 return new;
end $$;
drop trigger if exists neighborhood_validate_post on public.posts;
create trigger neighborhood_validate_post before insert or update on public.posts for each row execute function public.neighborhood_validate_post();
-- Saved external program interest is not an enrollment or a reward claim.
create table if not exists public.welfare_program_favorites (
 user_id uuid not null references auth.users on delete cascade,
 program_key text not null check(length(program_key) between 1 and 200),primary key(user_id,program_key));
alter table public.welfare_program_favorites enable row level security;
drop policy if exists welfare_favorites_own on public.welfare_program_favorites;
create policy welfare_favorites_own on public.welfare_program_favorites for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
grant select,insert,delete on public.welfare_program_favorites to authenticated;
-- Additional institution fields shown in A03/A12, none invent availability.
alter table public.activity_programs add column if not exists application_method text not null default 'app' check(application_method in('app','phone','visit'));
alter table public.activity_programs add column if not exists contact_phone text;
alter table public.activity_programs add column if not exists draft boolean not null default false;
alter table public.institution_notices add column if not exists important boolean not null default false;
alter table public.institution_notices add column if not exists pinned boolean not null default false;
alter table public.institution_notices add column if not exists publish_at timestamptz;
alter table public.institution_notices add column if not exists linked_program uuid references public.activity_programs;
create table if not exists public.activity_program_drafts (
 id uuid primary key default gen_random_uuid(),org_id uuid not null references public.activity_organizations on delete cascade,
 data jsonb not null default '{}'::jsonb,updated_at timestamptz not null default now());
alter table public.activity_program_drafts enable row level security;
drop policy if exists program_drafts_members on public.activity_program_drafts;
create policy program_drafts_members on public.activity_program_drafts for select to authenticated using(public.activity_is_member(org_id));
grant select on public.activity_program_drafts to authenticated;
-- Institution program edit/draft/method: owner authorization stays server-side.
create or replace function public.activity_save_program_v3(data jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); result uuid:=(data->>'id')::uuid;old public.activity_programs; n integer;is_draft boolean:=coalesce((data->>'draft')::boolean,false);method text:=coalesce(data->>'application_method','app'); draft_key uuid:=(data->>'draft_id')::uuid;
begin
 if uid is null or not public.activity_is_member((data->>'org_id')::uuid) then raise exception '기관 담당자 권한이 필요해요' using errcode='42501';end if;
 if draft_key is not null and not exists(select 1 from public.activity_program_drafts d where d.id=draft_key and d.org_id=(data->>'org_id')::uuid) then raise exception '임시 저장 수정 권한이 없어요' using errcode='42501';end if;
 if is_draft and result is null then
  if draft_key is null then insert into public.activity_program_drafts(org_id,data) values((data->>'org_id')::uuid,data-'draft_id') returning id into result;
  else update public.activity_program_drafts set data=data-'draft_id',updated_at=now() where id=draft_key returning id into result;end if;
  return result;
 end if;
 if method not in('app','phone','visit') then raise exception '신청 방법을 확인해 주세요';end if;
 if method='phone' and coalesce(data->>'contact_phone','') !~ '^[+0-9() -]{7,30}$' then raise exception '연락처를 확인해 주세요';end if;
 if char_length(btrim(coalesce(data->>'title',''))) not between 1 and 100 then raise exception '프로그램 이름을 써 주세요';end if;
 if result is null then result:=public.activity_save_program_v2(data);
 else
  select * into old from public.activity_programs where id=result for update;
  if old.id is null or old.org_id<>(data->>'org_id')::uuid then raise exception '수정 권한이 없어요' using errcode='42501';end if;
  select count(*) into n from public.activity_enrollments where program_id=result and status in('applied','approved','completed');
  if (data->>'capacity')::int<n then raise exception '신청 인원보다 정원을 줄일 수 없어요';end if;
  if n>0 and (method<>old.application_method or (data->>'fee')::int<>old.fee or (data->>'kind')<>old.kind) then raise exception '신청자가 있는 프로그램의 신청 방법·비용·유형은 바꿀 수 없어요';end if;
  if (data->>'ends_at')::timestamptz<=(data->>'starts_at')::timestamptz or (data->>'deadline')::timestamptz>(data->>'starts_at')::timestamptz then raise exception '일정을 확인해 주세요';end if;
  update public.activity_programs set title=data->>'title',description=data->>'description',category=data->>'category',kind=data->>'kind',place_name=data->>'place_name',lat=(data->>'lat')::float8,lng=(data->>'lng')::float8,starts_at=(data->>'starts_at')::timestamptz,ends_at=(data->>'ends_at')::timestamptz,deadline=(data->>'deadline')::timestamptz,capacity=(data->>'capacity')::int,fee=(data->>'fee')::int,transports=array(select jsonb_array_elements_text(data->'transports')),participation=data->>'participation',difficulty=(data->>'difficulty')::int,target_audience=data->>'target_audience',preparations=data->>'preparations',floor_guide=data->>'floor_guide' where id=result;
 end if;
 update public.activity_programs set application_method=method,contact_phone=nullif(btrim(data->>'contact_phone'),''),draft=is_draft,status=case when is_draft then 'closed' when old.draft then 'open' else status end where id=result;
 if draft_key is not null then delete from public.activity_program_drafts where id=draft_key;end if;
 return result;
end $$;
create or replace function public.activity_candidates() returns setof public.activity_programs language sql stable security definer set search_path=public as $$
 select a.* from activity_programs a join activity_organizations o on o.id=a.org_id and o.approved
 join activity_preferences p on p.user_id=auth.uid()
 where not a.draft and a.application_method='app' and a.kind='activity' and a.status='open' and a.starts_at>now() and a.deadline>now()
 and a.category=any(p.interests) and p.transport=any(a.transports) and (p.participation='무관' or p.participation=a.participation)
 and a.difficulty<=p.difficulty and extract(epoch from(a.ends_at-a.starts_at))/60<=p.max_minutes
 and activity_distance(p.lat,p.lng,a.lat,a.lng)<=p.radius_km
 and (select count(*) from activity_enrollments where program_id=a.id and status in('applied','approved','completed'))<a.capacity
 and not exists(select 1 from activity_enrollments where program_id=a.id and user_id=auth.uid() and status in('applied','approved','completed'))
 order by exists(select 1 from activity_sponsorships s where s.program_id=a.id and s.payment_confirmed and s.starts_at<=now() and s.ends_at>now()) desc,
 exists(select 1 from activity_enrollments e join activity_programs h on h.id=e.program_id where e.user_id=auth.uid() and e.status='completed' and h.category=a.category),
 activity_distance(p.lat,p.lng,a.lat,a.lng),a.starts_at,a.id
$$;
-- Phone/visit programs may be found, but cannot generate in-app enrollments.
create or replace function public.activity_validate_application_method() returns trigger language plpgsql set search_path='' as $$begin
 if exists(select 1 from public.activity_programs p where p.id=new.program_id and (p.draft or p.application_method<>'app')) then raise exception '기관에 직접 문의해 신청해 주세요';end if;return new;end $$;
drop trigger if exists activity_application_method on public.activity_enrollments;
create trigger activity_application_method before insert on public.activity_enrollments for each row execute function public.activity_validate_application_method();
-- An atomic batch reuses the existing authorization, capacity and reward logic.
create or replace function public.activity_manage_batch(enrollments uuid[],action text,reason text default '') returns void
language plpgsql security invoker set search_path='' as $$
declare eid uuid;
begin
 if auth.uid() is null then raise exception '로그인이 필요해요' using errcode='42501'; end if;
 if cardinality(enrollments) not between 1 and 100 or action not in('approved','rejected','completed') then raise exception '선택한 신청을 확인해 주세요'; end if;
 for eid in select distinct unnest(enrollments) order by 1 loop
  if action='rejected' then perform public.activity_reject_with_reason(eid,reason);
  else perform public.activity_manage(eid,action); end if;
 end loop;
end $$;
do $$ declare r record;begin
 for r in select oid::regprocedure signature from pg_proc where pronamespace='public'::regnamespace and proname in('neighborhood_state','meetup_participate','activity_manage_batch','activity_save_program_v3') loop
  execute format('revoke all on function %s from public,anon',r.signature);
  execute format('grant execute on function %s to authenticated',r.signature);
 end loop;
end $$;
alter table public.reports drop constraint if exists reports_reason_check;
alter table public.reports add constraint reports_reason_check check(reason in('욕설·비방','광고','사기 의심','음란·불쾌한 내용','기타'));
notify pgrst,'reload schema';
commit;
