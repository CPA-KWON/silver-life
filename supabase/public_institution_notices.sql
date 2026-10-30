-- Public-source notice indexes are independent of verified partner agencies.
-- No organizations, memberships, reader records or reward eligibility created.
begin;
create table if not exists public.public_institution_notices (
 id uuid primary key,
 institution_name text not null check(char_length(institution_name) between 1 and 150),
 institution_kind text not null check(institution_kind in('복지관','주민센터','보건소','경로당','기타')),
 region_sido text not null,region_sigungu text not null,
 title text not null check(char_length(title) between 1 and 300),
 summary text not null check(char_length(summary) between 1 and 1000),
 source_url text not null unique check(source_url ~ '^https://[^[:space:]]+$'),
 source_board text not null check(source_board ~ '^https://[^[:space:]]+$'),
 published_on date not null,source_verified_at timestamptz not null,
 archived boolean not null default false,published boolean not null default false,
 updated_at timestamptz not null default now()
);
alter table public.public_institution_notices enable row level security;
revoke all on public.public_institution_notices from public,anon,authenticated;
grant select on public.public_institution_notices to authenticated;
do $$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='public_institution_notices' and policyname='public_source_notice_read') then
  create policy public_source_notice_read on public.public_institution_notices for select to authenticated
   using(published and published_on<=(now() at time zone 'Asia/Seoul')::date);
 end if;
end $$;
create index if not exists public_source_notice_region on public.public_institution_notices(region_sido,region_sigungu,published_on desc,id) where published;
notify pgrst,'reload schema';
commit;
