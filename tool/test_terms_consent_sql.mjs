import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
// Offline, isolated PostgreSQL validation. No app secrets or network access.
// Run: PGLITE_MODULE=/absolute/path/to/@electric-sql/pglite/dist/index.js node tool/test_terms_consent_sql.mjs
const modulePath=process.env.PGLITE_MODULE;
if(!modulePath)throw new Error('Set PGLITE_MODULE to the local PGlite module path.');
const {PGlite}=await import(pathToFileURL(modulePath).href);
const db=new PGlite();const root=fileURLToPath(new URL('../',import.meta.url));
const read=n=>readFile(root+'supabase/'+n,'utf8'),q=async(s,a=[])=>(await db.query(s,a)).rows;
const id=n=>`00000000-0000-4000-8000-00000000000${n}`;
const [existing,newcomer,noMeta,badMeta]=[1,2,3,4].map(id);
async function as(user,f){await db.exec('set role authenticated');await q("select set_config('request.jwt.claim.sub',$1,false)",[user]);try{return await f();}finally{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub','',false)");}}
const addUser=(user,meta)=>q('insert into auth.users(id,raw_user_meta_data) values($1,$2)',[user,meta]);
const accepted=(user,v)=>as(user,async()=>(await q('select terms_accepted($1) r',[v]))[0].r);

await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,raw_user_meta_data jsonb);create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;grant usage on schema auth to authenticated;`);
await addUser(existing,{nickname:'기존'}); // joined before the SQL ran
await db.exec(await read('terms_consent.sql'));
await db.exec(await read('terms_consent.sql')); // re-run must be safe

// Existing member: not agreed until they accept, and only for that version.
assert.equal(await accepted(existing,'v1'),false);
await as(existing,()=>q('select accept_terms($1)',['v1']));
await as(existing,()=>q('select accept_terms($1)',['v1'])); // twice is fine
assert.equal(await accepted(existing,'v1'),true);
assert.equal(await accepted(existing,'v2'),false);
assert.equal((await q('select * from user_consents where user_id=$1',[existing])).length,2);

// New signup: recorded by the trigger with no session.
await addUser(newcomer,{terms_version:'v1'});
assert.equal(await accepted(newcomer,'v1'),true);
const rows=await q('select document from user_consents where user_id=$1 order by document',[newcomer]);
assert.deepEqual(rows.map(r=>r.document),['privacy','terms']);

// Signups without or with a bad version still succeed; they are asked later.
await addUser(noMeta,{nickname:'메타없음'});
assert.equal(await accepted(noMeta,'v1'),false);
await addUser(badMeta,{terms_version:'x'.repeat(50)});
assert.equal(await accepted(badMeta,'v1'),false);
assert.equal((await q('select * from auth.users where id=$1',[badMeta])).length,1);
await as(noMeta,async()=>{await assert.rejects(()=>q('select accept_terms($1)',['x'.repeat(50)]),/check/);});

// Only your own record: no parameter names another user, and the table is closed.
await as(noMeta,async()=>{
 await assert.rejects(()=>q('select * from user_consents'));
 await assert.rejects(()=>q("insert into user_consents(user_id,document,version) values($1,'terms','v1')",[existing]));
 await q('select accept_terms($1)',['v9']);
});
assert.equal(await accepted(existing,'v9'),false);
await db.exec('set role anon');
await assert.rejects(()=>q('select accept_terms($1)',['v1']));
await assert.rejects(()=>q('select terms_accepted($1)',['v1']));
await assert.rejects(()=>q('select record_signup_consent()'));
await db.exec('reset role');

// Account deletion cleans up and is not blocked.
await q('delete from auth.users where id=$1',[newcomer]);
assert.equal((await q('select * from user_consents where user_id=$1',[newcomer])).length,0);
await db.close();
console.log('terms consent isolated database checks passed');
