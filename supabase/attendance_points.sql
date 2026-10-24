-- 출석체크 + 포인트. Supabase SQL Editor에서 한 번 실행합니다(다시 실행해도 안전).
-- 출석일 기준: 한국시간(Asia/Seoul) 오전 0시. 날짜 계산은 항상 서버 시간으로 합니다.
-- 앱은 표를 읽기만 하고, 출석·포인트 지급은 attendance_check_in() 함수로만 합니다.
begin;

-- 사용자별 포인트 지갑(현재 잔액·누적 획득·마지막 출석일·연속 출석일).
create table if not exists public.point_wallets (
  user_id uuid primary key references auth.users on delete cascade,
  balance integer not null default 0 check (balance >= 0),
  total_earned integer not null default 0 check (total_earned >= 0),
  last_attended_on date,
  current_streak integer not null default 0 check (current_streak >= 0),
  updated_at timestamptz not null default now()
);

-- 날짜별 출석 이력과 그날 지급 포인트. (사용자, 날짜)당 1줄이라 중복 출석 불가.
create table if not exists public.attendance_days (
  user_id uuid not null references auth.users on delete cascade,
  attended_on date not null,
  streak integer not null check (streak >= 1),
  points integer not null check (points > 0),
  created_at timestamptz not null default now(),
  primary key (user_id, attended_on)
);

-- 포인트 변동 내역. 나중에 다른 보상·사용(음수 amount)을 reason으로 추가합니다.
create table if not exists public.point_ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade,
  amount integer not null check (amount <> 0),
  reason text not null check (reason in ('attendance')),
  ref_date date,
  created_at timestamptz not null default now(),
  unique (user_id, reason, ref_date)
);
create index if not exists point_ledger_user_idx
  on public.point_ledger (user_id, created_at desc);

alter table public.point_wallets enable row level security;
alter table public.attendance_days enable row level security;
alter table public.point_ledger enable row level security;

-- 본인 것만 읽기. 쓰기 권한은 주지 않습니다(함수만 씀).
revoke all on public.point_wallets, public.attendance_days, public.point_ledger
  from public, anon, authenticated;
grant select on public.point_wallets, public.attendance_days, public.point_ledger
  to authenticated;
drop policy if exists point_wallets_own_read on public.point_wallets;
create policy point_wallets_own_read on public.point_wallets
  for select to authenticated using (user_id = auth.uid());
drop policy if exists attendance_days_own_read on public.attendance_days;
create policy attendance_days_own_read on public.attendance_days
  for select to authenticated using (user_id = auth.uid());
drop policy if exists point_ledger_own_read on public.point_ledger;
create policy point_ledger_own_read on public.point_ledger
  for select to authenticated using (user_id = auth.uid());

-- 오늘(한국시간) 날짜. 기기 시계가 아니라 DB 서버 시계를 씁니다.
create or replace function public.attendance_today()
returns date language sql stable set search_path = '' as $$
  select (now() at time zone 'Asia/Seoul')::date;
$$;

-- 연속 출석일에 따른 그날 총 지급 포인트(보너스는 더하지 않고 대체).
create or replace function public.attendance_points_for(streak integer)
returns integer language sql immutable set search_path = '' as $$
  select case streak when 30 then 10 when 14 then 5 when 7 then 3 else 1 end;
$$;

create or replace function public.attendance_status_for(p_user uuid, p_today date)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'today', p_today,
    'attended_today', coalesce(w.last_attended_on = p_today, false),
    -- 어제도 오늘도 출석하지 않았으면 연속 기록은 끊긴 상태(0)로 보여줍니다.
    'streak', case when w.last_attended_on >= p_today - 1
                   then w.current_streak else 0 end,
    'balance', coalesce(w.balance, 0),
    'total_earned', coalesce(w.total_earned, 0),
    'today_points', (select d.points from public.attendance_days d
                     where d.user_id = p_user and d.attended_on = p_today)
  )
  from (select 1) one
  left join public.point_wallets w on w.user_id = p_user;
$$;

-- 출석 처리 본체. 함수 하나가 한 트랜잭션이라 출석 기록·내역·잔액이 함께
-- 저장되거나 함께 취소됩니다. 지갑 줄을 잠가(for update) 여러 기기에서 동시에
-- 눌러도 한 번만 지급합니다.
create or replace function public.attendance_check_in_for(p_user uuid, p_today date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  w public.point_wallets;
  v_streak integer;
  v_points integer;
begin
  if p_user is null then
    raise exception 'login required' using errcode = '42501';
  end if;
  insert into public.point_wallets (user_id) values (p_user)
    on conflict (user_id) do nothing;
  select * into w from public.point_wallets where user_id = p_user for update;

  if w.last_attended_on = p_today then
    return public.attendance_status_for(p_user, p_today)
      || jsonb_build_object('already', true);
  end if;
  if w.last_attended_on is not null and w.last_attended_on > p_today then
    raise exception 'attendance date is in the past' using errcode = '22023';
  end if;

  v_streak := case when w.last_attended_on = p_today - 1
                   then w.current_streak + 1 else 1 end;
  v_points := public.attendance_points_for(v_streak);

  insert into public.attendance_days (user_id, attended_on, streak, points)
    values (p_user, p_today, v_streak, v_points);
  insert into public.point_ledger (user_id, amount, reason, ref_date)
    values (p_user, v_points, 'attendance', p_today);
  update public.point_wallets set
    balance = balance + v_points,
    total_earned = total_earned + v_points,
    last_attended_on = p_today,
    current_streak = v_streak,
    updated_at = now()
  where user_id = p_user;

  return public.attendance_status_for(p_user, p_today)
    || jsonb_build_object('already', false, 'points', v_points);
end;
$$;

-- 앱이 부르는 함수 2개: 로그인한 본인, 서버의 오늘 날짜로만 동작합니다.
create or replace function public.attendance_status()
returns jsonb language sql stable security definer set search_path = '' as $$
  select public.attendance_status_for(auth.uid(), public.attendance_today());
$$;
create or replace function public.attendance_check_in()
returns jsonb language sql security definer set search_path = '' as $$
  select public.attendance_check_in_for(auth.uid(), public.attendance_today());
$$;

revoke all on function public.attendance_status_for(uuid, date),
  public.attendance_check_in_for(uuid, date),
  public.attendance_status(), public.attendance_check_in()
  from public, anon, authenticated;
grant execute on function public.attendance_status(),
  public.attendance_check_in() to authenticated;

commit;
