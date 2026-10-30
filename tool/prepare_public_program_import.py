"""Build reviewable SQL from collected facts. Does not connect to the database."""
import argparse
import json
from pathlib import Path

COLUMNS = {'facility_name':'text','source':'text','source_id':'bigint','service_group':'text',
 'title':'text','category':'text','description':'text','schedule':'text','target':'text','period':'text',
 'how_to_apply':'text','fee':'text','is_free':'boolean','capacity':'integer','place':'text','note':'text',
 'source_url':'text','source_verified_at':'timestamptz','source_status':'text','registration_starts_on':'date',
 'registration_ends_on':'date','program_ends_on':'date','contact_phone':'text','preparations':'text','location_is_offsite':'boolean'}

def build(data):
    rows=data['programs']
    if len({(r['source'],r['source_id']) for r in rows})!=len(rows):raise ValueError('Duplicate source keys')
    for r in rows:
        if not r['source'].startswith('50plus_') or not r['source_url'].startswith('https://www.50plus.or.kr/'):
            raise ValueError('Unreviewed source')
    body=json.dumps(rows,ensure_ascii=False,separators=(',',':'))
    if '$publiccatalog$' in body:raise ValueError('Unsafe SQL delimiter')
    root=Path(__file__).resolve().parents[1]
    sql=(root/'supabase/public_program_catalog.sql').read_text()+'\n-- Public facts only; partner rights and rewards are never imported.\nbegin;\n'
    sql+='insert into public.welfare_programs ('+', '.join(COLUMNS)+')\nselect '+', '.join(COLUMNS)
    sql+=' from jsonb_to_recordset($publiccatalog$'+body+'$publiccatalog$::jsonb)\nas imported('
    sql+=', '.join(k+' '+v for k,v in COLUMNS.items())+')\n'
    sql+="where source_status='open' and registration_starts_on<=(now() at time zone 'Asia/Seoul')::date and registration_ends_on>=(now() at time zone 'Asia/Seoul')::date and program_ends_on>=(now() at time zone 'Asia/Seoul')::date\n"
    sql+='on conflict (source,source_id) do update set\n'+',\n'.join(k+'=excluded.'+k for k in COLUMNS if k not in ['source','source_id'])+',\nupdated_at=now();\n'
    # Only explicit source closures are propagated. A fetch failure/unknown
    # dates never deletes or closes existing data. No personal rows are touched.
    closed=[r['url'] for r in data.get('excluded',[]) if r['reason'] in ['source_not_open','detail_not_open']]
    payload=json.dumps(closed,ensure_ascii=False,separators=(',',':'))
    sql+="update public.welfare_programs set source_status='closed',updated_at=now() where source like '50plus_%' and source_url in (select jsonb_array_elements_text($closedcatalog$"+payload+"$closedcatalog$::jsonb));\ncommit;\n"
    sql+="select count(*) filter(where source like '50plus_%') as added_public_programs,count(*) filter(where source not like '50plus_%') as preserved_existing_programs,count(*) as total_programs from public.welfare_programs;\n"
    return sql

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--data',required=True);p.add_argument('--output',required=True);a=p.parse_args()
    Path(a.output).write_text(build(json.loads(Path(a.data).read_text())))
    print('Import SQL prepared. No server changes were made.')
