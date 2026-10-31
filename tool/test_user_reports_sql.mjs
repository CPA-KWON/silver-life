import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
// Offline, isolated PostgreSQL validation. No app secrets or network access.
// Run: PGLITE_MODULE=/absolute/path/to/@electric-sql/pglite/dist/index.js node tool/test_user_reports_sql.mjs
const modulePath=process.env.PGLITE_MODULE;
if(!modulePath)throw new Error('Set PGLITE_MODULE to the local PGlite module path.');
const {PGlite}=await import(pathToFileURL(modulePath).href);
const db=new PGlite();const root=fileURLToPath(new URL('../',import.meta.url));
const read=n=>readFile(root+'supabase/'+n,'utf8'),q=async(s,a=[])=>(await db.query(s,a)).rows;
const id=n=>`00000000-0000-4000-8000-00000000000${n}`;
const [a,b,c]=[1,2,3].map(id);
async function as(user,f){await db.exec('set role authenticated');await q("select set_config('request.jwt.claim.sub',$1,false)",[user]);try{return await f();}finally{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub','',false)");}}
const report=(from,name,reason='광고')=>as(from,()=>q('select report_user($1,$2)',[name,reason]));
const count=async()=>Number((await q('select count(*) c from user_reports'))[0].c);

await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;grant usage on schema auth to authenticated;create table public.profiles(id uuid primary key references auth.users on delete cascade,name text,birth_year int,nickname text unique);`);
for(const [i,user] of [a,b,c].entries()){await q('insert into auth.users values($1)',[user]);await q('insert into profiles values($1,$2,1960,$3)',[user,'실명'+i,'이웃'+i]);}
await db.exec(await read('user_reports.sql'));
await db.exec(await read('user_reports.sql')); // re-run must be safe

await report(a,'이웃1');
assert.equal(await count(),1);
const [row]=await q('select * from user_reports');
assert.equal(row.reporter_id,a);assert.equal(row.reported_id,b);assert.equal(row.reason,'광고');

// Same person twice refused with the duplicate code the app recognises, even with another reason.
await assert.rejects(()=>report(a,'이웃1','기타'),e=>e.code==='23505');
assert.equal(await count(),1);
// Different reporter or different target is fine.
await report(c,'이웃1','사기 의심');await report(a,'이웃2','음란·불쾌한 내용');
assert.equal(await count(),3);

await assert.rejects(()=>report(a,'이웃0'),/나를 신고/);
await assert.rejects(()=>report(a,'없는이웃'),/찾을 수 없어요/);
await assert.rejects(()=>report(b,'이웃0','없는 사유'),/check/);
assert.equal(await count(),3);

// Reports stay private: table and summary closed to members and logged-out visitors.
await as(a,async()=>{
 await assert.rejects(()=>q('select * from user_reports'));
 await assert.rejects(()=>q('select * from user_report_summary'));
 await assert.rejects(()=>q("insert into user_reports(reporter_id,reported_id,reason) values($1,$2,'광고')",[a,c]));
 await assert.rejects(()=>q('delete from user_reports'));
});
await db.exec('set role anon');await assert.rejects(()=>q("select report_user('이웃1','광고')"));await assert.rejects(()=>q('select * from user_report_summary'));await db.exec('reset role');

// Team view shows who and how many.
const summary=await q("select * from user_report_summary where 신고된_사용자='이웃1'");
assert.equal(summary.length,2);assert.equal(Number(summary[0].누적_신고수),2);

// Account deletion is not blocked as reporter or reported.
await q('delete from auth.users where id=$1',[b]);
assert.equal(await count(),1);
await q('delete from auth.users where id=$1',[a]);
assert.equal(await count(),0);
await db.close();
console.log('user report isolated database checks passed');
