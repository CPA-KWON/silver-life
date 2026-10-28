-- 회원 탈퇴 (Run in the SQL Editor. Safe to re-run.)
--
-- 앱은 delete_my_account()만 부른다. 이 함수는 로그인한 본인(auth.uid())의
-- auth.users 줄만 지우고, 나머지는 각 표의 "on delete cascade"로 함께 지워진다.
-- service_role 키는 쓰지 않는다.
--
-- 2026-10-28 supabase/*.sql 전체 점검 결과 (사용자와 연결된 칸):
--   profiles, posts, comments, favorites, checkins, reports,
--   activity_org_members/preferences/experiences/enrollments/benefits/missions,
--   point_wallets, attendance_days, point_ledger, pet_* 8개
--     → 모두 auth.users 또는 profiles에 on delete cascade (자동 삭제)
--   남의 글에 단 내 댓글·신고, 내 글에 달린 남의 댓글·신고 → post_id/comment_id cascade
--   activity_enrollments.experience_id, activity_benefits.enrollment_id
--     → 둘 다 같은 사용자 줄이 한 번에 지워지므로 막히지 않음
--   institution_notices.created_by → auth.users (cascade 없음) ⇒ 탈퇴가 막힘
--     → 공지는 기관 것이라 남기고, 작성자 칸만 비우도록(on delete set null) 아래에서 변경
--   activity_organizations / activity_programs → 기관 소속이라 사용자 탈퇴와 무관

begin;

-- 1. 기관 공지: 작성자가 탈퇴해도 공지는 남기고 created_by만 비운다.
do $$
declare c record;
begin
  if to_regclass('public.institution_notices') is null then return; end if;
  for c in
    select con.conname
    from pg_constraint con
    join pg_attribute att on att.attrelid = con.conrelid and att.attnum = any(con.conkey)
    where con.conrelid = 'public.institution_notices'::regclass
      and con.contype = 'f' and att.attname = 'created_by'
  loop
    execute format('alter table public.institution_notices drop constraint %I', c.conname);
  end loop;
  alter table public.institution_notices alter column created_by drop not null;
  alter table public.institution_notices
    add constraint institution_notices_created_by_fkey
    foreign key (created_by) references auth.users (id) on delete set null;
end $$;

-- 2. 탈퇴 함수: 인자 없이 로그인한 본인만 지운다.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  u uuid := auth.uid();
begin
  if u is null then
    raise exception '로그인이 필요해요.' using errcode = '42501';
  end if;
  delete from auth.users where id = u;
exception
  when foreign_key_violation then
    raise exception '탈퇴를 마치지 못했어요. 문의처로 알려주세요. (%)', sqlerrm
      using errcode = 'P0001';
end $$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

commit;

-- 3. 결과 확인: 사용자 삭제를 막을 수 있는 연결이 남았는지.
--    "Success. No rows returned"가 나오면 정상이다.
--    줄이 나오면 그 표·칸 이름을 Claude에게 알려주세요(대시보드에서 직접 만든 표일 수 있음).
select con.conrelid::regclass as 표, con.conname as 연결이름,
       confrelid::regclass as 가리키는_표
from pg_constraint con
where con.contype = 'f'
  and con.connamespace <> 'auth'::regnamespace
  and con.confrelid in ('auth.users'::regclass, 'public.profiles'::regclass)
  and con.confdeltype in ('a', 'r');
