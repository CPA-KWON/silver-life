-- "고마워요 꽃" (Run in the SQL Editor after attendance_points.sql, pet_companion.sql,
-- meetup_participation.sql and neighborhood_mockups.sql. Safe to re-run; any error
-- rolls everything back.)
--
-- 앱은 meetup_flowers 표를 직접 읽거나 쓰지 않고 아래 함수만 부른다.
--   send_meetup_flower(post, to)  꽃 한 송이 보내기 (1P 차감과 꽃 기록을 한 번에)
--   meetup_participation(post)    기존 결과에 받은 꽃 수·보낼 수 있는지를 더함
--   my_flowers()                  내가 받은 꽃 목록
-- 포인트는 상대에게 넘어가지 않고 꽃 수만 올라간다.
-- 모임 글이나 계정이 지워지면 꽃 기록도 지워지고, 쓴 포인트는 돌려주지 않는다.

begin;

create table if not exists public.meetup_flowers (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  sender_id uuid not null references auth.users (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (post_id, sender_id, recipient_id),
  check (sender_id <> recipient_id)
);
create index if not exists meetup_flowers_recipient
  on public.meetup_flowers (recipient_id, created_at desc);
alter table public.meetup_flowers enable row level security;
revoke all on public.meetup_flowers from public, anon, authenticated;

-- 기존 허용값을 유지하면서 'flower'를 더한다.
alter table public.point_ledger drop constraint if exists point_ledger_reason_check;
alter table public.point_ledger add constraint point_ledger_reason_check
  check (reason in ('attendance', 'pet', 'flower'));

create or replace function public.send_meetup_flower(p_post uuid, p_to uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  u uuid := auth.uid();
  m public.posts;
  w public.point_wallets;
begin
  if u is null then
    raise exception '로그인이 필요해요.' using errcode = '42501';
  end if;
  if p_to is null or p_to = u then
    raise exception '나에게는 꽃을 보낼 수 없어요.' using errcode = 'P0001';
  end if;
  select * into m from public.posts where id = p_post;
  if not found or m.category <> '동네모임' or public.post_is_hidden(m.id) then
    raise exception '꽃을 보낼 수 없는 모임이에요.' using errcode = 'P0001';
  end if;
  if m.meetup_cancelled then
    raise exception '취소된 모임에는 꽃을 보낼 수 없어요.' using errcode = 'P0001';
  end if;
  if m.event_at is null or m.event_at > now() then
    raise exception '모임이 끝난 뒤에 꽃을 보낼 수 있어요.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.meetup_participants
                 where post_id = m.id and user_id = u)
     or not exists (select 1 from public.meetup_participants
                    where post_id = m.id and user_id = p_to) then
    raise exception '같은 모임에 참여한 이웃에게만 꽃을 보낼 수 있어요.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.user_blocks b
             where (b.user_id = u and b.blocked_id = p_to)
                or (b.user_id = p_to and b.blocked_id = u)) then
    raise exception '꽃을 보낼 수 없는 이웃이에요.' using errcode = 'P0001';
  end if;

  -- 지갑을 잠가 같은 사람의 동시 요청을 한 건씩 처리한다.
  select * into w from public.point_wallets where user_id = u for update;
  if exists (select 1 from public.meetup_flowers
             where post_id = m.id and sender_id = u and recipient_id = p_to) then
    raise exception '이미 꽃을 보냈어요.' using errcode = 'P0001';
  end if;
  if w.user_id is null or w.balance < 1 then
    raise exception '포인트가 부족해요' using errcode = 'P0001';
  end if;

  insert into public.meetup_flowers (post_id, sender_id, recipient_id)
  values (m.id, u, p_to);
  update public.point_wallets
  set balance = balance - 1, updated_at = now()
  where user_id = u;
  -- ref_date는 비운다. 채우면 unique(user_id, reason, ref_date)에 걸려 하루 한 송이만 보낼 수 있다.
  insert into public.point_ledger (user_id, amount, reason) values (u, -1, 'flower');
  return jsonb_build_object('balance', w.balance - 1);
end $$;

-- neighborhood_mockups.sql의 최신 정의에 꽃 정보를 더한 것.
-- user_id는 지금 꽃을 보낼 수 있는 상대에게만 내려준다.
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
  can_send boolean;
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
  can_send := not m.meetup_cancelled
    and m.event_at is not null and m.event_at <= now()
    and not public.post_is_hidden(m.id)
    and exists (select 1 from public.meetup_participants
                where post_id = m.id and user_id = u);
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
               'is_me', mp.user_id = u,
               'flowers', (select count(*) from public.meetup_flowers f
                           where f.recipient_id = mp.user_id),
               'flower_sent', sent.yes,
               'can_send_flower', ok.yes,
               'user_id', case when ok.yes then mp.user_id end)
             order by (mp.user_id = m.author_id) desc, mp.joined_at)
      from public.meetup_participants mp
      left join public.public_profiles pp on pp.id = mp.user_id
      cross join lateral (
        select exists (select 1 from public.meetup_flowers f
                       where f.post_id = m.id and f.sender_id = u
                         and f.recipient_id = mp.user_id) as yes
      ) sent
      cross join lateral (
        select can_send and mp.user_id <> u and not sent.yes
          and not exists (select 1 from public.user_blocks b
                          where (b.user_id = u and b.blocked_id = mp.user_id)
                             or (b.user_id = mp.user_id and b.blocked_id = u)) as yes
      ) ok
      where mp.post_id = m.id), '[]'::jsonb)
  );
end $$;

-- 내가 받은 꽃 (최근 순). 내가 차단한 이웃의 꽃은 목록에서 뺀다.
create or replace function public.my_flowers()
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
    select jsonb_agg(jsonb_build_object(
             'sender_nickname', coalesce(pp.nickname, '알 수 없음'),
             'meetup_title', case when public.post_is_hidden(p.id) and p.author_id <> u
                                  then '숨겨진 모임' else p.title end,
             'event_at', p.event_at,
             'created_at', f.created_at)
           order by f.created_at desc)
    from public.meetup_flowers f
    join public.posts p on p.id = f.post_id
    left join public.public_profiles pp on pp.id = f.sender_id
    where f.recipient_id = u
      and not exists (select 1 from public.user_blocks b
                      where b.user_id = u and b.blocked_id = f.sender_id)
  ), '[]'::jsonb);
end $$;

revoke all on function public.send_meetup_flower(uuid, uuid) from public, anon;
revoke all on function public.meetup_participation(uuid) from public, anon;
revoke all on function public.my_flowers() from public, anon;
grant execute on function public.send_meetup_flower(uuid, uuid) to authenticated;
grant execute on function public.meetup_participation(uuid) to authenticated;
grant execute on function public.my_flowers() to authenticated;

commit;

notify pgrst, 'reload schema';

-- 결과 확인: 꽃 기록 수(처음에는 0)와 허용된 포인트 사유
select (select count(*) from public.meetup_flowers) as 꽃_기록_수,
       pg_get_constraintdef(oid) as 포인트_사유_규칙
from pg_constraint
where conname = 'point_ledger_reason_check'
  and conrelid = 'public.point_ledger'::regclass;
