"use client";

/** Migrate students, course registration and past results from the old portal (V082). Each upload reads the
 *  spreadsheet's own columns (matriculation number, course code, marks…) and matches on them; nothing is typed. */
import { useState } from "react";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { xlsxRowsAsync, buildXlsx } from "@/lib/xlsx";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

type Tab = "biodata" | "students" | "registration" | "results";
const MIGRATE = ["exams", "facultyexams", "hod", "dean", "records", "academic", "registrar", "dregistrar", "super"];

export function Migration({ actingOffice }: { actingOffice: string | null }) {
  const may = MIGRATE.includes(actingOffice ?? "");
  const [tab, setTab] = useState<Tab>("biodata");
  const [session, setSession] = useState("");
  const [semester, setSemester] = useState("1");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [result, setResult] = useState<{ tab: Tab; counts: Record<string, number>; firstError?: string | null } | null>(null);
  const [progress, setProgress] = useState<{ label: string; sent: number; of: number } | null>(null);

  async function upload(kind: Tab, file: File) {
    setBusy(true);
    setProblem(null);
    setResult(null);
    setProgress(null);
    try {
      setProgress({ label: "Reading the file", sent: 0, of: 0 });
      const grid = await xlsxRowsAsync(await file.arrayBuffer(), (n) => setProgress({ label: "Reading the file", sent: n, of: 0 }));
      const header = (grid[0] ?? []).map((c) => String(c ?? "").trim());
      if (!header.some((h) => /matric|reg|mat\.?\s*no/i.test(h))) {
        setProblem({ status: 400, title: "That file has no matriculation-number column.", detail: "The first row must name the columns; a matriculation (or registration) number is required." });
        return;
      }
      /* transform every row, yielding to the tab every few thousand so a large file stays responsive */
      const cols = resolveColumns(kind, header);
      const dataRows = grid.slice(1);
      const rows: Record<string, string>[] = [];
      for (let i = 0; i < dataRows.length; i++) {
        const r = dataRows[i];
        if (r.some((c) => String(c ?? "").trim() !== "")) {
          const o = applyRow(cols, r);
          if (o.matric && !/^matric/i.test(o.matric)) rows.push(o);
        }
        if ((i & 8191) === 8191) { setProgress({ label: "Preparing the rows", sent: i + 1, of: dataRows.length }); await new Promise((res) => setTimeout(res)); }
      }
      if (!rows.length) { setProblem({ status: 400, title: "The file had no rows to read.", detail: "Export the list from the old portal and upload it." }); return; }
      const path = kind === "biodata" ? "/api/bff/api/v1/results/legacy/biodata"
        : kind === "students" ? "/api/bff/api/v1/results/legacy/students"
        : kind === "registration" ? "/api/bff/api/v1/results/legacy/registration" : "/api/bff/api/v1/results/legacy/results";
      /* a large export goes up in batches — the importers upsert on the matriculation number, so each
         batch is independent and idempotent; the counts are summed as the batches come back */
      const CHUNK = kind === "biodata" ? 200 : 400;
      const chunks: typeof rows[] = [];
      for (let i = 0; i < rows.length; i += CHUNK) chunks.push(rows.slice(i, i + CHUNK));
      const totals: Record<string, number> = {};
      let firstErr: string | null = null;
      let sent = 0;
      setProgress({ label: "Importing", sent: 0, of: rows.length });
      for (const chunk of chunks) {
        const scoped = kind !== "students" && kind !== "biodata";
        const body = scoped ? { session, semester: Number(semester), rows: chunk } : { rows: chunk };
        const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Legacy ${kind} imported${scoped ? ` for ${session} semester ${semester}` : ""}: rows ${sent + 1} to ${sent + chunk.length} of ${rows.length}`) }, body: JSON.stringify(body) });
        const j = await r.json().catch(() => null);
        if (!r.ok) {
          const base = (j ?? { status: r.status, title: r.statusText }) as Problem;
          setProblem({ ...base, detail: `${base.detail ? base.detail + " " : ""}${sent.toLocaleString()} of ${rows.length.toLocaleString()} rows were imported before this batch was refused. The import is idempotent — fix the file and upload it again; the rows already in will update, not duplicate.` });
          if (Object.keys(totals).length) setResult({ tab: kind, counts: totals, firstError: firstErr });
          return;
        }
        const counts = (j ?? {}) as Record<string, unknown>;
        for (const [k, v] of Object.entries(counts)) if (typeof v === "number") totals[k] = (totals[k] ?? 0) + v;
        if (!firstErr && typeof counts.first_error === "string" && counts.first_error) firstErr = counts.first_error;
        sent += chunk.length;
        setProgress({ label: "Importing", sent, of: rows.length });
      }
      setResult({ tab: kind, counts: totals, firstError: firstErr });
    } catch {
      setProblem({ status: 400, title: "That file could not be read as a spreadsheet.", detail: "Upload the .xlsx exported from the old portal." });
    } finally {
      setBusy(false);
      setProgress(null);
    }
  }

  /* the download templates — the columns each import reads, with one example row to delete */
  const TEMPLATES: Record<Tab, { name: string; headers: string[]; example: string[] }> = {
    biodata: {
      name: "Student biography",
      headers: ["Matriculation Number", "Surname", "Other Names", "Sex", "Date of Birth", "Programme", "Level",
        "Entry Mode", "Entry Session", "Phone", "Email", "Address", "Nationality", "State", "LGA",
        "Guardian Name", "Guardian Address", "Sponsor Name", "Sponsor Address", "Next of Kin Name", "Next of Kin Address",
        "Extracurricular", "Application No"],
      example: ["MOAUM/CSC/22/0001", "Doe", "John Ada (example — delete this row)", "M", "2003-05-14", "Computer Science", "300",
        "UTME", "2022/2023", "08030000000", "john.doe@example.com", "12 Example Street, Makurdi", "Nigeria", "Benue", "Makurdi",
        "Mr Doe Senior", "12 Example Street, Makurdi", "Mr Doe Senior", "12 Example Street, Makurdi", "Jane Doe", "12 Example Street, Makurdi",
        "Football, Debate", "10000000AA"],
    },
    students: {
      name: "Students biodata",
      headers: ["Matriculation Number", "Surname", "Other Names", "Programme", "Sex", "Date of Birth", "Entry Mode", "Entry Session", "Level"],
      example: ["MOAUM/CSC/22/0001", "Doe", "John Ada (example — delete this row)", "Computer Science", "M", "2003-05-14", "UTME", "2022/2023", "300"],
    },
    registration: {
      name: "Course registration",
      headers: ["Matriculation Number", "Course Code", "Course Title", "Units", "Level"],
      example: ["MOAUM/CSC/22/0001", "CSC 301", "Operating Systems (example — delete this row)", "3", "300"],
    },
    results: {
      name: "Past results",
      headers: ["Matriculation Number", "Course Code", "Course Title", "Units", "Level", "CA", "Exam", "Total", "Outcome"],
      example: ["MOAUM/CSC/22/0001", "CSC 301", "Operating Systems (example — delete this row)", "3", "300", "25", "55", "80", "GRADED"],
    },
  };

  function downloadTemplate(kind: Tab) {
    const t = TEMPLATES[kind];
    const blob = buildXlsx(t.headers, [t.example], t.name);
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `${t.name} template.xlsx`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  const needScope = tab !== "students" && tab !== "biodata";
  const scopeReady = !needScope || (/^[0-9]{4}\/[0-9]{4}$/.test(session) && ["1", "2", "3"].includes(semester));
  const CARDS: Record<Tab, [string, string][]> = {
    biodata: [["rows", "Rows read"], ["created", "New students"], ["updated", "Updated"], ["contacts", "Contacts set"], ["biography", "Biography values"], ["accounts", "Sign-in accounts"], ["no_programme", "Programme not found"], ["bad_number", "Bad matric format"], ["skipped", "Skipped (error)"]],
    students: [["rows", "Rows read"], ["created", "New students"], ["updated", "Updated"], ["no_programme", "Programme not found"], ["bad_number", "Bad matric format"], ["skipped", "Skipped (error)"]],
    registration: [["rows", "Rows read"], ["students", "Students"], ["offerings", "Courses"], ["registrations", "Registrations"], ["no_student", "No such student"], ["no_course", "No such course"]],
    results: [["rows", "Rows read"], ["students", "Students"], ["results", "Results posted"], ["registrations", "Registrations made"], ["no_student", "No such student"], ["no_course", "No such course"], ["no_mark", "No / invalid mark"]],
  };

  /* map an old-portal export's own column names onto the keys the importer reads, so a real file
     uploads without renaming — CA in [0,40], Exam in [0,60], Total in [0,100]; an out-of-range
     mark is skipped and reported, not fatal. */
  /** an Excel date serial, a DD-MM-YYYY / ISO string, or the 0000-00-00 sentinel → ISO or "" */
  function normDob(s: string): string {
    const t = s.trim();
    if (!t || /^0{2,4}[-/]0{1,2}[-/]0{1,2}$/.test(t)) return "";
    if (/^\d{4}-\d{2}-\d{2}$/.test(t)) return t;
    const m = t.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$/); // DD-MM-YYYY (Nigerian order)
    if (m) return `${m[3]}-${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}`;
    if (/^\d{4,6}(\.0+)?$/.test(t)) { // Excel serial (days since 1899-12-30)
      const d = new Date(Date.UTC(1899, 11, 30) + Math.trunc(Number(t)) * 86400000);
      const y = d.getUTCFullYear();
      return y >= 1940 && y <= 2015 ? d.toISOString().slice(0, 10) : "";
    }
    return "";
  }

  /** a Nigerian mobile with a possibly-lost leading zero or +234 → 0XXXXXXXXXX or "" */
  function normPhone(s: string): string {
    const d = s.replace(/\D/g, "");
    if (d.length === 11 && d.startsWith("0")) return d;
    if (d.length === 10) return "0" + d;
    if (d.length === 13 && d.startsWith("234")) return "0" + d.slice(3);
    if (d.length === 14 && d.startsWith("2340")) return "0" + d.slice(4);
    return "";
  }

  type Col = { key: string; idx: number; norm?: (s: string) => string };

  /* resolve each field's column index from the header ONCE — the header is the same for every
     row, so matching column names with regex per row (over tens of thousands of rows) is what
     froze the tab. Here it is done once and every row is then a cheap read by index. */
  function resolveColumns(kind: Tab, header: string[]): Col[] {
    const h = header.map((x) => String(x ?? "").trim().toLowerCase());
    const at = (...names: RegExp[]) => h.findIndex((x) => names.some((n) => n.test(x)));
    const cols: Col[] = [];
    const add = (key: string, idx: number, norm?: (s: string) => string) => { if (idx >= 0) cols.push({ key, idx, norm }); };
    add("matric", at(/matric/, /reg\.?\s*(no|number)/, /registration/, /mat\.?\s*no/, /matno/));
    if (kind === "biodata") {
      add("surname", at(/surname/, /last\s*name/));
      add("otherNames", at(/other\s*name/, /first\s*name/, /given/));
      add("name", at(/full\s*name/, /^name$/, /student\s*name/, /^names$/));
      add("programme", at(/programme/, /program/, /course of study/));
      add("sex", at(/^sex$/, /gender/));
      add("dob", at(/birth/, /^dob$/, /d\.o\.b/), normDob);
      add("entryMode", at(/entry\s*mode/, /mode of entry/, /mode_entry/, /^mode$/, /admission type/));
      add("entrySession", at(/entry\s*session/, /^yoe$/, /year of entry/, /admission\s*session/, /session admitted/));
      add("level", at(/current\s*level/, /^level$/, /^lvl$/));
      add("phone", at(/phone/, /mobile/, /gsm/, /^tel$/), normPhone);
      add("email", at(/^e-?mail$/, /e-?mail/));
      add("address", at(/^address$/, /home\s*address/, /residential/, /contact\s*address/));
      add("nationality", at(/nationality/));
      add("state", at(/state\s*of\s*origin/, /^state$/));
      add("lga", at(/^lga$/, /local\s*govt/, /local\s*government/));
      add("guardianName", at(/guardian\s*name/, /guardianname/));
      add("guardianAddress", at(/guardian\s*address/, /guardianaddress/));
      add("sponsorName", at(/sponsor\s*name/, /sponsorname/));
      add("sponsorAddress", at(/sponsor\s*address/, /sponsoraddress/));
      add("nokName", at(/nok\s*name/, /nokname/, /next\s*of\s*kin.*name/, /kin\s*name/));
      add("nokAddress", at(/nok\s*address/, /nokaddress/, /next\s*of\s*kin.*address/, /kin\s*address/));
      add("extracurricular", at(/extra.?curricular/, /hobb/));
      add("appno", at(/^appno$/, /application\s*no/, /app\s*no/));
    } else if (kind === "students") {
      add("surname", at(/surname/, /last\s*name/));
      add("otherNames", at(/other\s*name/, /first\s*name/, /given/));
      add("name", at(/full\s*name/, /^name$/, /student\s*name/, /^names$/));
      add("programme", at(/programme/, /program/, /course of study/, /department|dept/));
      add("sex", at(/^sex$/, /gender/));
      add("dob", at(/birth/, /^dob$/, /d\.o\.b/));
      add("entryMode", at(/entry\s*mode/, /mode of entry/, /^mode$/, /admission type/));
      add("entrySession", at(/entry\s*session/, /admission\s*session/, /year of entry/, /session admitted/));
      add("level", at(/current\s*level/, /^level$/, /^lvl$/));
    } else {
      add("course", at(/course\s*code/, /^course$/, /^code$/, /subject\s*code/));
      add("units", at(/unit/, /^cu$/, /credit/));
      add("level", at(/^level$/, /^lvl$/));
      if (kind === "results") {
        add("ca", at(/\bca\b/, /continuous/, /c\.a/));
        add("exam", at(/exam/, /examination/));
        add("total", at(/total/, /^score$/, /^mark$/, /aggregate/));
        add("outcome", at(/outcome/, /remark/, /status/, /grade/));
      }
    }
    return cols;
  }

  /** one spreadsheet row → the importer's keys, using the pre-resolved columns (no per-row regex) */
  function applyRow(cols: Col[], r: (string | number | null)[]): Record<string, string> {
    const o: Record<string, string> = {};
    for (const c of cols) {
      let v = String(r[c.idx] ?? "").trim();
      if (c.norm) v = c.norm(v);
      if (v) o[c.key] = v;
    }
    return o;
  }

  return (
    <>
      <Note kind="info" title="Bring the record over from the old portal">
        Start with the students, so results and registration can match them by matriculation number: upload the
        <b> full student biography</b> (biodata, contact, guardian, sponsor and next-of-kin, and a sign-in account in one
        pass) or, if you only have the core list, <b>students (core only)</b>. Then the course registration and the past
        results. Each upload reads the spreadsheet&rsquo;s own columns and matches on the matriculation number and the
        course code &mdash; nothing is typed. A past result is imported as final under a legacy minute, so it counts on
        the transcript and the GPA exactly as one entered here. Every import is your act.
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Examinations Officer, HODs and Records">Your office may not migrate records.</Note> : null}

      <div className="card"><div className="card__body">
        <div className="role-tabs" role="tablist">
          {([["biodata", "1 · Student biography (full)"], ["students", "1 · Students (core only)"], ["registration", "2 · Course registration"], ["results", "3 · Past results"]] as [Tab, string][]).map(([k, l]) => (
            <button key={k} type="button" role="tab" aria-selected={tab === k ? "true" : "false"} onClick={() => { setTab(k); setResult(null); setProblem(null); }}>{l}</button>
          ))}
        </div>
      </div></div>

      {problem ? <ProblemNotice problem={problem} /> : null}

      <Panel title={tab === "biodata" ? "Student biography exported from the old portal" : tab === "students" ? "Students exported from the old portal" : tab === "registration" ? "Course registration of a past semester" : "Past results of a semester"}
             right={tab === "students" || tab === "biodata" ? "The first step" : `${session || "session"} · semester ${semester}`}>
        <PBody>
          {needScope ? (
            <div className="grid grid--3">
              <Field id="mg-ses" label="Session" hint="The session these records belong to, e.g. 2024/2025"><input id="mg-ses" className="ctl tnum" value={session} placeholder="2024/2025" onChange={(e) => setSession(e.target.value.trim())} /></Field>
              <Field id="mg-sem" label="Semester"><select id="mg-sem" className="ctl" value={semester} onChange={(e) => setSemester(e.target.value)}><option value="1">First semester</option><option value="2">Second semester</option><option value="3">Third semester</option></select></Field>
              <div />
            </div>
          ) : null}
          <div className="sub2" style={{ marginBottom: 8 }}>
            {tab === "biodata" ? "Columns read: matriculation number, name, programme, sex, date of birth, level, entry mode/session, phone, email, address, nationality, state, LGA, guardian, sponsor and next-of-kin. The matric number is kept exactly as the old portal issued it; a date in any common form and a phone with a lost leading zero are normalised; a matric sign-in account is created (no password is taken from the file — the student sets one through the reset, sent to the phone or email here)."
              : tab === "students" ? "Columns read: matriculation number, name (or surname + other names), programme (code or name), sex, date of birth, entry mode, level. The session is read from the matric number when not given."
              : tab === "registration" ? "Columns read: matriculation number, course code, units. Each student's approved registration and course entries are created for the semester above."
              : "Columns read: matriculation number, course code, and the mark. Fill CA and Exam where the old record splits them (they add to the total); otherwise leave those blank and fill Total (0–100). Units and outcome are read when present."}
          </div>
          <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
            <Btn kind="ghost" onClick={() => downloadTemplate(tab)}>Download template</Btn>
            <label className={`btn btn--primary${!may || (needScope && !scopeReady) || busy ? " btn--disabled" : ""}`} style={{ cursor: may && scopeReady && !busy ? "pointer" : "not-allowed", margin: 0, opacity: !may || (needScope && !scopeReady) ? 0.6 : 1 }}>
              {busy
                ? (progress
                    ? (progress.of > 0
                        ? `${progress.label} — ${progress.sent.toLocaleString()} of ${progress.of.toLocaleString()}…`
                        : progress.sent > 0
                          ? `${progress.label} — ${progress.sent.toLocaleString()} rows…`
                          : `${progress.label}…`)
                    : "Importing…")
                : `Upload ${tab === "biodata" ? "biography" : tab === "students" ? "students" : tab === "registration" ? "registration" : "results"} file`}
              <input type="file" accept=".xlsx" style={{ display: "none" }} disabled={!may || (needScope && !scopeReady) || busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(tab, f); e.target.value = ""; }} />
            </label>
            {needScope && !scopeReady ? <span className="sub2">Enter the session (YYYY/YYYY) and semester first.</span> : null}
          </div>
          <div className="sub2" style={{ marginTop: 8 }}>Download the template, fill it from the old-portal export (delete the example row), and upload it. Column names are matched flexibly, so an export that already has these columns can be uploaded as-is.</div>
        </PBody>
      </Panel>

      {result && result.tab === tab ? (
        <>
          <Tiles items={CARDS[tab].map(([k, label]) => {
            const v = Number(result.counts[k] ?? 0);
            const bad = (/no_|bad_|skipped/.test(k)) && v > 0;
            return [label, String(v), bad ? "var(--red-ink)" : /created|results|registrations|students/.test(k) ? "var(--green-ink)" : null, ""] as [string, string, string | null, string];
          })} />
          <Note kind="ok" title="Imported">
            {tab === "biodata" ? `${result.counts.created ?? 0} students created, ${result.counts.updated ?? 0} updated; ${result.counts.contacts ?? 0} contacts and ${result.counts.biography ?? 0} biography values saved; ${result.counts.accounts ?? 0} sign-in accounts provisioned.`
              : tab === "students" ? `${result.counts.created ?? 0} students created, ${result.counts.updated ?? 0} updated.`
              : tab === "registration" ? `${result.counts.registrations ?? 0} registrations across ${result.counts.offerings ?? 0} courses.`
              : `${result.counts.results ?? 0} results posted.`}
            {" "}Rows that did not match are counted above; fix them at source and re-upload — the import is idempotent.
            {(result.counts.no_student ?? 0) > 0 ? <> <b>Import the students first</b> if a number was not found.</> : null}
            {(result.counts.skipped ?? 0) > 0 ? <> <b>{result.counts.skipped} row{result.counts.skipped === 1 ? "" : "s"} were skipped by an error</b> and are not on the register; the first was — <span className="tnum">{result.firstError ?? "no detail"}</span>. Fix those rows and re-upload.</> : null}
          </Note>
        </>
      ) : null}

      <Note kind="info" title="Order matters, and re-uploading is safe">
        <Pil kind="grey">1</Pil> Students &rarr; <Pil kind="grey">2</Pil> Registration &rarr; <Pil kind="grey">3</Pil> Results.
        A result needs the student and the course registration to exist, so the results import also creates the
        registration entry if it is missing. Uploading the same file again updates rather than duplicates.
        A large export is sent up in batches automatically, so a file of any size uploads in one go; if a batch is
        refused part-way, the rows already in stand and you can simply upload the file again.
      </Note>
    </>
  );
}
