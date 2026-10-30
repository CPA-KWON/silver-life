import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.env.PGLITE_MODULE??'@electric-sql/pglite');
const db=new PGlite();
const legacy=await readFile('supabase/welfare_programs.sql','utf8');
await db.exec(legacy.slice(legacy.indexOf('create table'),legacy.indexOf('alter table')));
await db.exec(`create role authenticated; alter table welfare_programs enable row level security;
grant select on welfare_programs to authenticated;
create policy public_read on welfare_programs for select to authenticated using(true);
insert into welfare_programs(facility_name,source,source_id,title,note) values('기존 기관','sangdo',1,'기존 프로그램','수동 편집 보존');`);
const sql=await readFile('supabase/import_public_programs_20261030.sql','utf8');
await db.exec(sql);const initial=(await db.query('select id,source,source_id from welfare_programs order by id')).rows;
assert(initial.length>1);await db.exec(sql);
assert.deepEqual((await db.query('select id,source,source_id from welfare_programs order by id')).rows,initial);
assert.equal((await db.query(`select note from welfare_programs where source='sangdo'`)).rows[0].note,'수동 편집 보존');
assert.equal((await db.query(`select count(*)::int n from welfare_programs where source_url is not null and source_url not like 'https://www.50plus.or.kr/%'`)).rows[0].n,0);
await db.exec('set role authenticated');
assert((await db.query('select count(*)::int n from welfare_programs')).rows[0].n>1);
for(const sql of [`insert into welfare_programs(facility_name,source,source_id,title) values('가짜','fake',1,'가짜')`, `update welfare_programs set title='변조'`]) {
 let denied=false;try { await db.exec(sql); } catch { denied=true; } assert(denied);
}
await db.close();console.log('PASS import idempotency, stable favorites IDs, original rows, provenance, read-only RLS');
