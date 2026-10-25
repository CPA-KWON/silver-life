-- Run in the SQL Editor. Safe to re-run: re-running refreshes the app table
-- from the two original tables the team imported from CSV
-- ("welfare_programs (sangdo)", "welfare_programs (heuksuk)"), which are
-- left untouched. Edit the originals in Table Editor, then run this again.
--
-- 복지관·문화센터 운영 프로그램 (안내용). 앱 시설 상세 화면의
-- "이 복지관에서 운영 중인 프로그램"이 이 표를 읽는다. 앱에서 신청하는
-- 활동(activity_programs)과는 별개다.

create table if not exists public.welfare_programs (
  id bigint generated always as identity primary key,
  -- 앱이 지도 검색 결과의 시설 이름과 맞춰보는 이름 (띄어쓰기 무시, 포함 관계로 비교)
  facility_name text not null,
  source text not null,          -- 원본 표: 'sangdo' / 'heuksuk'
  source_id bigint not null,     -- 원본 표의 id
  service_group text,
  title text not null,
  category text,
  description text,
  schedule text,                 -- 예: '매주 화요일 13:00~13:50'
  target text,
  purpose text,
  period text,
  how_to_apply text,
  fee text,
  is_free boolean,
  capacity integer,
  place text,
  hours text,
  note text,
  updated_at timestamptz not null default now(),
  unique (source, source_id)
);

alter table public.welfare_programs enable row level security;

-- 로그인한 사용자는 읽기만 가능. 쓰기 정책은 일부러 만들지 않는다
-- (수정은 팀이 대시보드에서 원본 표를 고친 뒤 이 SQL을 다시 실행).
drop policy if exists "Signed-in users can view welfare programs" on public.welfare_programs;
create policy "Signed-in users can view welfare programs"
on public.welfare_programs for select
to authenticated
using (true);

revoke insert, update, delete on public.welfare_programs from anon, authenticated;

-- 원본 두 표 → 앱 표로 복사 (이미 있으면 최신 내용으로 덮어씀)
insert into public.welfare_programs (
  facility_name, source, source_id, service_group, title, category, description,
  schedule, target, purpose, period, how_to_apply, fee, is_free, capacity, place, hours, note
)
select
  case
    when src.source = 'sangdo' then '상도은빛복지관'
    when src."장소" like '%낭만시니어라운지%' then '낭만시니어라운지'
    else '흑석종합사회복지관'
  end,
  src.source,
  src.id,
  nullif(trim(src."서비스그룹"), ''),
  trim(src."프로그램명"),
  nullif(trim(src."분류"), ''),
  nullif(trim(src."내용"), ''),
  nullif(trim(src."일정"), ''),
  nullif(trim(src."대상"), ''),
  nullif(trim(src."목적"), ''),
  nullif(trim(src."기간"), ''),
  nullif(trim(src."신청방법"), ''),
  nullif(trim(src."수강료"), ''),
  case lower(trim(src."무료여부")) when 'true' then true when 'false' then false end,
  nullif(regexp_replace(coalesce(src."정원", ''), '\D', '', 'g'), '')::integer,
  nullif(trim(src."장소"), ''),
  nullif(trim(src."운영시간"), ''),
  nullif(trim(src."비고"), '')
from (
  select 'sangdo' as source, s.id::bigint as id,
    s."서비스그룹"::text as "서비스그룹", s."프로그램명"::text as "프로그램명", s."분류"::text as "분류",
    s."내용"::text as "내용", s."일정"::text as "일정", s."대상"::text as "대상", s."목적"::text as "목적",
    s."기간"::text as "기간", s."신청방법"::text as "신청방법", s."수강료"::text as "수강료",
    s."무료여부"::text as "무료여부", s."정원"::text as "정원", s."장소"::text as "장소",
    s."운영시간"::text as "운영시간", s."비고"::text as "비고"
  from public."welfare_programs (sangdo)" s
  union all
  select 'heuksuk', h.id::bigint,
    h."서비스그룹"::text, h."프로그램명"::text, h."분류"::text,
    h."내용"::text, h."일정"::text, h."대상"::text, h."목적"::text,
    h."기간"::text, h."신청방법"::text, h."수강료"::text,
    h."무료여부"::text, h."정원"::text, h."장소"::text,
    h."운영시간"::text, h."비고"::text
  from public."welfare_programs (heuksuk)" h
) src
where nullif(trim(src."프로그램명"), '') is not null
on conflict (source, source_id) do update set
  facility_name = excluded.facility_name,
  service_group = excluded.service_group,
  title = excluded.title,
  category = excluded.category,
  description = excluded.description,
  schedule = excluded.schedule,
  target = excluded.target,
  purpose = excluded.purpose,
  period = excluded.period,
  how_to_apply = excluded.how_to_apply,
  fee = excluded.fee,
  is_free = excluded.is_free,
  capacity = excluded.capacity,
  place = excluded.place,
  hours = excluded.hours,
  note = excluded.note,
  updated_at = now();

-- 결과 확인: 시설별 개수 (상도은빛복지관 49, 흑석종합사회복지관 33, 낭만시니어라운지 3)
select facility_name as 시설, count(*) as 프로그램_수
from public.welfare_programs
group by facility_name
order by facility_name;
