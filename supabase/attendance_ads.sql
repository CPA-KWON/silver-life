-- PREPARED ONLY: apply after AdMob ownership, consent and signed callback setup.
-- Empty unit keeps production disabled. Existing attendance/pet records stay intact.
begin;
create table if not exists public.attendance_ad_config (
 id boolean primary key default true check(id), unit text not null default ''
);
alter table public.attendance_ad_config enable row level security;
revoke all on public.attendance_ad_config from public,anon,authenticated;
insert into public.attendance_ad_config(id) values(true) on conflict do nothing;
create table if not exists public.attendance_ad_sessions (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users on delete cascade,
 day date not null, points integer not null check(points=20),
 created_at timestamptz not null default now(), verified_at timestamptz,
 transaction_id text unique, consumed boolean not null default false
);
alter table public.attendance_ad_sessions enable row level security;
revoke all on public.attendance_ad_sessions from public,anon,authenticated;
-- Sessions and configuration are only accessible through bounded RPCs.
-- Shared quota: entering from pet care must not create a second daily allowance.
create or replace function public.attendance_ad_used_today(u uuid) returns integer
language sql stable security definer set search_path='' as $$
 select (select count(*)::integer from public.attendance_ad_sessions where user_id=u and day=public.attendance_today() and consumed)
 +coalesce((select ads from public.pet_daily where user_id=u and day=public.attendance_today()),0);
$$;
revoke all on function public.attendance_ad_used_today(uuid) from public,anon,authenticated;
create or replace function public.attendance_ad_status() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid(); d date:=public.attendance_today(); n integer; s integer; unit text;
begin
 if u is null then raise exception '로그인이 필요해요.'; end if;
 select streak into s from public.attendance_days where user_id=u and attended_on=d;
 n:=public.attendance_ad_used_today(u);
 select c.unit into unit from public.attendance_ad_config c where id;
 return jsonb_build_object('points',20,
   'remaining',greatest(0,2-n),'enabled',s is not null and coalesce(unit,'')<>'');
end $$;
create or replace function public.attendance_ad_start() returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); d date:=public.attendance_today(); offer jsonb; session uuid;
begin
 if u is null then raise exception '로그인이 필요해요.'; end if;
 perform 1 from public.point_wallets where user_id=u for update;
 offer:=public.attendance_ad_status();
 if not (offer->>'enabled')::boolean or (offer->>'remaining')::integer<=0 then raise exception '오늘 출석과 광고 설정을 확인해 주세요.'; end if;
 -- Reuse an unfinished, short-lived session; repeated taps cannot fill the table.
 select id into session from public.attendance_ad_sessions where user_id=u and day=d and not consumed and created_at>now()-interval '30 minutes' order by created_at desc limit 1;
 if session is null then insert into public.attendance_ad_sessions(user_id,day,points) values(u,d,(offer->>'points')::integer) returning id into session; end if;
 return jsonb_build_object('session',session);
end $$;
create or replace function public.attendance_verify_ad(p_session uuid,p_transaction text,p_unit text) returns void
language plpgsql security definer set search_path='' as $$
declare expected text; s public.attendance_ad_sessions;
begin
 select unit into expected from public.attendance_ad_config where id;
 if coalesce(expected,'')='' or p_unit is distinct from expected or nullif(p_transaction,'') is null then raise exception 'invalid unit'; end if;
 select * into s from public.attendance_ad_sessions where id=p_session for update;
 if not found or s.day<>public.attendance_today() or s.created_at<now()-interval '30 minutes' then raise exception 'expired'; end if;
 if s.transaction_id is not null then
   if s.transaction_id=p_transaction then return; end if;
   raise exception 'conflicting transaction';
 end if;
 update public.attendance_ad_sessions set verified_at=now(),transaction_id=p_transaction where id=s.id;
end $$;
create or replace function public.attendance_ad_claim(p_session uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); d date:=public.attendance_today(); s public.attendance_ad_sessions; n integer;
begin
 if u is null then raise exception '로그인이 필요해요.'; end if;
 -- Same wallet lock as attendance and pet spending, then session lock.
 perform 1 from public.point_wallets where user_id=u for update;
 select * into s from public.attendance_ad_sessions where id=p_session and user_id=u and day=d for update;
 if not found then raise exception 'invalid session'; end if;
 if s.consumed then return jsonb_build_object('granted',true,'already',true,'points',s.points); end if;
 if s.verified_at is null then return jsonb_build_object('granted',false); end if;
 n:=public.attendance_ad_used_today(u);
 if n>=2 then raise exception '오늘 광고 보상을 모두 받았어요.'; end if;
 if not exists(select 1 from public.attendance_days where user_id=u and attended_on=d) then raise exception '출석이 필요해요.'; end if;
 update public.attendance_ad_sessions set consumed=true where id=s.id;
 update public.point_wallets set balance=balance+s.points,total_earned=total_earned+s.points,updated_at=now() where user_id=u;
 -- Null ref_date allows multiple ad rows; session consumption is the unique key.
 insert into public.point_ledger(user_id,amount,reason) values(u,s.points,'attendance');
 return jsonb_build_object('granted',true,'already',false,'points',s.points);
end $$;
revoke all on function public.attendance_ad_status(),public.attendance_ad_start(),public.attendance_ad_claim(uuid),public.attendance_verify_ad(uuid,text,text) from public,anon,authenticated;
grant execute on function public.attendance_ad_status(),public.attendance_ad_start(),public.attendance_ad_claim(uuid) to authenticated;
grant execute on function public.attendance_verify_ad(uuid,text,text) to service_role;
-- Preserve the current pet function while applying the reciprocal shared cap.
do $$ declare source text; updated text; begin
 select pg_get_functiondef(p.oid) into source from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='pet_action' and p.pronargs=3;
 if source is not null then
   updated:=replace(source,'if daily.ads>=2 then','if public.attendance_ad_used_today(u)>=2 then');
   if updated<>source then execute updated; end if;
 end if;
end $$;
commit;
