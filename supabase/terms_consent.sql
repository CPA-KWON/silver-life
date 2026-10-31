-- 이용약관·개인정보 처리방침 동의 기록 (Run in the SQL Editor. Safe to re-run;
-- any error rolls everything back.)
--
-- 새 가입자: 가입할 때 보낸 terms_version을 아래 트리거가 기록한다
--   (이메일 인증 전에는 로그인 상태가 아니라 앱이 직접 기록할 수 없다).
-- 기존 가입자: 처음 글·댓글·모임을 쓸 때 앱이 terms_accepted로 확인하고
--   동의를 받으면 accept_terms로 기록한다.
-- 약관 버전(lib/profile/terms_page.dart의 kTermsVersion)이 바뀌면 다시 동의받는다.

begin;

create table if not exists public.user_consents (
  user_id uuid not null references auth.users (id) on delete cascade,
  document text not null check (document in ('terms', 'privacy')),
  version text not null check (char_length(version) between 1 and 20),
  agreed_at timestamptz not null default now(),
  primary key (user_id, document, version)
);
alter table public.user_consents enable row level security;
revoke all on public.user_consents from public, anon, authenticated;

create or replace function public.record_signup_consent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v text := new.raw_user_meta_data ->> 'terms_version';
begin
  if v is not null and char_length(v) between 1 and 20 then
    insert into public.user_consents (user_id, document, version)
    values (new.id, 'terms', v), (new.id, 'privacy', v)
    on conflict do nothing;
  end if;
  return new;
exception
  -- 동의 기록 문제로 회원가입 자체가 막히면 안 된다. 기록이 없으면 첫 글쓰기 때 다시 묻는다.
  when others then
    return new;
end $$;

drop trigger if exists record_signup_consent on auth.users;
create trigger record_signup_consent
after insert on auth.users
for each row execute function public.record_signup_consent();

create or replace function public.terms_accepted(p_version text)
returns boolean
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
  return (select count(*) = 2 from public.user_consents
          where user_id = u and version = p_version
            and document in ('terms', 'privacy'));
end $$;

create or replace function public.accept_terms(p_version text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare u uuid := auth.uid();
begin
  if u is null then
    raise exception '로그인이 필요해요.' using errcode = '42501';
  end if;
  insert into public.user_consents (user_id, document, version)
  values (u, 'terms', p_version), (u, 'privacy', p_version)
  on conflict do nothing;
end $$;

revoke all on function public.record_signup_consent() from public, anon, authenticated;
revoke all on function public.terms_accepted(text) from public, anon;
revoke all on function public.accept_terms(text) from public, anon;
grant execute on function public.terms_accepted(text) to authenticated;
grant execute on function public.accept_terms(text) to authenticated;

commit;

notify pgrst, 'reload schema';

-- 결과 확인: 동의 기록 수(처음에는 0)와 가입 트리거가 있는지(1)
select (select count(*) from public.user_consents) as 동의_기록_수,
       (select count(*) from pg_trigger
        where tgname = 'record_signup_consent' and not tgisinternal) as 가입_트리거;
