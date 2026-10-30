// 친구 추가 + 친구 체크인 공유 DB 검증 (supabase/friends.sql)
// 실행: PGLITE_MODULE=<pglite 경로> node test/friends_database_test.mjs
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.env.PGLITE_MODULE??'@electric-sql/pglite');
const db=new PGlite(); let count=0;
const A='00000000-0000-0000-0000-00000000000a',B='00000000-0000-0000-0000-00000000000b',
  C='00000000-0000-0000-0000-00000000000c',D='00000000-0000-0000-0000-00000000000d';
async function q(sql,params=[]){return (await db.query(sql,params)).rows;}
async function as(id,fn){await db.exec(`reset role;set role authenticated;set request.jwt.claim.sub='${id}';`);try{return await fn();}finally{await db.exec('reset role');}}
async function asAnon(fn){await db.exec(`reset role;set role anon;`);try{return await fn();}finally{await db.exec('reset role');}}
async function test(name,fn){await fn();count++;console.log(`PASS ${name}`);}
async function denied(fn,pattern){let error;try{await fn();}catch(e){error=e;}assert(error,'expected database to reject operation');if(pattern)assert.match(String(error.message),pattern);}
const request=(nick)=>q('select friend_request($1) r',[nick]).then(r=>r[0].r);
const list=()=>q('select * from friend_list()');
const presence=()=>q('select * from friends_presence()');
// 두 사람을 바로 친구로 만드는 도우미(요청→수락)
async function befriend(from,to,toNick){await as(from,()=>request(toNick));const id=(await as(to,list)).find(r=>r.relation==='incoming').friendship_id;await as(to,()=>q('select friend_respond($1,true)',[id]));}

await db.exec(`
create role anon;create role authenticated;
create schema auth;create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;grant usage on schema public to authenticated,anon;
insert into auth.users values('${A}'),('${B}'),('${C}'),('${D}');
create table public.profiles(id uuid primary key references auth.users on delete cascade,nickname text not null unique,region_sido text,region_sigungu text);
insert into public.profiles values('${A}','알파','서울특별시','강남구'),('${B}','브라보','서울특별시','서초구'),('${C}','찰리','부산광역시','해운대구'),('${D}','델타','대구광역시','수성구');
create table public.facilities(id uuid primary key default gen_random_uuid(),name text not null,address text not null);
insert into public.facilities(name,address) values('강남 경로당','서울 강남구 1'),('서초 복지관','서울 서초구 2');
create table public.checkins(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles on delete cascade,facility_id uuid not null references public.facilities on delete cascade,checked_in_at timestamptz not null default now(),unique(user_id,facility_id));
create table public.user_blocks(user_id uuid not null references auth.users on delete cascade,blocked_id uuid not null references auth.users on delete cascade,primary key(user_id,blocked_id));
`);
const fac=async(name)=>(await q('select id from public.facilities where name=$1',[name]))[0].id;
const checkin=async(user,facility,agoMinutes=0)=>{await db.query(`insert into public.checkins(user_id,facility_id,checked_in_at) values($1,$2,now()-($3||' minutes')::interval) on conflict(user_id,facility_id) do update set checked_in_at=excluded.checked_in_at`,[user,await fac(facility),String(agoMinutes)]);};
const sql=await readFile(new URL('../supabase/friends.sql',import.meta.url),'utf8');
await db.exec(sql);

await test('script can be re-run safely',()=>db.exec(sql));
await test('anonymous role cannot execute any friend function',()=>asAnon(async()=>{
  for(const call of ['friend_list()','friends_presence()','friend_share_get()',"friend_request('알파')",'friend_share_set(true)'])
    await denied(()=>q(`select ${call}`),/permission denied/);
}));
await test('signed-out token (no uid) is rejected',()=>as('',async()=>{
  await denied(()=>request('알파'),/로그인/);
  assert.equal((await list()).length,0);assert.equal((await presence()).length,0);
}));
await test('apps cannot read or write the new tables directly',()=>as(A,async()=>{
  await denied(()=>q('select * from public.friendships'),/permission denied/);
  await denied(()=>q('select * from public.friend_settings'),/permission denied/);
  await denied(()=>q(`insert into public.friendships(requester_id,addressee_id,status) values('${A}','${B}','accepted')`),/permission denied/);
  await denied(()=>q(`insert into public.friend_settings(user_id,share_presence) values('${A}',false)`),/permission denied/);
}));

await test('request by nickname: sender sees outgoing, receiver sees incoming',async()=>{
  assert.equal(await as(A,()=>request('브라보')),'requested');
  const a=await as(A,list),b=await as(B,list);
  assert.equal(a.length,1);assert.equal(a[0].relation,'outgoing');assert.equal(a[0].nickname,'브라보');
  assert.equal(b.length,1);assert.equal(b[0].relation,'incoming');assert.equal(b[0].nickname,'알파');
  assert.equal(b[0].region_sigungu,'강남구');
  assert.equal((await as(C,list)).length,0,'third party sees nothing');
});
await test('invalid requests are rejected with friendly messages',()=>as(A,async()=>{
  await denied(()=>request('없는사람'),/찾을 수 없어요/);
  await denied(()=>request('알파'),/내 닉네임/);
  await denied(()=>request('브라보'),/이미 친구 요청을 보냈어요/);
  await denied(()=>request('   '),/찾을 수 없어요/);
}));
await test('pending request does not reveal check-ins',async()=>{
  await checkin(B,'강남 경로당');
  assert.equal((await as(A,presence)).length,0);
});
await test('only the addressee can accept; requester and strangers cannot',async()=>{
  const id=(await as(B,list))[0].friendship_id;
  await as(A,()=>denied(()=>q('select friend_respond($1,true)',[id]),/처리할 수 있는 친구 요청이 없어요/));
  await as(C,()=>denied(()=>q('select friend_respond($1,true)',[id]),/처리할 수 있는 친구 요청이 없어요/));
  await as(B,()=>q('select friend_respond($1,true)',[id]));
  assert.equal((await as(A,list))[0].relation,'friend');assert.equal((await as(B,list))[0].relation,'friend');
  await as(B,()=>denied(()=>q('select friend_respond($1,true)',[id]),/처리할 수 있는 친구 요청이 없어요/));
});
await test('duplicate request after becoming friends is rejected both ways',async()=>{
  await as(A,()=>denied(()=>request('브라보'),/이미 친구예요/));
  await as(B,()=>denied(()=>request('알파'),/이미 친구예요/));
});
await test('friend sees friend check-in with facility name; not-yet-friend does not',async()=>{
  const seen=await as(A,presence);
  assert.equal(seen.length,1);assert.equal(seen[0].nickname,'브라보');assert.equal(seen[0].facility_name,'강남 경로당');
  assert.equal((await as(C,presence)).length,0,'stranger sees nothing');
  assert.equal((await as(B,presence)).length,0,'own check-in is not listed');
});
await test('only the latest facility per friend is shown, newest friend first',async()=>{
  await checkin(B,'서초 복지관',5);await checkin(B,'강남 경로당',60);
  const seen=await as(A,presence);assert.equal(seen.length,1);assert.equal(seen[0].facility_name,'서초 복지관');
});
await test('check-ins older than 3 hours or in the future are hidden',async()=>{
  await checkin(B,'서초 복지관',181);await checkin(B,'강남 경로당',200);
  assert.equal((await as(A,presence)).length,0);
  await checkin(B,'강남 경로당',-30);
  assert.equal((await as(A,presence)).length,0);
  await checkin(B,'강남 경로당',10);await checkin(B,'서초 복지관',200);
  assert.equal((await as(A,presence)).length,1);
});
await test('sharing switch: default on, off hides from friends, on shows again',async()=>{
  assert.equal((await as(B,()=>q('select friend_share_get() v')))[0].v,true);
  await as(B,()=>q('select friend_share_set(false)'));
  assert.equal((await as(B,()=>q('select friend_share_get() v')))[0].v,false);
  assert.equal((await as(A,presence)).length,0);
  await as(B,()=>q('select friend_share_set(true)'));
  assert.equal((await as(A,presence)).length,1);
  await as(B,()=>denied(()=>q('select friend_share_set(null)'),/선택해 주세요/));
});
await test('one user cannot change another user\'s switch',async()=>{
  await as(A,()=>q('select friend_share_set(false)'));
  assert.equal((await as(B,()=>q('select friend_share_get() v')))[0].v,true);
  await as(A,()=>q('select friend_share_set(true)'));
});
await test('reverse pending request becomes a friendship immediately',async()=>{
  await as(C,()=>request('델타'));
  assert.equal(await as(D,()=>request('찰리')),'accepted');
  assert.equal((await as(C,list)).find(r=>r.nickname==='델타').relation,'friend');
});
await test('decline deletes the request and allows a new one later',async()=>{
  await as(C,()=>request('알파'));
  const id=(await as(A,list)).find(r=>r.relation==='incoming').friendship_id;
  await as(A,()=>q('select friend_respond($1,false)',[id]));
  assert.equal((await as(A,list)).filter(r=>r.nickname==='찰리').length,0);
  assert.equal(await as(C,()=>request('알파')),'requested');
  const id2=(await as(A,list)).find(r=>r.relation==='incoming').friendship_id;
  await as(C,()=>q('select friend_remove($1)',[id2]));
  assert.equal((await as(A,list)).filter(r=>r.nickname==='찰리').length,0,'sender can cancel');
});
await test('either side can unfriend; strangers cannot; repeated removal is harmless',async()=>{
  const id=(await as(A,list)).find(r=>r.nickname==='브라보').friendship_id;
  await as(C,()=>q('select friend_remove($1)',[id]));
  assert.equal((await as(A,list)).filter(r=>r.nickname==='브라보').length,1,'stranger removal does nothing');
  await as(B,()=>q('select friend_remove($1)',[id]));
  await as(B,()=>q('select friend_remove($1)',[id]));
  assert.equal((await as(A,list)).filter(r=>r.nickname==='브라보').length,0);
  assert.equal((await as(A,presence)).length,0,'no longer a friend, check-in hidden');
});
await test('blocking hides a friendship, hides check-ins and stops new requests without revealing the block',async()=>{
  await befriend(A,B,'브라보');
  assert.equal((await as(A,presence)).length,1);
  await db.query(`insert into public.user_blocks values('${A}','${B}')`);
  assert.equal((await as(A,presence)).length,0,'blocker no longer sees');
  assert.equal((await as(B,presence)).length,0,'blocked person no longer sees either');
  assert.equal((await as(A,list)).filter(r=>r.nickname==='브라보').length,0);
  const msg=await as(B,async()=>{try{await request('알파');}catch(e){return e.message;}});
  const unknown=await as(B,async()=>{try{await request('없는사람');}catch(e){return e.message;}});
  assert.equal(msg,unknown,'blocked message matches unknown-nickname message');
  await db.query(`delete from public.user_blocks`);
  assert.equal((await as(A,presence)).length,1,'unblock restores sharing');
});
await test('outgoing pending requests are capped at 30',async()=>{
  const ids=[];
  for(let i=0;i<31;i++){const id=`10000000-0000-0000-0000-${String(i).padStart(12,'0')}`;ids.push(id);
    await db.query('insert into auth.users values($1)',[id]);await db.query('insert into public.profiles values($1,$2,null,null)',[id,`이웃${i}`]);}
  await as(D,async()=>{
    for(let i=0;i<30;i++)await request(`이웃${i}`);
    await denied(()=>request('이웃30'),/너무 많아요/);
  });
});
await test('deleting an account removes friendships, settings and the person from lists',async()=>{
  await as(B,()=>q('select friend_share_set(false)'));
  await db.query(`delete from public.profiles where id='${B}'`);
  await db.query(`delete from auth.users where id='${B}'`);
  assert.equal((await q(`select count(*)::int c from public.friendships where '${B}' in (requester_id,addressee_id)`))[0].c,0);
  assert.equal((await q(`select count(*)::int c from public.friend_settings where user_id='${B}'`))[0].c,0);
  assert.equal((await as(A,list)).filter(r=>r.nickname==='브라보').length,0);
});
console.log(`${count} tests passed`);
