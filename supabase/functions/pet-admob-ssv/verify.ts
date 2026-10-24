// Google AdMob SSV: preserve signed query bytes; ECDSA P-256/SHA-256, DER → P1363.
export function decode64(value: string): Uint8Array {
 const normal=value.replace(/-/g,'+').replace(/_/g,'/');
 return Uint8Array.from(atob(normal.padEnd(Math.ceil(normal.length/4)*4,'=')),c=>c.charCodeAt(0));
}
export function derSignature(der: Uint8Array): Uint8Array {
 if(der.length<8||der.length>72||der[0]!==0x30||der[1]!==der.length-2)throw Error('DER');
 let at=2;const out=new Uint8Array(64);
 for(let i=0;i<2;i++){
  if(der[at++]!==2)throw Error('DER');const length=der[at++];let part=der.slice(at,at+length);at+=length;
  if(length<1||part.length!==length||(part[0]&128))throw Error('DER');
  if(part[0]===0&&part.length>1)part=part.slice(1);
  if(part.length>32)throw Error('DER');out.set(part,32*i+32-part.length);
 }
 if(at!==der.length)throw Error('DER');return out;
}
export async function verifyCallback(url: URL,keys: {keyId: number;base64:string}[],now=Date.now()) {
 const query=url.search.slice(1);if(query.length>4096)throw Error('query');
 const parts=query.split('&');if(parts.length<3||!parts.at(-2)!.startsWith('signature=')||!parts.at(-1)!.startsWith('key_id='))throw Error('order');
 const p=url.searchParams;for(const key of new Set(p.keys()))if(p.getAll(key).length!==1)throw Error('duplicate');
 const key=keys.find(k=>String(k.keyId)===p.get('key_id'));if(!key)throw Error('key');
 const signed=parts.slice(0,-2).join('&');
 const imported=await crypto.subtle.importKey('spki',decode64(key.base64),{name:'ECDSA',namedCurve:'P-256'},false,['verify']);
 const valid=await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},imported,derSignature(decode64(p.get('signature')!)),new TextEncoder().encode(signed));
 if(!valid)throw Error('signature');
 const session=p.get('custom_data')??'',transaction=p.get('transaction_id')??'',unit=p.get('ad_unit')??'';
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(session)||!transaction||transaction.length>200||!unit)throw Error('payload');
 const timestamp=Number(p.get('timestamp'));if(!Number.isFinite(timestamp)||Math.abs(now-timestamp)>3600000)throw Error('expired');
 return {session,transaction,unit};
}
