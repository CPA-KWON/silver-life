import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {PGlite} = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const db = new PGlite();
const read = name => readFile(new URL('../supabase/'+name, import.meta.url),'utf8');
const u='00000000-0000-4000-8000-000000000001',m='00000000-0000-4000-8000-000000000002',v='00000000-0000-4000-8000-000000000003';
const o='10000000-0000-4000-8000-000000000001';
const ids=Array.from({length:5},(_,i)=>`20000000-0000-4000-8000-00000000000${i+1}`);
const offer='30000000-0000-4000-8000-000000000001';
const query = async(sql,args=[]) => (await db.query(sql,args)).rows;
async function as(user,fn){await db.exec('reset role;set role authenticated');await query("select set_config('request.jwt.claim.sub',$1,false)",[user]);try{return await fn();}finally{await db.exec('reset role');}}
await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;create table public.profiles(id uuid primary key,nickname text);`);
await query('insert into auth.users values($1),($2),($3)',[u,m,v]);
await db.exec(await read('activity_expansion.sql'));
await db.exec(await read('activity_usability_fix.sql'));
await db.exec(await read('activity_mockup_v2.sql'));
await query('insert into activity_organizations values($1,\'복지관\',true)',[o]);
await query('insert into activity_org_members values($1,$2)',[o,m]);
await query("insert into activity_preferences values($1,'동네',37.5,127,3,array['건강·운동'],'도보','무관',120,3,true)",[u]);
for(let i=0;i<5;i++)await query(`insert into activity_programs(id,org_id,title,description,category,kind,place_name,lat,lng,starts_at,ends_at,deadline,capacity,fee,transports,participation,difficulty) values($1,$2,$3,'실제 안내','건강·운동',$4,'복지관',37.5+$5::float8,127,(date_trunc('week',now() at time zone 'Asia/Seoul')+interval '5 days 10 hours'+$6::int*interval '2 hour') at time zone 'Asia/Seoul',(date_trunc('week',now() at time zone 'Asia/Seoul')+interval '5 days 11 hours'+$6::int*interval '2 hour') at time zone 'Asia/Seoul',now()+interval '1 hour',10,0,array['도보'],'함께',1)`,[ids[i],o,'프로그램'+i,i===4?'experience':'activity',i===0||i===3?0:0.01,i]);
await query("insert into activity_experiences values($1,$2,'스마트폰 안내','건강·운동','10년 넘게 스마트폰을 알려드렸어요','오후','복지관','대면',true)",[offer,u]);
await as(u,async()=>{
 await query('insert into activity_program_favorites values($1,$2)',[u,ids[0]]);
 assert.equal((await query('select * from activity_program_favorites')).length,1);
 await assert.rejects(()=>query('insert into activity_program_favorites values($1,$2)',[v,ids[1]]));
});
await as(v,async()=>assert.equal((await query('select * from activity_program_favorites')).length,0));
let enrollment;
await as(u,async()=>{
 enrollment=(await query('select activity_apply_with_note($1,$2,$3) id',[ids[4],offer,'수요일 오후 가능합니다']))[0].id;
 const row=(await query('select * from activity_enrollments where id=$1',[enrollment]))[0];
 assert.equal(row.application_note,'수요일 오후 가능합니다');assert.equal(row.experience_snapshot.title,'스마트폰 안내');
 await query("update activity_experiences set description='바뀐 내용' where id=$1",[offer]);
 assert.equal((await query('select experience_snapshot from activity_enrollments where id=$1',[enrollment]))[0].experience_snapshot.description,'10년 넘게 스마트폰을 알려드렸어요');
});
await as(v,async()=>{assert.equal((await query('select * from activity_enrollments')).length,0);await assert.rejects(()=>query('select activity_reject_with_reason($1,$2)',[enrollment,'이유']));});
await as(m,async()=>{
 assert.equal((await query('select application_note from activity_enrollments where id=$1',[enrollment]))[0].application_note,'수요일 오후 가능합니다');
 await query('select activity_reject_with_reason($1,$2)',[enrollment,'이번 모집은 정원이 찼어요']);
});
await as(u,async()=>assert.equal((await query('select rejection_reason from activity_enrollments where id=$1',[enrollment]))[0].rejection_reason,'이번 모집은 정원이 찼어요'));
await as(m,async()=>{
 const data=(await query('select to_jsonb(p) data from activity_programs p where id=$1',[ids[0]]))[0].data;
 const id=(await query('select activity_save_program_v2($1) id',[{...data,target_audience:'60세 이상',preparations:'신분증',floor_guide:'1층 입구 → 엘리베이터 → 2층 강당'}]))[0].id;
 assert.equal((await query('select activity_program_detail($1) d',[id]))[0].d.program.preparations,'신분증');
});
await as(v,async()=>await assert.rejects(()=>query("select activity_save_program_v2(jsonb_build_object('org_id',$1::text))",[o])));
// Fixed current-week sequence for deterministic replacement checks.
await query("insert into activity_missions values($1,date_trunc('week',now() at time zone 'Asia/Seoul')::date,1,$2)",[u,ids[0]]);
await as(u,async()=>{
 const choices=(await query('select activity_mission_choices(1) d'))[0].d;
 assert(choices.some(c=>c.id===ids[3]));
 await query('select activity_replace_mission(1,$1)',[ids[3]]);
 assert.equal((await query('select program_id from activity_missions'))[0].program_id,ids[3]);
 await query('select activity_apply($1)',[ids[3]]);
 await assert.rejects(()=>query('select activity_replace_mission(1,$1)',[ids[0]]));
 assert.equal((await query('select program_id from activity_missions'))[0].program_id,ids[3]);
});
await db.exec('set role anon');await assert.rejects(()=>query('select activity_mission_choices(1)'));await db.exec('reset role');
await db.exec(await read('activity_mockup_v2.sql'));
assert.equal((await query('select count(*)::int n from activity_program_favorites'))[0].n,1);
await db.exec(`create role service_role;create table public.facilities(id uuid primary key,name text,lat double precision,lng double precision);`);
await db.exec(await read('attendance_points.sql'));await db.exec(await read('pet_companion.sql'));
await db.exec(await read('activity_program_mission_rewards.sql'));
await as(u,async()=>{
 await query("select pet_action('adopt','{\"name\":\"콩이\"}'::jsonb,gen_random_uuid())");
 await assert.rejects(()=>query('select activity_claim_program_mission(1)'));
});
await query("update activity_enrollments set status='completed',completed_at=now() where program_id=$1 and user_id=$2",[ids[3],u]);
await as(u,async()=>{
 const a=(await query('select activity_claim_program_mission(1) r'))[0].r;assert.equal(a.points,50);
 const b=(await query('select activity_claim_program_mission(1) r'))[0].r;assert.equal(b.already,true);
 assert.equal((await query('select balance from point_wallets where user_id=$1',[u]))[0].balance,50);
 await assert.rejects(()=>query('select activity_claim_program_mission(3)'));
});
await as(v,async()=>await assert.rejects(()=>query('select activity_claim_program_mission(1)')));
for(let stage=2;stage<=3;stage++){
 const id=ids[stage-2];
 await query("insert into activity_missions values($1,date_trunc('week',now() at time zone 'Asia/Seoul')::date,$2,$3)",[u,stage,id]);
 await query("insert into activity_enrollments(program_id,user_id,status,original_fee,final_fee,completed_at) values($1,$2,'completed',0,0,now())",[id,u]);
 await as(u,()=>query('select activity_claim_program_mission($1)',[stage]));
}
await as(u,async()=>{
 assert.equal((await query('select balance from point_wallets where user_id=$1',[u]))[0].balance,150);
 assert.equal((await query('select experience from pet_companions where user_id=$1',[u]))[0].experience,30);
 assert.equal((await query("select count(*)::int n from pet_history where kind='program_mission'"))[0].n,3);
});
await db.exec(await read('activity_program_mission_rewards.sql'));
await db.exec('set role anon');await assert.rejects(()=>query('select activity_claim_program_mission(1)'));await db.exec('reset role');
console.log('PASS: favorites RLS, immutable submitted snapshot+note, agency visibility/rejection reason, metadata, member restrictions, valid mission replacement, applied mission preservation, anonymous block, repeat migration, 3-stage wallet/EXP rewards, idempotency and unauthorized reward guards');
await db.close();
