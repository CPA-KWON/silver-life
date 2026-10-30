-- One user-selected usual institution. Does not change residence/eligibility,
-- facility favorites, institution staff access, enrollments or notifications.
begin;
create table if not exists public.my_notice_institutions (
 user_id uuid primary key references auth.users(id) on delete cascade,
 institution_name text not null,
 region_sido text not null,region_sigungu text not null,
 updated_at timestamptz not null default now()
);
alter table public.my_notice_institutions enable row level security;
revoke all on public.my_notice_institutions from public,anon,authenticated;
grant select,insert,update,delete on public.my_notice_institutions to authenticated;
do $$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='my_notice_institutions' and policyname='own_usual_institution') then
  create policy own_usual_institution on public.my_notice_institutions for all to authenticated
   using(user_id=auth.uid()) with check(user_id=auth.uid() and exists(
     select 1 from public.public_institution_notices n where n.published
       and n.institution_name=my_notice_institutions.institution_name
       and n.region_sido=my_notice_institutions.region_sido and n.region_sigungu=my_notice_institutions.region_sigungu));
 end if;
end $$;
create or replace view public.public_notice_institutions with(security_invoker=true) as
 select n.institution_name,n.region_sido,n.region_sigungu,min(n.institution_kind) institution_kind,
 min(n.source_board) source_board,
 (select case when count(distinct f.address)=1 then min(f.address) else null end from public.facilities f
   where regexp_replace(f.name,'^(서울시립|시립|구립)[[:space:]]*','')=n.institution_name
    and f.region_sido=n.region_sido and f.region_sigungu=n.region_sigungu) address
 from public.public_institution_notices n where n.published
 group by n.institution_name,n.region_sido,n.region_sigungu;
revoke all on public.public_notice_institutions from public,anon;
grant select on public.public_notice_institutions to authenticated;
notify pgrst,'reload schema';
commit;
