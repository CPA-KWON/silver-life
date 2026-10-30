begin;
alter table public.pet_walks drop constraint if exists pet_walks_user_id_day_key;
update public.pet_walks set finished=true where not finished and day<public.attendance_today();
create unique index if not exists pet_walks_one_active on public.pet_walks(user_id) where not finished;
do $patch$
declare definition text;
begin
 definition:=pg_get_functiondef('public.pet_action(text,jsonb,uuid)'::regprocedure);
 definition:=replace(definition,$old$  when 'walk_start' then
   if daily.walked then raise exception '오늘 산책 보상은 이미 받았어요.';end if;
   insert into public.pet_walks(user_id,day) values(u,d) on conflict(user_id,day) do update set finished=false;
   select * into walk from public.pet_walks where user_id=u and day=d;result:=jsonb_build_object('session',walk.id);
$old$,$new$  when 'walk_start' then
   select * into walk from public.pet_walks where user_id=u and day=d and not finished;
   if not found then
    insert into public.pet_walks(user_id,day) values(u,d) returning * into walk;
   end if;
   result:=jsonb_build_object('session',walk.id);
$new$);
 definition:=replace(definition,$old$   if daily.walked then result:='{"already":true}';else$old$,$new$   if daily.walked then
    update public.pet_walks set finished=true where user_id=u and id=(p_payload->>'id')::uuid;
    result:='{"already":true}';else$new$);
 if strpos(definition,'expected_price')=0 then
 definition:=replace(definition,$old$   if catalog.species<>pet.species$old$,$new$   if p_payload ? 'expected_price' and (p_payload->>'expected_price')::integer<>catalog.price then raise exception '가격이 바뀌었어요. 상품을 다시 확인해주세요.';end if;
   if catalog.species<>pet.species$new$);
 end if;
 execute definition;
end $patch$;
commit;
select '산책 여러 번 가능 · 보상 하루 한 번 · 가격 확인 적용' as result;
