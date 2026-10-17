import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHandler } from '../supabase/functions/facility-search/handler.ts';

const values = { SUPABASE_URL: 'https://supabase.invalid', SUPABASE_ANON_KEY: 'public-test-key', NAVER_SEARCH_CLIENT_ID: 'server-id', NAVER_SEARCH_CLIENT_SECRET: 'server-secret' };
function fixture({ authStatus = 200, upstreamStatus = 200, fail = false, env = values } = {}) {
  const calls = [];
  const handler = createHandler({ env: key => env[key], fetch: async (url, init) => {
    calls.push({ url: String(url), init });
    if (fail) throw new Error('private upstream information');
    return String(url).endsWith('/auth/v1/user')
      ? Response.json(authStatus === 200 ? { id: 'test-user', role: 'authenticated' } : { message: 'invalid' }, { status: authStatus })
      : Response.json(upstreamStatus === 200 ? { items: [{ title: '복지관' }] } : { error: 'private upstream information' }, { status: upstreamStatus });
  }});
  return { calls, handler };
}
function request(body = { query: '중구 병원' }, token = 'test-session') {
  return new Request('https://supabase.invalid/functions/v1/facility-search', { method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body) });
}
test('missing session never calls Auth or NAVER', async () => {
  const { handler, calls } = fixture(); assert.equal((await handler(request({}, null))).status, 401); assert.equal(calls.length, 0);
});
test('invalid session cannot consume NAVER quota', async () => {
  const { handler, calls } = fixture({ authStatus: 401 }); assert.equal((await handler(request())).status, 401); assert.equal(calls.length, 1);
});
test('valid session calls fixed NAVER endpoint with server-only credentials', async () => {
  const { handler, calls } = fixture(); const result = await handler(request());
  assert.equal(result.status, 200); assert.deepEqual(await result.json(), { items: [{ title: '복지관' }] });
  const url = new URL(calls[1].url); assert.equal(url.origin, 'https://naverapihub.apigw.ntruss.com'); assert.equal(url.searchParams.get('query'), '중구 병원'); assert.equal(url.searchParams.get('display'), '5');
  assert.equal(calls[1].init.headers['X-NCP-APIGW-API-KEY'], 'server-secret'); assert(!JSON.stringify(await (await handler(request())).json()).includes('server-secret'));
});
test('empty and excessive queries rejected before NAVER', async () => {
  for (const query of ['', 'x'.repeat(121), 7]) { const { handler, calls } = fixture(); assert.equal((await handler(request({ query }))).status, 400); assert.equal(calls.length, 1); }
});
test('malformed JSON returns useful client error', async () => {
  const { handler } = fixture(); assert.equal((await handler(new Request('https://supabase.invalid', { method: 'POST', headers: { Authorization: 'Bearer test' }, body: '{' }))).status, 400);
});
test('upstream quota failure remains distinguishable', async () => {
  const { handler } = fixture({ upstreamStatus: 429 }); assert.equal((await handler(request())).status, 429);
});
test('upstream failure does not expose private response', async () => {
  const { handler } = fixture({ upstreamStatus: 403 }); const result = await handler(request()); assert.equal(result.status, 502); assert(!(await result.text()).includes('private'));
});
test('network and auth outages are retryable', async () => {
  assert.equal((await fixture({ fail: true }).handler(request())).status, 503);
  assert.equal((await fixture({ authStatus: 503 }).handler(request())).status, 503);
});
test('missing deployment secrets gives prepared response', async () => {
  const { handler, calls } = fixture({ env: {} }); assert.equal((await handler(request())).status, 503); assert.equal(calls.length, 0);
});
test('preflight supported and other HTTP methods rejected', async () => {
  const { handler, calls } = fixture(); assert.equal((await handler(new Request('https://supabase.invalid', { method: 'OPTIONS' }))).status, 200); assert.equal((await handler(new Request('https://supabase.invalid'))).status, 405); assert.equal(calls.length, 0);
});
