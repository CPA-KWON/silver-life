import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const db = new PGlite();
const user = '00000000-0000-0000-0000-000000000001';
const other = '00000000-0000-0000-0000-000000000002';
const third = '00000000-0000-0000-0000-000000000003';
const fourth = '00000000-0000-0000-0000-000000000004';
let count = 0;
async function q(sql, values = []) { return (await db.query(sql, values)).rows; }
async function as(id, fn) {
  await db.exec(`set role ${id ? 'authenticated' : 'anon'};`);
  await q("select set_config('request.jwt.claim.sub',$1,false)", [id ?? '']);
  try { return await fn(); } finally { await db.exec('reset role'); }
}
async function test(name, fn) { await fn(); console.log(`PASS ${++count} ${name}`); }
async function denied(fn) { await assert.rejects(fn); }
await db.exec(`create role anon; create role authenticated; create schema auth;
  create table auth.users(id uuid primary key, raw_user_meta_data jsonb);
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
  grant usage on schema auth to authenticated, anon;
  grant execute on function auth.uid() to authenticated, anon;`);
for (const file of ['schema.sql', 'community_schema.sql', 'facilities_schema.sql',
  'region_split.sql', 'facility_region.sql', 'facilities_rls_fix.sql', 'reports.sql']) {
  await db.exec(await readFile(new URL(`../supabase/${file}`, import.meta.url), 'utf8'));
}
await db.exec('grant usage on schema public to authenticated, anon; grant all on all tables in schema public to authenticated, anon;');
for (const [id, nickname] of [[user, '첫 회원'], [other, '다른 작성자'], [third, '셋째'], [fourth, '넷째']]) {
  await q('insert into auth.users values($1,$2)', [id, { nickname, name: '비공개 이름', birth_year: 1960, region_sido: '서울특별시', region_sigungu: '중구' }]);
}
const migration = await readFile(new URL('../supabase/integration_security.sql', import.meta.url), 'utf8');
await db.exec(migration);
await test('security migration is repeatable', () => db.exec(migration));
let facility;
const data = { name: '복지관', address: '서울특별시 중구 테스트로', lat: 37.5, lng: 127, region_sido: '서울특별시', region_sigungu: '중구' };
await test('signed-in member can register a facility', () => as(user, async () => {
  facility = (await q('select ensure_facility($1) id', [data]))[0].id;
  assert(facility);
}));
await test('reusing facility never overwrites shared coordinates', () => as(other, async () => {
  assert.equal((await q('select ensure_facility($1) id', [{ ...data, lat: 1 }]))[0].id, facility);
  assert.equal((await q('select lat from facilities where id=$1', [facility]))[0].lat, 37.5);
}));
await test('invalid coordinates are rejected', () => as(user, () => denied(() => q('select ensure_facility($1)', [{ ...data, lat: 999 }]))));
await test('anonymous facility creation is denied', () => as(null, () => denied(() => q('select ensure_facility($1)', [data]))));
await test('client cannot rewrite or delete a facility', () => as(user, async () => {
  await denied(() => q('update facilities set lat=1 where id=$1', [facility]));
  await denied(() => q('delete from facilities where id=$1', [facility]));
}));
await test('private profiles remain limited to owner', () => as(user, async () => {
  const rows = await q('select * from profiles');
  assert.equal(rows.length, 1); assert.equal(rows[0].id, user); assert.equal(rows[0].birth_year, 1960);
}));
await test('public author metadata excludes private names and birth years', () => as(user, async () => {
  const rows = await q('select * from public_profiles where id=$1', [other]);
  assert.deepEqual(Object.keys(rows[0]).sort(), ['id', 'nickname', 'region_sido', 'region_sigungu']);
  assert.equal(rows[0].nickname, '다른 작성자');
  await denied(() => q('select birth_year from public_profiles'));
}));
await test('anonymous public profile access is denied', () => as(null, () => denied(() => q('select * from public_profiles'))));
let post;
await as(other, async () => { post = (await q("insert into posts(author_id,category,title,content) values($1,'자유게시판','소식','내용') returning id", [other]))[0].id; });
await test('cross-user computed author relation preserves nickname and region filters', () => as(user, async () => {
  const rows = await q("select p.id,a.nickname from posts p cross join lateral profiles(p) a where a.region_sido='서울특별시' and a.region_sigungu='중구'");
  assert.equal(rows[0].id, post); assert.equal(rows[0].nickname, '다른 작성자');
}));
await as(other, () => q('insert into comments(post_id,author_id,content) values($1,$2,$3)', [post, other, '댓글']));
await test('comment author relation exposes only safe metadata', () => as(user, async () => {
  const rows = await q('select a.* from comments c cross join lateral profiles(c) a');
  assert.equal(rows[0].nickname, '다른 작성자'); assert(!('name' in rows[0]));
}));
await db.exec(`insert into checkins(user_id,facility_id,checked_in_at) values
  ('${user}','${facility}',now()), ('${other}','${facility}',now()-interval '1h'),
  ('${third}','${facility}',now()-interval '4h'), ('${fourth}','${facility}',now()+interval '1h');`);
await test('direct check-in reads cannot reveal other member locations', () => as(user, async () => {
  const rows = await q('select user_id from checkins'); assert.deepEqual(rows, [{ user_id: user }]);
}));
await test('presence returns active count and only my status', () => as(user, async () => {
  const result = (await q('select facility_presence($1) data', [facility]))[0].data;
  assert.deepEqual(result, { count: 2, checked_in: true });
}));
await test('expired and future check-ins never mark member present', () => as(third, async () => {
  assert.deepEqual((await q('select facility_presence($1) data', [facility]))[0].data, { count: 2, checked_in: false });
}));
await test('anonymous presence lookup is denied', () => as(null, () => denied(() => q('select facility_presence($1)', [facility]))));
await test('member cannot change another member check-in', () => as(user, async () => {
  assert.equal((await q('update checkins set checked_in_at=now() where user_id=$1 returning id', [other])).length, 0);
}));
await test('three reports hide a post while its author retains access', async () => {
  for (const id of [user, third, fourth]) await as(id, () => q("insert into reports(reporter_id,post_id,reason) values($1,$2,'기타')", [id, post]));
  await as(user, async () => assert.equal((await q('select id from posts where id=$1', [post])).length, 0));
  await as(other, async () => assert.equal((await q('select id from posts where id=$1', [post])).length, 1));
});
await db.close();
console.log(`${count} integration security checks passed`);
