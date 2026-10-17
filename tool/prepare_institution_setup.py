"""Build a reviewable, repeatable SQL setup; never connects to a server."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TABLES = ['activity_organizations', 'activity_org_members', 'activity_preferences',
          'activity_experiences', 'activity_programs', 'activity_sponsorships',
          'activity_enrollments', 'activity_benefits', 'activity_missions']


def body(filename):
    lines = (ROOT / 'supabase' / filename).read_text().splitlines()
    return '\n'.join(line for line in lines
                     if line.strip().lower() not in ('begin;', 'commit;'))


def build():
    names = ','.join("'" + name + "'" for name in TABLES)
    return f"""-- Silver Life institution setup. Review before running on the matching project.
-- Existing posts/users/experiences are retained. No fake public programs added.
begin;
select pg_advisory_xact_lock(hashtext('silver-life-institution-setup'));
do $setup$
declare existing integer;
begin
  if to_regclass('public.profiles') is null or to_regclass('public.posts') is null
     or to_regclass('public.comments') is null or to_regclass('public.facilities') is null then
    raise exception '기본 서비스 테이블을 먼저 확인해주세요.';
  end if;
  select count(*) into existing from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in ({names}) and c.relkind='r';
  if existing=0 then
    execute $base$
{body('activity_expansion.sql')}
$base$;
  elsif existing<>9 then
    raise exception '활동 테이블이 일부만 존재합니다. 중복 생성하지 않고 중단합니다.';
  end if;
end $setup$;

{body('integration_security.sql')}

{body('activity_usability_fix.sql')}

-- Only the specifically authorized test account joins this verification org.
do $member$
declare uid uuid; org uuid;
begin
  select id into uid from auth.users where lower(email)='ins@silverlife.invalid';
  if uid is null then raise exception '승인받은 ins 검증 계정을 찾을 수 없습니다.'; end if;
  select o.id into org from activity_org_members m join activity_organizations o on o.id=m.org_id
    where m.user_id=uid and o.approved order by o.id limit 1;
  if org is null then
    select id into org from activity_organizations where name='Silver Life 운영 검증 기관' order by id limit 1;
    if org is null then
      insert into activity_organizations(name,approved) values('Silver Life 운영 검증 기관',true) returning id into org;
    else
      update activity_organizations set approved=true where id=org;
    end if;
    insert into activity_org_members(org_id,user_id) values(org,uid) on conflict do nothing;
  end if;
end $member$;
notify pgrst, 'reload schema';
commit;

select '설정 완료' as result, o.name as institution, p.nickname as operator
from public.activity_org_members m join public.activity_organizations o on o.id=m.org_id
join public.profiles p on p.id=m.user_id join auth.users u on u.id=m.user_id
where lower(u.email)='ins@silverlife.invalid';
"""


if __name__ == '__main__':
    import sys
    destination = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'supabase' / 'institution_setup.sql'
    destination.write_text(build())
    print('기관 설정 SQL 준비 완료:', destination)
