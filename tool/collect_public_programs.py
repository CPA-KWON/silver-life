"""Collect public factual course metadata; never enroll or create partner agencies.

python3 tool/collect_public_programs.py --output data/public_programs_20261030.json
Public HTML only, bounded pagination, sequential requests and a disk cache.
No posters, descriptions, personal names, accounts or applicant data are copied.
"""
import argparse
import datetime as dt
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import time
import urllib.parse
import urllib.request

CENTERS = dict(djc='동작', gnc='관악', sch='서초', ysc='용산',
               gch='금천', sdc='성동', gsc='강서', gdc='강동', ycp='양천',
               sdm='서대문', nwc='노원', sbc='성북', ddc='동대문', gbc='강북')
CACHE = Path('/private/tmp/silver-public-source')
KST = dt.timezone(dt.timedelta(hours=9))

def text(markup):
    markup = re.sub(r'<(?:script|style)\b.*?</(?:script|style)>', '', markup, flags=re.S)
    markup = re.sub(r'<[^>]*>', ' ', markup)
    return re.sub(r'\s+', ' ', html.unescape(markup)).strip()

class Nodes(HTMLParser):
    def __init__(self, markup):
        super().__init__(); self.root = {'tag':'root','attrs':{},'children':[]}; self.stack=[self.root]
        self.feed(markup)
    def handle_starttag(self, tag, attrs):
        node={'tag':tag,'attrs':dict(attrs),'children':[]};self.stack[-1]['children'].append(node)
        if tag not in ['input','br','img','meta','link','hr','wbr','source']:self.stack.append(node)
    def handle_endtag(self, tag):
        for i in range(len(self.stack)-1,0,-1):
            if self.stack[i]['tag']==tag:self.stack=self.stack[:i];break
    def handle_data(self,data):self.stack[-1]['children'].append(data)

def nodes(n, tag=None, cls=None):
    if isinstance(n,str):return
    if (tag is None or n['tag']==tag) and (cls is None or cls in n['attrs'].get('class','').split()):yield n
    for c in n['children']:yield from nodes(c,tag,cls)

def plain(n):
    if isinstance(n,str):return n
    return ' '.join(plain(c) for c in n['children'])

def clean(n):return re.sub(r'\s+',' ',plain(n)).strip()
def dates(s):return re.findall(r'(20\d{2})[.\-/](\d{1,2})[.\-/](\d{1,2})',s)
def iso_date(parts):return dt.date(*map(int,parts)).isoformat()

def fetch(url):
    name=re.sub(r'[^A-Za-z0-9.-]','_',urllib.parse.urlsplit(url).path+'_'+urllib.parse.urlsplit(url).query)
    file=CACHE/(name+'.html');CACHE.mkdir(parents=True,exist_ok=True)
    if file.exists() and time.time()-file.stat().st_mtime<3600:return file.read_text()
    request=urllib.request.Request(url,headers={'User-Agent':'SilverLifePublicCatalog/1.0 (public course facts; no login)'})
    with urllib.request.urlopen(request,timeout=15) as response:data=response.read().decode('utf-8')
    file.write_text(data);time.sleep(.15);return data

def parse_list(markup, base):
    out=[]
    for row in nodes(Nodes(markup).root,'tr'):
        links=[a for a in nodes(row,'a') if 'education-detail.do?id=' in a['attrs'].get('href','')]
        if not links:continue
        link=links[0];fields={}
        for td in nodes(row,'td'):
            labels=list(nodes(td,'label'))
            if labels:
                label=clean(labels[0]);fields[label.replace(':','').strip()]=clean(td).removeprefix(label).strip()
        out.append({'url':urllib.parse.urljoin(base,html.unescape(link['attrs']['href'])),
                    'state':clean(link),'fields':fields})
    return out

def parse_detail(markup):
    root=Nodes(markup).root
    application=list(nodes(root,cls='application-box'))
    result={'phone':None,'rooms':[],'slots':[],'preparations':[],'state':None}
    for node in nodes(root,'a'):
        href=node['attrs'].get('href','')
        if href.startswith('tel:') and re.fullmatch(r'[0-9+()\- ]+',href[4:]):
            result['phone']=href[4:];break
    if result['phone'] and re.fullmatch(r'\d{4}-\d{4}',result['phone']):
        # These are Seoul centers and the same page's official footer has 02.
        if re.search(r'tel:[\s]*02-',markup):result['phone']='02-'+result['phone']
    if application:
        result['state']='closed' if '신청마감' in clean(application[0]) else (
            'open' if any('education-apply.do' in a['attrs'].get('href','') and clean(a)=='수강신청'
                          for a in nodes(application[0],'a')) else 'unknown')
    for table in nodes(root,'table'):
        if '교육일정' not in clean(table) and not any('일시' in clean(th) for th in nodes(table,'th')):continue
        for row in nodes(table,'tr'):
            cells=list(nodes(row,'td'))
            if len(cells)<5:continue
            result['slots'].append(clean(cells[0]).removeprefix('일시 :').strip())
            result['rooms'].append(clean(cells[1]).removeprefix('장소 :').strip())
            result['preparations'].append(clean(cells[-1]).removeprefix('준비물 :').strip())
    # Explicit restrictions in text only; image-only eligibility is not guessed.
    info=' '.join(clean(n) for n in nodes(root,cls='course-info'))
    restrictions=[]
    for pattern in [r'여성\s*대상',r'남성\s*대상',r'만\s*\d{2}\s*세\s*이상',r'\d{2}\s*~\s*\d{2}\s*세']:
        restrictions.extend(re.findall(pattern,info))
    result['restrictions']=list(dict.fromkeys(restrictions))
    for k in ['rooms','preparations']:result[k]=list(dict.fromkeys(result[k]))
    return result

def category(title):
    if re.search(r'투자|절세|재무|상속|금융|부자|보험|부동산',title):return '생활·기술'
    if re.search(r'AI|디지털|스마트폰|SNS|인스타|컴퓨터|챗|영어|일본어|중국어',title,re.I):return '배움·디지털'
    if re.search(r'건강|운동|요가|댄스|걷기|경락|명상|치매|심리|마음|호흡|체조|스트레칭',title):return '건강·운동'
    if re.search(r'노래|팝송|음악|캐럴|합창|미술|공예|그림|사진|뜨개|악기|우쿨|여행|커피|바리스타|캘리|라떼|영화',title):return '문화·취미'
    if re.search(r'취업|경비|돌봄|청소|클리닝|정리|수납|창업|자격|도우미|리빙|강사|직무|도배',title):return '생활·기술'
    return '배움·디지털'

def collect(today):
    out=[];excluded=[];errors=[];checked=dt.datetime.now(KST).isoformat()
    for code,district in CENTERS.items():
        seen=set();count=0
        for page in range(1,21):
            url=f'https://www.50plus.or.kr/{code}/education.do?state=JOIN&page={page}'
            try:listing=parse_list(fetch(url),url)
            except Exception as e:errors.append({'url':url,'error':type(e).__name__});break
            unseen=[r for r in listing if r['url'] not in seen]
            if not unseen:break
            for item in unseen:
                seen.add(item['url']);f=item['fields'];period=dates(f.get('모집기간',''));education=dates(f.get('교육기간',''))
                reason=None
                if item['state']!='수강신청':reason='source_not_open'
                elif len(period)!=2 or len(education)!=2:reason='incomplete_dates'
                elif iso_date(period[-1])<today:reason='deadline_passed'
                elif iso_date(period[0])>today:reason='not_started'
                elif iso_date(education[-1])<today:reason='course_ended'
                if reason:excluded.append({'url':item['url'],'reason':reason});continue
                try:detail=parse_detail(fetch(item['url']))
                except Exception as e:errors.append({'url':item['url'],'error':type(e).__name__});continue
                if detail['state']!='open':excluded.append({'url':item['url'],'reason':'detail_not_open'});continue
                title=f.get('제목','').strip()
                if not title:excluded.append({'url':item['url'],'reason':'no_title'});continue
                out.append({'facility_name':district+'50플러스센터','source':'50plus_'+code,
                    'source_id':int(urllib.parse.parse_qs(urllib.parse.urlsplit(item['url']).query)['id'][0]),
                    'title':title,'service_group':f.get('소분류'),'category':category(title),
                    'description':None,'schedule':(detail['slots'][0]+f" · 총 {len(detail['slots'])}회") if detail['slots'] else f.get('교육기간'),
                    'period':f.get('교육기간'),'target':' · '.join(detail['restrictions']) or '세부 참여 조건은 기관 원문에서 확인해 주세요',
                    'fee':f.get('수강료'),'is_free':f.get('수강료')=='0원',
                    'capacity':int(f['정원']) if f.get('정원','').isdigit() else None,
                    'place':' / '.join(detail['rooms']) or None,
                    'how_to_apply':'기관 공식 홈페이지에서 수강신청 · 기관 회원가입이 필요할 수 있어요',
                    'note':'공식 공개 강좌 정보를 요약한 안내입니다. 실시간 잔여석·신청 확정·앱 참여 보상은 기관 연동 전까지 제공하지 않습니다.',
                    'source_url':item['url'],'source_verified_at':checked,'source_status':'open',
                    'registration_starts_on':iso_date(period[0]),'registration_ends_on':iso_date(period[-1]),
                    'program_ends_on':iso_date(education[-1]),'contact_phone':detail['phone'],
                    'location_is_offsite':not detail['rooms'] or bool(re.search(r'외부|탐방|현장|한강|나들이|산책|걷기|견학|출구|인근|일대|숲|온라인|ZOOM|zoom|유튜브|박물관|아트홀|그린푸줏간|대학교|뉴시니어센터', ' / '.join(detail['rooms']))),
                    'preparations':' / '.join(detail['preparations']) or None})
                count+=1
        print(f'{district}: {count} verified open',flush=True)
    return {'checked_at':checked,'as_of':today,'scope':'서울 50플러스센터 공개 접수 강좌',
            'programs':out,'excluded':excluded,'errors':errors}

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True)
    parser.add_argument('--as-of',default=dt.datetime.now(KST).date().isoformat());args=parser.parse_args()
    result=collect(args.as_of);path=Path(args.output);path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'included':len(result['programs']),'excluded':len(result['excluded']),'errors':len(result['errors'])}))
