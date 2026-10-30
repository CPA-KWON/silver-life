import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
// Offline, isolated PostgreSQL validation. No app secrets or network access.
// Run: PGLITE_MODULE=/absolute/path/to/@electric-sql/pglite/dist/index.js node tool/test_flower_gift_sql.mjs
const modulePath=process.env.PGLITE_MODULE;
if(!modulePath)throw new Error('Set PGLITE_MODULE to the local PGlite module path.');
const {PGlite}=await import(pathToFileURL(modulePath).href);
const db=new PGlite();const root=fileURLToPath(new URL('../',import.meta.url));
const read=n=>readFile(root+'supabase/'+n,'utf8'),q=async(s,a=[])=>(await db.query(s,a)).rows;
const id=n=>`00000000-0000-4000-8000-00000000000${n}`;
const [host,a,b,outsider,poor,noWallet,c]=[1,2,3,4,5,6,7].map(id);
async function as(user,f){await db.exec('set role authenticated');await q("select set_config('request.jwt.claim.sub',$1,false)",[user]);try{return await f();}finally{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub','',false)");}}

await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;grant usage on schema auth to authenticated;create table public.profiles(id uuid primary key references auth.users on delete cascade,name text,birth_year int,nickname text,region_sido text,region_sigungu text);create table public.facilities(id uuid primary key,name text,lat float8,lng float8);`);
await db.exec(await read('community_schema.sql'));await db.exec(await read('reports.sql'));
await db.exec(`alter table posts add column event_at timestamptz;alter table posts add column facility_id uuid;create view public_profiles as select id,nickname,region_sido,region_sigungu from profiles;grant select on public_profiles to authenticated;grant select,insert,update,delete on posts,comments to authenticated;`);
await db.exec(await read('activity_expansion.sql'));await db.exec(await read('activity_usability_fix.sql'));await db.exec(await read('activity_mockup_v2.sql'));await db.exec(await read('institution_notices.sql'));
await db.exec(await read('attendance_points.sql'));await db.exec(await read('pet_companion.sql'));
await db.exec(await read('meetup_participation.sql'));await db.exec(await read('neighborhood_mockups.sql'));
await db.exec(await read('account_deletion.sql'));
const before=(await q("select pg_get_constraintdef(oid) d from pg_constraint where conname='point_ledger_reason_check'"))[0].d;
assert.match(before,/attendance/);assert.match(before,/pet/);
await db.exec(await read('flower_gift.sql'));
await db.exec(await read('flower_gift.sql')); // re-run must be safe

for(const [i,user] of [host,a,b,outsider,poor,noWallet,c].entries()){
 await q('insert into auth.users values($1)',[user]);
 await q("insert into profiles(id,name,birth_year,nickname,region_sido,region_sigungu) values($1,$2,1960,$3,'서울특별시','동작구')",[user,'실명'+i,'이웃'+i]);
}
for(const [user,balance] of [[host,5],[a,5],[b,2],[outsider,5],[poor,0],[c,5]])await q('insert into point_wallets(user_id,balance,total_earned) values($1,$2,$2)',[user,balance]);

async function meetup(members,{past=true}={}){
 const [{id:post}]=await q("insert into posts(author_id,category,title,content,event_at) values($1,'동네모임','산책','같이 걸어요',now()+interval '2 days') returning id",[host]);
 for(const user of members)await q('insert into meetup_participants(post_id,user_id) values($1,$2) on conflict do nothing',[post,user]);
 if(past)await q("update posts set event_at=now()-interval '1 day' where id=$1",[post]);
 return post;
}
const send=(from,post,to)=>as(from,()=>q('select send_meetup_flower($1,$2) r',[post,to]));
const balance=async u=>(await q('select balance from point_wallets where user_id=$1',[u]))[0].balance;
const flowers=async()=>Number((await q('select count(*) c from meetup_flowers'))[0].c);
const ledger=async()=>Number((await q("select count(*) c from point_ledger where reason='flower'"))[0].c);
// Rejections must leave points, flowers and the ledger untouched.
async function refused(from,post,to,pattern){
 const state=[await flowers(),await ledger(),from===noWallet?null:await balance(from)];
 await assert.rejects(()=>send(from,post,to),pattern);
 assert.deepEqual([await flowers(),await ledger(),from===noWallet?null:await balance(from)],state);
}

const everyone=[a,b,poor,noWallet];
const p=await meetup(everyone);

// Rules
await refused(a,p,a,/나에게는/);
await refused(outsider,p,a,/같은 모임/);
await refused(a,p,outsider,/같은 모임/);
const upcoming=await meetup([a,b],{past:false});
await refused(a,upcoming,b,/끝난 뒤/);
const cancelled=await meetup([a,b]);await q('update posts set meetup_cancelled=true where id=$1',[cancelled]);
await refused(a,cancelled,b,/취소된/);
const hidden=await meetup([a,b]);
for(const reporter of [outsider,poor,noWallet])await q("insert into reports(reporter_id,post_id,reason) values($1,$2,'기타')",[reporter,hidden]);
await refused(a,hidden,b,/보낼 수 없는 모임/);
await refused(poor,p,a,/^error: 포인트가 부족해요$|포인트가 부족해요/);
await refused(noWallet,p,a,/포인트가 부족해요/);
const notMeetup=(await q("insert into posts(author_id,category,title,content) values($1,'자유게시판','글','내용') returning id",[host]))[0].id;
await refused(a,notMeetup,b,/보낼 수 없는 모임/);
await q('insert into user_blocks(user_id,blocked_id) values($1,$2)',[b,a]);
await refused(a,p,b,/보낼 수 없는 이웃/);
await refused(b,p,a,/보낼 수 없는 이웃/);
await q('delete from user_blocks');
await db.exec('set role anon');await assert.rejects(()=>q('select send_meetup_flower($1,$2)',[p,a]));await assert.rejects(()=>q('select my_flowers()'));await db.exec('reset role');

// Sending: 1P off the sender only, nothing to the recipient, ledger in the same call.
assert.equal((await send(a,p,b))[0].r.balance,4);
assert.equal(await balance(a),4);assert.equal(await balance(b),2);
const [row]=await q("select * from point_ledger where reason='flower'");
assert.equal(row.amount,-1);assert.equal(row.user_id,a);assert.equal(row.ref_date,null);
assert.equal((await q('select total_earned from point_wallets where user_id=$1',[a]))[0].total_earned,5);
// One per person per meetup, even when the app is bypassed.
await refused(a,p,b,/이미 꽃을/);
await assert.rejects(()=>q('insert into meetup_flowers(post_id,sender_id,recipient_id) values($1,$2,$3)',[p,a,b]),/unique|duplicate/);
await assert.rejects(()=>q('insert into meetup_flowers(post_id,sender_id,recipient_id) values($1,$2,$2)',[p,a]),/check/);
// A second flower the same day (other person, other meetup) must not hit the ledger's unique rule.
await send(a,p,host);
const p2=await meetup([a,b]);await send(a,p2,b);
assert.equal(await balance(a),2);assert.equal(await ledger(),3);
// Balance can't go below zero: b has 2P.
await send(b,p,a);await send(b,p,host);await refused(b,p2,a,/포인트가 부족해요/);assert.equal(await balance(b),0);
// Ledger reasons: existing values kept, others refused.
for(const reason of ['attendance','pet','flower'])await q('insert into point_ledger(user_id,amount,reason) values($1,1,$2)',[c,reason]);
await assert.rejects(()=>q("insert into point_ledger(user_id,amount,reason) values($1,1,'other')",[c]),/check/);
await q('delete from point_ledger where user_id=$1',[c]);

// App cannot touch the table directly.
await as(a,async()=>{await assert.rejects(()=>q('select * from meetup_flowers'));await assert.rejects(()=>q('insert into meetup_flowers(post_id,sender_id,recipient_id) values($1,$2,$3)',[p,a,poor]));});

// meetup_participation: counts for everyone, user_id only for someone I can send to now.
const view=(user,post)=>as(user,async()=>(await q('select meetup_participation($1) r',[post]))[0].r);
let state=await view(a,p);const by=n=>state.participants.find(x=>x.nickname===n);
assert.equal(by('이웃2').flowers,2);assert.equal(by('이웃2').flower_sent,true);assert.equal(by('이웃2').can_send_flower,false);assert.equal(by('이웃2').user_id,null);
assert.equal(by('이웃1').is_me,true);assert.equal(by('이웃1').can_send_flower,false);assert.equal(by('이웃1').user_id,null);
assert.equal(by('이웃4').can_send_flower,true);assert.equal(by('이웃4').user_id,poor);
assert.equal(JSON.stringify(state).includes('실명'),false);assert.equal(JSON.stringify(state).includes('birth'),false);
state=await view(outsider,p);assert.ok(state.participants.every(x=>x.can_send_flower===false&&x.user_id===null));
state=await view(a,upcoming);assert.ok(state.participants.every(x=>x.can_send_flower===false&&x.user_id===null));
state=await view(host,hidden);assert.ok(state.participants.every(x=>x.can_send_flower===false&&x.user_id===null));
state=await view(host,cancelled);assert.ok(state.participants.every(x=>x.can_send_flower===false));
await q('insert into user_blocks(user_id,blocked_id) values($1,$2)',[poor,a]);
state=await view(a,p);assert.equal(by('이웃4').can_send_flower,false);assert.equal(by('이웃4').user_id,null);
await q('delete from user_blocks');

// my_flowers: nickname, meetup, date; no private data.
let mine=await as(b,async()=>(await q('select my_flowers() r'))[0].r);
assert.equal(mine.length,2);assert.equal(mine[0].sender_nickname,'이웃1');assert.equal(mine[0].meetup_title,'산책');assert.ok(mine[0].event_at&&mine[0].created_at);
assert.equal(JSON.stringify(mine).includes('실명'),false);assert.equal(JSON.stringify(mine).includes(a),false);
await q('insert into user_blocks(user_id,blocked_id) values($1,$2)',[b,a]);
assert.equal((await as(b,async()=>(await q('select my_flowers() r'))[0].r)).length,0);
await q('delete from user_blocks');
for(const reporter of [outsider,poor,noWallet])await q("insert into reports(reporter_id,post_id,reason) values($1,$2,'기타')",[reporter,p2]);
mine=await as(b,async()=>(await q('select my_flowers() r'))[0].r);
assert.equal(mine.filter(x=>x.meetup_title==='숨겨진 모임').length,1);

// Account deletion is not blocked, as sender or recipient; flowers go, spent points stay spent.
await as(a,()=>q('select delete_my_account()'));
assert.equal((await q('select * from auth.users where id=$1',[a])).length,0);
assert.equal(Number((await q('select count(*) c from meetup_flowers where sender_id=$1 or recipient_id=$1',[a]))[0].c),0);
await as(host,()=>q('select delete_my_account()'));
assert.equal((await q('select * from auth.users where id=$1',[host])).length,0);
assert.equal(await flowers(),0);
assert.equal(await balance(b),0);
await db.close();
console.log('flower gift isolated database checks passed');
