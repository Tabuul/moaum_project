"use client";

/** Upload a department's course structure from the CCMAS document (or an .xlsx). ICT/Super and the HOD load it;
 *  each course is created and offered to the programme at its level. Level and semester come from the document's
 *  own headings (100 Level / First Semester); nothing is typed. (V084) */
import { useState } from "react";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { docxBlocks } from "@/lib/docx";
import { xlsxRows, buildXlsx } from "@/lib/xlsx";
import { brandedXlsx, brandedPrint, downloadBlob, docSerial } from "@/lib/exportbrand";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { semesterText } from "@/lib/student-portal";

interface ProgrammeOption { code: string; name: string; facultyName?: string }
interface Row { code: string; title: string; units: string; status: string; level: number | null; semester: number | null; lh: string; ph: string; programmeCode?: string; category?: string }
interface Loaded { code: string; title: string; units: number; level: number; semester: number | null; kind: string; basis: string }
const MAY = ["ict"];

export function Courses({ programmes, actingOffice }: { programmes: ProgrammeOption[]; actingOffice: string | null }) {
  const may = MAY.includes(actingOffice ?? "");
  const [programme, setProgramme] = useState("");
  const [curriculum, setCurriculum] = useState("CCMAS_MOAU");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [preview, setPreview] = useState<Row[] | null>(null);
  const [loaded, setLoaded] = useState<Loaded[] | null>(null);
  const [listing, setListing] = useState(false);
  const [unregistered, setUnregistered] = useState<{ programme: string; rows: number }[]>([]);
  const [exporting, setExporting] = useState(false);
  const [openSession, setOpenSession] = useState("");
  const [openSem, setOpenSem] = useState("1");
  const [openMsg, setOpenMsg] = useState<string | null>(null);

  async function openRegistration() {
    if (!/^\d{4}\/\d{4}$/.test(openSession.trim())) { setProblem({ status: 400, title: "Enter the session as YYYY/YYYY, e.g. 2024/2025." }); notifyProblem({ status: 400, title: "Enter the session as YYYY/YYYY, e.g. 2024/2025." }); return; }
    setBusy(true); setProblem(null); setOpenMsg(null);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue/open-registration?session=${encodeURIComponent(openSession.trim())}&semester=${openSem}`, { method: "POST", headers: { "X-Reason": reasonHeader(`Open course registration for ${openSession.trim()} semester ${openSem}`) } });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setOpenMsg(`${Number(j?.opened ?? 0).toLocaleString()} course${Number(j?.opened ?? 0) === 1 ? "" : "s"} opened for ${openSession.trim()} · ${semesterText(Number(openSem))}. Students now see the real courses at registration.`);
      notify(`Registration opened · ${Number(j?.opened ?? 0).toLocaleString()} courses`);
    } finally { setBusy(false); }
  }

  async function viewLoaded(prog = programme) {
    if (!prog) return;
    setListing(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue/offered?programme=${encodeURIComponent(prog)}`);
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setLoaded(j as Loaded[]);
    } finally {
      setListing(false);
    }
  }

  function downloadTemplate() {
    const blob = buildXlsx(
      ["Course Code", "Course Title", "Units", "Status", "Level", "Semester", "Lecture Hours", "Practical Hours"],
      [
        ["BSU-SOC-101", "Introduction to Sociology", "3", "C", "100", "1", "45", ""],
        ["BSU-SOC-102", "Social Institutions", "2", "C", "100", "2", "30", ""],
      ],
      "Course structure",
    );
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "Course structure template.xlsx";
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function rowsFromDocx(buf: ArrayBuffer): Promise<Row[]> {
    const blocks = await docxBlocks(buf);
    const rows: Row[] = [];
    let level: number | null = null;
    let semester: number | null = null;
    for (const b of blocks) {
      if (b.kind === "p") {
        const lm = b.text.match(/(\d{3})\s*level/i);
        if (lm) level = Number(lm[1]);
        if (/first|1st/i.test(b.text) && /semester/i.test(b.text)) semester = 1;
        else if (/second|2nd/i.test(b.text) && /semester/i.test(b.text)) semester = 2;
        else if (/third|3rd/i.test(b.text) && /semester/i.test(b.text)) semester = 3;
        continue;
      }
      for (const r of b.rows) {
        const code = (r[0] ?? "").trim();
        if (!code || /^course\s*code$/i.test(code) || /^total$/i.test((r[1] ?? "").trim())) continue;
        rows.push({ code, title: (r[1] ?? "").trim(), units: (r[2] ?? "").trim(), status: (r[3] ?? "").trim(), level, semester, lh: (r[4] ?? "").trim(), ph: (r[5] ?? "").trim() });
      }
    }
    return rows;
  }

  async function rowsFromXlsx(buf: ArrayBuffer): Promise<Row[]> {
    const grid = await xlsxRows(buf);
    const header = (grid[0] ?? []).map((c) => String(c ?? "").trim().toLowerCase());
    const at = (names: string[]) => header.findIndex((h) => names.some((n) => h.includes(n)));
    /* "Course Code" also contains "course", so match the title on "title" first and, only failing that,
       a "course" column that is not the code column — otherwise the title reads the code */
    const codeIx = at(["code"]);
    let titleIx = at(["title"]);
    if (titleIx < 0) titleIx = header.findIndex((h, i) => i !== codeIx && h.includes("course"));
    const ci = { code: codeIx, title: titleIx, units: at(["unit"]), status: at(["status"]), level: at(["level"]), sem: at(["semester", "sem"]), lh: at(["lh", "lecture"]), ph: at(["ph", "practical"]),
      prog: at(["programme_code", "programme code", "programmecode"]), cat: at(["course_category", "course category", "curriculum", "category"]) };
    if (ci.code < 0) return [];
    return grid.slice(1).filter((r) => (r[ci.code] ?? "").toString().trim()).map((r) => {
      const g = (i: number) => (i >= 0 ? String(r[i] ?? "").trim() : "");
      const lv = Number(g(ci.level).replace(/[^0-9]/g, ""));
      /* the semester cell may read a word ("First"/"Second"/"Third") or a digit — accept both */
      const semRaw = g(ci.sem);
      let sm = Number(semRaw.replace(/[^0-9]/g, ""));
      if (!sm) sm = /first|1st/i.test(semRaw) ? 1 : /second|2nd/i.test(semRaw) ? 2 : /third|3rd/i.test(semRaw) ? 3 : 0;
      return { code: g(ci.code), title: g(ci.title), units: g(ci.units), status: g(ci.status), level: lv || null, semester: sm || null, lh: g(ci.lh), ph: g(ci.ph), programmeCode: g(ci.prog) || undefined, category: g(ci.cat) || undefined };
    }).filter((x) => !/^course\s*code$/i.test(x.code));
  }

  async function read(file: File) {
    setBusy(true);
    setProblem(null);
    setMsg(null);
    setPreview(null);
    try {
      const buf = await file.arrayBuffer();
      const rows = file.name.toLowerCase().endsWith(".xlsx") ? await rowsFromXlsx(buf) : await rowsFromDocx(buf);
      if (!rows.length) { setProblem({ status: 400, title: "No courses were found in that file.", detail: "Download the template, or upload the CCMAS .docx (its tables of Course Code, Title, Units, Status) or an .xlsx with those columns." }); notifyProblem({ status: 400, title: "No courses were found in that file.", detail: "Download the template, or upload the CCMAS .docx (its tables of Course Code, Title, Units, Status) or an .xlsx with those columns." }); return; }
      setPreview(rows);
    } catch {
      setProblem({ status: 400, title: "That file could not be read.", detail: "Upload the department's CCMAS .docx or an .xlsx." }); notifyProblem({ status: 400, title: "That file could not be read.", detail: "Upload the department's CCMAS .docx or an .xlsx." });
    } finally {
      setBusy(false);
    }
  }

  async function upload() {
    if (!preview) return;
    const perRow = preview.some((r) => r.programmeCode);
    if (!perRow && !programme) { setProblem({ status: 400, title: "Choose a programme, or upload a file with a programme_code column.", detail: "A file without a Programme Code column loads against the one programme chosen above." }); notifyProblem({ status: 400, title: "Choose a programme, or upload a file with a programme_code column.", detail: "A file without a Programme Code column loads against the one programme chosen above." }); return; }
    setBusy(true);
    setProblem(null);
    setMsg(null);
    setUnregistered([]);
    try {
      /* group the rows by the programme (and curriculum) each row names, so a single file of many
         departments loads at once; a file without a programme_code column uses the one chosen above */
      const groups = new Map<string, { programme: string; curriculum: string; rows: Row[] }>();
      for (const row of preview) {
        const pc = row.programmeCode || programme;
        if (!pc) continue;
        const cur = (row.category || curriculum || "").toUpperCase();
        const key = `${pc}|${cur}`;
        let g = groups.get(key);
        if (!g) { g = { programme: pc, curriculum: ["CCMAS", "BMAS", "CCMAS_BSU", "CCMAS_MOAU"].includes(cur.replace(/[- ]/g, "_")) ? cur.replace(/[- ]/g, "_") : curriculum, rows: [] }; groups.set(key, g); }
        g.rows.push(row);
      }
      const totals = { courses: 0, offers: 0, bad_code: 0, skipped: 0 };
      let firstErr: string | null = null;
      let done = 0;
      const notRegistered: { programme: string; rows: number }[] = [];
      for (const g of groups.values()) {
        const r = await fetch("/api/bff/api/v1/catalogue/import", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Course structure uploaded for ${g.programme}`) }, body: JSON.stringify({ programme: g.programme, rows: g.rows, curriculum: g.curriculum }) });
        const j = await r.json().catch(() => null);
        if (!r.ok) {
          const base = (j ?? { status: r.status, title: r.statusText }) as Problem;
          const text = `${base.title ?? ""} ${base.detail ?? ""}`;
          /* an unregistered programme is data, not a fault — set it aside and keep loading the rest */
          if (/no programme is coded or named/i.test(text)) {
            const seen = notRegistered.find((x) => x.programme === g.programme);
            if (seen) seen.rows += g.rows.length; else notRegistered.push({ programme: g.programme, rows: g.rows.length });
            continue;
          }
          setProblem({ ...base, detail: `${base.detail ? base.detail + " " : ""}${done} of ${groups.size} programmes were loaded before this one (${g.programme}) was refused. The import is idempotent — fix and upload again.` });
          setUnregistered(notRegistered);
          return;
        }
        const c = (j ?? {}) as { courses?: number; offers?: number; bad_code?: number; skipped?: number; first_error?: string | null };
        totals.courses += Number(c.courses ?? 0); totals.offers += Number(c.offers ?? 0);
        totals.bad_code += Number(c.bad_code ?? 0); totals.skipped += Number(c.skipped ?? 0);
        if (!firstErr && c.first_error) firstErr = c.first_error;
        done += 1;
      }
      setUnregistered(notRegistered);
      const skippedRows = notRegistered.reduce((s, x) => s + x.rows, 0);
      setMsg(`${totals.courses} courses created or updated across ${done} programme${done === 1 ? "" : "s"}${totals.bad_code ? ` · ${totals.bad_code} rows had a code the catalogue could not accept` : ""}${totals.skipped ? ` · ${totals.skipped} skipped by an error (first: ${firstErr ?? "no detail"})` : ""}${notRegistered.length ? ` · ${skippedRows} rows across ${notRegistered.length} programme${notRegistered.length === 1 ? "" : "s"} not yet on the register were held back` : ""}.`);
      notify(`Course structure loaded · ${totals.courses} courses`);
      setPreview(null);
      if (programme) void viewLoaded();
    } finally {
      setBusy(false);
    }
  }

  const byLevel = preview ? [...new Set(preview.map((r) => r.level))].filter(Boolean).sort() : [];

  const LOADED_COLS = ["Code", "Title", "Units", "Level", "Semester", "Basis"];
  const loadedRows = () => (loaded ?? []).map((c) => [c.code, c.title, c.units, c.level, c.semester ?? "", c.basis]);
  const progLabel = programmes.find((p) => p.code === programme)?.name ?? programme;
  async function exportLoadedXlsx() {
    downloadBlob(await brandedXlsx(`Courses offered — ${progLabel}`, LOADED_COLS, loadedRows(), { serial: docSerial("CRS") }), `Courses ${programme}.xlsx`);
  }
  function exportLoadedPdf() {
    brandedPrint(`Courses offered — ${progLabel}`, `${(loaded ?? []).length} courses`, LOADED_COLS, loadedRows(), docSerial("CRS"));
  }

  /* the whole uploaded catalogue — every course offered to every programme */
  const ALL_COLS = ["Faculty", "Programme Code", "Programme", "Level", "Semester", "Course Code", "Title", "Units", "Kind", "Basis", "Curriculum"];
  interface AllRow { faculty: string; programme_code: string; programme: string; level: number; semester: number | null; code: string; title: string; units: number; kind: string; basis: string; curriculum: string | null }
  async function fetchAll(): Promise<AllRow[] | null> {
    setExporting(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/catalogue/catalogue-export");
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      return j as AllRow[];
    } finally { setExporting(false); }
  }
  const allRows = (rows: AllRow[]) => rows.map((c) => [c.faculty, c.programme_code, c.programme, c.level, c.semester ?? "", c.code, c.title, c.units, c.kind, c.basis, c.curriculum ?? ""]);
  async function exportAllXlsx() {
    const rows = await fetchAll(); if (!rows) return;
    if (!rows.length) { setMsg("No courses have been uploaded yet."); return; }
    downloadBlob(await brandedXlsx("All courses in the catalogue", ALL_COLS, allRows(rows), { serial: docSerial("CAT") }), "All courses (catalogue).xlsx");
  }
  async function exportAllPdf() {
    const rows = await fetchAll(); if (!rows) return;
    if (!rows.length) { setMsg("No courses have been uploaded yet."); return; }
    brandedPrint("All courses in the catalogue", `${rows.length} courses across all programmes`, ALL_COLS, allRows(rows), docSerial("CAT"));
  }

  return (
    <>
      <Note kind="info" title="Load a department's approved course structure">
        Upload the CCMAS document for a programme. Each course — with its units, status and lecture/practical hours — is
        created in the catalogue and offered to the programme at its level; the level and semester are read from the
        document&rsquo;s own headings. Uploading again updates rather than duplicates. The Directorate of ICT and the
        Super Administrator may load any department&rsquo;s; an HOD loads their own.
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Directorate of ICT, the Super Administrator and HODs">Your office may not upload a course structure.</Note> : null}

      <Panel title="The programme and its document" right="CCMAS structure">
        <PBody>
          <Field id="cu-prog" label="Programme" hint="The programme these courses belong to">
            <SearchSelect id="cu-prog" value={programme} placeholder="Search a programme…"
              options={programmes.map((p) => ({ value: p.code, label: `${p.name}${p.facultyName ? ` · ${p.facultyName}` : ""}` }))}
              onChange={(v) => { setProgramme(v); setLoaded(null); }} />
          </Field>
          <Field id="cu-curr" label="Curriculum" hint="The track this structure is for — a student sees only the rows of their own track; a row for any cohort is shared">
            <select id="cu-curr" className="ctl" value={curriculum} onChange={(e) => setCurriculum(e.target.value)}>
              <option value="CCMAS_MOAU">CCMAS — MOAU cohorts (entered 2024/2025 on)</option>
              <option value="CCMAS_BSU">CCMAS — BSU cohort (entered 2023/2024)</option>
              <option value="BMAS">BMAS — cohorts up to 2022/2023</option>
              <option value="CCMAS">CCMAS — any cohort (shared rows)</option>
            </select>
          </Field>
          <div className="row">
            <Btn kind="ghost" onClick={downloadTemplate}>Download template</Btn>
            <Btn kind="ghost" disabled={!programme || listing} onClick={() => void viewLoaded()}>{listing ? "Loading…" : "View loaded courses"}</Btn>
            <label className={`btn btn--primary m-0${!may || busy ? " btn--disabled" : ""}`} style={{ cursor: may && !busy ? "pointer" : "not-allowed", opacity: !may ? 0.6 : 1 }}>
              {busy ? "Reading…" : "Choose the course document (.docx or .xlsx)"}
              <input type="file" accept=".docx,.xlsx" style={{ display: "none" }} disabled={!may || busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void read(f); e.target.value = ""; }} />
            </label>
            {!programme ? <span className="sub2">Choose a programme above, or upload a file that has a <b>programme_code</b> column to load every department at once.</span> : null}
          </div>
          <div className="sub2 mt-2">The course structure applies to <b>all sessions</b> — there is no session to enter. The template carries a <b>Semester</b> column alongside Level, so each course says which semester it runs — no reliance on the document&rsquo;s headings. Status: C core, R required, E elective, GST. Fill it, or upload the CCMAS .docx as before.</div>
          <div className="row mt-3" style={{ paddingTop: "var(--s-3)", borderTop: "1px solid var(--line)" }}>
            <span className="sub2"><b>Download every uploaded course</b> across all programmes:</span>
            <Btn kind="ghost" disabled={exporting} onClick={() => void exportAllXlsx()}>{exporting ? "Preparing…" : "All courses — Excel"}</Btn>
            <Btn kind="ghost" disabled={exporting} onClick={() => void exportAllPdf()}>{exporting ? "Preparing…" : "All courses — PDF"}</Btn>
          </div>
        </PBody>
      </Panel>

      {problem ? <ProblemNotice problem={problem} /> : null}
      {msg ? <Note kind="ok" title="Course structure loaded">{msg}</Note> : null}

      <Panel title="Open course registration for a session" right="After the structure is uploaded">
        <PBody>
          <div className="sub2 mb-2">Registration shows a course only once it is <b>offered</b> for the session. Open the session here to offer every uploaded course of that semester — then students see their real programme and level courses instead of demo data. Safe to run again; already-offered courses are skipped.</div>
          <div className="row row--end">
            <Field id="or-ses" label="Session"><input id="or-ses" className="ctl tnum" style={{ maxWidth: 160 }} value={openSession} placeholder="2024/2025" onChange={(e) => setOpenSession(e.target.value)} /></Field>
            <Field id="or-sem" label="Semester"><select id="or-sem" className="ctl" value={openSem} onChange={(e) => setOpenSem(e.target.value)}><option value="1">First</option><option value="2">Second</option><option value="3">Third</option></select></Field>
            <Btn kind="primary" disabled={busy || !may} onClick={() => void openRegistration()}>{busy ? "Working…" : "Open course registration"}</Btn>
          </div>
          {openMsg ? <Note kind="ok" title="Course registration opened">{openMsg}</Note> : null}
        </PBody>
      </Panel>

      {unregistered.length ? (
        <Note kind="bad" title={`${unregistered.length} programme${unregistered.length === 1 ? "" : "s"} not on the register — their courses were held back`}>
          <div className="sub2 mb-2">These programme codes are in the file but not yet registered (mostly postgraduate). Register them first, then upload again — the import is idempotent, so the courses already loaded stay put.</div>
          <div className="row row--tight" style={{ maxHeight: 180, overflowY: "auto", border: "1px solid var(--line)", borderRadius: "var(--r-md)", padding: "var(--s-2)" }}>
            {unregistered.map((u) => (
              <span key={u.programme} className="tnum t-sm" style={{ background: "var(--chip)", borderRadius: "var(--r)", padding: "2px 6px" }}>{u.programme} · {u.rows}</span>
            ))}
          </div>
          <div className="sub2 mt-2">
            <Btn kind="ghost" onClick={() => { const blob = buildXlsx(["Programme Code", "Rows held back"], unregistered.map((u) => [u.programme, String(u.rows)]), "Unregistered programmes"); const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = "Unregistered programmes.xlsx"; a.click(); URL.revokeObjectURL(a.href); }}>Download the list</Btn>
          </div>
        </Note>
      ) : null}

      {loaded ? (
        <Panel title="Courses offered to this programme" right={<span className="row">
          <span className="sub2">{loaded.length} course{loaded.length === 1 ? "" : "s"} · {loaded.reduce((n, c) => n + Number(c.units || 0), 0)} units</span>
          <Btn kind="ghost" disabled={!loaded.length} onClick={() => void exportLoadedXlsx()}>Download Excel</Btn>
          <Btn kind="ghost" disabled={!loaded.length} onClick={exportLoadedPdf}>Download PDF</Btn>
        </span>}>
          {loaded.length ? (
            <div className="tablewrap" style={{ maxHeight: 320, overflowY: "auto", border: "1px solid var(--line)", borderRadius: "var(--r-md)" }}>
              <table className="tbl--data">
                <thead><tr><th>Code</th><th>Title</th><th>Units</th><th>Level</th><th>Sem</th><th>Basis</th></tr></thead>
                <tbody>
                  {loaded.map((c) => (
                    <tr key={c.code + c.level}><td className="tnum">{c.code}</td><td>{c.title}</td><td className="tnum">{c.units}</td><td className="tnum">{c.level}</td><td className="tnum">{c.semester ?? "—"}</td><td className="sub2">{c.basis}</td></tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : <PBody><div className="sub2">No course has been loaded for this programme yet. Upload the structure below.</div></PBody>}
        </Panel>
      ) : null}

      {preview ? (
        <Panel title="Read from the document — check, then load" right={`${preview.length} course${preview.length === 1 ? "" : "s"}${byLevel.length ? ` · levels ${byLevel.join(", ")}` : ""}`}>
          <PBody>
            <Tiles items={[
              ["Courses read", String(preview.length), null, "Ready to load"],
              ["Levels", byLevel.length ? byLevel.join(", ") : "—", null, "From the headings"],
              ["With a code the rule rejects", String(preview.filter((r) => !/^[A-Z][A-Z0-9 /-]{2,19}$/.test(r.code.toUpperCase())).length), null, "Shown, not loaded"],
            ]} />
            <div className="tablewrap" style={{ maxHeight: 260, overflowY: "auto", border: "1px solid var(--line)", borderRadius: "var(--r-md)" }}>
              <table className="tbl--data">
                <thead><tr><th>Code</th><th>Title</th><th>Units</th><th>Status</th><th>Level</th><th>Sem</th></tr></thead>
                <tbody>
                  {preview.slice(0, 200).map((r, i) => (
                    <tr key={i}><td className="tnum">{r.code}</td><td>{r.title}</td><td className="tnum">{r.units}</td><td>{r.status}</td><td className="tnum">{r.level ?? "—"}</td><td className="tnum">{r.semester ?? "—"}</td></tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="row mt-3">
              <Btn kind="primary" size="md" disabled={busy || !may} onClick={() => void upload()}>{busy ? "Loading…" : `Load ${preview.length} courses`}</Btn>
              <Btn kind="ghost" size="md" disabled={busy} onClick={() => setPreview(null)}>Cancel</Btn>
            </div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
