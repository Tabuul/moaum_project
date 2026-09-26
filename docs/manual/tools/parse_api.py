"""Inventory every HTTP endpoint of the Spring API: controller, method, path, guard (resolved), javadoc line."""
import json, pathlib, re, sys, collections

ROOT = pathlib.Path(__file__).resolve().parents[3] / "api/src/main/java/ng/edu/moaum/portal"
OUT = pathlib.Path(__file__).parent / "out"
OUT.mkdir(exist_ok=True)

MAPPING = re.compile(r'@(?:org\.springframework\.web\.bind\.annotation\.)?(Get|Post|Put|Delete|Patch|Request)Mapping\s*(\(([^)]*)\))?', re.S)
PRE = re.compile(r'@PreAuthorize\s*\(\s*(.+?)\s*\)\s*$', re.S)


def attr_path(args: str) -> str:
    if not args:
        return ""
    args = args.strip()
    m = re.match(r'^"([^"]*)"$', args)
    if m:
        return m.group(1)
    m = re.search(r'(?:value|path)\s*=\s*"([^"]*)"', args)
    if m:
        return m.group(1)
    m = re.search(r'(?:value|path)\s*=\s*\{\s*"([^"]*)"', args)
    if m:
        return m.group(1)
    m = re.match(r'^"([^"]*)"\s*,', args)
    return m.group(1) if m else ""


def method_of(kind: str, args: str) -> str:
    if kind != "Request":
        return kind.upper()
    m = re.search(r'RequestMethod\.([A-Z]+)', args or "")
    return m.group(1) if m else "ANY"


def constants(src: str) -> dict:
    out = {}
    for m in re.finditer(r'static\s+final\s+String\s+([A-Z_0-9]+)\s*=\s*((?:"[^"]*"\s*\+?\s*)+);', src, re.S):
        out[m.group(1)] = "".join(re.findall(r'"([^"]*)"', m.group(2)))
    return out


def offices(expr: str) -> list:
    # offices named inside a negated check (!hasAnyAuthority(...)) are excluded, not allowed
    positive = re.sub(r"!\s*has(?:Any)?Authority\([^)]*\)", "", expr)
    return sorted(set(re.findall(r"OFFICE_([a-z]+)", positive)))


def resolve(expr: str, consts: dict) -> str:
    expr = expr.strip()
    parts = []
    for tok in re.split(r'\s*\+\s*', expr):
        tok = tok.strip()
        if tok.startswith('"') and tok.endswith('"'):
            parts.append(tok[1:-1])
        elif tok in consts:
            parts.append(consts[tok])
        else:
            parts.append(tok)
    return "".join(parts)


PERMIT_ALL = ["/actuator/health", "/actuator/health/**", "/api/v1/platform/status", "/api/v1/auth/sign-in", "/api/v1/auth/bootstrap", "/api/v1/auth/offices",
    "/api/v1/auth/forgot", "/api/v1/auth/reset", "/api/v1/auth/sso", "/api/v1/auth/sso/start", "/api/v1/auth/sso/callback",
    "/api/v1/applicant/lookup", "/api/v1/applicant/register", "/api/v1/applicant/sign-in", "/api/v1/applicant/forgot", "/api/v1/applicant/reset",
    "/api/v1/payments/webhook/paystack", "/api/v1/payments/webhook/flutterwave", "/api/v1/payments/webhook/quickteller", "/api/v1/payments/quickteller/start",
    "/api/v1/student-auth/sign-in", "/api/v1/pg/apply", "/api/v1/pg/programmes", "/api/v1/pg/status", "/api/v1/pg/sign-in", "/api/v1/pg/referee/**",
    "/api/v1/verify/**", "/api/v1/helpdesk/track", "/api/v1/examiners/invitation/*", "/api/v1/examiners/activate"]


def is_permit_all(path: str) -> bool:
    for pat in PERMIT_ALL:
        if pat.endswith("/**"):
            if path == pat[:-3] or path.startswith(pat[:-2]):
                return True
        elif pat.endswith("/*"):
            rest = path[len(pat) - 1:] if path.startswith(pat[:-1]) else None
            if rest is not None and "/" not in rest and rest:
                return True
        elif path == pat:
            return True
    return False


endpoints = []
for f in sorted(ROOT.rglob("*.java")):
    src = f.read_text(encoding="utf-8", errors="replace")
    if "@RestController" not in src and "@Controller" not in src:
        continue
    consts = constants(src)
    cm = re.search(r'@RequestMapping\s*\(([^)]*)\)\s*(?:@[\w.]+(?:\((?:[^()]|\([^()]*\))*\))?\s*)*(?:public\s+)?(?:final\s+)?class', src, re.S)
    base = attr_path(cm.group(1)) if cm else ""
    class_pre = None
    cpm = re.search(r'@PreAuthorize\s*\(((?:[^()]|\([^()]*\))*)\)\s*(?:@[\w.]+(?:\((?:[^()]|\([^()]*\))*\))?\s*)*(?:public\s+)?(?:final\s+)?class', src, re.S)
    if cpm:
        class_pre = resolve(cpm.group(1), consts)
    module = f.relative_to(ROOT).parts[0]
    lines = src.splitlines()
    for m in MAPPING.finditer(src):
        # skip the class-level mapping
        after = src[m.end():m.end() + 400]
        if re.match(r'\s*(?:@\w+(?:\([^)]*\))?\s*)*(?:public\s+)?(?:final\s+)?class\b', after):
            continue
        kind, _, args = m.group(1), m.group(2), m.group(3)
        path = attr_path(args or "")
        verb = method_of(kind, args or "")
        # the annotations and javadoc just above
        start = src.rfind("\n\n", 0, m.start())
        block_above = src[start:m.start()]
        # the signature just below
        sig = re.search(r'\n\s*(?:public\s+|protected\s+|private\s+)?[\w<>\[\],\s.?]+?\s+(\w+)\s*\(', src[m.end():m.end() + 1200])
        name = sig.group(1) if sig else "?"
        if name == f.stem or name[:1].isupper():
            continue
        sig_abs = m.end() + (sig.start() if sig else 0)
        window = src[start:sig_abs]
        pm = re.search(r'@PreAuthorize\s*\(((?:[^()]|\([^()]*\))*)\)', window, re.S)
        guard = resolve(pm.group(1), consts) if pm else (class_pre or "")
        doc = ""
        dm = re.search(r'/\*\*(.*?)\*/', block_above, re.S)
        if dm:
            doc = " ".join(l.strip(" *") for l in dm.group(1).strip().splitlines()).strip()
            doc = re.sub(r'\s+', ' ', doc)[:220]
        else:
            lm = re.findall(r'//\s*(.+)', block_above)
            if lm:
                doc = lm[-1].strip()[:220]
        full = (base.rstrip("/") + "/" + path.lstrip("/")).rstrip("/") if path else base
        line_no = src[:m.start()].count("\n") + 1
        public = is_permit_all(full) and not offices(guard)
        endpoints.append({
            "module": module, "controller": f.stem, "file": str(f.relative_to(ROOT.parents[4])).replace("\\", "/"), "line": line_no,
            "method": verb, "path": full or "/", "handler": name, "guard": guard, "offices": offices(guard),
            "access": "public" if public else ("any signed-in user" if (not guard or (not offices(guard) and "isAuthenticated" in guard)) else "offices"), "excluded": sorted(set(re.findall(r"OFFICE_([a-z]+)", "".join(re.findall(r"!\s*has(?:Any)?Authority\([^)]*\)", guard))))), "doc": doc,
        })

endpoints.sort(key=lambda e: (e["module"], e["path"], e["method"]))
(OUT / "api.json").write_text(json.dumps(endpoints, indent=1), encoding="utf-8")
by_mod = collections.Counter(e["module"] for e in endpoints)
with (OUT / "api.md").open("w", encoding="utf-8") as w:
    w.write(f"# API endpoints ({len(endpoints)})\n\n")
    for mod in sorted(by_mod):
        w.write(f"\n## {mod} ({by_mod[mod]})\n\n| Method | Path | Handler | Access | Doc |\n|---|---|---|---|---|\n")
        for e in [x for x in endpoints if x["module"] == mod]:
            acc = e["access"] if e["access"] != "offices" else ", ".join(e["offices"])
            w.write(f"| {e['method']} | `{e['path']}` | {e['controller']}.{e['handler']} | {acc} | {e['doc'].replace('|', '/')} |\n")
print(len(endpoints), "endpoints;", sum(1 for e in endpoints if e["access"] == "any signed-in user"), "without a guard;", dict(by_mod))
