# One-off data prep script — geocodes 경로당 by searching NAVER Local
# Search for "{구} {이름}" and taking the first hit's mapx/mapy, instead of
# a dedicated (currently unavailable) geocoding API.
import sys
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
        return None, None, f"HTTP {resp.status_code}: {resp.text[:200]}"
    items = resp.json().get("items", [])
    if not items:
        return None, None, "no results"
    item = items[0]
    lng = int(item["mapx"]) / 10000000
    lat = int(item["mapy"]) / 10000000
    return lat, lng, None


def main():
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else None
    df = pd.read_excel("(서울시경로당)현황3644(25.6월말 기준).xlsx")
    if limit:
        df = df.head(limit)

    ok = 0
    fail = 0
    for _, r in df.iterrows():
        gu = r["시군구명"]
        name = r["시설명(경로당명)"]
        query = f"{gu} {name}"
        lat, lng, err = find_coords(query)
        if err:
            fail += 1
            print(f"FAIL  {query!r}: {err}")
        else:
            ok += 1
            print(f"OK    {query!r} -> {lat}, {lng}")
        time.sleep(0.15)

    print(f"\n{ok} ok, {fail} failed, {ok + fail} total")


if __name__ == "__main__":
    main()
