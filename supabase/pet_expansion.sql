-- Pet expansion. Apply after pet_companion.sql. Additive, preserves dog, wallets, history.
begin;
alter table public.pet_companions add column if not exists species text not null default 'dog' check(species in ('dog','cat'));
create table if not exists public.pet_item_catalog(
 id text primary key,name text not null,species text not null check(species in('dog','cat')),
 slot text not null check(slot in('body','head','neck','badge')),source text not null check(source in('points','play','activity')),
 price integer not null default 0 check(price>=0),min_stage integer not null default 0 check(min_stage between 0 and 2),
 product_id text unique,enabled boolean not null default true
);
alter table public.pet_item_catalog enable row level security;
revoke all on public.pet_item_catalog from public,anon,authenticated;
grant select on public.pet_item_catalog to authenticated;
drop policy if exists catalog_read on public.pet_item_catalog;
create policy catalog_read on public.pet_item_catalog for select to authenticated using(true);
insert into public.pet_item_catalog(id,name,species,slot,source,price,min_stage,product_id) values
('hat','털모자','dog','head','points',150,0,null),
('knit','줄무늬 니트','dog','body','points',250,0,null),
('winter','겨울 니트','dog','body','points',300,1,null),
('flower','꽃핀','dog','head','points',100,0,null),
('dog_walk_vest','동네 산책 조끼','dog','body','points',150,0,null),
('dog_flower_cardigan','꽃무늬 가디건','dog','body','points',180,0,null),
('dog_raincoat','노란 우비','dog','body','points',200,1,null),
('dog_winter_coat','겨울 누빔 코트','dog','body','play',0,0,'silverlife.dog_winter_coat'),
('dog_outing_overall','나들이 멜빵옷','dog','body','play',0,0,'silverlife.dog_outing_overall'),
('dog_walk_hat','산책 챙모자','dog','head','points',100,1,null),
('dog_flower_pin','꽃 장식','dog','head','points',80,0,null),
('dog_ribbon','체크 리본','dog','neck','points',100,0,null),
('dog_first_walk_badge','첫 산책 배지','dog','badge','activity',0,0,null),
('dog_outing_scarf','나들이 스카프','dog','neck','play',0,0,'silverlife.dog_outing_scarf'),
('cat_walk_vest','고양이 산책 조끼','cat','body','points',150,0,null),
('cat_stripe_knit','줄무늬 니트','cat','body','points',150,0,null),
('cat_raincoat','연두 우비','cat','body','points',200,1,null),
('cat_flower_cardigan','꽃 가디건','cat','body','play',0,0,'silverlife.cat_flower_cardigan'),
('cat_outing_overall','나들이 멜빵옷','cat','body','play',0,0,'silverlife.cat_outing_overall'),
('cat_beret','귀가 보이는 베레모','cat','head','points',100,1,null),
('cat_flower_pin','작은 꽃핀','cat','head','points',80,0,null),
('cat_ribbon','체크 리본','cat','neck','points',100,0,null),
('cat_first_walk_badge','첫 산책 배지','cat','badge','activity',0,0,null),
('cat_moon_scarf','달무늬 스카프','cat','neck','play',0,0,'silverlife.cat_moon_scarf')
on conflict(id) do nothing;
alter table public.pet_inventory drop constraint if exists pet_inventory_item_check;
do $$begin
 if not exists(select 1 from pg_constraint where conname='pet_inventory_catalog_fk') then
 alter table public.pet_inventory add constraint pet_inventory_catalog_fk foreign key(item) references public.pet_item_catalog(id);
 end if;
end $$;
-- Preserve history while allowing more than one walk per day. Only one active
-- session is allowed; points/EXP remain capped by pet_daily.walked.
alter table public.pet_walks drop constraint if exists pet_walks_user_id_day_key;
update public.pet_walks set finished=true where not finished and day<public.attendance_today();
create unique index if not exists pet_walks_one_active on public.pet_walks(user_id) where not finished;
create or replace function public.pet_state_for(u uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
 'expansion',true,
 'ads_enabled',exists(select 1 from public.pet_config where key='admob_unit' and value<>'' and value not like 'ca-app-pub-3940256099942544/%'),
 'store_enabled',exists(select 1 from public.pet_config where key='play_enabled' and value='true'),
 'pet',(select to_jsonb(p)-'user_id' from public.pet_companions p where user_id=u),
 'today',public.attendance_today(),'balance',coalesce((select balance from public.point_wallets where user_id=u),0),
 'daily',coalesce((select to_jsonb(d)-'user_id'-'day' from public.pet_daily d where user_id=u and day=public.attendance_today()),'{}'::jsonb),
 'attended',exists(select 1 from public.attendance_days where user_id=u and attended_on=public.attendance_today()),
 'owned',coalesce((select jsonb_agg(item order by item) from public.pet_inventory where user_id=u),'[]'::jsonb),
 'worn',coalesce((select jsonb_agg(item order by item) from public.pet_inventory where user_id=u and worn),'[]'::jsonb),
 'snacks',coalesce((select jsonb_agg(jsonb_build_object('item',item,'quantity',quantity)) from public.pet_snacks where user_id=u),'[]'::jsonb),
 'history',coalesce((select jsonb_agg(to_jsonb(h)-'user_id' order by h.created_at desc,h.id desc) from public.pet_history h where user_id=u),'[]'::jsonb),
 'programs',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'program_id',p.id,'title',p.title,'place_name',p.place_name,'status',e.status,
 'rewarded',exists(select 1 from public.pet_history h where h.user_id=u and reference='program:'||e.id)) order by e.created_at desc)
 from public.activity_enrollments e join public.activity_programs p on p.id=e.program_id where e.user_id=u and e.status in('applied','approved','completed')),'[]'::jsonb),
 'missions',public.pet_missions_for(u),
 'pending_ad',(select id from public.pet_ad_sessions where user_id=u and day=public.attendance_today() and verified_at is not null and not consumed order by created_at limit 1),
 'walk',(select to_jsonb(w)-'user_id'||jsonb_build_object('facility_name',(select name from public.facilities f where f.id=w.facility_id)) from public.pet_walks w where user_id=u and day=public.attendance_today() and not finished)
 );
$$;
create or replace function public.pet_action(p_action text,p_payload jsonb,p_request uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid();d date:=public.attendance_today();pet public.pet_companions;daily public.pet_daily;
 cached public.pet_requests;walk public.pet_walks;ad public.pet_ad_sessions;
 v_item text:=p_payload->>'item';v_name text;delta integer:=0;xp integer:=0;fill integer:=0;
 price integer:=0;title text;kind text;ref text;result jsonb:='{}';attendance jsonb;
 m jsonb;mi integer;all_m jsonb;enrollment uuid;program_title text;
 n integer;latitude double precision;longitude double precision;accuracy double precision;seen timestamptz;facility uuid;
 old_balance integer;unit text; catalog public.pet_item_catalog;
begin
 if u is null then raise exception 'login required' using errcode='42501';end if;
 if p_request is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception '잘못된 요청이에요.';end if;
 -- 기존 출석 함수와 같은 잠금 순서(지갑 → 반려동물)로 동시 지급·구매를 직렬화.
 insert into public.point_wallets(user_id) values(u) on conflict do nothing;
 select balance into old_balance from public.point_wallets where user_id=u for update;
 select * into cached from public.pet_requests where user_id=u and request=p_request;
 if found then
  if cached.action<>p_action or cached.payload<>p_payload then raise exception '요청 번호가 다른 작업에 사용됐어요.';end if;
  return jsonb_build_object('state',public.pet_state_for(u),'outcome',cached.outcome);
 end if;
 select * into pet from public.pet_companions where user_id=u for update;
 if p_action='adopt' then
  if pet.user_id is not null then raise exception '이미 함께하는 반려동물이 있어요.';end if;
  v_name:=btrim(p_payload->>'name');
  if v_name is null or char_length(v_name) not between 1 and 6 then raise exception '이름은 1~6자로 지어주세요.';end if;
  if coalesce(p_payload->>'species','dog') not in ('dog','cat') then raise exception '반려동물 종류를 확인해주세요.';end if;
  if v_name !~ '^[가-힣a-zA-Z0-9 ]+$' then raise exception '이름에는 한글·영문·숫자만 사용할 수 있어요.';end if;
  insert into public.pet_companions(user_id,name,species) values(u,v_name,coalesce(p_payload->>'species','dog'));
  insert into public.pet_snacks values(u,'sweet',2);
  title:=v_name||'를 입양했어요';kind:='adopt';ref:='adopt';
 else
  if pet.user_id is null then raise exception '반려동물을 먼저 입양해주세요.';end if;
  insert into public.pet_daily(user_id,day) values(u,d) on conflict do nothing;
  select * into daily from public.pet_daily where user_id=u and day=d for update;
  case p_action
  when 'rename' then
   v_name:=btrim(p_payload->>'name');if v_name is null or char_length(v_name) not between 1 and 6 then raise exception '이름은 1~6자로 지어주세요.';end if;
   update public.pet_companions set name=v_name where user_id=u;
  when 'feed' then
   case v_item
   when 'food' then
    if daily.free_feeds>=3 then raise exception '오늘의 무료 사료를 모두 먹었어요.';end if;
    update public.pet_daily set free_feeds=free_feeds+1 where user_id=u and day=d;fill:=1;title:='기본 사료를 먹었어요';
   when 'sweet' then
    update public.pet_snacks set quantity=quantity-1 where user_id=u and pet_snacks.item='sweet' and quantity>0;
    if not found then raise exception '보유한 고구마 간식이 없어요.';end if;
    fill:=2;xp:=5;title:='고구마 간식을 먹었어요';
   when 'gum' then delta:=-50;fill:=1;xp:=10;title:='우유 껌을 먹었어요';
   when 'cake' then delta:=-120;fill:=3;xp:=20;title:='특별 케이크를 먹었어요';
   else raise exception '알 수 없는 간식이에요.';end case;
   if pet.species='cat' then title:=case v_item when 'food' then '기본 사료를 먹었어요' when 'sweet' then '촉촉 참치를 먹었어요' when 'gum' then '연어 트릿을 먹었어요' else '닭고기 수프를 먹었어요' end;end if;
   kind:='feed';
  when 'buy' then
   select * into catalog from public.pet_item_catalog where id=v_item and enabled;
   if not found or catalog.source<>'points' then raise exception '아이템 획득 방법을 확인해주세요.';end if;
   if p_payload ? 'expected_price' and (p_payload->>'expected_price')::integer<>catalog.price then raise exception '가격이 바뀌었어요. 상품을 다시 확인해주세요.';end if;
   if catalog.species<>pet.species then raise exception '다른 동물 전용 아이템이에요.';end if;
   if pet.stage<catalog.min_stage then raise exception '성장기가 되면 열려요.';end if;
   if exists(select 1 from public.pet_inventory where user_id=u and item=v_item) then result:='{"already":true}';
   else
    insert into public.pet_inventory(user_id,item) values(u,v_item);delta:=-catalog.price;kind:='purchase';title:=catalog.name||'를 샀어요';
   end if;
  when 'wear' then
   if jsonb_typeof(p_payload->'items')<>'array' or p_payload->'items' is null then raise exception '옷을 선택해주세요.';end if;
   if exists(select 1 from jsonb_array_elements_text(p_payload->'items') v left join public.pet_item_catalog c on c.id=v
    where c.id is null or c.species<>pet.species or c.min_stage>pet.stage or not exists(select 1 from public.pet_inventory i where i.user_id=u and i.item=v)) then raise exception '보유한 호환 아이템만 입힐 수 있어요.';end if;
   if exists(select 1 from jsonb_array_elements_text(p_payload->'items') v join public.pet_item_catalog c on c.id=v group by c.slot having count(*)>1) then raise exception '같은 위치에는 하나만 입힐 수 있어요.';end if;
   update public.pet_inventory i set worn=(p_payload->'items' ? i.item) where i.user_id=u;
   title:='꾸미기를 바꿨어요';kind:='outfit';
  when 'attendance' then
   attendance:=public.attendance_check_in_for(u,d);
   ref:='attendance:'||d;
   if not exists(select 1 from public.pet_history h where h.user_id=u and h.reference=ref) then
    xp:=10;title:='오늘 출석했어요';kind:='attendance';
    result:=jsonb_build_object('points',case when (attendance->>'already')::boolean then 0 else (attendance->>'points')::int end);
   else result:='{"already":true}';end if;
  when 'program_reward' then
   enrollment:=(p_payload->>'id')::uuid;
   select p.title into program_title from public.activity_enrollments e join public.activity_programs p on p.id=e.program_id
    where e.id=enrollment and e.user_id=u and e.status='completed';
   if not found then raise exception '기관의 참여 완료 확인이 필요해요.';end if;
   ref:='program:'||enrollment;kind:='program';title:=program_title||' 참여 확인';delta:=200;xp:=50;
  when 'mission_reward' then
   mi:=(p_payload->>'stage')::int;all_m:=public.pet_missions_for(u);
   select value into m from jsonb_array_elements(all_m) where (value->>'stage')::int=mi;
   if m is null or not (m->>'completed')::boolean then raise exception '미션을 먼저 완료해주세요.';end if;
   if mi>1 and exists(select 1 from jsonb_array_elements(all_m) a where (a->>'stage')::int<mi and not (a->>'claimed')::boolean) then raise exception '앞 단계 보상부터 받아주세요.';end if;
   ref:='mission:'||date_trunc('week',d::timestamp)::date||':'||mi;kind:='mission';title:='주간 미션 '||mi||'단계를 완료했어요';
   if mi=2 then delta:=100;else xp:=case mi when 1 then 10 else 30 end;end if;
  when 'grow' then
   if pet.stage>=2 or pet.experience<(case pet.stage when 0 then 200 else 500 end) then raise exception '성장 경험치를 조금 더 모아주세요.';end if;
   update public.pet_companions set stage=stage+1,stage_dates=stage_dates||jsonb_build_object((stage+1)::text,now()) where user_id=u;
   title:=case pet.stage when 0 then '성장기가 되었어요' else '성체가 되었어요' end;kind:='growth';ref:='growth:'||(pet.stage+1);
  when 'walk_start' then
   select * into walk from public.pet_walks where user_id=u and day=d and not finished;
   if not found then
    insert into public.pet_walks(user_id,day) values(u,d) returning * into walk;
   end if;
   result:=jsonb_build_object('session',walk.id);
  when 'walk_cancel' then
   update public.pet_walks set finished=true,arrived_at=null where user_id=u and id=(p_payload->>'id')::uuid;
  when 'walk_sync' then
   select * into walk from public.pet_walks where user_id=u and id=(p_payload->>'id')::uuid and day=d and not finished for update;
   if not found then raise exception '진행 중인 산책을 확인해주세요.';end if;
   n:=greatest(0,coalesce((p_payload->>'steps')::int,0));
   if n>200000 or n>extract(epoch from now()-walk.started_at)*4+20 then raise exception '걸음 수를 다시 확인해주세요.';end if;
   update public.pet_walks set steps=greatest(steps,n),eligible=eligible or n>=2000 where id=walk.id;
   latitude:=(p_payload->>'lat')::double precision;longitude:=(p_payload->>'lng')::double precision;accuracy:=(p_payload->>'accuracy')::double precision;
   seen:=to_timestamp((p_payload->>'location_at')::double precision/1000);
   if latitude between -90 and 90 and longitude between -180 and 180 and accuracy between 0 and 60 and seen between now()-interval '90 seconds' and now()+interval '5 seconds' then
    select f.id into facility from public.facilities f where public.activity_distance(latitude,longitude,f.lat,f.lng)<=0.1 order by public.activity_distance(latitude,longitude,f.lat,f.lng) limit 1;
    if facility is not null then
     update public.pet_walks set facility_id=facility,
      arrived_at=case when facility_id=facility and last_seen_at>=now()-interval '45 seconds' then coalesce(arrived_at,now()) else now() end,
      last_seen_at=now(),eligible=eligible or (facility_id=facility and arrived_at<=now()-interval '2 minutes' and last_seen_at>=now()-interval '45 seconds') where id=walk.id;
    else update public.pet_walks set arrived_at=null,last_seen_at=now(),facility_id=null where id=walk.id;end if;
   end if;
  when 'walk_reward' then
   if daily.walked then
    update public.pet_walks set finished=true where user_id=u and id=(p_payload->>'id')::uuid;
    result:='{"already":true}';else
    select * into walk from public.pet_walks where user_id=u and day=d and id=(p_payload->>'id')::uuid and eligible and not finished;
    if not found then raise exception '산책 완료 조건을 먼저 채워주세요.';end if;
    update public.pet_daily set walked=true where user_id=u and day=d;
    update public.pet_walks set finished=true where id=walk.id;
    insert into public.pet_inventory(user_id,item) values(u,pet.species||'_first_walk_badge') on conflict do nothing;
    ref:='walk:'||d;kind:='walk';title:=walk.steps||'걸음 산책';delta:=30;xp:=10;
   end if;
  when 'ad_session' then
   select value into unit from public.pet_config where key='admob_unit';
   if coalesce(unit,'')='' then raise exception '광고 계정을 연결하고 있어요. 잠시 후 다시 확인해주세요.';end if;
   if daily.ads>=2 then raise exception '오늘 광고 보상을 모두 받았어요.';end if;
   insert into public.pet_ad_sessions(user_id,day) values(u,d) returning * into ad;result:=jsonb_build_object('session',ad.id);
  when 'ad_claim' then
   select * into ad from public.pet_ad_sessions where user_id=u and id=(p_payload->>'session')::uuid and day=d for update;
   if not found or ad.verified_at is null then raise exception '광고 보상을 확인 중이에요. 잠시 후 다시 확인해주세요.';end if;
   if ad.consumed then result:='{"already":true}';else
    if daily.ads>=2 then raise exception '오늘 광고 보상을 모두 받았어요.';end if;
    update public.pet_daily set ads=ads+1 where user_id=u and day=d;
    update public.pet_ad_sessions set consumed=true where id=ad.id;
    ref:='ad:'||ad.id;kind:='ad';title:='광고 보상을 받았어요';delta:=20;
   end if;
  else raise exception '지원하지 않는 작업이에요.';end case;
 end if;
 if ref is not null and exists(select 1 from public.pet_history h where h.user_id=u and h.reference=ref) then
  delta:=0;xp:=0;title:=null;kind:=null;result:='{"already":true}';
 end if;
 if old_balance+delta<0 then raise exception '포인트가 부족해요. 오늘의 활동에서 모아보세요.';end if;
 if delta<>0 then
  update public.point_wallets set balance=balance+delta,total_earned=total_earned+greatest(delta,0),updated_at=now() where user_id=u;
  insert into public.point_ledger(user_id,amount,reason) values(u,delta,'pet');
 end if;
 update public.pet_companions set experience=experience+xp,fullness=least(5,fullness+fill) where user_id=u;
 if title is not null then
  insert into public.pet_history(user_id,reference,title,kind,points,experience) values(u,coalesce(ref,p_action||':'||p_request),title,kind,case when p_action='attendance' then coalesce((result->>'points')::int,0) else delta end,xp);
 end if;
 result:=jsonb_build_object('points',delta,'experience',xp,'already',false)||result;
 insert into public.pet_requests(user_id,request,action,payload,outcome) values(u,p_request,p_action,p_payload,result);
 return jsonb_build_object('state',public.pet_state_for(u),'outcome',result);
end $$;

revoke all on function public.pet_state_for(uuid),public.pet_action(text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.pet_action(text,jsonb,uuid) to authenticated;
commit;
