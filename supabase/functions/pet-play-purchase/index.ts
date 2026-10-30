// Gateway JWT verification remains enabled; validate the user against Auth too.
// Secrets: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON (server only), PLAY_PACKAGE_NAME.
// No secret or purchase token is logged or returned to the app.
const encoder = new TextEncoder();
function b64url(bytes: Uint8Array) {return btoa(String.fromCharCode(...bytes)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');}
let cachedToken='',expires=0;
async function accessToken() {
  if(cachedToken && Date.now()<expires)return cachedToken;
  const account=JSON.parse(Deno.env.get('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON') || '{}');
  if(!account.client_email || !account.private_key)throw Error('configuration');
  const now=Math.floor(Date.now()/1000);
  const header=b64url(encoder.encode(JSON.stringify({alg:'RS256',typ:'JWT'})));
  const payload=b64url(encoder.encode(JSON.stringify({iss:account.client_email,scope:'https://www.googleapis.com/auth/androidpublisher',aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600})));
  const der=Uint8Array.from(atob(account.private_key.replace(/-----[^-]+-----/g,'').replace(/\s/g,'')),c=>c.charCodeAt(0));
  const key=await crypto.subtle.importKey('pkcs8',der,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
  const sig=new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,encoder.encode(`${header}.${payload}`)));
  const response=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:`${header}.${payload}.${b64url(sig)}`}),signal:AbortSignal.timeout(10000)});
  if(!response.ok)throw Error('google auth');
  const body=await response.json();cachedToken=body.access_token;expires=Date.now()+Math.min(body.expires_in,3300)*1000;return cachedToken;
}
const reply=(message:string,status:number)=>Response.json({verified:false,message},{status});
Deno.serve(async(req:Request)=>{
  if(req.method!=='POST')return reply('method',405);
  const base=Deno.env.get('SUPABASE_URL'),secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),anon=Deno.env.get('SUPABASE_ANON_KEY');
  if(!base||!secret||!anon)return reply('구매 확인을 준비하고 있어요.',503);
  const authorization=req.headers.get('Authorization');if(!authorization?.startsWith('Bearer '))return reply('로그인이 필요해요.',401);
  try{
    const auth=await fetch(`${base}/auth/v1/user`,{headers:{apikey:anon,Authorization:authorization},signal:AbortSignal.timeout(8000)});
    if(!auth.ok)return reply('다시 로그인해주세요.',401);
    const user=await auth.json();
    const {token,product}=await req.json();
    if(typeof token!=='string'||token.length<5||token.length>4096||typeof product!=='string'||!/^silverlife\.(dog|cat)_[a-z_]+$/.test(product))return reply('구매 정보를 확인해주세요.',400);
    // Confirm product and runtime gate using server data, before contacting Play.
    const headers={apikey:secret,Authorization:`Bearer ${secret}`,'Content-Type':'application/json'};
    const cfg=await fetch(`${base}/rest/v1/pet_config?key=eq.play_enabled&value=eq.true&select=key`,{headers,signal:AbortSignal.timeout(8000)});
    if(!cfg.ok||(await cfg.json()).length!==1)return reply('판매를 준비하고 있어요.',503);
    const catalog=await fetch(`${base}/rest/v1/pet_item_catalog?product_id=eq.${encodeURIComponent(product)}&source=eq.play&enabled=eq.true&select=id`,{headers,signal:AbortSignal.timeout(8000)});
    if(!catalog.ok||(await catalog.json()).length!==1)return reply('상품 정보를 확인해주세요.',400);
    const google=await accessToken();
    const pkg=Deno.env.get('PLAY_PACKAGE_NAME')||'com.silverlife.app';
    const url=`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(pkg)}/purchases/products/${encodeURIComponent(product)}/tokens/${encodeURIComponent(token)}`;
    const verified=await fetch(url,{headers:{Authorization:`Bearer ${google}`},signal:AbortSignal.timeout(10000)});
    if(!verified.ok)return reply('구매를 확인하지 못했어요. 잠시 후 다시 확인해주세요.',503);
    const purchase=await verified.json();
    if(purchase.obfuscatedExternalAccountId!==user.id)return reply('이 구매는 다른 앱 계정과 연결되어 있어요.',409);
    if(purchase.purchaseState!==0)return reply('아직 완료된 구매가 아니에요.',409);
    if(purchase.consumptionState!==0)return reply('영구 소장 상품의 구매 상태를 확인해주세요.',409);
    // Grant atomically first, then acknowledge. A retry is safe if acknowledgment fails.
    const stored=await fetch(`${base}/rest/v1/rpc/pet_grant_play_purchase`,{method:'POST',headers,body:JSON.stringify({p_user:user.id,p_token:token,p_product:product,p_order:purchase.orderId??''}),signal:AbortSignal.timeout(8000)});
    if(!stored.ok)return reply('구매 저장을 확인하고 있어요. 다시 확인해주세요.',503);
    if(purchase.acknowledgementState!==1){
      const ack=await fetch(`${url}:acknowledge`,{method:'POST',headers:{Authorization:`Bearer ${google}`,'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(10000)});
      if(!ack.ok)return reply('구매 확인을 마무리하고 있어요. 다시 확인해주세요.',503);
    }
    return Response.json({verified:true});
  }catch{return reply('구매 확인 중이에요. 잠시 후 구매 복원으로 확인해주세요.',503);}
});
