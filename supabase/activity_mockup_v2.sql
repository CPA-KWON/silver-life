-- Activity mockup v2: additive, repeatable. Apply after existing activity/pet SQL.
-- Keeps existing activities, enrollment records, grants and RLS policies.
begin;
alter table public.activity_programs add column if not exists target_audience text not null default '';
alter table public.activity_programs add column if not exists preparations text not null default '';
alter table public.activity_programs add column if not exists floor_guide text not null default '';
alter table public.activity_enrollments add column if not exists application_note text not null default '';
alter table public.activity_enrollments add column if not exists rejection_reason text not null default '';
create table if not exists public.activity_program_favorites (
 user_id uuid not null references auth.users on delete cascade,
 program_id uuid not null references public.activity_programs on delete cascade,
 primary key(user_id,program_id)
);
alter table public.activity_program_favorites enable row level security;
revoke all on public.activity_program_favorites from anon,authenticated;
grant select,insert,delete on public.activity_program_favorites to authenticated;
do $$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='activity_program_favorites' and policyname='own_program_favorites') then
  create policy own_program_favorites on public.activity_program_favorites for all to authenticated
   using(user_id=auth.uid()) with check(user_id=auth.uid() and exists(select 1 from public.activity_programs p join public.activity_organizations o on o.id=p.org_id where p.id=program_id and o.approved));
 end if;
end $$;
create or replace function public.activity_apply_with_note(target_program uuid,target_experience uuid,application_note text default '')
 returns uuid language plpgsql security definer set search_path='' as $$
declare u uuid:=public.activity_require_user(); result uuid;
begin
 if char_length(coalesce(application_note,''))>200 then raise exception '전달할 말은 200자까지 적어 주세요.';end if;
 -- Original RPC validates ownership/category/availability, locks capacity and snapshots experience.
 result:=public.activity_apply(target_program,target_experience);
 update public.activity_enrollments set application_note=coalesce(activity_apply_with_note.application_note,''),rejection_reason=''
  where id=result and user_id=u;
 return result;
end $$;
create or replace function public.activity_save_program_v2(data jsonb) returns uuid
 language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if greatest(char_length(coalesce(data->>'target_audience','')),char_length(coalesce(data->>'preparations','')),char_length(coalesce(data->>'floor_guide','')))>2000 then raise exception '안내는 항목당 2000자까지 적어 주세요.';end if;
 result:=public.activity_save_program(data);
 update public.activity_programs set target_audience=coalesce(data->>'target_audience',''),preparations=coalesce(data->>'preparations',''),floor_guide=coalesce(data->>'floor_guide','') where id=result;
 return result;
end $$;
create or replace function public.activity_reject_with_reason(enrollment uuid,reason text) returns void
 language plpgsql security definer set search_path='' as $$
begin
 if char_length(trim(coalesce(reason,''))) not between 1 and 300 then raise exception '반려 사유를 1~300자로 적어 주세요.';end if;
 perform public.activity_manage(enrollment,'rejected');
 update public.activity_enrollments set rejection_reason=trim(reason) where id=enrollment;
end $$;
-- A replacement must satisfy the same radius, interest, chronological and stage rules as the original planner.
create or replace function public.activity_mission_choices(target_stage integer) returns jsonb
 language plpgsql stable security definer set search_path=public as $$
declare u uuid:=activity_require_user();w date:=date_trunc('week',now() at time zone 'Asia/Seoul')::date;
 pref activity_preferences; prev activity_programs; later activity_programs; result jsonb;
begin
 if target_stage not between 1 and 3 then raise exception '미션 단계를 확인해 주세요.';end if;
 select * into pref from activity_preferences where user_id=u;
 if not found then raise exception '추천 조건을 먼저 저장해 주세요.';end if;
 if exists(select 1 from activity_missions m join activity_enrollments e on e.program_id=m.program_id and e.user_id=u where m.user_id=u and m.week_start=w and m.stage=target_stage and e.status in('applied','approved','completed')) then raise exception '신청한 미션은 바꿀 수 없어요.';end if;
 if not exists(select 1 from activity_missions m where m.user_id=u and m.week_start=w and m.stage=target_stage) then raise exception '현재 주의 미션을 먼저 만들어 주세요.';end if;
 select a.* into prev from activity_missions m join activity_programs a on a.id=m.program_id where m.user_id=u and m.week_start=w and m.stage<target_stage order by m.stage desc limit 1;
 select a.* into later from activity_missions m join activity_programs a on a.id=m.program_id where m.user_id=u and m.week_start=w and m.stage>target_stage order by m.stage limit 1;
 select coalesce(jsonb_agg(activity_program_data(c)),'[]'::jsonb) into result from activity_candidates() c
 where (c.starts_at at time zone 'Asia/Seoul')::date>=w and (c.starts_at at time zone 'Asia/Seoul')::date<w+7
  and (prev.id is null or c.starts_at>=prev.ends_at) and (later.id is null or c.ends_at<=later.starts_at)
  and (target_stage<>1 or (c.difficulty=1 and extract(epoch from(c.ends_at-c.starts_at))/60<=60 and activity_distance(pref.lat,pref.lng,c.lat,c.lng)<=least(pref.radius_km,1)))
  and (target_stage<>2 or (prev.id is not null and activity_distance(c.lat,c.lng,prev.lat,prev.lng)>0.1 and not exists(select 1 from activity_enrollments e join activity_programs p on p.id=e.program_id where e.user_id=u and e.status='completed' and activity_distance(c.lat,c.lng,p.lat,p.lng)<=0.1)))
  and (target_stage<>3 or c.participation='함께')
  and not exists(select 1 from activity_missions m where m.user_id=u and m.week_start=w and m.program_id=c.id);
 return result;
end $$;
create or replace function public.activity_replace_mission(target_stage integer,target_program uuid) returns void
 language plpgsql security definer set search_path=public as $$
declare u uuid:=activity_require_user();w date:=date_trunc('week',now() at time zone 'Asia/Seoul')::date; current_program uuid;
begin
 perform 1 from activity_preferences where user_id=u for update;
 select m.program_id into current_program from activity_missions m where m.user_id=u and m.week_start=w and m.stage=target_stage;
 -- Serialize against enrollment changes in either program, in deterministic order.
 perform 1 from activity_programs p where p.id in(current_program,target_program) order by p.id for update;
 if not exists(select 1 from jsonb_array_elements(activity_mission_choices(target_stage)) c where c->>'id'=target_program::text) then raise exception '현재 조건에 맞는 다른 프로그램을 골라 주세요.';end if;
 update activity_missions m set program_id=target_program where m.user_id=u and m.week_start=w and m.stage=target_stage;
 if not found then raise exception '이번 주 미션을 먼저 만들어 주세요.';end if;
end $$;
revoke all on function public.activity_apply_with_note(uuid,uuid,text),public.activity_save_program_v2(jsonb),public.activity_reject_with_reason(uuid,text),public.activity_mission_choices(integer),public.activity_replace_mission(integer,uuid) from public,anon,authenticated;
grant execute on function public.activity_apply_with_note(uuid,uuid,text),public.activity_save_program_v2(jsonb),public.activity_reject_with_reason(uuid,text),public.activity_mission_choices(integer),public.activity_replace_mission(integer,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
