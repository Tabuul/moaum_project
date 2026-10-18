"""Each crawled page load with the slow statements PostgreSQL logged while it loaded (the second load of each page).
usage: python -I attribute.py <recrawl.jsonl> <server log> <offset>"""
import json, re, sys
from datetime import datetime, timedelta, timezone

jsonl, log, offset = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(log, "rb") as f:
    f.seek(offset)
    text = f.read().decode("utf-8", "replace")
stmts = []
for e in re.split(r"\n(?=\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", text):
    m = re.match(r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+) WAT .*?duration: ([0-9.]+) ms\s+(?:statement|execute [^:]*): (.*)", e, re.S)
    if not m:
        continue
    end = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f").replace(tzinfo=timezone(timedelta(hours=1)))
    stmts.append((end, float(m.group(2)), re.sub(r"\s+", " ", m.group(3)).strip()))
for line in open(jsonl, encoding="utf-8"):
    r = json.loads(line)
    if r.get("round") != 2:
        continue
    end = datetime.fromisoformat(r["at"].replace("Z", "+00:00"))
    start = end - timedelta(milliseconds=r["ms"])
    inside = [(ms, s) for (t, ms, s) in stmts if start - timedelta(seconds=1) <= t <= end + timedelta(seconds=1)]
    if r["ms"] < 4000:
        continue
    print(f"\n{r['ms'] / 1000:5.1f} s  {r['office']} {r['path']}")
    for ms, s in sorted(inside, key=lambda x: -x[0])[:6]:
        print(f"    {ms / 1000:5.1f} s  {s[:170]}")
