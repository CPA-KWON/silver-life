"""Verify center coordinates against official addresses; use existing facility RPC.

Never creates an activity_organization, membership, enrollment or reward.
Requires the local app config and an authenticated session; prints counts only.
"""
import argparse
import json
import math
from pathlib import Path
import re
import urllib.request
from collect_public_programs import fetch,Nodes,nodes,clean,text

def normalize(s):return re.sub(r'\s+|서울시|서울특별시|서울시립|시립|구립|[()]','',s)
def road(s):
    s=re.sub(r'(서울특별시|서울시|서울)\s+[가-힣]+구','',s)
    s=re.sub(r'([가-힣0-9]+로)\s+(\d+[가-힣]*길)',r'\1\2',s)
    m=re.search(r'([가-힣0-9·]+(?:로|길))\s*(\d+(?:-\d+)?)',s)
    return ''.join(m.groups()) if m else None

def same_place(matches):
    if not matches:return False
    lat=float(matches[0]['mapy'])/1e7;lng=float(matches[0]['mapx'])/1e7
    for x in matches:
        dy=math.radians(float(x['mapy'])/1e7-lat);dx=math.radians(float(x['mapx'])/1e7-lng)
        meters=6371000*2*math.asin(math.sqrt(math.sin(dy/2)**2+math.cos(math.radians(lat))*math.cos(math.radians(float(x['mapy'])/1e7))*math.sin(dx/2)**2))
        if meters>50:return False
    return True

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--data',required=True);p.add_argument('--config',required=True)
    p.add_argument('--session',required=True);p.add_argument('--output',required=True);p.add_argument('--apply',action='store_true')
    a=p.parse_args();cfg=json.loads(Path(a.config).read_text());session=json.loads(Path(a.session).read_text())
    dataset=json.loads(Path(a.data).read_text());centers={r['facility_name']:r for r in dataset['programs']}
    def request(path,data):
        r=urllib.request.Request(cfg['SUPABASE_URL']+path,data=json.dumps(data).encode(),headers={
            'apikey':cfg['SUPABASE_ANON_KEY'],'Authorization':'Bearer '+session['access_token'],'Content-Type':'application/json'})
        with urllib.request.urlopen(r,timeout=25) as f:return json.load(f)
    result=[]
    for name,r in centers.items():
        root=Nodes(fetch(r['source_url'])).root;footers=list(nodes(root,'address',cls='footer-address'))
        footer=clean(footers[0]) if footers else ''
        address=re.search(r'(?:서울특별시|서울시|서울)\s+.*?(?=사업자등록번호|대표자|전화|이메일|$)',footer)
        official=address.group(0).strip() if address else ''
        cache=Path('/private/tmp/silver-public-source')/(r['source']+'-map.json')
        if cache.exists():found=json.loads(cache.read_text())
        else:
            found=request('/functions/v1/facility-search',{'query':name})['items']
            cache.write_text(json.dumps(found,ensure_ascii=False))
        matches=[x for x in found if normalize(text(x['title']))==normalize(name)
                 and road(official) and road(x.get('roadAddress',''))==road(official)]
        if len(matches)>1 and same_place(matches):matches=matches[:1]
        entry={'name':name,'source_url':r['source_url'],'official_address':official,'verified':len(matches)==1}
        if len(matches)!=1:entry['map_candidates']=[{'name':text(x['title']),'address':x.get('roadAddress')} for x in found]
        if len(matches)==1:
            x=matches[0];lat=int(x['mapy'])/1e7;lng=int(x['mapx'])/1e7
            if not(33<lat<39 and 124<lng<132):raise ValueError('Invalid Korean coordinates')
            phones=[v['attrs']['href'][4:] for v in nodes(footers[0],'a') if v['attrs'].get('href','').startswith('tel:')]
            data={'name':name,'address':x.get('roadAddress') or x['address'],'lat':lat,'lng':lng,'category':'복지관',
                  'telephone':phones[0] if phones else None,'region_sido':'서울특별시',
                  'region_sigungu':re.search(r'서울특별시\s+(\S+구)',x['address']).group(1)}
            entry.update(data);entry['coordinate_source']='네이버 지역 검색 · 공식 도로명·건물번호 대조'
            if a.apply:entry['facility_id']=request('/rest/v1/rpc/ensure_facility',{'data':data})
        result.append(entry);print(name, 'verified' if entry['verified'] else 'manual_check_required',flush=True)
    Path(a.output).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'verified':sum(r['verified'] for r in result),'total':len(result),'applied':a.apply}))
