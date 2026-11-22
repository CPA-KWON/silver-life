type Dependencies = {
  env: (key: string) => string | undefined;
  fetch: typeof fetch;
};

// 'nearby' (category buttons, generic words): nearest-first within 5km.
// 'accuracy' (typed names): best match nationwide, x/y only for distances.
type Nearby = { keyword: string; lat: number; lng: number; group?: string; mode: 'nearby' | 'accuracy' };

// Only Korean coordinates and the hospital/pharmacy group codes are accepted.
function parseNearby(value: unknown): Nearby | null {
  if (!value || typeof value !== 'object') return null;
  const { keyword, lat, lng, group, mode = 'nearby' } = value as Record<string, unknown>;
  if (typeof keyword !== 'string' || !keyword.trim() || keyword.length > 60) return null;
  if (typeof lat !== 'number' || !(lat >= 33 && lat <= 39)) return null;
  if (typeof lng !== 'number' || !(lng >= 124 && lng <= 132)) return null;
  if (group !== undefined && group !== 'HP8' && group !== 'PM9') return null;
  if (mode !== 'nearby' && mode !== 'accuracy') return null;
  return { keyword: keyword.trim(), lat, lng, group, mode };
}

// Kakao places in the requested order, or null so the caller falls back to NAVER.
async function kakaoNearby(fetcher: typeof fetch, key: string, nearby: Nearby) {
  try {
    const upstream = new URL('https://dapi.kakao.com/v2/local/search/keyword.json');
    upstream.searchParams.set('query', nearby.keyword);
    upstream.searchParams.set('x', String(nearby.lng));
    upstream.searchParams.set('y', String(nearby.lat));
    if (nearby.mode === 'nearby') {
      upstream.searchParams.set('radius', '5000');
      upstream.searchParams.set('sort', 'distance');
    } else {
      upstream.searchParams.set('sort', 'accuracy');
    }
    upstream.searchParams.set('size', '15');
    if (nearby.group) upstream.searchParams.set('category_group_code', nearby.group);
    const result = await fetcher(upstream, {
      headers: { Authorization: `KakaoAK ${key}` },
      signal: AbortSignal.timeout(5000),
    });
    if (!result.ok) return null;
    const data = await result.json();
    if (!Array.isArray(data.documents)) return null;
    return data.documents.map((d: Record<string, string>) => ({
      name: String(d.place_name ?? ''),
      category: String(d.category_name ?? ''),
      address: String(d.road_address_name || d.address_name || ''),
      telephone: String(d.phone ?? ''),
      lat: Number(d.y),
      lng: Number(d.x),
    })).filter((p: { name: string; lat: number; lng: number }) =>
      p.name && Number.isFinite(p.lat) && Number.isFinite(p.lng));
  } catch {
    return null;
  }
}

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Dependency injection lets tests verify authentication and upstream failures
// without using a real account, key, or NAVER quota.
export function createHandler(deps: Dependencies) {
  return async (request: Request): Promise<Response> => {
    const reply = (status: number, data: unknown) => new Response(JSON.stringify(data), {
      status, headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    });
    if (request.method === 'OPTIONS') return new Response(null, { headers: cors });
    if (request.method !== 'POST') return reply(405, { error: 'POST 요청이 필요합니다.' });
    const authorization = request.headers.get('Authorization') ?? '';
    if (!/^Bearer \S+$/i.test(authorization)) return reply(401, { error: '로그인이 필요합니다.' });
    const url = deps.env('SUPABASE_URL');
    const anon = deps.env('SUPABASE_ANON_KEY');
    const clientId = deps.env('NAVER_SEARCH_CLIENT_ID');
    const secret = deps.env('NAVER_SEARCH_CLIENT_SECRET');
    if (!url || !anon || !clientId || !secret) return reply(503, { error: '시설 검색을 준비 중입니다.' });
    try {
      // Ask Auth to verify the user's actual session; a public project key
      // or an unsigned JWT must never authorize paid upstream requests.
      const auth = await deps.fetch(`${url}/auth/v1/user`, {
        headers: { Authorization: authorization, apikey: anon },
        signal: AbortSignal.timeout(5000),
      });
      if (!auth.ok) return reply(auth.status >= 500 ? 503 : 401, { error: '로그인을 확인해 주세요.' });
      const user = await auth.json();
      if (!user.id || user.role !== 'authenticated') return reply(401, { error: '로그인이 필요합니다.' });
      if (Number(request.headers.get('Content-Length')) > 4096) return reply(413, { error: '검색어가 너무 깁니다.' });
      const rawBody = await request.text();
      if (rawBody.length > 4096) return reply(413, { error: '검색어가 너무 깁니다.' });
      let body;
      try { body = JSON.parse(rawBody); } catch { return reply(400, { error: '검색어를 확인해 주세요.' }); }
      const query = typeof body?.query === 'string' ? body.query.trim() : '';
      if (!query || query.length > 120) return reply(400, { error: '검색어를 확인해 주세요.' });
      // Kakao terms allow live display only, never storage: the app marks
      // these places and resolves them through NAVER before saving any.
      const nearby = parseNearby(body?.nearby);
      const kakaoKey = deps.env('KAKAO_REST_API_KEY');
      if (nearby && kakaoKey) {
        const places = await kakaoNearby(deps.fetch, kakaoKey, nearby);
        if (places) return reply(200, { source: 'kakao', places });
      }
      const upstream = new URL('https://naverapihub.apigw.ntruss.com/search/v1/local');
      upstream.searchParams.set('query', query);
      upstream.searchParams.set('display', '5');
      const result = await deps.fetch(upstream, {
        headers: { 'X-NCP-APIGW-API-KEY-ID': clientId, 'X-NCP-APIGW-API-KEY': secret },
        signal: AbortSignal.timeout(8000),
      });
      if (result.status === 429) return reply(429, { error: '잠시 후 다시 시도해 주세요.' });
      if (!result.ok) return reply(502, { error: '시설을 불러오지 못했어요.' });
      const data = await result.json();
      if (!Array.isArray(data.items)) return reply(502, { error: '시설 정보를 확인하지 못했어요.' });
      return reply(200, { items: data.items });
    } catch {
      return reply(503, { error: '시설 검색 연결을 확인해 주세요.' });
    }
  };
}
