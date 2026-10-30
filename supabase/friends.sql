-- 친구 추가 + "친구는 지금 어디에?" (친구 체크인 공유)
--
-- 실행 방법: Supabase 대시보드 > SQL Editor > New query > 붙여넣기 > Run
-- 여러 번 실행해도 안전합니다(이미 있으면 덮어쓰거나 건너뜀).
-- 먼저 실행되어 있어야 하는 파일: schema.sql, facilities_schema.sql,
--   integration_security.sql, neighborhood_mockups.sql(차단 user_blocks),
--   facility_mockups.sql(체크인 facility_check_in)
--
-- 개인정보 원칙 (기존 규칙을 풀지 않음)
-- - profiles/checkins 는 지금처럼 "본인 것만" 읽습니다. 이 파일은 그 정책을 바꾸지 않습니다.
-- - 새 표 2개는 앱이 직접 읽거나 쓸 수 없습니다. 아래 함수로만 접근합니다.
-- - 친구의 체크인은 "수락된 친구" + "상대가 공개를 켠 경우"에만, 최근 3시간 안의 것만 보입니다.
-- - 차단 관계(어느 쪽이든)에서는 요청도, 체크인 공유도 되지 않습니다.
-- - 회원 탈퇴 시 on delete cascade 로 친구 관계와 설정도 함께 지워집니다.

begin;

-- 1) 친구 관계 -------------------------------------------------------------
create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users (id) on delete cascade,
  addressee_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (requester_id <> addressee_id)
);
-- A→B 와 B→A 를 같은 한 쌍으로 보고 중복을 막습니다.
create unique index if not exists friendships_pair_unique
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index if not exists friendships_requester_idx on public.friendships (requester_id);
create index if not exists friendships_addressee_idx on public.friendships (addressee_id);

-- 2) 친구에게 내 체크인 보이기 설정 (기본: 보임, 수락된 친구에게만) -----------
create table if not exists public.friend_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  share_presence boolean not null default true,
  updated_at timestamptz not null default now()
);

-- 정책(policy)을 만들지 않고 권한도 모두 회수 → 앱이 표를 직접 읽거나 쓸 수 없음.
alter table public.friendships enable row level security;
alter table public.friend_settings enable row level security;
revoke all on table public.friendships, public.friend_settings from public, anon, authenticated;

-- 3) 친구 요청 (닉네임으로) ---------------------------------------------------
-- 돌려주는 값: 'requested'(요청 보냄) / 'accepted'(상대가 먼저 보낸 요청이 있어 바로 친구가 됨)
create or replace function public.friend_request(target_nickname text)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid();
  t uuid;
  f public.friendships;
begin
  if u is null then raise exception '로그인이 필요해요' using errcode = '42501'; end if;
  select p.id into t from public.profiles p where p.nickname = trim(coalesce(target_nickname, ''));
  -- 차단 관계는 "없는 닉네임"과 같은 문구로 답해, 차단 여부가 드러나지 않게 합니다.
  if t is null or exists (
    select 1 from public.user_blocks b
    where (b.user_id = u and b.blocked_id = t) or (b.user_id = t and b.blocked_id = u)
  ) then
    raise exception '해당 닉네임의 이웃을 찾을 수 없어요';
  end if;
  if t = u then raise exception '내 닉네임은 친구로 추가할 수 없어요'; end if;

  select * into f from public.friendships x
  where least(x.requester_id, x.addressee_id) = least(u, t)
    and greatest(x.requester_id, x.addressee_id) = greatest(u, t);
  if found then
    if f.status = 'accepted' then raise exception '이미 친구예요'; end if;
    if f.requester_id = u then
      raise exception '이미 친구 요청을 보냈어요. 상대가 수락하면 친구가 돼요';
    end if;
    -- 상대가 먼저 보낸 요청이 있으면 바로 수락 처리
    update public.friendships set status = 'accepted', responded_at = now() where id = f.id;
    return 'accepted';
  end if;

  if (select count(*) from public.friendships x where x.requester_id = u and x.status = 'pending') >= 30 then
    raise exception '보낸 요청이 너무 많아요. 상대가 수락하거나 취소한 뒤 다시 보내 주세요';
  end if;
  insert into public.friendships (requester_id, addressee_id) values (u, t);
  return 'requested';
end $$;

-- 4) 받은 요청 수락 / 거절 ----------------------------------------------------
create or replace function public.friend_respond(p_request uuid, p_accept boolean)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid();
  n integer;
begin
  if u is null then raise exception '로그인이 필요해요' using errcode = '42501'; end if;
  if p_accept is null then raise exception '수락 또는 거절을 선택해 주세요'; end if;
  if p_accept then
    update public.friendships set status = 'accepted', responded_at = now()
    where id = p_request and addressee_id = u and status = 'pending';
  else
    delete from public.friendships
    where id = p_request and addressee_id = u and status = 'pending';
  end if;
  get diagnostics n = row_count;
  if n = 0 then raise exception '처리할 수 있는 친구 요청이 없어요'; end if;
end $$;

-- 5) 친구 끊기 / 보낸 요청 취소 (양쪽 모두 가능, 이미 없어도 오류 없이 통과) ----
create or replace function public.friend_remove(p_friendship uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception '로그인이 필요해요' using errcode = '42501'; end if;
  delete from public.friendships
  where id = p_friendship and (requester_id = u or addressee_id = u);
end $$;

-- 6) 내 친구·요청 목록: relation = friend(친구) / incoming(받은 요청) / outgoing(보낸 요청)
create or replace function public.friend_list()
returns table (
  friendship_id uuid, friend_id uuid, nickname text,
  region_sido text, region_sigungu text, relation text, created_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select f.id, o.id, o.nickname, o.region_sido, o.region_sigungu,
         case when f.status = 'accepted' then 'friend'
              when f.addressee_id = auth.uid() then 'incoming'
              else 'outgoing' end,
         f.created_at
  from public.friendships f
  join public.profiles o
    on o.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
  where auth.uid() is not null
    and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
    and not exists (
      select 1 from public.user_blocks b
      where (b.user_id = auth.uid() and b.blocked_id = o.id)
         or (b.user_id = o.id and b.blocked_id = auth.uid())
    )
  order by case when f.status = 'pending' and f.addressee_id = auth.uid() then 0
                when f.status = 'accepted' then 1 else 2 end,
           o.nickname;
$$;

-- 7) 내 체크인 공개 설정 읽기/바꾸기 -------------------------------------------
create or replace function public.friend_share_get()
returns boolean
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then null
              else coalesce((select s.share_presence from public.friend_settings s
                             where s.user_id = auth.uid()), true) end;
$$;

create or replace function public.friend_share_set(p_share boolean)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요해요' using errcode = '42501'; end if;
  if p_share is null then raise exception '공개 여부를 선택해 주세요'; end if;
  insert into public.friend_settings (user_id, share_presence, updated_at)
  values (auth.uid(), p_share, now())
  on conflict (user_id) do update set share_presence = excluded.share_presence, updated_at = now();
end $$;

-- 8) 친구는 지금 어디에? : 수락된 친구 중 최근 3시간 안에 체크인한 사람 --------
-- 친구가 여러 시설에 체크인했으면 가장 최근 1곳만 보여줍니다.
create or replace function public.friends_presence()
returns table (
  friend_id uuid, nickname text, facility_id uuid,
  facility_name text, facility_address text, checked_in_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select x.user_id, x.nickname, x.facility_id, x.name, x.address, x.checked_in_at
  from (
    select distinct on (c.user_id)
           c.user_id, p.nickname, c.facility_id, fa.name, fa.address, c.checked_in_at
    from public.checkins c
    join public.facilities fa on fa.id = c.facility_id
    join public.profiles p on p.id = c.user_id
    where auth.uid() is not null
      and c.user_id <> auth.uid()
      and c.checked_in_at >= now() - interval '3 hours'
      and c.checked_in_at <= now()
      and exists (
        select 1 from public.friendships f
        where f.status = 'accepted'
          and ((f.requester_id = auth.uid() and f.addressee_id = c.user_id)
            or (f.addressee_id = auth.uid() and f.requester_id = c.user_id))
      )
      and coalesce((select s.share_presence from public.friend_settings s
                    where s.user_id = c.user_id), true)
      and not exists (
        select 1 from public.user_blocks b
        where (b.user_id = auth.uid() and b.blocked_id = c.user_id)
           or (b.user_id = c.user_id and b.blocked_id = auth.uid())
      )
    order by c.user_id, c.checked_in_at desc
  ) x
  order by x.checked_in_at desc;
$$;

-- 9) 로그인한 사용자만 함수 실행 가능 --------------------------------------------
revoke all on function
  public.friend_request(text), public.friend_respond(uuid, boolean),
  public.friend_remove(uuid), public.friend_list(),
  public.friend_share_get(), public.friend_share_set(boolean),
  public.friends_presence()
from public, anon;
grant execute on function
  public.friend_request(text), public.friend_respond(uuid, boolean),
  public.friend_remove(uuid), public.friend_list(),
  public.friend_share_get(), public.friend_share_set(boolean),
  public.friends_presence()
to authenticated;

notify pgrst, 'reload schema';
commit;
