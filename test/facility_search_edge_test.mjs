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

function kakaoFixture({ kakaoStatus = 200, key = 'kakao-secret' } = {}) {
  const calls = [];
  const env = { ...values, ...(key ? { KAKAO_REST_API_KEY: key } : {}) };
  const handler = createHandler({ env: k => env[k], fetch: async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith('/auth/v1/user')) return Response.json({ id: 'test-user', role: 'authenticated' });
    if (String(url).startsWith('https://dapi.kakao.com/')) {
      return kakaoStatus === 200
        ? Response.json({ documents: [{ place_name: '가까운약국', category_name: '의료,건강 > 약국', road_address_name: '서울 중구 세종대로 1', address_name: '서울 중구 태평로1가 1', phone: '02-1', x: '126.978', y: '37.566' }] })
        : Response.json({ error: 'private' }, { status: kakaoStatus });
    }
    return Response.json({ items: [{ title: '네이버약국' }] });
  }});
  return { calls, handler };
}
const nearbyBody = { query: '중구 약국', nearby: { keyword: '약국', lat: 37.56, lng: 126.97, group: 'PM9' } };
test('nearby search asks Kakao nearest-first with server-only key', async () => {
  const { handler, calls } = kakaoFixture(); const result = await handler(request(nearbyBody));
  assert.equal(result.status, 200);
  const body = await result.json(); assert.equal(body.source, 'kakao');
  assert.deepEqual(body.places[0], { name: '가까운약국', category: '의료,건강 > 약국', address: '서울 중구 세종대로 1', telephone: '02-1', lat: 37.566, lng: 126.978 });
  const url = new URL(calls[1].url); assert.equal(url.searchParams.get('sort'), 'distance'); assert.equal(url.searchParams.get('x'), '126.97'); assert.equal(url.searchParams.get('y'), '37.56'); assert.equal(url.searchParams.get('category_group_code'), 'PM9');
  assert.equal(calls[1].init.headers.Authorization, 'KakaoAK kakao-secret'); assert(!JSON.stringify(body).includes('kakao-secret'));
});
test('Kakao failure or missing key falls back to NAVER', async () => {
  for (const fixtureOptions of [{ kakaoStatus: 429 }, { kakaoStatus: 500 }, { key: '' }]) {
    const { handler } = kakaoFixture(fixtureOptions); const body = await (await handler(request(nearbyBody))).json();
    assert.equal(body.source, undefined); assert.deepEqual(body.items, [{ title: '네이버약국' }]);
  }
});
test('invalid nearby values never reach Kakao', async () => {
  for (const nearby of [{ keyword: '약국', lat: 0, lng: 126.9 }, { keyword: '', lat: 37.5, lng: 126.9 }, { keyword: '약국', lat: 37.5, lng: 126.9, group: 'XX' }, { keyword: '약국', lat: '37.5', lng: 126.9 }]) {
    const { handler, calls } = kakaoFixture(); await handler(request({ query: '약국', nearby }));
    assert(!calls.some(c => c.url.startsWith('https://dapi.kakao.com/')));
  }
});
test('category searches stay within 5km while typed names rank by accuracy', async () => {
  const sent = async nearby => { const { handler, calls } = kakaoFixture(); await handler(request({ query: '약국', nearby })); return new URL(calls[1].url).searchParams; };
  const near = await sent({ keyword: '약국', lat: 37.56, lng: 126.97 });
  assert.equal(near.get('sort'), 'distance'); assert.equal(near.get('radius'), '5000');
  const typed = await sent({ keyword: '서울대학교병원', lat: 37.56, lng: 126.97, mode: 'accuracy' });
  assert.equal(typed.get('sort'), 'accuracy'); assert.equal(typed.get('radius'), null); assert.equal(typed.get('x'), '126.97');
  const { handler, calls } = kakaoFixture(); await handler(request({ query: '약국', nearby: { keyword: '약국', lat: 37.5, lng: 126.9, mode: 'random' } }));
  assert(!calls.some(c => c.url.startsWith('https://dapi.kakao.com/')));
});
