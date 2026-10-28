-- 동네모임 참여하기 (Run in the SQL Editor after reports.sql and
-- integration_security.sql. Safe to re-run; any error rolls everything back.)
--
-- 앱은 meetup_participants 표를 직접 읽거나 쓰지 않는다. 아래 함수만 부른다.
--   meetup_join(post)           참여하기 (모임 줄을 for update로 잠가 정원 초과를 막음)
--   meetup_leave(post)          참여 취소 (모임장·지난 모임은 불가)
--   meetup_participation(post)  참여자 수·최대 인원·내 상태·닉네임 목록
--   my_meetups()                내가 참여한 모임 목록
-- 닉네임은 public_profiles에서만 가져온다(실명·출생연도 노출 금지).

begin;

-- 1. 최대 인원 (기존 모임은 기본값 10명)
alter table public.posts
  add column if not exists max_participants integer not null default 10;
alter table public.posts drop constraint if exists posts_max_participants_range;
alter table public.posts add constraint posts_max_participants_range
  check (max_participants between 2 and 30);

-- 2. 참여자 표. 모임 글이 지워지거나 회원이 탈퇴하면 같이 지워진다.
create table if not exists public.meetup_participants (
  post_id uuid not null references public.posts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index if not exists meetup_participants_user
  on public.meetup_participants (user_id);
alter table public.meetup_participants enable row level security;
revoke all on public.meetup_participants from public, anon, authenticated;

-- 3. 모임장 자동 참여 + 최대 인원을 현재 참여자 수보다 줄이지 못하게
create or replace function public.meetup_host_join()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.category = '동네모임' then
    insert into public.meetup_participants (post_id, user_id)
    values (new.id, new.author_id)
    on conflict do nothing;
  end if;
  return new;
end $$;

drop trigger if exists meetup_host_join on public.posts;
create trigger meetup_host_join
after insert or update of category on public.posts
for each row execute function public.meetup_host_join();

create or replace function public.meetup_capacity_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare joined integer;
begin
  if new.max_participants < old.max_participants then
    select count(*) into joined
    from public.meetup_participants where post_id = new.id;
    if joined > new.max_participants then
      raise exception '이미 %명이 참여해서 최대 인원을 %명보다 줄일 수 없어요.', joined, joined
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists meetup_capacity_guard on public.posts;
create trigger meetup_capacity_guard
before update of max_participants on public.posts
for each row execute function public.meetup_capacity_guard();

-- 이미 있는 모임의 모임장도 참여자로 넣는다.
insert into public.meetup_participants (post_id, user_id, joined_at)
select id, author_id, created_at from public.posts where category = '동네모임'
on conflict do nothing;

-- 4. 참여하기
create or replace function public.meetup_join(p_post uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  u uuid := auth.uid();
  m public.posts;
  joined integer;
begin
  if u is null then
    raise exception '로그인이 필요해요.' using errcode = '42501';
  end if;
  -- 같은 모임에 동시에 여러 명이 눌러도 한 명씩 차례로 처리된다.
  select * into m from public.posts where id = p_post for update;
  if not found or m.category <> '동네모임' then
    raise exception '모임을 찾을 수 없어요.' using errcode = 'P0001';
  end if;
  if public.post_is_hidden(m.id) then
    raise exception '신고로 숨겨진 모임에는 참여할 수 없어요.' using errcode = 'P0001';
  end if;
  if m.event_at is null or m.event_at <= now() then
    raise exception '이미 지난 모임이에요.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.meetup_participants
             where post_id = m.id and user_id = u) then
    raise exception '이미 참여한 모임이에요.' using errcode = 'P0001';
  end if;
  select count(*) into joined from public.meetup_participants where post_id = m.id;
  if joined >= m.max_participants then
    raise exception '모집이 마감됐어요.' using errcode = 'P0001';
  end if;
  insert into public.meetup_participants (post_id, user_id) values (m.id, u);
end $$;

-- 5. 참여 취소
create or replace function public.meetup_leave(p_post uuid)
returns void
language plpgsql
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
  select * into m from public.posts where id = p_post for update;
  if not found or m.category <> '동네모임' then
    raise exception '모임을 찾을 수 없어요.' using errcode = 'P0001';
  end if;
  if m.author_id = u then
    raise exception '모임장은 참여를 취소할 수 없어요.' using errcode = 'P0001';
  end if;
  if m.event_at is null or m.event_at <= now() then
    raise exception '이미 지난 모임은 취소할 수 없어요.' using errcode = 'P0001';
  end if;
  delete from public.meetup_participants where post_id = m.id and user_id = u;
  if not found then
    raise exception '참여하지 않은 모임이에요.' using errcode = 'P0001';
  end if;
end $$;

-- 6. 참여 현황 (글을 볼 수 있는 사람에게만: 숨겨진 모임은 모임장만)
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
     or (m.author_id <> u and public.post_is_hidden(m.id)) then
    raise exception '모임을 찾을 수 없어요.' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'max_participants', m.max_participants,
    'count', (select count(*) from public.meetup_participants where post_id = m.id),
    'joined', exists (select 1 from public.meetup_participants
                      where post_id = m.id and user_id = u),
    'is_host', m.author_id = u,
    'is_past', m.event_at is null or m.event_at <= now(),
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

-- 7. 내가 참여한 모임 (다가오는 모임 먼저, 가까운 날짜순)
create or replace function public.my_meetups()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare u uuid := auth.uid();
begin
  if u is null then
    raise exception '로그인이 필요해요.' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(x.data order by x.upcoming desc,
                     case when x.upcoming then x.event_at end asc,
                     case when not x.upcoming then x.event_at end desc)
    from (
      select p.event_at, p.event_at > now() as upcoming,
             jsonb_build_object(
               'id', p.id, 'title', p.title, 'event_at', p.event_at,
               'facility_name', f.name, 'is_host', p.author_id = u,
               'count', (select count(*) from public.meetup_participants c
                         where c.post_id = p.id),
               'max_participants', p.max_participants) as data
      from public.meetup_participants mp
      join public.posts p on p.id = mp.post_id and p.category = '동네모임'
      left join public.facilities f on f.id = p.facility_id
      where mp.user_id = u
        and (p.author_id = u or not public.post_is_hidden(p.id))
    ) x), '[]'::jsonb);
end $$;

revoke all on function public.meetup_host_join() from public, anon, authenticated;
revoke all on function public.meetup_capacity_guard() from public, anon, authenticated;
revoke all on function public.meetup_join(uuid) from public, anon;
revoke all on function public.meetup_leave(uuid) from public, anon;
revoke all on function public.meetup_participation(uuid) from public, anon;
revoke all on function public.my_meetups() from public, anon;
grant execute on function public.meetup_join(uuid) to authenticated;
grant execute on function public.meetup_leave(uuid) to authenticated;
grant execute on function public.meetup_participation(uuid) to authenticated;
grant execute on function public.my_meetups() to authenticated;

commit;

-- 8. 결과 확인: 모임 수와 참여자 수 (모임마다 최소 1명 = 모임장)
select count(*) as 모임_수,
       (select count(*) from public.meetup_participants) as 참여_기록_수,
       count(*) filter (where not exists (
         select 1 from public.meetup_participants mp
         where mp.post_id = p.id and mp.user_id = p.author_id)) as 모임장_빠진_모임
from public.posts p where p.category = '동네모임';
