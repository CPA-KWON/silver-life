-- Apply after activity_expansion.sql; safe to reapply. No client role expansion.
-- New place means >100m from the previous mission and every completed venue.
begin;
create or replace function public.activity_home() returns jsonb language plpgsql stable security definer set search_path=public as $$
declare u uuid:=activity_require_user(); w date:=date_trunc('week',now() at time zone 'Asia/Seoul')::date;
begin return jsonb_build_object(
 'preferences',(select to_jsonb(p) from activity_preferences p where user_id=u),
 'recommendations',coalesce((select jsonb_agg(activity_program_data(c)) from (select * from activity_candidates() limit 12)c),'[]'::jsonb),
 'programs',coalesce((select jsonb_agg(activity_program_data(a) order by a.starts_at) from activity_programs a join activity_organizations o on a.org_id=o.id where o.approved and a.status='open' and a.starts_at>now() and a.deadline>now() and (select count(*) from activity_enrollments e where e.program_id=a.id and e.status in('applied','approved','completed'))<a.capacity),'[]'::jsonb),
 'experiences',coalesce((select jsonb_agg(to_jsonb(e) order by e.title) from activity_experiences e where user_id=u),'[]'::jsonb),
 'applications',coalesce((select jsonb_agg(to_jsonb(e)||jsonb_build_object('program',activity_program_data(a)) order by e.created_at desc) from activity_enrollments e join activity_programs a on a.id=e.program_id where e.user_id=u),'[]'::jsonb),
 'missions',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('program',activity_program_data(a),'status',coalesce(e.status,'unstarted')) order by m.stage) from activity_missions m join activity_programs a on a.id=m.program_id left join activity_enrollments e on e.user_id=m.user_id and e.program_id=m.program_id where m.user_id=u and m.week_start=w),'[]'::jsonb),
 'organizations',coalesce((select jsonb_agg(to_jsonb(o)) from activity_organizations o where activity_is_member(o.id)),'[]'::jsonb),
 'benefit_expires_at',(select max(expires_at) from activity_benefits where user_id=u and starts_at<=now() and expires_at>now())); end $$;

create or replace function public.activity_plan_week(rebuild_unstarted boolean default false) returns void language plpgsql security definer set search_path=public as $$
declare u uuid:=activity_require_user(); w date:=date_trunc('week',now() at time zone 'Asia/Seoul')::date;
 p activity_preferences; chosen activity_programs; prev activity_programs; later activity_programs; s integer;
begin
 select * into p from activity_preferences where user_id=u for update;
 if not found then raise exception '활동 설정을 먼저 저장해주세요.'; end if;
 if rebuild_unstarted then
  delete from activity_missions m where m.user_id=u and m.week_start=w and not exists(select 1 from activity_enrollments e where e.program_id=m.program_id and e.user_id=u and e.status in('applied','approved','completed'));
 end if;
 for s in 1..(case when p.expand_choices then 3 else 1 end) loop
  select a.* into chosen from activity_missions m join activity_programs a on a.id=m.program_id where m.user_id=u and m.week_start=w and m.stage=s;
  if found then prev:=chosen; continue; end if;
  select a.* into later from activity_missions m join activity_programs a on a.id=m.program_id where m.user_id=u and m.week_start=w and m.stage>s order by m.stage limit 1;
  select c.* into chosen from activity_candidates() c
  where (c.starts_at at time zone 'Asia/Seoul')::date>=w and (c.starts_at at time zone 'Asia/Seoul')::date<w+7
   and (prev.id is null or c.starts_at>=prev.ends_at) and (later.id is null or c.ends_at<=later.starts_at)
   and (s<>1 or (c.difficulty=1 and extract(epoch from(c.ends_at-c.starts_at))/60<=60 and activity_distance(p.lat,p.lng,c.lat,c.lng)<=least(p.radius_km,1)))
   and (s<>2 or (activity_distance(c.lat,c.lng,prev.lat,prev.lng)>0.1 and not exists(select 1 from activity_enrollments visited join activity_programs place on place.id=visited.program_id where visited.user_id=u and visited.status='completed' and activity_distance(c.lat,c.lng,place.lat,place.lng)<=0.1))) and (s<>3 or c.participation='함께')
   and not exists(select 1 from activity_missions m where m.user_id=u and m.week_start=w and m.program_id=c.id) limit 1;
  if not found then exit; end if;
  insert into activity_missions values(u,w,s,chosen.id); prev:=chosen;
 end loop;
end $$;

create or replace function public.activity_agency() returns jsonb language plpgsql stable security definer set search_path=public as $$
declare u uuid:=activity_require_user(); begin return jsonb_build_object(
 'programs',coalesce((select jsonb_agg(activity_program_data(p) order by p.starts_at desc) from activity_programs p where activity_is_member(p.org_id)),'[]'::jsonb),
 'applications',coalesce((select jsonb_agg(to_jsonb(e)||jsonb_build_object('program',activity_program_data(p),'applicant',jsonb_build_object('nickname',(select nickname from profiles where id=e.user_id))) order by e.created_at desc) from activity_enrollments e join activity_programs p on p.id=e.program_id where activity_is_member(p.org_id)),'[]'::jsonb),
 'metrics',(with eligible as (select count(*) n from activity_enrollments e join activity_programs p on p.id=e.program_id where activity_is_member(p.org_id) and p.ends_at<=now() and e.status in('approved','completed')), completed as (select e.user_id,p.category from activity_enrollments e join activity_programs p on p.id=e.program_id where activity_is_member(p.org_id) and e.status='completed')
 select jsonb_build_object('completed',count(*),'participants',count(distinct user_id),'categories',count(distinct category),'eligible',(select n from eligible),'completion_rate',round(100.0*count(*)/nullif((select n from eligible),0),1),'repeat_rate',round(100.0*(select count(*) from(select user_id from completed group by user_id having count(*)>1)x)/nullif(count(distinct user_id),0),1),'repeat_participants',(select count(*) from(select user_id from completed group by user_id having count(*)>1)x)) from completed)); end $$;
notify pgrst, 'reload schema';
commit;
