"""Generate the mechanical references: role-permission matrix, API reference, database catalogue."""
import json, pathlib, re, collections

INV = pathlib.Path(__file__).parent / "out"
REPO = pathlib.Path(__file__).resolve().parents[3]
OUT = INV / "generated"
OUT.mkdir(exist_ok=True)

api = json.loads((INV / "api.json").read_text(encoding="utf-8"))
routes = json.loads((INV / "routes.json").read_text(encoding="utf-8"))
offices = [l.split("|") for l in (INV / "offices.psv").read_text(encoding="utf-8").splitlines() if l]
OFFICE = {c: (t, s) for c, t, s in offices}

# ── module labels (API module → documentation module name) ─────────────────
LABEL = {
    "admissions": "Undergraduate admissions", "allocation": "Course allocation", "alumni": "Alumni", "apimgmt": "API keys",
    "applicant": "Applicant portal", "auditlog": "Audit log", "auth": "Authentication", "calendar": "Academic calendar",
    "catalogue": "Academic structure & courses", "cbt": "CBT question bank", "clearance": "Clearance", "college": "College of Health Sciences",
    "credentials": "Documents, certificates & ID cards", "dean": "Dean's desk", "deferments": "Deferments", "examiners": "External examiners",
    "expenditure": "Expenditure & stores", "finance": "Finance & fees", "governance": "Governance", "graduation": "Graduation",
    "health": "Health centre", "helpdesk": "ICT help desk", "hod": "HOD's desk", "hostel": "Hostel", "hrm": "Human resources",
    "iam": "Identity & accounts", "library": "Library", "lms": "Learning materials (LMS)", "matriculation": "Matriculation",
    "payments": "Payment gateways", "pgadmissions": "Postgraduate school", "platform": "Platform, notices & mail", "provost": "Provost's desk",
    "ref": "Reference data", "registration": "Course registration", "reporting": "Reporting", "reports": "Reports", "results": "Results & assessment",
    "siwes": "SIWES", "staff": "Staff", "stats": "Statistics", "student": "Student records", "studentportal": "Student portal",
    "support": "Support services", "transfers": "Transfers", "verify": "Public verification", "wallet": "Wallet",
}

# ── 1 · role-permission matrix ─────────────────────────────────────────────
WRITE = {"POST", "PUT", "DELETE", "PATCH"}
matrix = collections.defaultdict(lambda: collections.defaultdict(set))   # module → office → {R,W}
public_by_module = collections.Counter()
open_by_module = collections.Counter()
for e in api:
    mod = e["module"]
    if e["access"] == "public":
        public_by_module[mod] += 1
        continue
    if e["access"] == "any signed-in user":
        open_by_module[mod] += 1
        continue
    for o in e["offices"]:
        matrix[mod][o].add("W" if e["method"] in WRITE else "R")

office_order = ["super", "admin", "ict", "ictagent", "vc", "dvc", "registrar", "dregistrar", "academic", "records", "bursar", "financecontroller",
                "audit", "deputyaudit", "hrm", "provost", "collegesecretary", "mbbscoordinator", "dean", "facultyofficer", "facultyexams", "hod",
                "exams", "lecturer", "siwes", "pgschool", "pgsecretary", "extexaminer", "housing", "services", "security", "library", "student", "applicant"]
office_order += [o for o in OFFICE if o not in office_order]

def cell(s):
    if "W" in s:
        return "Act"
    if "R" in s:
        return "Read"
    return "—"

with (OUT / "permission-matrix.md").open("w", encoding="utf-8") as w:
    w.write("## Module × office matrix (derived from every `@PreAuthorize` guard in the API)\n\n")
    w.write("**Act** = the office is named on at least one POST/PUT/DELETE endpoint of the module; **Read** = named on GET endpoints only; **—** = not named. "
            "\"Open\" counts endpoints any signed-in user may call (typically `/me` screens); \"Public\" counts endpoints that need no sign-in.\n\n")
    short = {o: o for o in office_order}
    w.write("| Module | " + " | ".join(office_order) + " | Open | Public |\n|---|" + "---|" * (len(office_order) + 2) + "\n")
    for mod in sorted(matrix.keys() | set(public_by_module) | set(open_by_module), key=lambda m: LABEL.get(m, m)):
        row = [cell(matrix[mod].get(o, set())) for o in office_order]
        w.write(f"| {LABEL.get(mod, mod)} (`{mod}`) | " + " | ".join(row) + f" | {open_by_module[mod] or ''} | {public_by_module[mod] or ''} |\n")
    w.write("\n## Office legend\n\n| Code | Title | Scope kind |\n|---|---|---|\n")
    for o in office_order:
        if o in OFFICE:
            w.write(f"| `{o}` | {OFFICE[o][0]} | {OFFICE[o][1]} |\n")
    # per-office detail: modules it acts in / reads
    w.write("\n## What each office may do, module by module\n")
    for o in office_order:
        if o not in OFFICE:
            continue
        acts = sorted(LABEL.get(m, m) for m in matrix if "W" in matrix[m].get(o, set()))
        reads = sorted(LABEL.get(m, m) for m in matrix if matrix[m].get(o) == {"R"})
        menu = routes and [r for r in routes["routes"] if o in r["menus"]]
        w.write(f"\n### {OFFICE[o][0]} (`{o}`)\n- **Acts in:** {', '.join(acts) or 'none'}\n- **Reads only:** {', '.join(reads) or 'none'}\n- **Menu items:** {len(menu)}\n")

# ── 2 · endpoint-level permission table and API reference ──────────────────
with (OUT / "api-reference.md").open("w", encoding="utf-8") as w:
    w.write(f"Total endpoints: {len(api)}. Base URL: `https://<host>/api/v1`. All endpoints except those marked *public* require `Authorization: Bearer <token>`; "
            "state-changing calls made through the frontend also carry an `X-Reason` header that becomes the audit reason.\n\n")
    for mod in sorted(set(e["module"] for e in api), key=lambda m: LABEL.get(m, m)):
        es = [e for e in api if e["module"] == mod]
        w.write(f"\n### {LABEL.get(mod, mod)} (`{mod}`, {len(es)} endpoints)\n\n| Method | Endpoint | Purpose | Who may call | Source |\n|---|---|---|---|---|\n")
        for e in es:
            who = "public" if e["access"] == "public" else ("any signed-in user" if e["access"] == "any signed-in user" else ", ".join(e["offices"]))
            doc = e["doc"].replace("|", "/") or e["handler"]
            w.write(f"| {e['method']} | `{e['path']}` | {doc} | {who} | `{e['file'].split('portal/')[-1]}:{e['line']}` |\n")

# ── 3 · database catalogue ─────────────────────────────────────────────────
tables = [l.split("|") for l in (INV / "tables.psv").read_text(encoding="utf-8").splitlines() if l]
cols = collections.defaultdict(list)
for l in (INV / "columns.psv").read_text(encoding="utf-8").splitlines():
    if l:
        s, t, c, ty, n, d = l.split("|", 5)
        cols[(s, t)].append((c, ty, n, d))
uniq = collections.defaultdict(list)
checks = collections.defaultdict(list)
for l in (INV / "constraints.psv").read_text(encoding="utf-8").splitlines():
    if l:
        rel, name, d = l.split("|", 2)
        (uniq if d.startswith("UNIQUE") else checks)[rel].append(d)
trig = collections.Counter()
for l in (INV / "triggers.psv").read_text(encoding="utf-8").splitlines():
    if l:
        trig[l.split("|")[0]] += 1

# the comment above CREATE TABLE in the migrations, and the migration that created it
purpose, created_in = {}, {}
for f in sorted(REPO.glob("db/V*.sql")):
    src = f.read_text(encoding="utf-8", errors="replace")
    lines = src.splitlines()
    for i, line in enumerate(lines):
        m = re.match(r'\s*CREATE TABLE(?: IF NOT EXISTS)?\s+([a-z_]+)\.([a-z_0-9]+)', line)
        if not m:
            continue
        key = f"{m.group(1)}.{m.group(2)}"
        created_in.setdefault(key, f.name.split("__")[0])
        buf = []
        j = i - 1
        while j >= 0 and lines[j].strip().startswith("--"):
            buf.insert(0, lines[j].strip().lstrip("-").strip())
            j -= 1
        text = " ".join(b for b in buf if b and not set(b) <= set("─═- "))
        if text:
            purpose.setdefault(key, re.sub(r'\s+', ' ', text)[:260])
# audit-attached tables
attached = set()
for f in REPO.glob("db/V*.sql"):
    for m in re.finditer(r"audit\.attach\('([a-z_]+\.[a-z_0-9]+)'\)", f.read_text(encoding="utf-8", errors="replace")):
        attached.add(m.group(1))
exempt = set()
for f in REPO.glob("db/V*.sql"):
    for m in re.finditer(r"audit\.exempt\('([a-z_]+\.[a-z_0-9]+)'", f.read_text(encoding="utf-8", errors="replace")):
        exempt.add(m.group(1))

SCHEMA_PURPOSE = {
    "admissions": "Undergraduate and postgraduate admissions: CAPS lists, applicants, screening, Post-UTME, offers, PG applications and research",
    "apimgmt": "API keys for integrations", "assessment": "Scores, score sheets, results, GPA, standing", "audit": "The audit spine: every attributed change, hash-chained",
    "catalogue": "Courses, offerings and curriculum", "clearance": "Clearance units and items", "college": "College of Health Sciences (MB;BS) specifics",
    "credentials": "Issued documents, certificates, transcripts, ID cards, verification", "expenditure": "Vouchers, requisitions, stores",
    "extexam": "External examiners", "finance": "Fee schedules, charges, payment references, positions", "governance": "Governance instruments",
    "health": "Health centre", "helpdesk": "ICT help desk tickets", "hostel": "Hostel inventory, applications, allocations, stays", "hrm": "Human resources",
    "iam": "Persons, accounts, office assignments, sessions", "library": "Library", "lms": "Learning materials", "notify": "Notification module role home",
    "payments": "Payment gateway module role home", "people": "Students, contacts, status changes, matriculation, deferments, transfers",
    "platform": "Notices, numbering, settings, correlation", "policy": "Academic sessions, grading and progression policy", "records": "Graduands and records",
    "ref": "Reference data: faculties, departments, programmes, offices", "registration": "Course registration", "reporting": "Reporting views (audit-exempt)",
    "reports": "Saved reports", "public": "Migration ledger and legacy import staging",
}
with (OUT / "database-reference.md").open("w", encoding="utf-8") as w:
    by_schema = collections.defaultdict(list)
    for row in tables:
        by_schema[row[0]].append(row)
    w.write(f"Total tables: {len(tables)} across {len(by_schema)} schemas (the `public` schema, which holds the migration ledger and legacy import staging, is listed last). "
            f"Audit-attached tables: {len(attached)}; audit-exempt (blobs, public telemetry, reporting): {len(exempt)}.\n\n")
    w.write("| Schema | Tables | Purpose |\n|---|---|---|\n")
    for s in sorted(by_schema, key=lambda x: (x == "public", x)):
        w.write(f"| `{s}` | {len(by_schema[s])} | {SCHEMA_PURPOSE.get(s, '')} |\n")
    for s in sorted(by_schema, key=lambda x: (x == "public", x)):
        w.write(f"\n### Schema `{s}` — {SCHEMA_PURPOSE.get(s, '')}\n\n| Table | Purpose | Primary key | References | Cols | Unique | Triggers | Audit | Since |\n|---|---|---|---|---|---|---|---|---|\n")
        for sch, t, comment, pk, refs, ncol, ntrig, _ in by_schema[s]:
            key = f"{sch}.{t}"
            p = comment or purpose.get(key, "")
            au = "attached" if key in attached else ("exempt" if key in exempt else "")
            u = "; ".join(x.replace("UNIQUE ", "") for x in uniq.get(key, []))[:120]
            w.write(f"| `{t}` | {p} | {pk or ''} | {(refs or '').replace(sch + '.', '')} | {ncol} | {u} | {ntrig} | {au} | {created_in.get(key, '')} |\n")
    # status columns: CHECK constraints listing IN (...) values
    w.write("\n### Status and kind columns (from CHECK constraints)\n\n| Table | Constraint |\n|---|---|\n")
    for rel in sorted(checks):
        for d in checks[rel]:
            if " IN (" in d and "ANY (ARRAY" in d or "IN (" in d:
                m = re.search(r'\(\(?([a-z_]+)\)? = ANY \(ARRAY\[(.+?)\]', d) or re.search(r'\(([a-z_]+) IN \((.+?)\)', d)
                if m:
                    vals = re.sub(r"::text", "", m.group(2))
                    w.write(f"| `{rel}` | `{m.group(1)}` ∈ {vals[:240]} |\n")
    # column detail appendix
    w.write("\n### Column detail\n")
    for s in sorted(by_schema, key=lambda x: (x == "public", x)):
        for sch, t, *_ in by_schema[s]:
            w.write(f"\n**`{sch}.{t}`**: " + ", ".join(f"{c} `{ty}`{'' if n == 'YES' else ' NOT NULL'}" for c, ty, n, d in cols[(sch, t)]) + "\n")

print("matrix modules", len(matrix), "| endpoints", len(api), "| tables", len(tables), "| purposes found", sum(1 for r in tables if (r[2] or purpose.get(f'{r[0]}.{r[1]}'))), "| attached", len(attached), "exempt", len(exempt))
