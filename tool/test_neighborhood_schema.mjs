import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
// Offline, isolated PostgreSQL validation. No app secrets or network access.
// Run: PGLITE_MODULE=/absolute/path/to/@electric-sql/pglite/dist/index.js node tool/test_neighborhood_schema.mjs
import {fileURLToPath,pathToFileURL} from 'node:url';
const modulePath=process.env.PGLITE_MODULE;
if(!modulePath)throw new Error('Set PGLITE_MODULE to the local PGlite module path.');
const {PGlite}=await import(pathToFileURL(modulePath).href);
const db=new PGlite();const root=fileURLToPath(new URL('../',import.meta.url));
const read=n=>readFile(root+'supabase/'+n,'utf8'),q=async(s,a=[])=>(await db.query(s,a)).rows;
const u='00000000-0000-4000-8000-000000000001',v='00000000-0000-4000-8000-000000000002',w='00000000-0000-4000-8000-000000000003';
async function as(id,f){await db.exec('set role authenticated');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);try{return await f();}finally{await db.exec('reset role');}}
await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;grant usage on schema auth to authenticated;create table public.profiles(id uuid primary key references auth.users on delete cascade,nickname text,region_sido text,region_sigungu text);create table public.facilities(id uuid primary key,name text,lat float8,lng float8);`);
await db.exec(await read('community_schema.sql'));await db.exec(await read('reports.sql'));
await db.exec(`alter table posts add column event_at timestamptz;alter table posts add column facility_id uuid;create view public_profiles as select id,nickname,region_sido,region_sigungu from profiles;grant select on public_profiles to authenticated;grant select,insert,update,delete on posts,comments to authenticated;`);
await db.exec(await read('activity_expansion.sql'));await db.exec(await read('activity_usability_fix.sql'));await db.exec(await read('activity_mockup_v2.sql'));await db.exec(await read('institution_notices.sql'));
await db.exec(await read('meetup_participation.sql'));
await db.exec(await read('neighborhood_mockups.sql'));
for(const id of[u,v,w]){await q('insert into auth.users values($1)',[id]);await q("insert into profiles values($1,$2,'서울특별시','동작구')",[id,id.slice(-1)]);}
const p=(await q("insert into posts(author_id,category,title,content,event_at,max_participants) values($1,'동네모임','산책','동네에서 걸어요',now()+interval '2 days',2) returning id",[u]))[0].id;
await as(v,async()=>{await q('select meetup_participate($1,true)',[p]);await q('select meetup_participate($1,true)',[p]);assert.equal((await q('select neighborhood_state(array[$1::uuid]) s',[p]))[0].s[0].member_count,2);});
await as(w,async()=>await assert.rejects(()=>q('select meetup_participate($1,true)',[p])));
await as(v,async()=>{await q('select meetup_participate($1,false)',[p]);assert.equal((await q('select neighborhood_state(array[$1::uuid]) s',[p]))[0].s[0].member_count,1);});
await as(w,async()=>{await q('select meetup_participate($1,true)',[p]);await assert.rejects(()=>q('insert into meetup_participants(user_id,post_id) values($1,$2)',[v,p]));await q('insert into post_likes values($1,$2)',[w,p]);await assert.rejects(()=>q('insert into post_likes values($1,$2)',[w,p]));});
await as(v,async()=>{await q('insert into user_blocks(user_id,blocked_id) values($1,$2)',[v,u]);assert.equal((await q('select * from posts where id=$1',[p])).length,0);assert.equal((await q('select neighborhood_state(array[$1::uuid]) s',[p]))[0].s.length,0);});
await as(u,async()=>{await assert.rejects(()=>q('select meetup_participate($1,false)',[p]));await assert.rejects(()=>q("update posts set image_paths=array[$2] where id=$1",[p,v+'/posts/stolen.jpg']));});
await db.exec('set role anon');await assert.rejects(()=>q('select neighborhood_state(array[$1::uuid])',[p]));await db.exec('reset role');
await db.exec(await read('neighborhood_mockups.sql'));
await db.exec(await read('meetup_history.sql'));
await as(w,async()=>{await q('select meetup_participate($1,false)',[p]);let list=(await q('select my_meetups() r'))[0].r;assert.equal(list.find(x=>x.id===p).participation_cancelled,true);await q('select meetup_participate($1,true)',[p]);list=(await q('select my_meetups() r'))[0].r;assert.equal(list.filter(x=>x.id===p).length,1);assert.equal(list.find(x=>x.id===p).participation_cancelled,false);});
await as(v,async()=>{assert.equal((await q('select my_meetups() r'))[0].r.length,0);await assert.rejects(()=>q('select * from meetup_withdrawals'));});
await db.exec(await read('meetup_history.sql'));
await db.exec(`create role service_role bypassrls;create schema storage;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,primary key(bucket_id,name));
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$select string_to_array(name,'/')$$;
grant usage on schema storage to authenticated;grant select,insert,delete on storage.objects to authenticated;
`);
await db.exec(await read('neighborhood_media.sql'));
await db.exec(await read('institution_access_requests.sql'));
const facility='00000000-0000-4000-8000-000000000099',request='00000000-0000-4000-8000-000000000088';
await q("insert into facilities(id,name,lat,lng) values($1,'검증 복지관',37.5,127)",[facility]);
await as(v,async()=>{await q('delete from user_blocks where user_id=$1',[v]);});
await as(v,async()=>{
 await q("insert into storage.objects(bucket_id,name) values('neighborhood-media',$1)",[v+'/org-proofs/test.jpg']);
 await q("select institution_request_access($1,$2::jsonb)",[request,JSON.stringify({facility_id:facility,institution_kind:'복지관',contact_name:'담당자',department:'문화팀',duties:['프로그램 운영'],contact_phone:'02-1234-5678',proof_paths:[v+'/org-proofs/test.jpg'],consent:true})]);
 await q("select institution_request_access($1,$2::jsonb)",[request,'{}']);
 assert.equal((await q('select * from institution_access_requests')).length,1);
 assert.equal((await q('select * from activity_org_members')).length,0);
 await assert.rejects(()=>q('select institution_review_access($1,true)',[request]));
 await assert.rejects(()=>q("update institution_access_requests set status='approved' where id=$1",[request]));
});
await as(w,async()=>{
 assert.equal((await q('select * from institution_access_requests')).length,0);
 assert.equal((await q("select * from storage.objects where bucket_id='neighborhood-media' and name=$1",[v+'/org-proofs/test.jpg'])).length,0);
 await assert.rejects(()=>q('select institution_cancel_access($1)',[request]));
});
await q("select institution_review_access($1,false,'00000000-0000-4000-8000-000000000099','담당 부서 연락처를 확인해 주세요')",[request]);
await as(v,async()=>{assert.equal((await q('select * from institution_access_requests'))[0].status,'rejected');});
const request2='00000000-0000-4000-8000-000000000087';
await as(v,async()=>{await q("select institution_request_access($1,$2::jsonb)",[request2,JSON.stringify({facility_id:facility,institution_kind:'복지관',contact_name:'담당자',department:'문화팀',duties:['프로그램 운영'],contact_phone:'02-1234-5678',proof_paths:[],consent:true})]);});
await q('select institution_review_access($1,true)',[request2]);
await as(v,async()=>{assert.equal((await q('select * from activity_org_members')).length,1);assert.equal((await q('select activity_is_member(org_id) ok from activity_org_members'))[0].ok,true);});
await db.exec(await read('institution_access_requests.sql'));
const orgId=(await q('select org_id from institution_access_requests where id=$1',[request2]))[0].org_id;
const now=Date.now(), iso=d=>new Date(now+d*86400000).toISOString();
const data={org_id:orgId,title:'서버 검증 프로그램',description:'실제 운영이 아닌 격리 테스트',category:'건강·운동',kind:'activity',place_name:'검증 복지관',lat:37.5,lng:127,starts_at:iso(2),ends_at:iso(2.1),deadline:iso(1),capacity:2,fee:0,transports:['도보'],participation:'함께',difficulty:1,target_audience:'60세 이상',preparations:'신분증',floor_guide:'2층'};
let program,phoneProgram;
await as(v,async()=>{
 const draft=(await q('select activity_save_program_v3($1::jsonb) id',[JSON.stringify({org_id:orgId,title:'임시 저장',draft:true})]))[0].id;
 assert.equal((await q('select * from activity_program_drafts')).length,1);
 await q('select activity_save_program_v3($1::jsonb)',[JSON.stringify({org_id:orgId,title:'임시 수정',draft:true,draft_id:draft})]);
 assert.equal((await q('select data from activity_program_drafts'))[0].data.title,'임시 수정');
 program=(await q('select activity_save_program_v3($1::jsonb) id',[JSON.stringify({...data,draft_id:draft})]))[0].id;
 assert.equal((await q('select * from activity_program_drafts')).length,0);
 phoneProgram=(await q('select activity_save_program_v3($1::jsonb) id',[JSON.stringify({...data,title:'전화 프로그램',application_method:'phone',contact_phone:'02-1234-5678'})]))[0].id;
});
let e1,e2;
await as(w,async()=>{
 await assert.rejects(()=>q("select activity_apply_with_note($1,null,'')",[phoneProgram]));
 e1=(await q("select activity_apply_with_note($1,null,'') id",[program]))[0].id;
 await assert.rejects(()=>q('select activity_save_program_v3($1::jsonb)',[JSON.stringify({...data,title:'위조 수정',id:program})]));
});
await as(u,async()=>{e2=(await q("select activity_apply_with_note($1,null,'') id",[program]))[0].id;});
await as(v,async()=>{
 await assert.rejects(()=>q('select activity_save_program_v3($1::jsonb)',[JSON.stringify({...data,id:program,capacity:1})]));
 await assert.rejects(()=>q("select activity_manage_batch($1::uuid[],'approved','')",[[e1,'ffffffff-ffff-4fff-8fff-ffffffffffff']]));
 assert.equal((await q('select status from activity_enrollments where id=$1',[e1]))[0].status,'applied');
 await q("select activity_manage_batch($1::uuid[],'approved','')",[[e1,e2]]);
});
await q("update activity_programs set starts_at=now()-interval '2 hours',ends_at=now()-interval '1 hour',deadline=now()-interval '3 hours' where id=$1",[program]);
await as(v,async()=>{await q("select activity_manage_batch($1::uuid[],'completed','')",[[e1,e2]]);});
assert.equal((await q("select count(*) n from activity_enrollments where program_id=$1 and status='completed'",[program]))[0].n,2);
console.log('PASS: drafts/create/publish, phone enrollment denial, capacity edit denial, owner checks, atomic approval/completion, plus requests, private photos, canonical meetup history.');
await db.close();
