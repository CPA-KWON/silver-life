"""Collect factual public notice indexes; no full articles/images/private data.

Records the actual original publication day, never invents an agency account.
The current-year crawl is bounded; older pinned index entries are kept archived.
"""
import argparse
import concurrent.futures
import datetime as dt
import hashlib
import html
import json
from pathlib import Path
import re
import time
import urllib.parse
import urllib.request
import uuid
from collect_public_programs import CENTERS, Nodes, nodes, clean

KST=dt.timezone(dt.timedelta(hours=9))
CACHE=Path('/private/tmp/silver-public-notices');CACHE.mkdir(exist_ok=True)
SOURCES=[{'name':name+'50플러스센터','url':f'https://www.50plus.or.kr/{code}/notice.do',
          'district':name+'구','kind':'기타','parser':'50plus'} for code,name in CENTERS.items()]+[
 {'name':'흑석종합사회복지관','url':'https://hswelfare.kr/?state=notice','district':'동작구','kind':'복지관','parser':'table'},
 {'name':'사당어르신종합복지관','url':'https://www.sadangeorsin.or.kr/bbs/board.php?bo_table=0301','district':'동작구','kind':'복지관','parser':'table'},
 {'name':'동작노인종합복지관','url':'https://www.djsw.or.kr/bbs/?bid=notice','district':'동작구','kind':'복지관','parser':'table'},
 {'name':'동작노인종합복지관','url':'https://www.djsw.or.kr/bbs/?bid=news','district':'동작구','kind':'복지관','parser':'table'},
 {'name':'동작이수사회복지관','url':'https://www.isuwelfare.or.kr/?state=notice','district':'동작구','kind':'복지관','parser':'table'},
]

def fetch(url):
    file=CACHE/(hashlib.sha256(url.encode()).hexdigest()+'.html')
    if file.exists() and time.time()-file.stat().st_mtime<3600:return file.read_text()
    req=urllib.request.Request(url,headers={'User-Agent':'SilverLifePublicNotice/1.0 (public notice index metadata)'})
    with urllib.request.urlopen(req,timeout=18) as f:
        raw=f.read();charset=f.headers.get_content_charset()
    m=re.search(rb'charset=[\"\']?([A-Za-z0-9_-]+)',raw[:6000]);charset=charset or (m.group(1).decode() if m else 'utf-8')
    if charset.lower() in ['euc-kr','ks_c_5601-1987']:charset='cp949'
    text=raw.decode(charset,errors='replace');file.write_text(text);time.sleep(.12);return text

def parse_day(s):
    m=re.search(r'(?<!\d)(20\d{2})[.\-/](\d{1,2})[.\-/](\d{1,2})(?!\d)',s)
    if not m:return None
    try:return dt.date(*map(int,m.groups())).isoformat()
    except ValueError:return None

def canonical(url):
    p=urllib.parse.urlsplit(html.unescape(url));q=urllib.parse.parse_qs(p.query,keep_blank_values=True)
    if p.scheme!='https' or not p.hostname:return None
    # Keep only identity and routing parameters, dropping pagination/tracking.
    if 'wr_id' in q:keys=['bo_table','wr_id']
    elif 'seq' in q:keys=['act','subAct','bid','seq']
    elif 'No' in q:keys=['state','Kind','Code','No','Thread','Type','Next']
    elif 'id' in q:keys=['id']
    elif 'num' in q and 'boardID' in q:keys=['Mode','boardID','num']
    else:return None
    return urllib.parse.urlunsplit((p.scheme,p.netloc,p.path,urllib.parse.urlencode([(k,q[k][0]) for k in keys if k in q]),''))

def parse_index(markup,base,parser):
    root=Nodes(markup).root;out=[]
    if parser=='50plus':
        for box in nodes(root,'div',cls='board-box'):
            titles=list(nodes(box,'h4',cls='board-box__info__title'));days=list(nodes(box,cls='board-box__info__post-date'))
            links=[a for a in nodes(box,'a') if 'detail.do?id=' in a['attrs'].get('href','')]
            if titles and days and links:
                out.append({'title':clean(titles[0]),'published_on':parse_day(clean(days[0])),
                            'source_url':canonical(urllib.parse.urljoin(base,links[0]['attrs']['href']))})
    else:
        for row in nodes(root,'tr'):
            links=[a for a in nodes(row,'a') if re.search(r'[?&](?:No|wr_id|seq)=',a['attrs'].get('href',''))]
            if not links:continue
            link=links[0];title=link['attrs'].get('title') or clean(link)
            title=re.sub(r'\s+(?:인기|NEW|첨부파일)\s*$','',title).strip()
            days=[parse_day(clean(td)) for td in nodes(row,'td') if re.fullmatch(r'\d{4}[.\-/]\d{1,2}[.\-/]\d{1,2}',clean(td))]
            out.append({'title':title,'published_on':next((d for d in days if d),None),
                        'source_url':canonical(urllib.parse.urljoin(base,link['attrs']['href']))})
    pages={}
    for a in nodes(root,'a'):
        href=html.unescape(a['attrs'].get('href',''));url=urllib.parse.urljoin(base,href)
        if urllib.parse.urlsplit(url).netloc!=urllib.parse.urlsplit(base).netloc:continue
        if re.search(r'[?&](?:wr_id|No|seq|id)=',url):continue
        q=urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
        value=q.get('page',q.get('Page',[None]))[0]
        if value and value.isdigit():pages[int(value)]=url
    return out,pages

def is_archive(title,published,today):
    if published<(today-dt.timedelta(days=60)).isoformat():return True
    # Staff recruitment / finance disclosures are preserved under archive,
    # separate from resident-facing service announcements.
    if re.search(r'직원|채용|합격자|입찰|수의계약|업무추진비|추가경정|예산|결산|회의록|서류전형',title):return True
    if re.search(r'모집\s*마감|접수\s*마감|종료\s*안내|결과\s*발표',title):return True
    months=re.findall(r'(\d{1,2})\s*월',title)
    if months and max(map(int,months))<today.month and str(today.year+1) not in title:return True
    return False

def record(item,source,today,checked):
    day=item.get('published_on');url=item.get('source_url');title=re.sub(r'\s+',' ',item.get('title','')).strip()
    if not day or day>today.isoformat() or not url or not title:return None
    if len(title)>300:return None
    return {'id':str(uuid.uuid5(uuid.NAMESPACE_URL,url)),'institution_name':source['name'],
            'institution_kind':source['kind'],'region_sido':'서울특별시','region_sigungu':source['district'],
            'title':title,'summary':'공식 홈페이지 공개 공지 · 자세한 대상·일정·신청 방법은 기관 원문에서 확인해 주세요.',
            'source_url':url,'published_on':day,'source_verified_at':checked,
            'archived':is_archive(title,day,today),'source_board':source['url'],'published':True}

def collect_source(source,today,checked):
    out={};pages={1:source['url']};seen_pages=set();coverage={'institution':source['name'],'board':source['url'],'pages':0,'errors':[]}
    for _ in range(100):
        remaining=sorted(p for p in pages if p not in seen_pages)
        if not remaining:break
        page=remaining[0];url=pages[page];seen_pages.add(page)
        try:items,more=parse_index(fetch(url),url,source['parser'])
        except Exception as e:coverage['errors'].append({'url':url,'error':type(e).__name__});break
        coverage['pages']+=1
        if not items:coverage['errors'].append({'url':url,'error':'no_parseable_notice_rows'});break
        added=0;recent=0
        for item in items:
            row=record(item,source,today,checked)
            if row:
                if row['published_on']>=f'{today.year}-01-01':recent+=1
                if row['published_on']>=f'{today.year}-01-01' or page==1:
                    if row['source_url'] not in out:added+=1
                    out[row['source_url']]=row
        pages.update(more)
        if page>1 and (recent==0 or added==0):break
    coverage['records']=len(out);coverage['current']=sum(not r['archived'] for r in out.values())
    coverage['capped']=len(seen_pages)>=100
    print(f"{source['name']}: {len(out)} notices / {coverage['pages']} pages",flush=True)
    return list(out.values()),coverage

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True);parser.add_argument('--as-of',default=dt.datetime.now(KST).date().isoformat())
    args=parser.parse_args();today=dt.date.fromisoformat(args.as_of);checked=dt.datetime.now(KST).isoformat()
    all_rows={};coverage=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
        for rows,status in ex.map(lambda s:collect_source(s,today,checked),SOURCES):
            coverage.append(status)
            for r in rows:all_rows[r['source_url']]=r
    data={'checked_at':checked,'as_of':args.as_of,'scope':'2026년 공식 공지 목록 및 첫 페이지의 오래된 상단 공지',
          'notices':sorted(all_rows.values(),key=lambda r:(r['published_on'],r['id']),reverse=True),'sources':coverage}
    Path(args.output).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'total':len(all_rows),'current':sum(not r['archived'] for r in all_rows.values()),'sources':len(coverage)}))
