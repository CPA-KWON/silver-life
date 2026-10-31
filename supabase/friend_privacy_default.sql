-- 체크인 공유를 기본으로 끄기 (Run in the SQL Editor after friends.sql.
-- Safe to re-run; any error rolls everything back.)
--
-- 위치에 가까운 정보라 본인이 고른 사람만 공개한다.
--   1) 기본값을 "안 보임"으로, 지금까지의 설정도 모두 "안 보임"으로 한 번 초기화
--   2) 설정 줄이 없는 사람을 "보임"으로 치던 함수 2개도 "안 보임"으로 수정
--   3) 처음 친구를 맺을 때 물어봤는지 기록(share_asked). 앱은 이 값을 보고 한 번만 묻는다.
-- 초기화는 share_asked 칸을 처음 만들 때 한 번만 일어나므로, 이 파일을 다시
-- 실행해도 사용자가 고른 설정은 지워지지 않는다.

begin;

alter table public.friend_settings alter column share_presence set default false;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'friend_settings'
      and column_name = 'share_asked'
  ) then
    alter table public.friend_settings
      add column share_asked boolean not null default false;
    update public.friend_settings set share_presence = false, updated_at = now();
  end if;
end $$;

create or replace function public.friend_share_get()
returns boolean
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then null
              else coalesce((select s.share_presence from public.friend_settings s
                             where s.user_id = auth.uid()), false) end;
$$;

create or replace function public.friend_share_asked()
returns boolean
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then null
              else coalesce((select s.share_asked from public.friend_settings s
                             where s.user_id = auth.uid()), false) end;
$$;

-- 물어본 뒤의 답이든 스위치로 바꾼 것이든, 직접 고른 것이므로 다시 묻지 않는다.
create or replace function public.friend_share_set(p_share boolean)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요해요' using errcode = '42501'; end if;
  if p_share is null then raise exception '공개 여부를 선택해 주세요'; end if;
  insert into public.friend_settings (user_id, share_presence, share_asked, updated_at)
  values (auth.uid(), p_share, true, now())
  on conflict (user_id) do update
    set share_presence = excluded.share_presence, share_asked = true, updated_at = now();
end $$;

-- friends.sql의 정의에서 설정 줄이 없을 때의 값만 false로 바꾼 것.
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
                    where s.user_id = c.user_id), false)
      and not exists (
        select 1 from public.user_blocks b
        where (b.user_id = auth.uid() and b.blocked_id = c.user_id)
           or (b.user_id = c.user_id and b.blocked_id = auth.uid())
      )
    order by c.user_id, c.checked_in_at desc
  ) x
  order by x.checked_in_at desc;
$$;

revoke all on function public.friend_share_asked() from public, anon;
grant execute on function public.friend_share_asked() to authenticated;

commit;

notify pgrst, 'reload schema';

-- 결과 확인: 처음 실행 직후에는 체크인을_보이는_사람이 0이어야 한다.
select count(*) filter (where share_presence) as 체크인을_보이는_사람,
       count(*) as 설정_줄_수,
       pg_get_expr(d.adbin, d.adrelid) as 기본값
from public.friend_settings
cross join (
  select ad.adbin, ad.adrelid from pg_attrdef ad
  join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
  where ad.adrelid = 'public.friend_settings'::regclass and a.attname = 'share_presence'
) d
group by d.adbin, d.adrelid;
