-- Additional mockups: additive schema. Apply account_deletion.sql and meetup_participation.sql from the team first, plus existing integration/activity SQL.
begin;
alter table public.posts add column if not exists meetup_topic text not null default '산책·운동';
alter table public.posts add column if not exists max_participants integer not null default 10 check(max_participants between 2 and 30);
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
alter table public.user_blocks enable row level security;
alter table public.post_likes enable row level security;
drop policy if exists user_blocks_own on public.user_blocks;
create policy user_blocks_own on public.user_blocks for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists post_likes_own on public.post_likes;
create policy post_likes_own on public.post_likes for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid() and exists(select 1 from public.posts p where p.id=post_id));
grant select,insert,delete on public.user_blocks,public.post_likes to authenticated;
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
 'joined',p.author_id=uid or exists(select 1 from public.meetup_participants m where m.post_id=p.id and m.user_id=uid),
 'member_count',(select count(*) from public.meetup_participants m where m.post_id=p.id),
 'participants',coalesce((select jsonb_agg(jsonb_build_object('nickname',r.nickname,'is_host',r.id=p.author_id,'is_me',r.id=uid)) from public.public_profiles r where
 (r.id=p.author_id or exists(select 1 from public.meetup_participants m where m.post_id=p.id and m.user_id=r.id))
 and not exists(select 1 from public.user_blocks b where b.user_id=uid and b.blocked_id=r.id)),'[]'::jsonb)
 )),'[]'::jsonb) into result from public.posts p
 where p.id=any(post_ids) and (p.author_id=uid or not public.post_is_hidden(p.id))
 and not exists(select 1 from public.user_blocks b where b.user_id=uid and b.blocked_id=p.author_id);
 return result;
end $$;
-- Use the team's canonical participant table and RPCs; no second membership store.
create or replace function public.meetup_participate(target uuid,participating boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); p public.posts; is_joined boolean;
begin
 if uid is null then raise exception '로그인이 필요해요' using errcode='42501';end if;
 select * into p from public.posts where id=target for update;
 if p.id is null or p.category<>'동네모임' or (p.author_id<>uid and public.post_is_hidden(target))
 or exists(select 1 from public.user_blocks b where b.user_id=uid and b.blocked_id=p.author_id) then raise exception '모임을 확인할 수 없어요';end if;
 if p.meetup_cancelled or p.event_at<=now() then raise exception '끝나거나 취소된 모임은 참여 상태를 바꿀 수 없어요';end if;
 select exists(select 1 from public.meetup_participants where post_id=target and user_id=uid) into is_joined;
 if participating and not is_joined then perform public.meetup_join(target);
 elsif not participating and is_joined then perform public.meetup_leave(target);end if;
 return public.neighborhood_state(array[target]);
end $$;
-- Also guard old app versions calling the team's join RPC directly.
create or replace function public.neighborhood_membership_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare p public.posts;begin
 select * into p from public.posts where id=new.post_id for update;
 if auth.uid() is not null and (p.meetup_cancelled or exists(select 1 from public.user_blocks b where b.user_id=new.user_id and b.blocked_id=p.author_id)) then raise exception '참여할 수 없는 모임이에요';end if;
 return new;end $$;
drop trigger if exists neighborhood_membership_guard on public.meetup_participants;
create trigger neighborhood_membership_guard before insert on public.meetup_participants for each row execute function public.neighborhood_membership_guard();
create or replace function public.meetup_participation(p_post uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  u uuid := auth.uid();
  m public.posts;
begin
  if u is null then
    raise exception '로그인이 필요해요.' using errcode = '42501';
  end if;
  select * into m from public.posts where id = p_post;
  if not found or m.category <> '동네모임'
     or (m.author_id <> u and public.post_is_hidden(m.id))
     or exists(select 1 from public.user_blocks b where b.user_id=u and b.blocked_id=m.author_id) then
    raise exception '모임을 찾을 수 없어요.' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'max_participants', m.max_participants,
    'count', (select count(*) from public.meetup_participants where post_id = m.id),
    'joined', exists (select 1 from public.meetup_participants
                      where post_id = m.id and user_id = u),
    'is_host', m.author_id = u,
    'is_past', m.meetup_cancelled or m.event_at is null or m.event_at <= now(),
    'participants', coalesce((
      select jsonb_agg(jsonb_build_object(
               'nickname', coalesce(pp.nickname, '알 수 없음'),
               'is_host', mp.user_id = m.author_id,
               'is_me', mp.user_id = u)
             order by (mp.user_id = m.author_id) desc, mp.joined_at)
      from public.meetup_participants mp
      left join public.public_profiles pp on pp.id = mp.user_id
      where mp.post_id = m.id), '[]'::jsonb)
  );
end $$;
-- Lock the post during edits too; cannot shrink capacity below actual attendees.
create or replace function public.neighborhood_validate_post() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.category='동네모임' then
  if new.meetup_topic not in('산책·운동','바둑·장기','노래·취미','배움','봉사') then raise exception '모임 분야를 확인해 주세요'; end if;
  if new.max_participants < (select count(*) from public.meetup_participants where post_id=new.id) then raise exception '참여 인원보다 정원을 줄일 수 없어요'; end if;
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
 if draft_key is not null and not exists(select 1 from public.activity_program_drafts d where d.id=draft_key and d.org_id=($1->>'org_id')::uuid) then raise exception '임시 저장 수정 권한이 없어요' using errcode='42501';end if;
 if is_draft and result is null then
  if draft_key is null then insert into public.activity_program_drafts(org_id,data) values(($1->>'org_id')::uuid,$1-'draft_id') returning id into result;
  else update public.activity_program_drafts set data=$1-'draft_id',updated_at=now() where id=draft_key returning id into result;end if;
  return result;
 end if;
 if greatest(char_length(coalesce(data->>'target_audience','')),char_length(coalesce(data->>'preparations','')),char_length(coalesce(data->>'floor_guide','')))>2000 then raise exception '안내는 항목당 2000자까지 적어 주세요.';end if;
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
