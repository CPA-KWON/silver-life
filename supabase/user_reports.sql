-- 사용자 신고 (Run in the SQL Editor. Safe to re-run; any error rolls everything back.)
--
-- 글·댓글 신고(reports)와 같은 사유를 쓰되, 대상이 사람이라 표를 따로 둔다.
-- 앱은 표를 직접 읽거나 쓰지 않고 report_user만 부른다. 닉네임은 겹치지 않고 이미
-- 화면에 공개된 값이라, 사용자 고유 번호를 앱에 새로 내보내지 않고 닉네임으로 받는다.
-- 사용자 신고는 자동으로 숨기거나 제한하지 않는다. 팀이 대시보드에서
-- user_report_summary(사용자 신고 모아보기)를 보고 판단한다.

begin;

create table if not exists public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users (id) on delete cascade,
  reported_id uuid not null references auth.users (id) on delete cascade,
  reason text not null check (reason in ('욕설·비방', '광고', '사기 의심', '음란·불쾌한 내용', '기타')),
  created_at timestamptz not null default now(),
  -- 같은 사람이 같은 사용자를 두 번 신고할 수 없다.
  unique (reporter_id, reported_id),
  check (reporter_id <> reported_id)
);
create index if not exists user_reports_reported on public.user_reports (reported_id);
alter table public.user_reports enable row level security;
revoke all on public.user_reports from public, anon, authenticated;

create or replace function public.report_user(p_nickname text, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  u uuid := auth.uid();
  target uuid;
begin
  if u is null then
    raise exception '로그인이 필요해요.' using errcode = '42501';
  end if;
  select id into target from public.profiles where nickname = p_nickname;
  if target is null then
    raise exception '사용자를 찾을 수 없어요.' using errcode = 'P0001';
  end if;
  if target = u then
    raise exception '나를 신고할 수는 없어요.' using errcode = 'P0001';
  end if;
  -- 중복이면 unique 규칙이 23505로 막고, 앱이 "이미 신고하셨어요"로 안내한다.
  insert into public.user_reports (reporter_id, reported_id, reason)
  values (u, target, p_reason);
end $$;

revoke all on function public.report_user(text, text) from public, anon;
grant execute on function public.report_user(text, text) to authenticated;

-- 팀이 대시보드(Table Editor)에서 보는 모아보기. 앱 계정은 볼 수 없다.
create or replace view public.user_report_summary
with (security_invoker = true)
as
select
  r.created_at as 신고일시,
  reported.nickname as 신고된_사용자,
  r.reason as 사유,
  reporter.nickname as 신고한_사람,
  count(*) over (partition by r.reported_id) as 누적_신고수,
  r.reported_id
from public.user_reports r
left join public.profiles reported on reported.id = r.reported_id
left join public.profiles reporter on reporter.id = r.reporter_id
order by r.created_at desc;
revoke all on public.user_report_summary from public, anon, authenticated;

commit;

notify pgrst, 'reload schema';

-- 결과 확인: 신고 기록 수(처음에는 0)
select count(*) as 사용자_신고_수 from public.user_reports;
