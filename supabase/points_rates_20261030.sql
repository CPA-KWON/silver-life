-- Existing wallet balances and completed attendance records are preserved.
-- Existing accounting unit = 100 P in the app. Future normal attendance = 500P.
begin;
create or replace function public.attendance_points_for(streak integer)
returns integer language sql immutable set search_path='' as $$
 select case streak when 30 then 50 when 14 then 25 when 7 then 15 else 5 end;
$$;
-- Patch only the ad award in the latest deployed pet_action definition so newer
-- safe-walk/repeat-walk fixes are not overwritten with an older full function.
do $$ declare source text; updated text; begin
 select pg_get_functiondef(p.oid) into source from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='pet_action' and p.pronargs=3;
 if source is null then raise exception 'pet_action is missing'; end if;
 updated:=replace(source,'title:=''광고 보상을 받았어요'';delta:=30;', 'title:=''광고 보상을 받았어요'';delta:=20;');
 if updated=source and position('title:=''광고 보상을 받았어요'';delta:=20;' in source)=0 then
   raise exception 'Unknown ad reward definition; no change applied';
 end if;
 if updated<>source then execute updated; end if;
end $$;
commit;
-- Read-only confirmation: normal/7/14/30 = 5/15/25/50 internal units.
select public.attendance_points_for(1) normal,public.attendance_points_for(7) day7,
 public.attendance_points_for(14) day14,public.attendance_points_for(30) day30;
