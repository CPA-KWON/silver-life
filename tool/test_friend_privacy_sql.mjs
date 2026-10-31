import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
// Offline, isolated PostgreSQL validation. No app secrets or network access.
// Run: PGLITE_MODULE=/absolute/path/to/@electric-sql/pglite/dist/index.js node tool/test_friend_privacy_sql.mjs
const modulePath=process.env.PGLITE_MODULE;
if(!modulePath)throw new Error('Set PGLITE_MODULE to the local PGlite module path.');
const {PGlite}=await import(pathToFileURL(modulePath).href);
const db=new PGlite();const root=fileURLToPath(new URL('../',import.meta.url));
const read=n=>readFile(root+'supabase/'+n,'utf8'),q=async(s,a=[])=>(await db.query(s,a)).rows;
const A='00000000-0000-4000-8000-00000000000a',B='00000000-0000-4000-8000-00000000000b',C='00000000-0000-4000-8000-00000000000c',D='00000000-0000-4000-8000-00000000000d';
async function as(user,f){await db.exec('set role authenticated');await q("select set_config('request.jwt.claim.sub',$1,false)",[user]);try{return await f();}finally{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub','',false)");}}
const share=u=>as(u,async()=>(await q('select friend_share_get() v'))[0].v);
const asked=u=>as(u,async()=>(await q('select friend_share_asked() v'))[0].v);
const setShare=(u,v)=>as(u,()=>q('select friend_share_set($1)',[v]));
const sees=u=>as(u,async()=>(await q('select nickname from friends_presence()')).map(r=>r.nickname).sort());
async function befriend(from,to,toNick){await as(from,()=>q('select friend_request($1)',[toNick]));const id=(await as(to,()=>q('select * from friend_list()'))).find(r=>r.relation==='incoming').friendship_id;await as(to,()=>q('select friend_respond($1,true)',[id]));}

await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;grant usage on schema public to authenticated,anon;
insert into auth.users values('${A}'),('${B}'),('${C}'),('${D}');
create table public.profiles(id uuid primary key references auth.users on delete cascade,nickname text not null unique,region_sido text,region_sigungu text);
insert into public.profiles values('${A}','알파','서울특별시','강남구'),('${B}','브라보','서울특별시','서초구'),('${C}','찰리','부산광역시','해운대구'),('${D}','델타','대구광역시','수성구');
create table public.facilities(id uuid primary key default gen_random_uuid(),name text not null,address text not null);
insert into public.facilities(name,address) values('경로당','서울');
create table public.checkins(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles on delete cascade,facility_id uuid not null references public.facilities on delete cascade,checked_in_at timestamptz not null default now(),unique(user_id,facility_id));
create table public.user_blocks(user_id uuid not null references auth.users on delete cascade,blocked_id uuid not null references auth.users on delete cascade,primary key(user_id,blocked_id));`);
await db.exec(await read('friends.sql'));

// Before: A chose to share, B has no settings row (treated as sharing), C chose not to.
await setShare(A,true);await setShare(C,false);
await befriend(A,D,'델타');await befriend(B,D,'델타');await befriend(C,D,'델타');
for(const u of [A,B,C])await q("insert into checkins(user_id,facility_id) select $1,id from facilities",[u]);
assert.deepEqual(await sees(D),['브라보','알파']);

await db.exec(await read('friend_privacy_default.sql'));

// After: everyone is hidden, including members with no settings row.
assert.deepEqual(await sees(D),[]);
for(const u of [A,B,C,D]){assert.equal(await share(u),false);assert.equal(await asked(u),false);}
assert.equal(Number((await q('select count(*) c from friend_settings where share_presence'))[0].c),0);

// Choosing yes shows only that person, only to accepted friends, and records the question.
await setShare(A,true);
assert.equal(await share(A),true);assert.equal(await asked(A),true);
assert.deepEqual(await sees(D),['알파']);
assert.deepEqual(await sees(B),[]); // B and A are not friends
// Choosing no also counts as answered.
await setShare(B,false);
assert.equal(await share(B),false);assert.equal(await asked(B),true);
assert.deepEqual(await sees(D),['알파']);

// Re-running must not wipe people's choices.
await db.exec(await read('friend_privacy_default.sql'));
assert.equal(await share(A),true);assert.equal(await asked(A),true);
assert.deepEqual(await sees(D),['알파']);

// New settings rows default to hidden.
await db.exec("insert into auth.users values('00000000-0000-4000-8000-00000000000e')");
await q("insert into friend_settings(user_id) values('00000000-0000-4000-8000-00000000000e')");
assert.equal((await q("select share_presence s,share_asked a from friend_settings where user_id='00000000-0000-4000-8000-00000000000e'"))[0].s,false);

// Blocks still hide a sharing friend.
await q('insert into user_blocks values($1,$2)',[D,A]);
assert.deepEqual(await sees(D),[]);
await q('delete from user_blocks');

// Closed to logged-out visitors; the table stays closed to the app.
await db.exec('set role anon');await assert.rejects(()=>q('select friend_share_asked()'));await assert.rejects(()=>q('select friend_share_set(true)'));await db.exec('reset role');
await as(A,async()=>{await assert.rejects(()=>q('select * from friend_settings'));});
const [check]=await q(`select pg_get_expr(ad.adbin,ad.adrelid) d from pg_attrdef ad join pg_attribute a on a.attrelid=ad.adrelid and a.attnum=ad.adnum where ad.adrelid='public.friend_settings'::regclass and a.attname='share_presence'`);
assert.equal(check.d,'false');

// Account deletion is not blocked.
await q('delete from auth.users where id=$1',[A]);
assert.equal((await q('select * from friend_settings where user_id=$1',[A])).length,0);
await db.close();
console.log('friend privacy isolated database checks passed');
