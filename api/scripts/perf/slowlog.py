"""The slow statements PostgreSQL logged (log_min_duration_statement) after a byte offset of its log, grouped by statement.

usage: python -I slowlog.py <log> <offset> [db]
"""
import re, sys
from collections import defaultdict

path, offset = sys.argv[1], int(sys.argv[2])
with open(path, "rb") as f:
    f.seek(offset)
    text = f.read().decode("utf-8", "replace")

# an entry starts with a timestamp; the duration line carries the statement (multi-line until the next timestamped line)
entries = re.split(r"\n(?=\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", text)
slow = []
for e in entries:
    m = re.search(r"LOG:\s+duration: ([0-9.]+) ms\s+(?:statement|execute [^:]*|parse [^:]*|bind [^:]*): (.*)", e, re.S)
    if not m:
        continue
    ms = float(m.group(1))
    stmt = re.sub(r"\s+", " ", m.group(2)).strip()
    slow.append((ms, stmt))

groups = defaultdict(list)
for ms, stmt in slow:
    key = re.sub(r"'[^']*'", "?", stmt)[:220]
    groups[key].append(ms)
print(f"{len(slow)} slow statements, {len(groups)} kinds")
for key, v in sorted(groups.items(), key=lambda kv: -max(kv[1]))[:40]:
    print(f"max {max(v)/1000:7.1f} s  n={len(v):3d}  {key}")
