import {verifyCallback} from '../pet-admob-ssv/verify.ts';
let cached: {keyId:number;base64:string}[]=[];let expires=0;
Deno.serve(async(req: Request)=>{
 if(req.method!=='GET')return new Response('method',{status:405});
 // Transient key/database failures must be retryable; invalid signatures must not.
 try {
  if(Date.now()>expires){
   const response=await fetch('https://www.gstatic.com/admob/reward/verifier-keys.json',{signal:AbortSignal.timeout(8000)});
   if(!response.ok)throw Error('keys');const data=await response.json();cached=data.keys;expires=Date.now()+3600000;
  }
 }catch{return new Response('key service unavailable',{status:503});}
 let verified;
 try{verified=await verifyCallback(new URL(req.url),cached);}catch{return new Response('verification failed',{status:400});}
 try{
  const base=Deno.env.get('SUPABASE_URL');const secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(!base||!secret)throw Error('configuration');
  const result=await fetch(`${base}/rest/v1/rpc/attendance_verify_ad`,{method:'POST',headers:{'apikey':secret,'Authorization':`Bearer ${secret}`,'Content-Type':'application/json'},
   body:JSON.stringify({p_session:verified.session,p_transaction:verified.transaction,p_unit:verified.unit}),signal:AbortSignal.timeout(8000)});
  return new Response(result.ok?'OK':'retry',{status:result.ok?200:503});
 }catch{return new Response('retry',{status:503});}
});
