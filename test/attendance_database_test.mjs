import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.env.PGLITE_MODULE??'@electric-sql/pglite');
const db=new PGlite(); let count=0;
const user='00000000-0000-0000-0000-000000000001',other='00000000-0000-0000-0000-000000000003';
async function q(sql,params=[]){return (await db.query(sql,params)).rows;}
async function as(id,fn){await db.exec(`reset role;set role authenticated;set request.jwt.claim.sub='${id}';`);try{return await fn();}finally{await db.exec('reset role');}}
async function test(name,fn){await fn();count++;console.log(`PASS ${name}`);}
async function denied(fn){let rejected=false;try{await fn();}catch{rejected=true;}assert(rejected,'expected database to reject operation');}
// Internal function lets the test pick the server "today" to simulate many days.
async function checkIn(day,id=user){return (await q(`select attendance_check_in_for('${id}','${day}'::date) r`))[0].r;}
const wallet=async(id=user)=>(await q(`select * from point_wallets where user_id='${id}'`))[0];
const plus=(base,n)=>{const d=new Date(`${base}T00:00:00Z`);d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);};
await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;grant usage on schema public to authenticated;insert into auth.users values('${user}'),('${other}');`);
const sql=await readFile(new URL('../supabase/attendance_points.sql',import.meta.url),'utf8');
await db.exec(sql);
await test('script can be re-run safely',()=>db.exec(sql));
await test('anonymous cannot check in',()=>as('',()=>denied(()=>q('select attendance_check_in()'))));
await test('client cannot call date-injecting internal function',()=>as(user,()=>denied(()=>q(`select attendance_check_in_for('${user}','2030-01-01')`))));
await test('client cannot write balance or history',()=>as(user,async()=>{
  await denied(()=>q(`insert into point_wallets(user_id,balance) values('${user}',999)`));
  await denied(()=>q(`insert into attendance_days values('${user}','2030-01-01',1,10)`));
  await denied(()=>q(`insert into point_ledger(user_id,amount,reason) values('${user}',5,'attendance')`));
}));
await test('fresh status has nothing attended',()=>as(user,async()=>{const s=(await q('select attendance_status() s'))[0].s;assert.equal(s.attended_today,false);assert.equal(s.streak,0);assert.equal(s.balance,0);}));
await test('client check-in uses server KST date once',()=>as(user,async()=>{
  const first=(await q('select attendance_check_in() r'))[0].r;
  const second=(await q('select attendance_check_in() r'))[0].r;
  assert.equal(first.already,false);assert.equal(first.points,5);
  assert.equal(second.already,true);assert.equal(second.balance,5);
  const kst=(await q(`select (now() at time zone 'Asia/Seoul')::date::text d`))[0].d;
  assert.equal(first.today,kst);
}));
await db.exec(`delete from point_ledger;delete from attendance_days;delete from point_wallets;`);
const start='2026-01-01';
await test('streak rewards replace base points on days 7, 14 and 30 across months',async()=>{
  const got=[];for(let i=0;i<31;i++)got.push((await checkIn(plus(start,i))).points);
  const expected=got.map((_,i)=>({7:15,14:25,30:50})[i+1]??5);
  assert.deepEqual(got,expected);
  const w=await wallet();assert.equal(w.current_streak,31);
  const total=expected.reduce((a,b)=>a+b,0);assert.equal(w.balance,total);assert.equal(w.total_earned,total);
  assert.equal((await q(`select count(*)::int c from attendance_days`))[0].c,31);
  assert.equal((await q(`select sum(amount)::int s from point_ledger`))[0].s,total);
});
await test('missing a day resets the streak to 1',async()=>{
  const r=await checkIn(plus(start,32));assert.equal(r.streak,1);assert.equal(r.points,5);
});
await test('status shows broken streak as 0 after a missed day',async()=>{
  const s=(await q(`select attendance_status_for('${user}','${plus(start,34)}') s`))[0].s;
  assert.equal(s.streak,0);assert.equal(s.attended_today,false);
});
await test('same day cannot be paid twice',async()=>{
  const before=(await wallet()).balance;const r=await checkIn(plus(start,32));
  assert.equal(r.already,true);assert.equal((await wallet()).balance,before);
});
await test('earlier date than last attendance is rejected',()=>denied(()=>checkIn(plus(start,10))));
await test('users only read their own rows',async()=>{
  await checkIn(start,other);
  await as(other,async()=>{
    assert.equal((await q('select * from point_wallets')).length,1);
    assert.equal((await q('select * from attendance_days')).length,1);
    assert.equal((await q('select * from point_ledger')).length,1);
  });
});
console.log(`${count} attendance database checks passed`);
