-- Program-specific weekly mission rewards. Additive; safe to reapply.
-- Separate from the existing pet weekly mission and enrollment participation rewards.
begin;
create or replace function public.activity_claim_program_mission(target_stage integer) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare u uuid:=public.activity_require_user();
 w date:=date_trunc('week',now() at time zone 'Asia/Seoul')::date;
 ref text;points integer;xp integer;
begin
 if target_stage not between 1 and 3 then raise exception '미션 단계를 확인해 주세요.';end if;
 -- Match pet_action lock ordering: pet, then wallet. This serializes all reward operations.
 perform 1 from public.pet_companions where user_id=u for update;
 if not found then raise exception '콩이를 먼저 입양해 주세요.';end if;
 ref:='program-mission:'||w||':'||target_stage;
 if exists(select 1 from public.pet_history where user_id=u and reference=ref) then
  return jsonb_build_object('already',true,'points',0,'experience',0);
 end if;
 if not exists(select 1 from public.activity_missions m join public.activity_enrollments e on e.user_id=m.user_id and e.program_id=m.program_id
   where m.user_id=u and m.week_start=w and m.stage=target_stage and e.status='completed') then
  raise exception '기관에서 미션 프로그램 참여를 완료로 확인해야 해요.';
 end if;
 points:=case target_stage when 1 then 50 when 2 then 100 else 0 end;
 xp:=case target_stage when 3 then 30 else 0 end;
 insert into public.point_wallets(user_id) values(u) on conflict(user_id) do nothing;
 perform 1 from public.point_wallets where user_id=u for update;
 if points>0 then
  update public.point_wallets set balance=balance+points,total_earned=total_earned+points,updated_at=now() where user_id=u;
  insert into public.point_ledger(user_id,amount,reason) values(u,points,'pet');
 end if;
 update public.pet_companions set experience=experience+xp where user_id=u;
 insert into public.pet_history(user_id,reference,title,kind,points,experience)
  values(u,ref,'프로그램별 주간 미션 '||target_stage||'단계를 완료했어요','program_mission',points,xp);
 return jsonb_build_object('already',false,'points',points,'experience',xp);
end $$;
revoke all on function public.activity_claim_program_mission(integer) from public,anon,authenticated;
grant execute on function public.activity_claim_program_mission(integer) to authenticated;
notify pgrst,'reload schema';
commit;
