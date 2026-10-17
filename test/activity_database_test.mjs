import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.env.PGLITE_MODULE??'@electric-sql/pglite');
const db=new PGlite(); let count=0;
const user='00000000-0000-0000-0000-000000000001',manager='00000000-0000-0000-0000-000000000002',other='00000000-0000-0000-0000-000000000003';
const org='10000000-0000-0000-0000-000000000001';
const p1='20000000-0000-0000-0000-000000000001',p2='20000000-0000-0000-0000-000000000002',p3='20000000-0000-0000-0000-000000000003',support='20000000-0000-0000-0000-000000000004';
const offer='30000000-0000-0000-0000-000000000001';
async function q(sql,params=[]){return (await db.query(sql,params)).rows;}
async function as(id,fn){await db.exec(`reset role;set role authenticated;set request.jwt.claim.sub='${id}';`);try{return await fn();}finally{await db.exec('reset role');}}
async function test(name,fn){await fn();count++;console.log(`PASS ${name}`);}
async function denied(fn){let rejected=false;try{await fn();}catch{rejected=true;}assert(rejected,'expected database to reject operation');}
await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;insert into auth.users values('${user}'),('${manager}'),('${other}');`);
await db.exec(await readFile(new URL('../supabase/activity_expansion.sql',import.meta.url),'utf8'));
await db.exec(`insert into activity_organizations values('${org}','지역 복지관',true);insert into activity_org_members values('${org}','${manager}');
insert into activity_preferences values('${user}','익숙한 동네',37.5,127,3,array['건강·운동'],'도보','무관',120,2,true);
insert into activity_programs(id,org_id,title,description,category,kind,place_name,lat,lng,starts_at,ends_at,deadline,capacity,fee,transports,participation,difficulty) values
('${p1}','${org}','동네 산책','함께 걸어요','건강·운동','activity','경로당',37.5,127,now()+interval '2h',now()+interval '3h',now()+interval '1h',2,5001,array['도보'],'혼자',1),
('${p2}','${org}','복지관 수업','함께 배워요','건강·운동','activity','새 복지관',37.51,127,now()+interval '4h',now()+interval '5h',now()+interval '1h',2,10000,array['도보'],'혼자',2),
('${p3}','${org}','동네 모임','함께 만나요','건강·운동','activity','문화센터',37.51,127,now()+interval '6h',now()+interval '7h',now()+interval '1h',2,0,array['도보'],'함께',1),
('${support}','${org}','경험 나눔 도우미','경험을 나눠요','건강·운동','experience','복지관',37.5,127,now()+interval '2h',now()+interval '3h',now()+interval '1h',1,0,array['도보'],'함께',1);
insert into activity_experiences values('${offer}','${user}','산책 지도','건강·운동','오래 산책 모임을 이끌었어요','주말 오전','동네','소규모 모임',true);`);
await test('anonymous cannot invoke home',()=>as('',()=>denied(()=>q('select activity_home()'))));
await test('users cannot assign institution membership',()=>as(user,()=>denied(()=>q(`insert into activity_org_members values('${org}','${user}')`))));
await test('users cannot create sponsorships',()=>as(user,()=>denied(()=>q(`insert into activity_sponsorships(program_id,starts_at,ends_at,payment_confirmed) values('${p1}',now(),now()+interval '1d',true)`))));
await test('users cannot grant own benefits',()=>as(user,()=>denied(()=>q(`insert into activity_benefits(user_id,enrollment_id,starts_at,expires_at) values('${user}',gen_random_uuid(),now(),now()+interval '30d')`))));
await test('users cannot invoke internal program data RPC',()=>as(user,()=>denied(()=>q(`select activity_program_data(p) from activity_programs p limit 1`))));
await test('other users cannot read private experiences',()=>as(other,async()=>assert.equal((await q('select * from activity_experiences')).length,0)));
await test('owner can read experiences',()=>as(user,async()=>assert.equal((await q('select * from activity_experiences')).length,1)));
await test('other user cannot change preferences',()=>as(other,async()=>assert.equal((await q(`update activity_preferences set radius_km=20 returning *`)).length,0)));
await test('unpaid sponsorship has no preference',async()=>{await q(`insert into activity_sponsorships(program_id,starts_at,ends_at) values('${p2}',now()-interval '1h',now()+interval '1d')`);await as(user,async()=>assert.equal((await q('select activity_home() data'))[0].data.recommendations[0].id,p1));});
await test('paid sponsorship leads only eligible candidates',async()=>{await q(`update activity_sponsorships set payment_confirmed=true`);await as(user,async()=>assert.equal((await q('select activity_home() data'))[0].data.recommendations[0].id,p2));});
await test('sponsored program outside selected radius excluded',async()=>{await q(`update activity_programs set lat=38 where id='${p2}'`);await as(user,async()=>assert(!(await q('select activity_home() data'))[0].data.recommendations.some(p=>p.id===p2)));await q(`update activity_programs set lat=37.51 where id='${p2}'`);});
await test('mission planning keeps chronology and easy first stage',()=>as(user,async()=>{await q('select activity_plan_week()');const m=(await q('select activity_home() data'))[0].data.missions;assert.equal(m.length,3);assert.equal(m[0].program.id,p1);for(let i=1;i<m.length;i++)assert(new Date(m[i].program.starts_at)>=new Date(m[i-1].program.ends_at));}));
await test('weekly planning is idempotent',()=>as(user,async()=>{await q('select activity_plan_week()');assert.equal((await q('select activity_home() data'))[0].data.missions.length,3);}));
await test('experience support requires owned matching offer',()=>as(other,()=>denied(()=>q(`select activity_apply('${support}','${offer}')`))));
let enrollment;
await test('experience application stores original offer snapshot',()=>as(user,async()=>{enrollment=(await q(`select activity_apply('${support}','${offer}') id`))[0].id;await q(`update activity_experiences set description='수정된 경험' where id='${offer}'`);const e=(await q(`select * from activity_enrollments where id='${enrollment}'`))[0];assert.equal(e.experience_snapshot.description,'오래 산책 모임을 이끌었어요');}));
await test('duplicate application rejected',()=>as(user,()=>denied(()=>q(`select activity_apply('${support}','${offer}')`))));
await test('capacity cannot be exceeded',async()=>{await q(`insert into activity_experiences(user_id,title,category,description,available_time,preferred_place,activity_type) values('${other}','경험','건강·운동','설명','오전','동네','모임')`);await as(other,()=>denied(()=>q(`select activity_apply('${support}',(select id from activity_experiences limit 1))`)));});
await test('ordinary user cannot approve',()=>as(user,()=>denied(()=>q(`select activity_manage('${enrollment}','approved')`))));
await test('institution can approve application',()=>as(manager,async()=>{await q(`select activity_manage('${enrollment}','approved')`);assert.equal((await q(`select status from activity_enrollments where id='${enrollment}'`))[0].status,'approved');}));
await test('completion before activity end rejected',()=>as(manager,()=>denied(()=>q(`select activity_manage('${enrollment}','completed')`))));
await q(`update activity_programs set starts_at=now()-interval '2h',ends_at=now()-interval '1h',deadline=now()-interval '3h' where id='${support}'`);
await test('institution completion grants exactly 30 day benefit',async()=>{await as(manager,()=>q(`select activity_manage('${enrollment}','completed')`));const b=(await q(`select extract(epoch from(expires_at-starts_at))/86400 days from activity_benefits`))[0];assert.equal(Number(b.days),30);});
await test('repeat completion cannot duplicate benefit',()=>as(manager,()=>denied(()=>q(`select activity_manage('${enrollment}','completed')`))));
await test('active benefit rounds odd fee upward',()=>as(user,async()=>assert.equal((await q(`select activity_program_detail('${p1}') data`))[0].data.quote,2501)));
let paid;
await test('server stores discounted fee, not a client amount',()=>as(user,async()=>{paid=(await q(`select activity_apply('${p1}') id`))[0].id;assert.equal((await q(`select final_fee from activity_enrollments where id='${paid}'`))[0].final_fee,2501);}));
await test('rebuild preserves already applied mission',()=>as(user,async()=>{await q('select activity_plan_week(true)');const m=(await q('select activity_home() data'))[0].data.missions;assert(m.some(m=>m.program_id===p1));for(let i=1;i<m.length;i++)assert(new Date(m[i].program.starts_at)>=new Date(m[i-1].program.ends_at));}));
await test('other user cannot cancel application',()=>as(other,()=>denied(()=>q(`select activity_cancel('${paid}')`))));
await test('owner can cancel before activity',()=>as(user,async()=>{await q(`select activity_cancel('${paid}')`);assert.equal((await q(`select status from activity_enrollments where id='${paid}'`))[0].status,'cancelled');}));
await test('expired benefit does not change already recorded fees',async()=>{await q(`update activity_benefits set starts_at=now()-interval '31d',expires_at=now()-interval '1h'`);await as(user,async()=>{assert.equal((await q(`select activity_program_detail('${p1}') data`))[0].data.quote,5001);assert.equal((await q(`select final_fee from activity_enrollments where id='${paid}'`))[0].final_fee,2501);});});
await test('reapplication uses current eligibility and fee',()=>as(user,async()=>{await q(`select activity_apply('${p1}')`);assert.equal((await q(`select final_fee from activity_enrollments where id='${paid}'`))[0].final_fee,5001);}));
await test('member can close only own institution program',()=>as(user,()=>denied(()=>q(`select activity_close_program('${p2}')`))));
await test('closed program rejects applications',async()=>{await as(manager,()=>q(`select activity_close_program('${p2}')`));await as(other,()=>denied(()=>q(`select activity_apply('${p2}')`)));});
await test('institution dashboard includes completion metrics',()=>as(manager,async()=>assert.equal((await q('select activity_agency() data'))[0].data.metrics.completed,1)));
await test('ordinary users see no institution applications',()=>as(other,async()=>assert.equal((await q('select activity_agency() data'))[0].data.applications.length,0)));

await test('member cannot support own institution',()=>as(manager,()=>denied(()=>q(`select activity_apply('${support}','${offer}')`))));
await test('ordinary user cannot create institutional program',()=>as(user,()=>denied(()=>q(`select activity_save_program(to_jsonb(p)-'id') from activity_programs p where id='${p1}'`))));
let created;
await test('verified member can register program through RPC',()=>as(manager,async()=>{created=(await q(`select activity_save_program(to_jsonb(p)-'id') id from activity_programs p where id='${p1}'`))[0].id;assert(created);assert.notEqual(created,p1);}));
await test('invalid fee rejected by server',()=>as(manager,()=>denied(()=>q(`select activity_save_program((to_jsonb(p)-'id')||'{"fee":-1}'::jsonb) from activity_programs p where id='${p1}'`))));
await test('invalid schedule rejected by server',()=>as(manager,()=>denied(()=>q(`select activity_save_program((to_jsonb(p)-'id')||jsonb_build_object('ends_at',p.starts_at)) from activity_programs p where id='${p1}'`))));
await test('completed participation rate uses ended approved activities',()=>as(manager,async()=>{const m=(await q('select activity_agency() data'))[0].data.metrics;assert.equal(m.eligible,1);assert.equal(Number(m.completion_rate),100);assert.equal(Number(m.repeat_rate),0);}));
await test('transport preference filters even paid sponsorship',async()=>{await q(`update activity_preferences set transport='자동차' where user_id='${user}'`);await as(user,async()=>assert.equal((await q('select activity_home() data'))[0].data.recommendations.length,0));await q(`update activity_preferences set transport='도보' where user_id='${user}'`);});
await test('activity duration remains within user limit',async()=>{await q(`update activity_preferences set max_minutes=30 where user_id='${user}'`);await as(user,async()=>assert.equal((await q('select activity_home() data'))[0].data.recommendations.length,0));await q(`update activity_preferences set max_minutes=120 where user_id='${user}'`);});
await test('interests filter recommendations',async()=>{await q(`update activity_preferences set interests=array['생활·기술'] where user_id='${user}'`);await as(user,async()=>assert.equal((await q('select activity_home() data'))[0].data.recommendations.length,0));await q(`update activity_preferences set interests=array['건강·운동'] where user_id='${user}'`);});
await test('expired sponsorship is not labeled sponsored',async()=>{await q(`update activity_sponsorships set starts_at=now()-interval '2d',ends_at=now()-interval '1d'`);await as(user,async()=>assert.equal((await q(`select activity_program_detail('${p2}') data`))[0].data.program.sponsored,false));});
await test('unapproved institutions are hidden and cannot accept applications',async()=>{await q(`update activity_organizations set approved=false where id='${org}'`);await as(other,async()=>{assert.equal((await q('select activity_home() data'))[0].data.programs.length,0);await denied(()=>q(`select activity_apply('${created}')`));});});
await db.close();console.log(`${count} database checks passed`);
