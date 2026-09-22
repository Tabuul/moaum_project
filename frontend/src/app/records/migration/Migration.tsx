"use client";

/** Migrate students, course registration and past results from the old portal (V082). Each upload reads the
 *  spreadsheet's own columns (matriculation number, course code, marks…) and matches on them; nothing is typed. */
import { useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { xlsxRowsAsync, buildXlsx } from "@/lib/xlsx";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { semesterText } from "@/lib/student-portal";

type Tab = "biodata" | "pgstudents" | "students" | "registration" | "results" | "pgregistration" | "pgresults" | "pgresearch" | "jamb" | "passports";
const MIGRATE = ["ict", "exams", "facultyexams", "hod", "dean", "records", "academic", "registrar", "dregistrar", "super"];
/* the matric shapes the biography/students importers accept — the University's own, or a legacy old-portal number */
const MATRIC_OK = /^(MOAUM\/[A-Z]{2,4}\/[0-9]{2}\/[0-9]{4}|[A-Z]{2,6}(\/[A-Z0-9]{2,6}){1,4}\/[0-9]{2,7})$/i;
/** a semester cell — "First"/"Second"/"Third" or 1/2/3 — to its number */
const semNum = (v: string) => { const t = v.trim().toLowerCase(); return t.startsWith("f") || t === "1" ? 1 : t.startsWith("s") || t === "2" ? 2 : t.startsWith("t") || t === "3" ? 3 : Number(v) || 0; };

export function Migration({ actingOffice }: { actingOffice: string | null }) {
  const may = MIGRATE.includes(actingOffice ?? "");
  const [tab, setTab] = useState<Tab>("biodata");
  const [session, setSession] = useState("");
  const [semester, setSemester] = useState("1");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [result, setResult] = useState<{ tab: Tab; counts: Record<string, number>; firstError?: string | null } | null>(null);
  const [progress, setProgress] = useState<{ label: string; sent: number; of: number } | null>(null);
  const [rejected, setRejected] = useState<{ rows: Record<string, string>[]; kind: Tab } | null>(null);
  const [pResult, setPResult] = useState<{ total: number; stored: number; attached: number; notFound: number; skipped: number; notFoundList: string[] } | null>(null);

  /** bulk passport photos: each file is named by the student's JAMB reg no; matched and stored, or skipped */
  async function uploadPassports(files: File[]) {
    setBusy(true); setProblem(null); setPResult(null); setProgress(null);
    try {
      const fileToBase64 = (file: File) => new Promise<string>((resolve, reject) => {
        const r = new FileReader();
        r.onload = () => { const s = String(r.result); const i = s.indexOf(","); resolve(i >= 0 ? s.slice(i + 1) : s); };
        r.onerror = () => reject(r.error);
        r.readAsDataURL(file);
      });
      /* Smaller batches keep each request well under the API's JSON size limit, and an oversized scan is
         held back rather than sent — a single ~15 MB+ image cannot be parsed and used to refuse the batch
         (and, before, halt the whole upload). Anything a batch cannot send is counted and listed, and the
         upload carries on to the end. Re-uploading is idempotent, so fixed files can go up again. */
      const CHUNK = 6;
      const MAX_BYTES = 8 * 1024 * 1024;   // hold back a scan larger than this; resize and re-upload it
      const totals = { total: 0, stored: 0, attached: 0, notFound: 0, skipped: 0 };
      const notFoundList: string[] = [];
      const problemFiles: string[] = [];
      let sent = 0, failed = 0;
      setProgress({ label: "Uploading photos", sent: 0, of: files.length });
      const usable: File[] = [];
      for (const f of files) {
        if (f.size > MAX_BYTES) { totals.total++; totals.skipped++; failed++; if (problemFiles.length < 5000) problemFiles.push(f.name); }
        else usable.push(f);
      }
      sent = files.length - usable.length;
      setProgress({ label: "Uploading photos", sent, of: files.length });
      for (let i = 0; i < usable.length; i += CHUNK) {
        const slice = usable.slice(i, i + CHUNK);
        try {
          const items = await Promise.all(slice.map(async (f) => ({ filename: f.name, contentType: f.type || "", contentBase64: await fileToBase64(f) })));
          const r = await fetch("/api/bff/api/v1/results/legacy/passports", {
            method: "POST",
            headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Legacy passport photos imported: ${sent + 1} to ${sent + slice.length} of ${files.length}`) },
            body: JSON.stringify({ items }),
          });
          const j = await r.json().catch(() => null);
          if (!r.ok) {
            /* one refused batch no longer stops the upload — count it, list its files, and carry on */
            totals.total += slice.length; totals.skipped += slice.length; failed += slice.length;
            for (const f of slice) if (problemFiles.length < 5000) problemFiles.push(f.name);
          } else {
            const c = (j ?? {}) as Record<string, unknown>;
            totals.total += Number(c.total ?? 0); totals.stored += Number(c.stored ?? 0); totals.attached += Number(c.attached ?? 0);
            totals.notFound += Number(c.notFound ?? 0); totals.skipped += Number(c.skipped ?? 0);
            if (Array.isArray(c.notFoundList)) for (const n of c.notFoundList) if (notFoundList.length < 5000 && typeof n === "string") notFoundList.push(n);
          }
        } catch {
          totals.total += slice.length; totals.skipped += slice.length; failed += slice.length;
          for (const f of slice) if (problemFiles.length < 5000) problemFiles.push(f.name);
        }
        sent += slice.length;
        setProgress({ label: "Uploading photos", sent, of: files.length });
      }
      setPResult({ ...totals, notFoundList: notFoundList.length ? notFoundList : problemFiles });
      if (failed) {
        setProblem({ status: 400, title: `${failed.toLocaleString()} photo${failed === 1 ? "" : "s"} could not be sent`,
          detail: `The rest were processed — a photo is held back when the scan is larger than 8 MB, or a batch is refused. Reduce those scans and upload just them again (re-uploading is idempotent, so nothing duplicates).${notFoundList.length ? "" : " Download the list below to see which files."}` });
      }
      notify(`${(files.length - failed).toLocaleString()} of ${files.length.toLocaleString()} passport photo${files.length === 1 ? "" : "s"} processed`);
    } catch {
      setProblem({ status: 400, title: "The photos could not be read.", detail: "Select image files (JPEG or PNG) named by the student's JAMB registration number." });
    } finally {
      setBusy(false); setProgress(null);
    }
  }

  function downloadNotFound() {
    if (!pResult?.notFoundList.length) return;
    const blob = buildXlsx(["JAMB Number (no matching student)"], pResult.notFoundList.map((n) => [n]), "Skipped photos");
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "passports — no matching student.xlsx";
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function upload(kind: Tab, file: File) {
    setBusy(true);
    setProblem(null);
    setResult(null);
    setProgress(null);
    setRejected(null);
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
      const rej: Record<string, string>[] = [];
      const matricKind = kind === "biodata" || kind === "pgstudents" || kind === "students" || kind === "jamb" || kind === "pgresearch";
      for (let i = 0; i < dataRows.length; i++) {
        const r = dataRows[i];
        if (r.some((c) => String(c ?? "").trim() !== "")) {
          const o = applyRow(cols, r);
          if (o.matric && !/^matric/i.test(o.matric)) {
            /* on the matric-keyed imports, hold back a row with no valid matriculation number so the
               officer can download and fix it, rather than send it only for the server to reject it */
            if (matricKind && !MATRIC_OK.test(o.matric)) rej.push({ ...o, reason: "No valid matriculation number" });
            else rows.push(o);
          }
        }
        if ((i & 8191) === 8191) { setProgress({ label: "Preparing the rows", sent: i + 1, of: dataRows.length }); await new Promise((res) => setTimeout(res)); }
      }
      setRejected(rej.length ? { rows: rej, kind } : null);
      if (!rows.length) { setProblem({ status: 400, title: rej.length ? "No row had a valid matriculation number." : "The file had no rows to read.", detail: rej.length ? `${rej.length.toLocaleString()} rows were read but none has a valid matriculation number. Download them below, fix the numbers, and upload again.` : "Export the list from the old portal and upload it." }); return; }
      const path = kind === "biodata" ? "/api/bff/api/v1/results/legacy/biodata"
        : kind === "pgstudents" ? "/api/bff/api/v1/results/legacy/pg-students"
        : kind === "students" ? "/api/bff/api/v1/results/legacy/students"
        : kind === "jamb" ? "/api/bff/api/v1/results/legacy/jamb-numbers"
        : kind === "pgregistration" ? "/api/bff/api/v1/results/legacy/pg-registration"
        : kind === "pgresults" ? "/api/bff/api/v1/results/legacy/pg-results"
        : kind === "pgresearch" ? "/api/bff/api/v1/results/legacy/pg-research"
        : kind === "registration" ? "/api/bff/api/v1/results/legacy/registration" : "/api/bff/api/v1/results/legacy/results";
      /* a large export goes up in batches — the importers upsert on the matriculation number, so each
         batch is independent and idempotent; the counts are summed as the batches come back */
      const scoped = kind === "registration" || kind === "results" || kind === "pgregistration" || kind === "pgresults";
      const twoSemesters = kind === "pgregistration" || kind === "pgresults"; // postgraduate study has two semesters
      /* registration and results carry the session and semester on each row (falling back to the fields
         above), so one file can hold many sessions and semesters — group by them and load each group */
      type G = { session: string; semester: number; rows: Record<string, string>[] };
      let groups: G[];
      if (scoped) {
        const map = new Map<string, G>();
        for (const o of rows) {
          const ses = o.session && /^[0-9]{4}\/[0-9]{4}$/.test(o.session) ? o.session : session;
          const sem = o.semester ? semNum(o.semester) : Number(semester);
          if (!/^[0-9]{4}\/[0-9]{4}$/.test(ses) || !(twoSemesters ? [1, 2] : [1, 2, 3]).includes(sem)) continue;
          const key = `${ses}|${sem}`;
          let g = map.get(key);
          if (!g) { g = { session: ses, semester: sem, rows: [] }; map.set(key, g); }
          g.rows.push(o);
        }
        groups = [...map.values()];
        if (!groups.length) { setProblem({ status: 400, title: "No session and semester to load against.", detail: "Add Session (YYYY/YYYY) and Semester columns to the file, or choose them in the fields above." }); return; }
      } else {
        groups = [{ session: "", semester: 0, rows }];
      }

      const CHUNK = kind === "biodata" || kind === "pgstudents" ? 200 : 400;
      const totalRows = groups.reduce((n, g) => n + g.rows.length, 0);
      const totals: Record<string, number> = {};
      let firstErr: string | null = null;
      let sent = 0;
      setProgress({ label: "Importing", sent: 0, of: totalRows });
      for (const g of groups) {
        for (let i = 0; i < g.rows.length; i += CHUNK) {
          const chunk = g.rows.slice(i, i + CHUNK);
          const body = scoped ? { session: g.session, semester: g.semester, rows: chunk } : { rows: chunk };
          const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Legacy ${kind} imported${scoped ? ` for ${g.session} semester ${g.semester}` : ""}: rows ${sent + 1} to ${sent + chunk.length} of ${totalRows}`) }, body: JSON.stringify(body) });
          const j = await r.json().catch(() => null);
          if (!r.ok) {
            const base = (j ?? { status: r.status, title: r.statusText }) as Problem;
            setProblem({ ...base, detail: `${base.detail ? base.detail + " " : ""}${sent.toLocaleString()} of ${totalRows.toLocaleString()} rows were imported before this batch was refused. The import is idempotent — fix the file and upload it again; the rows already in will update, not duplicate.` });
            if (Object.keys(totals).length) setResult({ tab: kind, counts: totals, firstError: firstErr });
            return;
          }
          const counts = (j ?? {}) as Record<string, unknown>;
          for (const [k, v] of Object.entries(counts)) if (typeof v === "number") totals[k] = (totals[k] ?? 0) + v;
          if (!firstErr && typeof counts.first_error === "string" && counts.first_error) firstErr = counts.first_error;
          sent += chunk.length;
          setProgress({ label: "Importing", sent, of: totalRows });
        }
      }
      setResult({ tab: kind, counts: totals, firstError: firstErr });
      notify(`Legacy ${kind} import complete`);
      /* a student upload may satisfy results that were held earlier for a student not on the register
         yet — reconcile them now, so results and biodata can be uploaded in either order (V204) */
      if (kind === "biodata" || kind === "pgstudents" || kind === "students") {
        try {
          const rr = await fetch("/api/bff/api/v1/results/legacy/reconcile-results", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Reconcile held past results after a student upload") }, body: "{}" });
          const rj = (await rr.json().catch(() => null)) as { reconciled?: number } | null;
          if (rr.ok && rj && (rj.reconciled ?? 0) > 0) notify(`${rj.reconciled} held past result${rj.reconciled === 1 ? "" : "s"} now matched to the newly loaded students`);
        } catch { /* reconcile is best-effort; a manual re-upload of the results also reconciles */ }
        try {
          const pr = await fetch("/api/bff/api/v1/results/legacy/reconcile-pg-results", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Reconcile held postgraduate results after a student upload") }, body: "{}" });
          const pj = (await pr.json().catch(() => null)) as { reconciled?: number } | null;
          if (pr.ok && pj && (pj.reconciled ?? 0) > 0) notify(`${pj.reconciled} held postgraduate result${pj.reconciled === 1 ? "" : "s"} now matched to the newly loaded students`);
        } catch { /* reconcile is best-effort */ }
      }
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
      headers: ["Matriculation Number", "JAMB Registration Number", "Surname", "Other Names", "Sex", "Date of Birth", "Programme", "Level",
        "Entry Mode", "Entry Session", "Phone", "Email", "Address", "Nationality", "State", "LGA",
        "Guardian Name", "Guardian Address", "Sponsor Name", "Sponsor Address", "Next of Kin Name", "Next of Kin Address",
        "Extracurricular", "Application No", "School Id"],
      example: ["MOAUM/CSC/22/0001", "202441922663AF", "Doe", "John Ada (example — delete this row)", "M", "2003-05-14", "Computer Science", "300",
        "UTME", "2022/2023", "08030000000", "john.doe@example.com", "12 Example Street, Makurdi", "Nigeria", "Benue", "Makurdi",
        "Mr Doe Senior", "12 Example Street, Makurdi", "Mr Doe Senior", "12 Example Street, Makurdi", "Jane Doe", "12 Example Street, Makurdi",
        "Football, Debate", "10000000AA", "S001"],
    },
    students: {
      name: "Students biodata",
      headers: ["Matriculation Number", "Surname", "Other Names", "Programme", "Sex", "Date of Birth", "Entry Mode", "Entry Session", "Level", "School Id"],
      example: ["MOAUM/CSC/22/0001", "Doe", "John Ada (example — delete this row)", "Computer Science", "M", "2003-05-14", "UTME", "2022/2023", "300", "S001"],
    },
    pgstudents: {
      name: "Postgraduate students",
      headers: ["matno", "appno", "Surname", "sex", "dob", "programme", "level", "mode_entry", "school_id",
        "phone", "email", "login_email", "address", "nationality", "state", "lga",
        "guardianname", "guardianaddress", "sponsorname", "sponsoraddress", "nokname", "nokaddress", "extracurricular", "faculty", "department"],
      example: ["MOAU/AM/BSM/MSC/24/0002", "20251005707251", "Barnabas Aondoawase Iorpuu (example — delete this row)", "Male", "2001-06-15", "C14569", "800", "MST", "S002",
        "08030000000", "", "student@example.com", "12 Example Street, Makurdi", "NIGERIA", "Benue", "Ushongo",
        "Guardian Name", "Guardian Address", "Sponsor Name", "Sponsor Address", "Next of Kin", "Next of Kin Address", "Reading", "MS", "BSM"],
    },
    registration: {
      name: "Course registration",
      headers: ["Matriculation Number", "Course Code", "Units", "Level", "Session", "Semester"],
      example: ["MOAUM/CSC/22/0001", "CSC 301", "3", "300", "2024/2025", "First"],
    },
    results: {
      name: "Past results",
      headers: ["Matriculation Number", "Course Code", "Level", "Session", "Semester", "CA", "Exam", "Total", "Outcome"],
      example: ["MOAUM/CSC/22/0001", "CSC 301", "300", "2024/2025", "First", "25", "55", "80", "GRADED"],
    },
    pgregistration: {
      name: "PG course registration",
      headers: ["Matriculation Number", "Course Code", "Course Title", "Units", "Kind", "Mode", "Session", "Semester"],
      example: ["MOAU/AM/BSM/MSC/24/0002", "BSM 801", "Advanced Management Theory", "3", "CORE", "Full-time", "2024/2025", "First"],
    },
    pgresults: {
      name: "PG past results",
      headers: ["Matriculation Number", "Course Code", "Course Title", "Units", "Kind", "Session", "Semester", "CA", "Exam", "Total"],
      example: ["MOAU/AM/BSM/MSC/24/0002", "BSM 801", "Advanced Management Theory", "3", "CORE", "2024/2025", "First", "35", "50", "85"],
    },
    pgresearch: {
      name: "PG research and thesis",
      headers: ["Matriculation Number", "Topic", "Stage", "Supervisor", "Second Supervisor", "Viva Score", "Viva Grade", "Viva Outcome",
        "Proposal Approved", "Seminar Held", "Title Registered", "Viva Held", "Final Submitted", "Cleared", "Award Date"],
      example: ["MOAU/AM/BSM/MSC/24/0002", "Working capital and firm value on the NGX", "AWARDED", "Prof. A. Doe", "Dr B. Roe", "78", "A", "PASS_MINOR",
        "2024-03-01", "2024-06-10", "2024-07-01", "2025-02-14", "2025-03-20", "2025-04-05", "2025-05-30"],
    },
    jamb: {
      name: "JAMB numbers",
      headers: ["Matriculation Number", "JAMB Registration Number"],
      example: ["MOAUM/CSC/22/0001", "202441922663AF"],
    },
    passports: { name: "Passport photos", headers: [], example: [] }, // no spreadsheet — image files, handled separately
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

  function downloadRejected() {
    if (!rejected) return;
    const pref = ["matric", "surname", "otherNames", "name", "programme", "level", "reason"];
    const present = new Set(rejected.rows.flatMap((r) => Object.keys(r)));
    const keys = [...pref.filter((k) => present.has(k)), ...[...present].filter((k) => !pref.includes(k))];
    const label = (k: string) => k === "matric" ? "Matriculation Number" : k === "otherNames" ? "Other Names" : k.charAt(0).toUpperCase() + k.slice(1);
    const blob = buildXlsx(keys.map(label), rejected.rows.map((r) => keys.map((k) => r[k] ?? "")), "Skipped rows");
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "skipped rows — no valid matric.xlsx";
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  const needScope = tab === "registration" || tab === "results" || tab === "pgregistration" || tab === "pgresults";
  const pgTwoSemesters = tab === "pgregistration" || tab === "pgresults";
  /* the file now carries Session and Semester per row; the fields below are only a fallback for a file
     that has neither column, so the upload is never gated on them */
  const scopeReady = true;
  const CARDS: Record<Tab, [string, string][]> = {
    biodata: [["rows", "Rows read"], ["created", "New students"], ["updated", "Updated"], ["contacts", "Contacts set"], ["biography", "Biography values"], ["accounts", "Sign-in accounts"], ["no_programme", "Programme not found"], ["bad_number", "Bad matric format"], ["skipped", "Skipped (error)"]],
    pgstudents: [["rows", "Rows read"], ["created", "New students"], ["updated", "Updated"], ["contacts", "Contacts set"], ["biography", "Biography values"], ["accounts", "Sign-in accounts"], ["no_programme", "Programme not found"], ["bad_number", "Bad matric format"], ["skipped", "Skipped (error)"]],
    students: [["rows", "Rows read"], ["created", "New students"], ["updated", "Updated"], ["no_programme", "Programme not found"], ["bad_number", "Bad matric format"], ["skipped", "Skipped (error)"]],
    registration: [["rows", "Rows read"], ["students", "Students"], ["offerings", "Courses"], ["registrations", "Registrations"], ["no_student", "No such student"], ["no_course", "No such course"]],
    results: [["rows", "Rows read"], ["students", "Students"], ["results", "Results posted"], ["registrations", "Registrations made"], ["held", "Held (student not loaded yet)"], ["no_course", "No such course"], ["no_mark", "No / invalid mark"], ["skipped", "Skipped (error)"]],
    pgregistration: [["rows", "Rows read"], ["students", "Students"], ["courses", "New courses"], ["registrations", "Registrations made"], ["no_student", "Not a PG student"], ["skipped", "Skipped (error)"]],
    pgresults: [["rows", "Rows read"], ["students", "Students"], ["results", "Results posted"], ["courses", "New courses"], ["held", "Held (student not loaded yet)"], ["no_mark", "No / invalid mark"], ["skipped", "Skipped (error)"]],
    pgresearch: [["rows", "Rows read"], ["matched", "Records set"], ["created", "New records"], ["updated", "Updated"], ["supervisors", "Supervisors set"], ["no_student", "Not a PG student"], ["skipped", "Skipped (error)"]],
    jamb: [["rows", "Rows read"], ["updated", "JAMB numbers set"], ["no_student", "No such student"]],
    passports: [], // photos have their own summary
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
    if (kind === "biodata" || kind === "pgstudents") {
      add("jamb", at(/jamb/, /utme\s*reg/));
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
      add("schoolId", at(/school\s*id/, /schoolid/, /^school$/));
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
      add("schoolId", at(/school\s*id/, /schoolid/, /^school$/));
    } else if (kind === "jamb") {
      add("jamb", at(/jamb/, /jamb\s*reg/, /jamb\s*no/, /jamb\s*number/, /utme\s*reg/));
    } else if (kind === "pgresearch") {
      add("topic", at(/topic/, /research\s*title/, /thesis\s*title/, /project\s*title/, /dissertation\s*title/, /^title$/));
      add("stage", at(/^stage$/, /status/));
      add("supervisor", at(/^supervisor$/, /main\s*supervisor/, /first\s*supervisor/, /supervisor\s*1/));
      add("supervisor2", at(/second\s*supervisor/, /supervisor\s*2/));
      add("coSupervisor", at(/co-?\s*supervisor/));
      add("vivaScore", at(/viva\s*score/, /defence\s*score/));
      add("vivaGrade", at(/viva\s*grade/, /research\s*grade/));
      add("vivaOutcome", at(/viva\s*outcome/, /defence\s*outcome/, /^outcome$/, /recommendation/));
      add("plagiarism", at(/plagiar/, /similarity/));
      add("pgsr", at(/pgsr/));
      add("proposalApproved", at(/proposal\s*approv/, /proposal\s*date/));
      add("seminarHeld", at(/seminar/));
      add("titleRegistered", at(/title\s*regist/));
      add("panelConstituted", at(/panel/));
      add("draftSubmitted", at(/draft/));
      add("vivaHeld", at(/viva\s*(held|date)/, /defence\s*date/));
      add("finalSubmitted", at(/final\s*sub/, /bound/));
      add("cleared", at(/clear/));
      add("awardDate", at(/award/, /graduat/));
    } else {
      add("course", at(/course\s*code/, /^course$/, /^code$/, /subject\s*code/));
      add("units", at(/unit/, /^cu$/, /credit/));
      add("level", at(/^level$/, /^lvl$/));
      add("session", at(/session/));
      add("semester", at(/semester/, /^sem$/));
      if (kind === "pgregistration" || kind === "pgresults") {
        add("title", at(/course\s*title/, /^title$/, /descrip/));
        add("kind", at(/^kind$/, /^type$/, /category/));
        add("mode", at(/study\s*mode/, /^mode$/));
      }
      if (kind === "results" || kind === "pgresults") {
        add("ca", at(/\bca\b/, /continuous/, /c\.a/));
        add("exam", at(/exam/, /examination/));
        add("total", at(/total/, /^score$/, /^mark$/, /aggregate/));
      }
      if (kind === "results") {
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
      {!may ? <Note kind="bad" title="This desk is for the ICT Directorate, the Examinations Officer, HODs and Records">Your office may not migrate records.</Note> : null}

      <div className="card"><div className="card__body">
        <div className="role-tabs" role="tablist">
          {([["biodata", "1 · Student biography (full)"], ["students", "1 · Students (core only)"], ["pgstudents", "1 · Postgraduate students"], ["registration", "2 · Course registration"], ["results", "3 · Past results"], ["pgregistration", "PG · registration"], ["pgresults", "PG · results"], ["pgresearch", "PG · research"], ["jamb", "4 · JAMB numbers"], ["passports", "5 · Passport photos"]] as [Tab, string][]).map(([k, l]) => (
            <button key={k} type="button" role="tab" aria-selected={tab === k ? "true" : "false"} onClick={() => { setTab(k); setResult(null); setProblem(null); setPResult(null); }}>{l}</button>
          ))}
        </div>
      </div></div>

      {problem ? <ProblemNotice problem={problem} /> : null}

      {tab === "passports" ? (
        <Panel title="Passport photos exported from the old portal" right="Matched by JAMB reg no in the file name">
          <PBody>
            <div className="sub2" style={{ marginBottom: 8 }}>
              Select the passport image files. Each file must be named by the student&rsquo;s <b>JAMB registration number</b>
              (for example <span className="tnum">202412345AB.jpg</span>); the number is read from the file name and matched
              to the student. A photo whose number matches no student on the portal is <b>skipped</b> and listed, not
              guessed at. JPEG or PNG; the photo then shows on the student&rsquo;s dashboard, course form and receipts.
            </div>
            <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
              <label className={`btn btn--primary${!may || busy ? " btn--disabled" : ""}`} style={{ cursor: may && !busy ? "pointer" : "not-allowed", margin: 0, opacity: !may ? 0.6 : 1 }}>
                {busy
                  ? (progress ? `${progress.label} — ${progress.sent.toLocaleString()} of ${progress.of.toLocaleString()}…` : "Uploading…")
                  : "Upload passport photos"}
                <input type="file" accept="image/*" multiple style={{ display: "none" }} disabled={!may || busy}
                       onChange={(e) => { const fs = Array.from(e.target.files ?? []); if (fs.length) void uploadPassports(fs); e.target.value = ""; }} />
              </label>
              <span className="sub2">You can select many files at once.</span>
            </div>
          </PBody>
        </Panel>
      ) : (
      <Panel title={tab === "biodata" ? "Student biography exported from the old portal" : tab === "pgstudents" ? "Postgraduate students exported from the old portal" : tab === "students" ? "Students exported from the old portal" : tab === "jamb" ? "JAMB registration numbers (matric → JAMB)" : tab === "registration" ? "Course registration of a past semester" : tab === "pgregistration" ? "Postgraduate course registration of a past semester" : tab === "pgresults" ? "Postgraduate past results of a semester" : tab === "pgresearch" ? "Postgraduate research / thesis records" : "Past results of a semester"}
             right={tab === "students" || tab === "biodata" || tab === "pgstudents" ? "The first step" : tab === "jamb" ? "So passport photos match" : tab === "pgresearch" ? "Matched by matriculation number" : `${session || "session"} · ${semesterText(Number(semester))}`}>
        <PBody>
          {needScope ? (
            <div className="grid grid--3">
              <Field id="mg-ses" label="Session (fallback)" hint="Used only for rows with no Session column, e.g. 2024/2025"><input id="mg-ses" className="ctl tnum" value={session} placeholder="2024/2025" onChange={(e) => setSession(e.target.value.trim())} /></Field>
              <Field id="mg-sem" label="Semester (fallback)"><select id="mg-sem" className="ctl" value={pgTwoSemesters && semester === "3" ? "1" : semester} onChange={(e) => setSemester(e.target.value)}><option value="1">First semester</option><option value="2">Second semester</option>{pgTwoSemesters ? null : <option value="3">Third semester</option>}</select></Field>
              <div />
            </div>
          ) : null}
          <div className="sub2" style={{ marginBottom: 8 }}>
            {tab === "pgstudents" ? "Columns read: matno (the MOAU/… postgraduate matric), appno, name, sex, dob, programme (the old-portal code, e.g. C14569 — created as a POST GRADUATE programme in the shared table from the faculty, department and the award in the matric when it is not there yet), level (kept as 700/800/900), phone, email/login_email, address, nationality, state, LGA, guardian, sponsor, next-of-kin, extracurricular. Entry mode is set to POSTGRADUATE and the school to S002 (→ BMAS curriculum), so each lands on their own postgraduate dashboard. A matric sign-in account is created — the student signs in first with their matric number and is asked to set a password."
              : tab === "biodata" ? "Columns read: matriculation number, JAMB registration number, name, programme, sex, date of birth, level, entry mode/session, phone, email, address, nationality, state, LGA, guardian, sponsor, next-of-kin and school id (S001/S003 undergraduate → CCMAS from 2023/2024, S002 postgraduate → BMAS). The matric number is kept exactly as the old portal issued it; a date in any common form and a phone with a lost leading zero are normalised; a matric sign-in account is created (no password is taken from the file — the student sets one through the reset, sent to the phone or email here)."
              : tab === "students" ? "Columns read: matriculation number, name (or surname + other names), programme (code or name), sex, date of birth, entry mode, level. The session is read from the matric number when not given."
              : tab === "jamb" ? "Columns read: matriculation number and JAMB registration number. The student is matched by matriculation number and their JAMB number is set on the register. Do this before uploading passport photos named by JAMB number, so a legacy student (who carries no JAMB number yet) can be matched. The application number is NOT the JAMB number — upload the real JAMB registration number."
              : tab === "registration" ? "Columns read: matriculation number, course code, units, level, session (YYYY/YYYY) and semester (First/Second or 1/2). The session and semester are read per row, so one file can carry many — an approved registration and its course entries are created for each. Student name and programme are not needed: the student is matched by matriculation number."
              : tab === "pgregistration" ? "Columns read: matriculation number, course code, course title, units, kind (CORE/ELECTIVE/DEFICIENCY/RESEARCH), mode (full/part-time), session (YYYY/YYYY) and semester (First/Second or 1/2 — postgraduate study has two semesters). The student must be a postgraduate already on the register (upload the postgraduate students first). A course not yet in the postgraduate catalogue is created for the student's programme from the title/units/kind; an endorsed registration and its entries are created for each session/semester."
              : tab === "pgresults" ? "Columns read: matriculation number, course code, course title, units, kind, session, semester, and the mark. Fill CA and Exam where the old record splits them (they add to the total); otherwise leave those blank and fill Total (0–100). The result is graded on the postgraduate scale (A 70+, B 60–69, C 50–59, F below 50 — no D/E, Policy 16), so it counts on the postgraduate register's CGPA. A row whose student is not on the register yet is HELD and posts automatically once that student is uploaded (in either order)."
              : tab === "pgresearch" ? "Columns read: matriculation number, topic, stage, supervisor(s), viva score/grade/outcome, plagiarism %, and the milestone dates (proposal approved, seminar, title registered, viva held, final submitted, cleared, award). The student must be a postgraduate on the register. The research record is created if absent (its degree kind — Project/Dissertation/Thesis — derived from the programme) and set from the row; the stage is taken as stated, else inferred from the furthest milestone present (an award date ⇒ AWARDED). Supervisors named on the row replace the record's current ones, so a re-upload updates rather than duplicates."
              : "Columns read: matriculation number, course code, level, session, semester, and the mark. The unit is taken from the course record, not the file — any “Units” column in the export (a 1/2/3 status code) is ignored. Fill CA and Exam where the old record splits them (they add to the total); otherwise leave those blank and fill Total (0–100). Session and semester are read per row; outcome is read when present. A row whose student is not on the register yet is HELD, not lost — it posts automatically once that student is uploaded (in either order)."}
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
                : `Upload ${tab === "biodata" ? "biography" : tab === "pgstudents" ? "postgraduate students" : tab === "students" ? "students" : tab === "jamb" ? "JAMB numbers" : tab === "registration" ? "registration" : tab === "pgregistration" ? "PG registration" : tab === "pgresults" ? "PG results" : tab === "pgresearch" ? "PG research" : "results"} file`}
              <input type="file" accept=".xlsx" style={{ display: "none" }} disabled={!may || (needScope && !scopeReady) || busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(tab, f); e.target.value = ""; }} />
            </label>
            {needScope && !scopeReady ? <span className="sub2">Enter the session (YYYY/YYYY) and semester first.</span> : null}
          </div>
          <div className="sub2" style={{ marginTop: 8 }}>Download the template, fill it from the old-portal export (delete the example row), and upload it. Column names are matched flexibly, so an export that already has these columns can be uploaded as-is.</div>
        </PBody>
      </Panel>
      )}

      {tab === "passports" && pResult ? (
        <>
          <Tiles items={[
            ["Photos uploaded", String(pResult.total), null, ""],
            ["Stored on record", String(pResult.stored + pResult.attached), (pResult.stored + pResult.attached) > 0 ? "var(--green-ink)" : null, "matched and saved"],
            ["No matching student", String(pResult.notFound), pResult.notFound > 0 ? "var(--red-ink)" : null, "skipped"],
            ["Could not read", String(pResult.skipped), pResult.skipped > 0 ? "var(--red-ink)" : null, "not an image"],
          ]} />
          <Note kind={pResult.notFound || pResult.skipped ? "info" : "ok"} title="Photos processed"
                action={pResult.notFoundList.length ? <Btn kind="ghost" onClick={downloadNotFound}>Download the skipped numbers</Btn> : undefined}>
            {pResult.stored + pResult.attached} photo{pResult.stored + pResult.attached === 1 ? "" : "s"} matched a student and were saved.
            {pResult.notFound > 0 ? <> {pResult.notFound} file{pResult.notFound === 1 ? "" : "s"} matched no student on the portal and were skipped — download the list to see which numbers.</> : null}
            {pResult.skipped > 0 ? <> {pResult.skipped} file{pResult.skipped === 1 ? "" : "s"} could not be read as an image.</> : null}
            {" "}Uploading the same photo again replaces it, so this is safe to re-run.
          </Note>
        </>
      ) : null}

      {result && result.tab === tab ? (
        <>
          <Tiles items={CARDS[tab].map(([k, label]) => {
            const v = Number(result.counts[k] ?? 0);
            const bad = (/no_|bad_|skipped/.test(k)) && v > 0;
            return [label, String(v), bad ? "var(--red-ink)" : /created|results|registrations|students/.test(k) ? "var(--green-ink)" : null, ""] as [string, string, string | null, string];
          })} />
          <Note kind="ok" title="Imported">
            {tab === "biodata" || tab === "pgstudents" ? `${result.counts.created ?? 0} ${tab === "pgstudents" ? "postgraduate students" : "students"} created, ${result.counts.updated ?? 0} updated; ${result.counts.contacts ?? 0} contacts and ${result.counts.biography ?? 0} biography values saved; ${result.counts.accounts ?? 0} sign-in accounts provisioned.`
              : tab === "students" ? `${result.counts.created ?? 0} students created, ${result.counts.updated ?? 0} updated.`
              : tab === "jamb" ? `${result.counts.updated ?? 0} JAMB number${result.counts.updated === 1 ? "" : "s"} set on the register. You can now upload passport photos named by JAMB number.`
              : tab === "registration" ? `${result.counts.registrations ?? 0} registrations across ${result.counts.offerings ?? 0} courses.`
              : tab === "pgregistration" ? `${result.counts.registrations ?? 0} postgraduate registrations for ${result.counts.students ?? 0} students${(result.counts.courses ?? 0) > 0 ? `; ${result.counts.courses} new courses added to the postgraduate catalogue` : ""}.`
              : tab === "pgresearch" ? `${result.counts.matched ?? 0} research records set (${result.counts.created ?? 0} new, ${result.counts.updated ?? 0} updated); ${result.counts.supervisors ?? 0} supervisors recorded.`
              : tab === "pgresults" ? `${result.counts.results ?? 0} postgraduate results posted${(result.counts.held ?? 0) > 0 ? `; ${result.counts.held} held for students not loaded yet (they post automatically once those students are uploaded)` : ""}. These count on the postgraduate register's CGPA.`
              : `${result.counts.results ?? 0} results posted${(result.counts.held ?? 0) > 0 ? `; ${result.counts.held} held for students not loaded yet (they post automatically once those students are uploaded)` : ""}.`}
            {" "}Rows that did not match are counted above; fix them at source and re-upload — the import is idempotent.
            {(result.counts.no_student ?? 0) > 0 ? <> <b>Import the students first</b> if a number was not found.</> : null}
            {(result.counts.skipped ?? 0) > 0 ? <> <b>{result.counts.skipped} row{result.counts.skipped === 1 ? "" : "s"} were skipped by an error</b> and are not on the register; the first was — <span className="tnum">{result.firstError ?? "no detail"}</span>. Fix those rows and re-upload.</> : null}
          </Note>
        </>
      ) : null}

      {rejected && rejected.kind === tab ? (
        <Note kind="bad" title={`${rejected.rows.length.toLocaleString()} row${rejected.rows.length === 1 ? "" : "s"} had no valid matriculation number and were not uploaded`}
              action={<Btn kind="ghost" onClick={downloadRejected}>Download the skipped rows</Btn>}>
          A matriculation number must be the University&rsquo;s own (MOAUM/DEPT/YY/NNNN) or a legacy old-portal number. These rows carried none the importer could read (often a blank or &ldquo;NULL&rdquo;). Download them, fix the numbers at source, and upload again &mdash; the import is idempotent, so the rows already in are untouched.
        </Note>
      ) : null}

      <Note kind="info" title="Order matters, and re-uploading is safe">
        <Pil kind="grey">1</Pil> Students &rarr; <Pil kind="grey">2</Pil> Registration &rarr; <Pil kind="grey">3</Pil> Results.
        A result needs the student and the course registration to exist, so the results import also creates the
        registration entry if it is missing. Uploading the same file again updates rather than duplicates.
        A large export is sent up in batches automatically, so a file of any size uploads in one go; if a batch is
        refused part-way, the rows already in stand and you can simply upload the file again.
      </Note>

      {may ? (
        <Note kind="info" title="How migrated students sign in — no password reset needed">
          A student brought over from the old portal signs in with their <b>number as both the username and the
          password</b> (matriculation number, or admission / JAMB number). The portal then makes them choose a real
          password on that first sign-in. Nothing is pre-set for the whole cohort — each student&rsquo;s first password
          is granted at the moment they sign in, so there is nothing to run here.
        </Note>
      ) : null}
    </>
  );
}
