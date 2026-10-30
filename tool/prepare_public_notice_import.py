"""Prepare reviewable, idempotent public notice SQL; no direct server writes."""
import argparse
import json
from pathlib import Path
import re

COLUMNS={'id':'uuid','institution_name':'text','institution_kind':'text','region_sido':'text',
 'region_sigungu':'text','title':'text','summary':'text','source_url':'text','source_board':'text',
 'published_on':'date','source_verified_at':'timestamptz','archived':'boolean','published':'boolean'}

def build(data):
    rows=data['notices']
    if len({r['source_url'] for r in rows})!=len(rows):raise ValueError('Duplicate URLs')
    if len({r['id'] for r in rows})!=len(rows):raise ValueError('Duplicate IDs')
    for r in rows:
        if not r['source_url'].startswith('https://') or not re.fullmatch(r'\d{4}-\d{2}-\d{2}',r['published_on']):raise ValueError('Invalid provenance')
    body=json.dumps(rows,ensure_ascii=False,separators=(',',':'))
    if '$noticemetadata$' in body:raise ValueError('Unsafe delimiter')
    root=Path(__file__).resolve().parents[1]
    sql=(root/'supabase/public_institution_notices.sql').read_text()+'\nbegin;\n'
    sql+='insert into public.public_institution_notices ('+', '.join(COLUMNS)+')\nselect '+', '.join(COLUMNS)
    sql+=' from jsonb_to_recordset($noticemetadata$'+body+'$noticemetadata$::jsonb) as imported('
    sql+=', '.join(k+' '+v for k,v in COLUMNS.items())+')\n'
    sql+="where published_on<=(now() at time zone 'Asia/Seoul')::date\non conflict (source_url) do update set\n"
    sql+=',\n'.join(k+'=excluded.'+k for k in COLUMNS if k not in ['id','source_url'])+',\nupdated_at=now();\ncommit;\n'
    sql+="select count(*) as imported_public_notices,count(distinct institution_name) as institutions,count(*) filter(where not archived and published_on >= (now() at time zone 'Asia/Seoul')::date-60) as recent_public_notices from public.public_institution_notices;\n"
    sql+='\n'+(root/'supabase/my_notice_institution.sql').read_text()
    return sql

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--data',required=True);p.add_argument('--output',required=True);a=p.parse_args()
    Path(a.output).write_text(build(json.loads(Path(a.data).read_text())))
    print('Public notice import SQL prepared; no server changes made.')
