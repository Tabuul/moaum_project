"""Inventory the frontend: menus per office, routes and their pages, titles, the API calls each page makes, exports and PDFs."""
import json, pathlib, re, collections

FE = pathlib.Path(__file__).resolve().parents[3] / "frontend/src"
OUT = pathlib.Path(__file__).parent / "out"
OUT.mkdir(exist_ok=True)

menus_src = (FE / "lib/menus.ts").read_text(encoding="utf-8")
body = menus_src[menus_src.index("= {") + 2: menus_src.rindex("};") + 1]
MENUS = json.loads(body)

shell = (FE / "components/proto/Shell.tsx").read_text(encoding="utf-8")
routes_body = shell[shell.index("export const ROUTES"):]
routes_body = routes_body[routes_body.index("{"):routes_body.index("};") + 1]
ROUTES = dict(re.findall(r'"([^"]+)":\s*"([^"]+)"', routes_body))
titles_src = (FE / "lib/titles.ts").read_text(encoding="utf-8")
TITLES = {k: (a, b) for k, a, b in re.findall(r'"([^"]+)":\s*\["([^"]*)",\s*"([^"]*)"\]', titles_src)}
# overrides in Shell
ov = shell[shell.index("OVERRIDES"):shell.index("export const TITLES")]
for k, a, b in re.findall(r'"([^"]+)":\s*\["([^"]*)",\s*"([^"]*)"\]', ov):
    TITLES[k] = (a, b)

pages = sorted(p for p in (FE / "app").rglob("page.tsx"))
def url_of(p: pathlib.Path) -> str:
    rel = p.parent.relative_to(FE / "app").as_posix()
    rel = re.sub(r'/?\([^)]*\)', '', rel)
    return "/" + rel if rel and rel != "." else "/"
PAGE_URLS = {url_of(p): p for p in pages}

def page_for(path: str):
    path = path.split('?')[0]
    if path in PAGE_URLS:
        return PAGE_URLS[path]
    # dynamic segments
    for u, p in PAGE_URLS.items():
        if "[" in u:
            pat = "^" + re.sub(r'\[\.\.\.[^\]]+\]', '.+', re.sub(r'\[[^\]]+\]', '[^/]+', u)) + "$"
            if re.match(pat, path):
                return p
    return None

calls_re = re.compile(r'(?:api<[^>]*>\(\s*|fetch\(\s*)`?["\'`]?(/api/(?:bff/api/)?v1/[A-Za-z0-9_\-/${}.?=&:]+)')

def calls_of(page: pathlib.Path) -> list:
    found = set()
    for f in page.parent.rglob("*.tsx"):
        s = f.read_text(encoding="utf-8", errors="replace")
        for m in calls_re.finditer(s):
            found.add(re.sub(r'\$\{[^}]*\}', '{x}', m.group(1)).replace("/api/bff/api/v1", "/api/v1"))
    for f in page.parent.rglob("*.ts"):
        s = f.read_text(encoding="utf-8", errors="replace")
        for m in calls_re.finditer(s):
            found.add(re.sub(r'\$\{[^}]*\}', '{x}', m.group(1)).replace("/api/bff/api/v1", "/api/v1"))
    return sorted(found)

def features_of(page: pathlib.Path) -> list:
    text = "\n".join(f.read_text(encoding="utf-8", errors="replace") for f in page.parent.glob("*.tsx"))
    feats = []
    for key, label in [("brandedXlsx", "Excel export"), ("brandedPrint", "print/PDF export"), ("<Modal", "modals"), ("<Steps", "wizard"), ("<Tabs", "tabs"),
                       ("<DTable", "data table"), ("Donut", "charts"), ("HBars", "charts"), ("scope__search", "search"), ("useQueryNav", "filters"),
                       ("<Field", "form"), ("RoleLine", "role line"), ("notify(", "toasts")]:
        if key in text and label not in feats:
            feats.append(label)
    return feats

route_rows = []
for rid, path in sorted(ROUTES.items()):
    pg = page_for(path)
    offices = sorted(o for o, m in MENUS.items() if any(i["id"] == rid for g in m["groups"] for i in g["items"]))
    route_rows.append({"route": rid, "path": path, "page": str(pg.relative_to(FE / "app")).replace("\\", "/") if pg else None,
                       "title": TITLES.get(rid, ("", ""))[0], "subtitle": TITLES.get(rid, ("", ""))[1], "menus": offices,
                       "calls": calls_of(pg) if pg else [], "features": features_of(pg) if pg else []})
# pages that no route names
routed_pages = {r["page"] for r in route_rows if r["page"]}
extra = []
for u, p in sorted(PAGE_URLS.items()):
    rel = str(p.relative_to(FE / "app")).replace("\\", "/")
    if rel not in routed_pages:
        extra.append({"path": u, "page": rel, "calls": calls_of(p), "features": features_of(p)})

(OUT / "routes.json").write_text(json.dumps({"routes": route_rows, "unrouted_pages": extra}, indent=1), encoding="utf-8")
with (OUT / "menus.md").open("w", encoding="utf-8") as w:
    w.write("# Menus by office (frontend/src/lib/menus.ts)\n")
    for office, m in MENUS.items():
        w.write(f"\n## {office} — {m['label']} (home {m['home']})\n")
        for g in m["groups"]:
            w.write(f"- **{g['name']}**\n")
            for i in g["items"]:
                r = ROUTES.get(i["id"], "—")
                pg = page_for(r) if r != "—" else None
                w.write(f"  - {i['label']} `{i['id']}` → `{r}`{' (NO PAGE)' if r != '—' and not pg else ''}{' badge ' + i['badge'] if i.get('badge') else ''}\n")
with (OUT / "routes.md").open("w", encoding="utf-8") as w:
    w.write(f"# Routes ({len(route_rows)}), unrouted pages ({len(extra)})\n\n| Route | Path | Page | Title | Menus | Features | API calls |\n|---|---|---|---|---|---|---|\n")
    for r in route_rows:
        w.write(f"| {r['route']} | `{r['path']}` | {r['page'] or 'NONE'} | {r['title']} | {', '.join(r['menus'])} | {', '.join(r['features'])} | {'<br>'.join('`'+c+'`' for c in r['calls'])} |\n")
    w.write("\n## Pages no menu route names\n\n| Path | Page | Features | API calls |\n|---|---|---|---|\n")
    for e in extra:
        w.write(f"| `{e['path']}` | {e['page']} | {', '.join(e['features'])} | {'<br>'.join('`'+c+'`' for c in e['calls'])} |\n")
missing = [r for r in route_rows if not r["page"]]
print(len(MENUS), "menus;", len(ROUTES), "routes;", len(pages), "pages;", len(missing), "routes without a page;", len(extra), "unrouted pages")
for r in missing:
    print("  NO PAGE:", r["route"], r["path"], r["menus"])
