-- Additive migration. Review and apply manually; never executed by the app.
begin;
create table public.activity_organizations (
 id uuid primary key default gen_random_uuid(), name text not null check(length(name) between 1 and 100), approved boolean not null default false
);
create table public.activity_org_members (
 org_id uuid references public.activity_organizations on delete cascade, user_id uuid references auth.users on delete cascade,
 primary key(org_id,user_id)
);
create table public.activity_preferences (
 user_id uuid primary key references auth.users on delete cascade,
 place_name text not null, lat double precision not null check(lat between -90 and 90), lng double precision not null check(lng between -180 and 180),
 radius_km integer not null check(radius_km in(1,3,5,10,20)), interests text[] not null check(cardinality(interests)>0 and interests <@ array['건강·운동','문화·취미','배움·디지털','생활·기술','지역·이야기']),
 transport text not null check(transport in('도보','대중교통','자동차')), participation text not null check(participation in('무관','혼자','함께')),
 max_minutes integer not null check(max_minutes between 15 and 480), difficulty integer not null check(difficulty between 1 and 3), expand_choices boolean not null default true
);
create table public.activity_experiences (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users on delete cascade,
 title text not null check(length(title) between 1 and 100), category text not null check(category=any(array['건강·운동','문화·취미','배움·디지털','생활·기술','지역·이야기'])),
 description text not null check(length(description) between 1 and 2000), available_time text not null,
 preferred_place text not null, activity_type text not null, active boolean not null default true
);
create table public.activity_programs (
 id uuid primary key default gen_random_uuid(), org_id uuid not null references public.activity_organizations,
 title text not null check(length(title) between 1 and 100), description text not null check(length(description) between 1 and 3000), category text not null check(category=any(array['건강·운동','문화·취미','배움·디지털','생활·기술','지역·이야기'])),
 kind text not null check(kind in('activity','experience')), place_name text not null,
 lat double precision not null check(lat between -90 and 90), lng double precision not null check(lng between -180 and 180),
 starts_at timestamptz not null, ends_at timestamptz not null, deadline timestamptz not null,
 capacity integer not null check(capacity between 1 and 1000), fee integer not null default 0 check(fee between 0 and 10000000),
 transports text[] not null check(cardinality(transports)>0 and transports <@ array['도보','대중교통','자동차']), participation text not null check(participation in('혼자','함께')),
 difficulty integer not null check(difficulty between 1 and 3), status text not null default 'open' check(status in('open','closed')),
 check(ends_at>starts_at), check(deadline<=starts_at), check(kind<>'experience' or fee=0)
);
create table public.activity_sponsorships (
 id uuid primary key default gen_random_uuid(), program_id uuid not null references public.activity_programs on delete cascade,
 starts_at timestamptz not null, ends_at timestamptz not null, payment_confirmed boolean not null default false, check(ends_at>starts_at)
);
create table public.activity_enrollments (
 id uuid primary key default gen_random_uuid(), program_id uuid not null references public.activity_programs,
 user_id uuid not null references auth.users on delete cascade, experience_id uuid references public.activity_experiences,
 experience_snapshot jsonb, status text not null check(status in('applied','approved','rejected','cancelled','completed')),
 original_fee integer not null, final_fee integer not null, created_at timestamptz not null default now(), completed_at timestamptz,
 unique(program_id,user_id)
);
create table public.activity_benefits (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users on delete cascade,
 enrollment_id uuid not null unique references public.activity_enrollments, starts_at timestamptz not null, expires_at timestamptz not null,
 check(expires_at>starts_at)
);
create table public.activity_missions (
 user_id uuid not null references auth.users on delete cascade, week_start date not null, stage integer not null check(stage between 1 and 3),
 program_id uuid not null references public.activity_programs, primary key(user_id,week_start,stage), unique(user_id,week_start,program_id)
);
create index on public.activity_enrollments(program_id,status);
create index on public.activity_enrollments(user_id);
create index on public.activity_programs(starts_at);
create index on public.activity_benefits(user_id,expires_at);

create function public.activity_is_member(target_org uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from activity_org_members m join activity_organizations o on o.id=m.org_id where m.org_id=target_org and m.user_id=auth.uid() and o.approved)
$$;
create function public.activity_require_user() returns uuid language plpgsql stable set search_path=public as $$
begin if auth.uid() is null then raise exception '로그인이 필요해요.'; end if; return auth.uid(); end $$;

do $$ declare t text; begin
 foreach t in array array['activity_organizations','activity_org_members','activity_preferences','activity_experiences','activity_programs','activity_sponsorships','activity_enrollments','activity_benefits','activity_missions'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon, authenticated',t);
 end loop;
end $$;
grant select on public.activity_organizations, public.activity_org_members, public.activity_programs, public.activity_enrollments, public.activity_benefits, public.activity_missions to authenticated;
grant select,insert,update on public.activity_preferences, public.activity_experiences to authenticated;
create policy own_preferences on public.activity_preferences for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy own_experiences on public.activity_experiences for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy approved_orgs on public.activity_organizations for select to authenticated using(approved or activity_is_member(id));
create policy own_membership on public.activity_org_members for select to authenticated using(user_id=auth.uid());
create policy approved_programs on public.activity_programs for select to authenticated using(exists(select 1 from activity_organizations o where o.id=org_id and o.approved));
create policy own_enrollment on public.activity_enrollments for select to authenticated using(user_id=auth.uid() or activity_is_member((select org_id from activity_programs where id=program_id)));
create policy own_benefits on public.activity_benefits for select to authenticated using(user_id=auth.uid());
create policy own_missions on public.activity_missions for select to authenticated using(user_id=auth.uid());

create function public.activity_distance(lat1 double precision,lng1 double precision,lat2 double precision,lng2 double precision)
 returns double precision language sql immutable set search_path=public as $$
 select 6371*2*asin(least(1.0,sqrt(power(sin(radians(lat2-lat1)/2),2)+cos(radians(lat1))*cos(radians(lat2))*power(sin(radians(lng2-lng1)/2),2))))
$$;
create function public.activity_program_data(target public.activity_programs) returns jsonb language sql stable security definer set search_path=public as $$
 select to_jsonb(target)||jsonb_build_object('org_name',(select name from activity_organizations where id=target.org_id),
 'enrolled',(select count(*) from activity_enrollments where program_id=target.id and status in('applied','approved','completed')),
 'sponsored',exists(select 1 from activity_sponsorships where program_id=target.id and payment_confirmed and starts_at<=now() and ends_at>now()),
 'distance_km',(select activity_distance(p.lat,p.lng,target.lat,target.lng) from activity_preferences p where p.user_id=auth.uid()))
$$;
create function public.activity_candidates() returns setof public.activity_programs language sql stable security definer set search_path=public as $$
 select a.* from activity_programs a join activity_organizations o on o.id=a.org_id and o.approved
 join activity_preferences p on p.user_id=auth.uid()
 where a.kind='activity' and a.status='open' and a.starts_at>now() and a.deadline>now()
 and a.category=any(p.interests) and p.transport=any(a.transports) and (p.participation='무관' or p.participation=a.participation)
 and a.difficulty<=p.difficulty and extract(epoch from(a.ends_at-a.starts_at))/60<=p.max_minutes
 and activity_distance(p.lat,p.lng,a.lat,a.lng)<=p.radius_km
 and (select count(*) from activity_enrollments where program_id=a.id and status in('applied','approved','completed'))<a.capacity
 and not exists(select 1 from activity_enrollments where program_id=a.id and user_id=auth.uid() and status in('applied','approved','completed'))
 order by exists(select 1 from activity_sponsorships s where s.program_id=a.id and s.payment_confirmed and s.starts_at<=now() and s.ends_at>now()) desc,
 exists(select 1 from activity_enrollments e join activity_programs h on h.id=e.program_id where e.user_id=auth.uid() and e.status='completed' and h.category=a.category),
 activity_distance(p.lat,p.lng,a.lat,a.lng),a.starts_at,a.id
$$;
create function public.activity_home() returns jsonb language plpgsql stable security definer set search_path=public as $$
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

create function public.activity_plan_week(rebuild_unstarted boolean default false) returns void language plpgsql security definer set search_path=public as $$
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
create function public.activity_program_detail(program_id uuid) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare u uuid:=activity_require_user(); a activity_programs; discount boolean;
begin
 select p.* into a from activity_programs p join activity_organizations o on o.id=p.org_id where p.id=program_id and o.approved;
 if not found then raise exception '활동을 찾을 수 없어요.'; end if;
 select exists(select 1 from activity_benefits b where b.user_id=u and b.starts_at<=now() and b.expires_at>now()) into discount;
 return jsonb_build_object('program',activity_program_data(a),'application',(select to_jsonb(e) from activity_enrollments e where e.program_id=a.id and e.user_id=u),
 'quote',case when discount then (a.fee+1)/2 else a.fee end);
end $$;
create function public.activity_apply(target_program uuid, target_experience uuid default null) returns uuid language plpgsql security definer set search_path=public as $$
declare u uuid:=activity_require_user(); a activity_programs; e activity_experiences; existing activity_enrollments; price integer; result uuid;
begin
 select p.* into a from activity_programs p join activity_organizations o on o.id=p.org_id and o.approved where p.id=target_program for update of p;
 if not found or a.status<>'open' or a.deadline<=now() or a.starts_at<=now() then raise exception '신청 가능한 활동이 아니에요.'; end if;
 select * into existing from activity_enrollments where program_id=a.id and user_id=u;
 if existing.status in('applied','approved','completed') then raise exception '이미 신청한 활동이에요.'; end if;
 if (select count(*) from activity_enrollments where program_id=a.id and status in('applied','approved','completed'))>=a.capacity then raise exception '정원이 모두 찼어요.'; end if;
 if a.kind='experience' then
  if activity_is_member(a.org_id) then raise exception '소속 기관에는 경험 나눔을 지원할 수 없어요.'; end if;
  select * into e from activity_experiences where id=target_experience and user_id=u and active and category=a.category;
  if not found then raise exception '같은 분야의 활성 경험을 선택해주세요.'; end if;
 elsif target_experience is not null then raise exception '일반 활동에는 경험을 제출할 수 없어요.'; end if;
 price:=a.fee;
 if exists(select 1 from activity_benefits where user_id=u and starts_at<=now() and expires_at>now()) then price:=(a.fee+1)/2; end if;
 insert into activity_enrollments(program_id,user_id,experience_id,experience_snapshot,status,original_fee,final_fee)
 values(a.id,u,e.id,case when e.id is not null then to_jsonb(e)-'user_id' else null end,'applied',a.fee,price)
 on conflict(program_id,user_id) do update set experience_id=excluded.experience_id,experience_snapshot=excluded.experience_snapshot,status='applied',original_fee=excluded.original_fee,final_fee=excluded.final_fee,created_at=now(),completed_at=null returning id into result;
 return result;
end $$;
create function public.activity_cancel(enrollment uuid) returns void language plpgsql security definer set search_path=public as $$
declare u uuid:=activity_require_user(); p uuid; a activity_programs;
begin
 select program_id into p from activity_enrollments where id=enrollment and user_id=u;
 select * into a from activity_programs where id=p for update;
 if not found or a.starts_at<=now() then raise exception '시작 전 활동만 취소할 수 있어요.'; end if;
 update activity_enrollments set status='cancelled' where id=enrollment and user_id=u and status in('applied','approved');
 if not found then raise exception '취소 가능한 신청이 아니에요.'; end if;
end $$;
create function public.activity_manage(enrollment uuid, action text) returns void language plpgsql security definer set search_path=public as $$
declare u uuid:=activity_require_user(); p uuid; a activity_programs; e activity_enrollments;
begin
 select program_id into p from activity_enrollments where id=enrollment;
 select * into a from activity_programs where id=p for update;
 if not found or not activity_is_member(a.org_id) then raise exception '기관 담당자 권한이 필요해요.'; end if;
 select * into e from activity_enrollments where id=enrollment for update;
 if e.user_id=u then raise exception '본인의 활동을 확인할 수 없어요.'; end if;
 if action='approved' and e.status='applied' then update activity_enrollments set status=action where id=e.id;
 elsif action='rejected' and e.status in('applied','approved') then update activity_enrollments set status=action where id=e.id;
 elsif action='completed' and e.status='approved' and a.ends_at<=now() then
  update activity_enrollments set status=action,completed_at=now() where id=e.id;
  if a.kind='experience' then insert into activity_benefits(user_id,enrollment_id,starts_at,expires_at) values(e.user_id,e.id,now(),now()+interval '30 days') on conflict(enrollment_id) do nothing; end if;
 else raise exception '현재 상태에서 처리할 수 없어요. 완료 확인은 활동 종료 후 가능해요.'; end if;
end $$;
create function public.activity_save_program(data jsonb) returns uuid language plpgsql security definer set search_path=public as $$
declare u uuid:=activity_require_user(); result uuid;
begin
 if not activity_is_member((data->>'org_id')::uuid) then raise exception '기관 담당자 권한이 필요해요.'; end if;
 if (data->>'deadline')::timestamptz<=now() or (data->>'starts_at')::timestamptz<=now() then raise exception '미래 일정을 선택해주세요.'; end if;
 insert into activity_programs(org_id,title,description,category,kind,place_name,lat,lng,starts_at,ends_at,deadline,capacity,fee,transports,participation,difficulty)
 values((data->>'org_id')::uuid,data->>'title',data->>'description',data->>'category',data->>'kind',data->>'place_name',(data->>'lat')::float8,(data->>'lng')::float8,
 (data->>'starts_at')::timestamptz,(data->>'ends_at')::timestamptz,(data->>'deadline')::timestamptz,(data->>'capacity')::int,(data->>'fee')::int,
 array(select jsonb_array_elements_text(data->'transports')),data->>'participation',(data->>'difficulty')::int) returning id into result;
 return result;
end $$;
create function public.activity_close_program(target_program uuid) returns void language plpgsql security definer set search_path=public as $$
declare u uuid:=activity_require_user(); begin
 update activity_programs set status='closed' where id=target_program and activity_is_member(org_id);
 if not found then raise exception '기관 담당자 권한이 필요해요.'; end if;
end $$;
create function public.activity_agency() returns jsonb language plpgsql stable security definer set search_path=public as $$
declare u uuid:=activity_require_user(); begin return jsonb_build_object(
 'programs',coalesce((select jsonb_agg(activity_program_data(p) order by p.starts_at desc) from activity_programs p where activity_is_member(p.org_id)),'[]'::jsonb),
 'applications',coalesce((select jsonb_agg(to_jsonb(e)||jsonb_build_object('program',activity_program_data(p),'applicant',jsonb_build_object('nickname',(select nickname from profiles where id=e.user_id))) order by e.created_at desc) from activity_enrollments e join activity_programs p on p.id=e.program_id where activity_is_member(p.org_id)),'[]'::jsonb),
 'metrics',(with eligible as (select count(*) n from activity_enrollments e join activity_programs p on p.id=e.program_id where activity_is_member(p.org_id) and p.ends_at<=now() and e.status in('approved','completed')), completed as (select e.user_id,p.category from activity_enrollments e join activity_programs p on p.id=e.program_id where activity_is_member(p.org_id) and e.status='completed')
 select jsonb_build_object('completed',count(*),'participants',count(distinct user_id),'categories',count(distinct category),'eligible',(select n from eligible),'completion_rate',round(100.0*count(*)/nullif((select n from eligible),0),1),'repeat_rate',round(100.0*(select count(*) from(select user_id from completed group by user_id having count(*)>1)x)/nullif(count(distinct user_id),0),1),'repeat_participants',(select count(*) from(select user_id from completed group by user_id having count(*)>1)x)) from completed)); end $$;

-- No public execute on definer functions. Internal helpers are not client RPCs.
do $$ declare f record; begin
 for f in select oid::regprocedure as signature,proname from pg_proc where pronamespace='public'::regnamespace and proname=any(array['activity_is_member','activity_require_user','activity_distance','activity_program_data','activity_candidates','activity_home','activity_plan_week','activity_program_detail','activity_apply','activity_cancel','activity_manage','activity_save_program','activity_close_program','activity_agency']) loop
  execute format('revoke all on function %s from public, anon, authenticated',f.signature);
  if f.proname in('activity_is_member','activity_home','activity_plan_week','activity_program_detail','activity_apply','activity_cancel','activity_manage','activity_save_program','activity_close_program','activity_agency') then
   execute format('grant execute on function %s to authenticated',f.signature);
  end if;
 end loop;
end $$;
commit;
