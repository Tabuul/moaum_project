"""List every call of a SQL function whose arguments hold a subquery — which keeps PostgreSQL from inlining a function that
returns rows into the query calling it (V550). Reads the database's SQL functions and function bodies (two psql exports, see
README §4) and the API's Java sources; prints one line a call: SRF or scalar, the function, where it is called, its arguments.

usage: python -I -X utf8 scan-calls.py <sql-functions.txt> <bodies.txt> <api/src/main/java>"""
import io
import os
import re
import sys

fns = {}
for line in io.open(sys.argv[1], encoding='utf-8'):
    parts = line.strip().split('|')
    if len(parts) == 3:
        fns[parts[0].lower()] = parts[1] in ('t', 'true')
call = re.compile(r'\b([a-z_]+)\.([a-z_0-9]+)\s*\(', re.I)


def args_at(text, i):
    """the text between the parenthesis at i and the one that closes it"""
    depth = 0
    for j in range(i, len(text)):
        if text[j] == '(':
            depth += 1
        elif text[j] == ')':
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
    return None


def scan(text, where):
    for m in call.finditer(text):
        name = (m.group(1) + '.' + m.group(2)).lower()
        if name not in fns:
            continue
        a = args_at(text, m.end() - 1)
        if a and re.search(r'\bselect\b', a, re.I):
            print('\t'.join(('SRF' if fns[name] else 'scalar', name, where, re.sub(r'\s+', ' ', a)[:200])))


for line in io.open(sys.argv[2], encoding='utf-8'):
    if '@@' in line:
        owner, body = line.split('@@', 1)
        scan(body, 'function ' + owner)
for root, _, files in os.walk(sys.argv[3]):
    for f in sorted(files):
        if f.endswith('.java'):
            p = os.path.join(root, f)
            scan(io.open(p, encoding='utf-8').read(), os.path.relpath(p, sys.argv[3]).replace(os.sep, '/'))
