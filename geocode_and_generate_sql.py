# One-off data prep script. Geocodes all 3644 rows via NAVER Local Search
# (by name, not address — see geocode_via_local_search.py for why) and
# writes the resulting INSERT statements to supabase/import_gyeongrodang.sql,
# overwriting the previous (national-dataset-based) version.
import time
import requests
import pandas as pd

CLIENT_ID = "vhhnls9i8g"
CLIENT_SECRET = "iis32yS41GgSZg9v3WO04sOxE5EJEZ08H286T3O0"
URL = "https://naverapihub.apigw.ntruss.com/search/v1/local"
HEADERS = {"X-NCP-APIGW-API-KEY-ID": CLIENT_ID, "X-NCP-APIGW-API-KEY": CLIENT_SECRET}


def find_coords(query: str):
    resp = requests.get(URL, params={"query": query, "display": 1}, headers=HEADERS, timeout=10)
    if resp.status_code != 200:
        return None, None
    items = resp.json().get("items", [])
    if not items:
        return None, None
    item = items[0]
    lng = int(item["mapx"]) / 10000000
    lat = int(item["mapy"]) / 10000000
    return lat, lng


def sql_escape(value):
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def main():
    df = pd.read_excel("(서울시경로당)현황3644(25.6월말 기준).xlsx")

    rows = []
    ok = 0
    fail = 0
    for i, r in df.iterrows():
        gu = r["시군구명"]
        name = r["시설명(경로당명)"]
        address = "서울특별시 " + str(r["주소(도로명)"])
        telephone = r["전화번호"] if pd.notna(r["전화번호"]) else None

        lat, lng = find_coords(f"{gu} {name}")
        if lat is None:
            fail += 1
        else:
            ok += 1
            rows.append((name, address, lat, lng, "경로당", telephone))

        if (i + 1) % 200 == 0:
            print(f"...{i + 1}/{len(df)} ({ok} ok, {fail} failed so far)")

        time.sleep(0.15)

    print(f"\nDone: {ok} ok, {fail} failed, {len(df)} total")

    with open("supabase/import_gyeongrodang.sql", "w", encoding="utf-8") as f:
        f.write("-- Generated from (서울시경로당)현황3644(25.6월말 기준).xlsx.\n")
        f.write("-- Coordinates found via NAVER Local Search by facility name\n")
        f.write(f"-- ({ok}/{len(df)} matched; {fail} had no search result and were skipped).\n")
        f.write("-- Run supabase/delete_old_gyeongrodang.sql first, then this, in the SQL Editor.\n\n")
        batch_size = 200
        for start in range(0, len(rows), batch_size):
            batch = rows[start:start + batch_size]
            f.write("insert into public.facilities (name, address, lat, lng, category, telephone) values\n")
            lines = []
            for name, address, lat, lng, category, telephone in batch:
                lines.append(
                    f"  ({sql_escape(name)}, {sql_escape(address)}, {lat}, {lng}, "
                    f"{sql_escape(category)}, {sql_escape(telephone)})"
                )
            f.write(",\n".join(lines))
            f.write("\non conflict (name, address) do nothing;\n\n")

    print("Wrote supabase/import_gyeongrodang.sql")


if __name__ == "__main__":
    main()
