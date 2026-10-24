-- 콩이 실제 저장·보상. attendance_points.sql 및 activity_expansion.sql 적용 후 실행.
-- 기존 활동/출석 RLS는 변경하지 않습니다. 새 표는 본인 읽기만, 쓰기는 RPC만 허용.
begin;
create table if not exists public.pet_companions (
 user_id uuid primary key references auth.users on delete cascade,
 name text not null check(char_length(btrim(name)) between 1 and 6),
 stage integer not null default 0 check(stage between 0 and 2),
 experience integer not null default 0 check(experience>=0),
 fullness integer not null default 2 check(fullness between 0 and 5),
 adopted_at timestamptz not null default now(),
 stage_dates jsonb not null default jsonb_build_object('0',now())
);
create table if not exists public.pet_daily (
 user_id uuid not null references auth.users on delete cascade, day date not null,
 free_feeds integer not null default 0 check(free_feeds between 0 and 3),
 ads integer not null default 0 check(ads between 0 and 2),walked boolean not null default false,
 primary key(user_id,day)
);
create table if not exists public.pet_inventory (
 user_id uuid not null references auth.users on delete cascade,item text not null check(item in('hat','knit','winter','flower')),
 worn boolean not null default false, primary key(user_id,item)
);
create table if not exists public.pet_snacks (
 user_id uuid not null references auth.users on delete cascade,item text not null check(item='sweet'),quantity integer not null check(quantity>=0),primary key(user_id,item)
);
create table if not exists public.pet_history (
 id bigint generated always as identity primary key,user_id uuid not null references auth.users on delete cascade,
 reference text not null,title text not null,kind text not null,points integer not null default 0,experience integer not null default 0,
 created_at timestamptz not null default now(),unique(user_id,reference)
);
create index if not exists pet_history_user_date on public.pet_history(user_id,created_at desc);
create table if not exists public.pet_requests (
 user_id uuid not null references auth.users on delete cascade,request uuid not null,action text not null,payload jsonb not null,
 outcome jsonb not null,created_at timestamptz not null default now(),primary key(user_id,request)
);
create table if not exists public.pet_walks (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users on delete cascade,
 day date not null,started_at timestamptz not null default now(),steps integer not null default 0 check(steps>=0),
 eligible boolean not null default false,finished boolean not null default false,
 facility_id uuid references public.facilities on delete set null,arrived_at timestamptz,last_seen_at timestamptz,
 unique(user_id,day)
);
create table if not exists public.pet_ad_sessions (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users on delete cascade,
 day date not null,created_at timestamptz not null default now(),verified_at timestamptz,
 transaction_id text unique,consumed boolean not null default false
);
-- 관리자만 설정. 실제 광고 단위 ID가 등록되기 전에는 실제 보상형 광고를 열지 않음.
create table if not exists public.pet_config (key text primary key,value text not null);
alter table public.pet_config enable row level security;
revoke all on public.pet_config from public,anon,authenticated;
insert into public.pet_config values('admob_unit','') on conflict do nothing;

do $$ declare t text; begin
 foreach t in array array['pet_companions','pet_daily','pet_inventory','pet_snacks','pet_history','pet_requests','pet_walks','pet_ad_sessions'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 execute format('drop policy if exists own_read on public.%I',t);
 execute format('create policy own_read on public.%I for select to authenticated using(user_id=auth.uid())',t);
 end loop;
end $$;
alter table public.point_ledger drop constraint if exists point_ledger_reason_check;
alter table public.point_ledger add constraint point_ledger_reason_check check(reason in('attendance','pet'));

-- 주간 실적: 한국시간 월요일 시작. 기존 활동 미션을 지우거나 덮어쓰지 않음.
create or replace function public.pet_missions_for(u uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 with week as(select date_trunc('week',now() at time zone 'Asia/Seoul')::date d),
 progress as(
 select 1 stage,least(3,count(*))::int n,3 target from public.attendance_days,week where user_id=u and attended_on>=week.d
 union all select 2,least(1,count(*))::int,1 from public.activity_enrollments e join public.activity_programs p on p.id=e.program_id cross join week where e.user_id=u and e.status='completed' and p.participation='함께' and (e.completed_at at time zone 'Asia/Seoul')::date>=week.d
 union all select 3,least(1,count(*))::int,1 from public.activity_enrollments e cross join week where e.user_id=u and e.status='completed' and (e.completed_at at time zone 'Asia/Seoul')::date>=week.d)
 select jsonb_agg(jsonb_build_object('stage',stage,'progress',n,'target',target,'completed',n>=target,
 'claimed',exists(select 1 from public.pet_history h,week where h.user_id=u and h.reference='mission:'||week.d||':'||stage)) order by stage) from progress;
$$;
create or replace function public.pet_state_for(u uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
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
create or replace function public.pet_state() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'login required' using errcode='42501';end if;
 return public.pet_state_for(auth.uid());
end $$;

create or replace function public.pet_action(p_action text,p_payload jsonb,p_request uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid();d date:=public.attendance_today();pet public.pet_companions;daily public.pet_daily;
 cached public.pet_requests;walk public.pet_walks;ad public.pet_ad_sessions;
 v_item text:=p_payload->>'item';v_name text;delta integer:=0;xp integer:=0;fill integer:=0;
 price integer:=0;title text;kind text;ref text;result jsonb:='{}';attendance jsonb;
 m jsonb;mi integer;all_m jsonb;enrollment uuid;program_title text;
 n integer;latitude double precision;longitude double precision;accuracy double precision;seen timestamptz;facility uuid;
 old_balance integer;unit text;
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
  insert into public.pet_companions(user_id,name) values(u,v_name);
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
   kind:='feed';
  when 'buy' then
   price:=case v_item when 'hat' then 150 when 'knit' then 250 when 'winter' then 300 when 'flower' then 100 else null end;
   if price is null then raise exception '이 아이템은 준비 중이에요.';end if;
   if v_item='winter' and pet.stage<1 then raise exception '성장기가 되면 열려요.';end if;
   if exists(select 1 from public.pet_inventory i where i.user_id=u and i.item=v_item) then result:='{"already":true}';
   else
    insert into public.pet_inventory(user_id,item) values(u,v_item);delta:=-price;kind:='purchase';
    title:=(case v_item when 'hat' then '털모자' when 'knit' then '줄무늬 니트' when 'winter' then '겨울 니트' else '꽃핀' end)||'를 샀어요';
   end if;
  when 'wear' then
   if jsonb_typeof(p_payload->'items')<>'array' or p_payload->'items' is null then raise exception '옷을 선택해주세요.';end if;
   if exists(select 1 from jsonb_array_elements_text(p_payload->'items') v where not exists(select 1 from public.pet_inventory i where i.user_id=u and i.item=v)) then raise exception '보유한 옷만 입힐 수 있어요.';end if;
   if p_payload->'items' ? 'knit' and p_payload->'items' ? 'winter' then raise exception '옷은 한 벌만 입힐 수 있어요.';end if;
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
   if daily.walked then raise exception '오늘 산책 보상은 이미 받았어요.';end if;
   insert into public.pet_walks(user_id,day) values(u,d) on conflict(user_id,day) do update set finished=false;
   select * into walk from public.pet_walks where user_id=u and day=d;result:=jsonb_build_object('session',walk.id);
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
   if daily.walked then result:='{"already":true}';else
    select * into walk from public.pet_walks where user_id=u and day=d and id=(p_payload->>'id')::uuid and eligible and not finished;
    if not found then raise exception '산책 완료 조건을 먼저 채워주세요.';end if;
    update public.pet_daily set walked=true where user_id=u and day=d;
    update public.pet_walks set finished=true where id=walk.id;
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
    ref:='ad:'||ad.id;kind:='ad';title:='광고 보상을 받았어요';delta:=30;
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

-- Edge Function만 호출 가능. Google 서명 검증을 통과한 거래를 한 번만 기록.
create or replace function public.pet_verify_ad(p_session uuid,p_transaction text,p_unit text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.pet_config where key='admob_unit' and (value=p_unit or split_part(value,'/',2)=p_unit) and value<>'' and value not like 'ca-app-pub-3940256099942544/%') then raise exception 'invalid ad unit';end if;
 update public.pet_ad_sessions set verified_at=now(),transaction_id=p_transaction
 where id=p_session and verified_at is null and created_at>=now()-interval '1 hour';
end $$;
revoke all on function public.pet_missions_for(uuid),public.pet_state_for(uuid),public.pet_state(),public.pet_action(text,jsonb,uuid),public.pet_verify_ad(uuid,text,text) from public,anon,authenticated;
grant execute on function public.pet_state(),public.pet_action(text,jsonb,uuid) to authenticated;
grant execute on function public.pet_verify_ad(uuid,text,text) to service_role;
commit;
