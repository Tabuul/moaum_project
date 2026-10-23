"use client";

/** Upload a department's course structure from the CCMAS document (or an .xlsx). ICT/Super and the HOD load it;
 *  each course is created and offered to the programme at its level. Level and semester come from the document's
 *  own headings (100 Level / First Semester); nothing is typed. (V084) */
import { useState } from "react";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { docxBlocks } from "@/lib/docx";
import { structureRowsFromDocx } from "@/lib/structure-docx";
import { xlsxRows, buildXlsx } from "@/lib/xlsx";
import { brandedXlsx, brandedPrint, downloadBlob, docSerial } from "@/lib/exportbrand";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { semesterText } from "@/lib/student-portal";
import { courseLabel, titleChoiceKey } from "@/lib/course-code";

interface ProgrammeOption { code: string; name: string; facultyName?: string }
interface Row { code: string; title: string; units: string; status: string; level: number | null; /** V386: "Both" for a course taught in the first and the second */ semester: number | "Both" | null; lh: string; ph: string; programmeCode?: string; category?: string; classification?: string }
interface Loaded { code: string; title: string; units: number; level: number; semester: number | null; kind: string; basis: string }
/** V369: what loading the structure would do to one GST/EPS course (catalogue.structure_placements) */
type Change = "NEW_TO_OFFICE" | "NEW_NO_OFFICE" | "TO_OFFICE" | "MARKED_GENERAL_NO_OFFICE" | "BACK_TO_DEPARTMENT" | "KEPT_WITH_OFFICE" | "KEPT_WITH_DEPARTMENT" | "OTHER_OFFICE_HOLDS";
interface Placement { code: string; title: string; programme: string; status: string; department: string | null; beforeOffice: string | null; beforeKind: string | null; afterOffice: string | null; afterKind: string; change: Change }
/** V460: an existing course whose units this programme would take differently once the structure loads (catalogue import/units) */
interface UnitChange { code: string; title: string; programme: string; level: number; fileUnits: number; courseUnits: number; nowUnits: number; department: string | null; change: "PROGRAMME_OWN" | "BACK_TO_COURSE" }
interface UnitChanges { rows: UnitChange[]; counts: { programmeOwn: number; backToCourse: number } }
interface Placements { placements: Placement[]; counts: { toGst: number; toEps: number; noOffice: number; backToDepartment: number; keptWithOffice: number; keptWithDepartment: number; otherOffice?: number } }
/** V646: a row whose code the pool holds under other titles (catalogue.structure_title_choices) — the same course or a separate one */
interface HeldCourse { code: string; title: string; curriculum: string | null; dept: string | null; level: number | null; semester: number | null; variant: string | null }
interface TitleChoiceRow { programme: string; code: string; title: string; level: number | null; held: HeldCourse[] }
type TitleDecision = { choice: "SAME"; sameAs: string } | { choice: "SEPARATE" };
/* the status (or Classification) as the file says it — V370: EPS is read whole, never as E */
const statusWord = (s: string) => ({ C: "Core", R: "Required", E: "Elective", G: "General (G)", GST: "General (GST)", EPS: "Entrepreneurship (EPS)" } as Record<string, string>)[s.toUpperCase()]
  ?? ({ C: "Core", R: "Required", E: "Elective", G: "General (G)" } as Record<string, string>)[s.charAt(0).toUpperCase()] ?? s;
const changeWord = (p: Placement) => ({
  NEW_TO_OFFICE: `New — filed with the ${p.afterOffice} office`,
  NEW_NO_OFFICE: "New — marked general, but no office's code family reaches it; it stays with its department until an office takes it",
  TO_OFFICE: `Goes to the ${p.afterOffice} office`,
  MARKED_GENERAL_NO_OFFICE: "Marked general, but no office's code family reaches it; no office's",
  BACK_TO_DEPARTMENT: "Back to its department — it was marked general with no office",
  KEPT_WITH_OFFICE: `Stays the ${p.beforeOffice} office's — the file marks it ${statusWord(p.status)}, but only the office gives a course back`,
  KEPT_WITH_DEPARTMENT: "Stays with its department — an office gave it back, so the file's G is not applied",
  OTHER_OFFICE_HOLDS: `Stays the ${p.beforeOffice} office's — the file says EPS; the EPS office can ask the ${p.beforeOffice} office for it`,
}[p.change]);
const MAY = ["ict"];

export function Courses({ programmes, actingOffice }: { programmes: ProgrammeOption[]; actingOffice: string | null }) {
  const may = MAY.includes(actingOffice ?? "");
  const [programme, setProgramme] = useState("");
  const [curriculum, setCurriculum] = useState("CCMAS_MOAU");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [preview, setPreview] = useState<Row[] | null>(null);
  const [placements, setPlacements] = useState<Placements | null>(null);
  // V460: the existing courses whose units this structure would change for its programme
  const [unitChanges, setUnitChanges] = useState<UnitChanges | null>(null);
  // V646: the rows whose code the pool holds under other titles, and the choice made for each (by code and title)
  const [titleRows, setTitleRows] = useState<TitleChoiceRow[] | null>(null);
  const [decisions, setDecisions] = useState<Record<string, TitleDecision>>({});
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

  /* the document's tables, their columns found by their headings (a leading S/N passed over, a table that runs on to the
     next page read with the columns before it) — lib/structure-docx */
  async function rowsFromDocx(buf: ArrayBuffer): Promise<Row[]> {
    return structureRowsFromDocx(await docxBlocks(buf));
  }

  async function rowsFromXlsx(buf: ArrayBuffer): Promise<Row[]> {
    const grid = await xlsxRows(buf);
    const header = (grid[0] ?? []).map((c) => String(c ?? "").trim().toLowerCase());
    const at = (names: string[]) => header.findIndex((h) => names.some((n) => h.includes(n)));
    /* "Course Code" also contains "course", so match the title on "title" first and, only failing that,
       a "course" column that is not the code column — otherwise the title reads the code */
    // the course's code: a "Course Code" column, else a code column that is not the programme's — a Programme Code column
    // before it was read as every course's code
    const exactCode = header.findIndex((h) => /course[\s_]*code/.test(h));
    const codeIx = exactCode >= 0 ? exactCode : header.findIndex((h) => h.includes("code") && !h.includes("programme"));
    let titleIx = at(["title"]);
    if (titleIx < 0) titleIx = header.findIndex((h, i) => i !== codeIx && h.includes("course"));
    const ci = { code: codeIx, title: titleIx, units: at(["unit"]), status: at(["status"]), level: at(["level"]), sem: at(["semester", "sem"]), lh: at(["lh", "lecture"]), ph: at(["ph", "practical"]),
      prog: at(["programme_code", "programme code", "programmecode"]), cat: at(["course_category", "course category", "curriculum", "category"]),
      // V370: a GST/EPS classification column, read alongside the status
      cls: at(["classification", "gst/eps", "gst_eps"]) };
    if (ci.code < 0) return [];
    return grid.slice(1).filter((r) => (r[ci.code] ?? "").toString().trim()).map((r) => {
      const g = (i: number) => (i >= 0 ? String(r[i] ?? "").trim() : "");
      const lv = Number(g(ci.level).replace(/[^0-9]/g, ""));
      /* the semester cell may read a word ("First"/"Second"/"Third") or a digit — accept both */
      const semRaw = g(ci.sem);
      // V386: "Both", "1 & 2", "First and Second" — taught in both semesters, read by the server as such
      const both = /^\s*(both|b|1\s*(&|and|\/|,|\+)\s*2|(first|1st)(\s*semester)?\s*(&|and|\/|,|\+)\s*(second|2nd))/i.test(semRaw);
      let sm = both ? 0 : Number(semRaw.replace(/[^0-9]/g, ""));
      if (!sm && !both) sm = /first|1st/i.test(semRaw) ? 1 : /second|2nd/i.test(semRaw) ? 2 : /third|3rd/i.test(semRaw) ? 3 : 0;
      return { code: g(ci.code), title: g(ci.title), units: g(ci.units), status: g(ci.status), level: lv || null, semester: both ? ("Both" as const) : sm || null, lh: g(ci.lh), ph: g(ci.ph), programmeCode: g(ci.prog) || undefined, category: g(ci.cat) || undefined, classification: g(ci.cls) || undefined };
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
      void readPlacements(rows, programme);
    } catch {
      setProblem({ status: 400, title: "That file could not be read.", detail: "Upload the department's CCMAS .docx or an .xlsx." }); notifyProblem({ status: 400, title: "That file could not be read.", detail: "Upload the department's CCMAS .docx or an .xlsx." });
    } finally {
      setBusy(false);
    }
  }

  /* group the rows by the programme (and curriculum) each row names, so a single file of many
     departments loads at once; a file without a programme_code column uses the one chosen above */
  function groupsOf(rows: Row[], prog: string) {
    const groups = new Map<string, { programme: string; curriculum: string; rows: Row[] }>();
    for (const row of rows) {
      const pc = row.programmeCode || prog;
      if (!pc) continue;
      const cur = (row.category || curriculum || "").toUpperCase();
      const key = `${pc}|${cur}`;
      let g = groups.get(key);
      if (!g) { g = { programme: pc, curriculum: ["CCMAS", "BMAS", "CCMAS_BSU", "CCMAS_MOAU"].includes(cur.replace(/[- ]/g, "_")) ? cur.replace(/[- ]/g, "_") : curriculum, rows: [] }; groups.set(key, g); }
      g.rows.push(row);
    }
    return groups;
  }

  /* V369: before loading, what the structure would do to the GST and EPS offices' courses — read by the server, nothing written */
  async function readPlacements(rows: Row[], prog: string) {
    setPlacements(null);
    setUnitChanges(null);
    setTitleRows(null);
    setDecisions({});
    if (!may) return;
    const groups = [...groupsOf(rows, prog).values()].map((g) => ({ programme: g.programme, rows: g.rows }));
    if (!groups.length) return;
    const body = JSON.stringify({ groups });
    const [r, u, t] = await Promise.all([
      fetch("/api/bff/api/v1/catalogue/import/placements", { method: "POST", headers: { "Content-Type": "application/json" }, body }),
      fetch("/api/bff/api/v1/catalogue/import/units", { method: "POST", headers: { "Content-Type": "application/json" }, body }),
      fetch("/api/bff/api/v1/catalogue/import/titles", { method: "POST", headers: { "Content-Type": "application/json" }, body }),
    ]);
    const j = await r.json().catch(() => null);
    if (r.ok && j) setPlacements(j as Placements);
    const k = await u.json().catch(() => null);
    if (u.ok && k) setUnitChanges(k as UnitChanges);
    const ti = await t.json().catch(() => null);
    if (t.ok && Array.isArray(ti)) setTitleRows(ti as TitleChoiceRow[]);
  }

  /* V646: one choice for each code and title the pool holds under other titles — the rows of every programme that carry it share it */
  const titleChoices = (() => {
    const seen = new Map<string, TitleChoiceRow & { programmes: string[] }>();
    for (const t of titleRows ?? []) {
      const k = titleChoiceKey(t.code, t.title);
      const s = seen.get(k);
      if (s) { if (!s.programmes.includes(t.programme)) s.programmes.push(t.programme); } else seen.set(k, { ...t, programmes: [t.programme] });
    }
    return [...seen.entries()].map(([key, t]) => ({ key, ...t }));
  })();
  const undecided = titleChoices.filter((t) => !decisions[t.key]).length;
  const decideAll = (choice: "SAME" | "SEPARATE") => setDecisions(Object.fromEntries(titleChoices.map((t) => [t.key,
    choice === "SAME" ? { choice: "SAME", sameAs: t.held[0]?.code ?? t.code } : { choice: "SEPARATE" }] as [string, TitleDecision])));
  /* the rows sent with their choice: titleChoice SAME (sameAs the course named) or SEPARATE, by the row's code and title */
  const withChoices = (rows: Row[]) => rows.map((r) => {
    const d = decisions[titleChoiceKey(r.code, r.title)];
    return !d ? r : d.choice === "SAME" ? { ...r, titleChoice: "SAME", sameAs: d.sameAs } : { ...r, titleChoice: "SEPARATE" };
  });

  async function upload() {
    if (!preview) return;
    const perRow = preview.some((r) => r.programmeCode);
    if (!perRow && !programme) { setProblem({ status: 400, title: "Choose a programme, or upload a file with a programme_code column.", detail: "A file without a Programme Code column loads against the one programme chosen above." }); notifyProblem({ status: 400, title: "Choose a programme, or upload a file with a programme_code column.", detail: "A file without a Programme Code column loads against the one programme chosen above." }); return; }
    // V646: a code the pool holds under another title is loaded only once the same course or a separate one is chosen
    if (undecided > 0) {
      const pr = { status: 400, title: `Choose for ${undecided} course${undecided === 1 ? "" : "s"}: the same course, or a separate one`, detail: "The pool holds these codes under other titles. Choose under \"Same code, different title\" below." };
      setProblem(pr); notifyProblem(pr); return;
    }
    setBusy(true);
    setProblem(null);
    setMsg(null);
    setUnregistered([]);
    try {
      const groups = groupsOf(preview, programme);
      const totals = { courses: 0, offers: 0, bad_code: 0, skipped: 0, existing: 0, classes_opened: 0 };
      let firstErr: string | null = null;
      let done = 0;
      const notRegistered: { programme: string; rows: number }[] = [];
      for (const g of groups.values()) {
        const r = await fetch("/api/bff/api/v1/catalogue/import", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Course structure uploaded for ${g.programme}`) }, body: JSON.stringify({ programme: g.programme, rows: withChoices(g.rows), curriculum: g.curriculum }) });
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
        const c = (j ?? {}) as { courses?: number; offers?: number; bad_code?: number; skipped?: number; first_error?: string | null; existing?: number; classes_opened?: number };
        totals.courses += Number(c.courses ?? 0); totals.offers += Number(c.offers ?? 0); totals.existing += Number(c.existing ?? 0);
        totals.classes_opened += Number(c.classes_opened ?? 0); // V405/V406: the classes the upload opened in semesters already open
        totals.bad_code += Number(c.bad_code ?? 0); totals.skipped += Number(c.skipped ?? 0);
        if (!firstErr && c.first_error) firstErr = c.first_error;
        done += 1;
      }
      setUnregistered(notRegistered);
      const skippedRows = notRegistered.reduce((s, x) => s + x.rows, 0);
      setMsg(`${totals.courses} courses created or updated across ${done} programme${done === 1 ? "" : "s"}${totals.existing ? ` · ${totals.existing} row${totals.existing === 1 ? "" : "s"} bound another department's course` : ""}${totals.classes_opened ? ` · ${totals.classes_opened} class${totals.classes_opened === 1 ? "" : "es"} opened in the semesters already running, ready to allocate` : ""}${totals.bad_code ? ` · ${totals.bad_code} rows had a code the catalogue could not accept` : ""}${totals.skipped ? ` · ${totals.skipped} skipped by an error (first: ${firstErr ?? "no detail"})` : ""}${notRegistered.length ? ` · ${skippedRows} rows across ${notRegistered.length} programme${notRegistered.length === 1 ? "" : "s"} not yet on the register were held back` : ""}.`);
      notify(`Course structure loaded · ${totals.courses} courses`);
      setPreview(null);
      setPlacements(null);
      setUnitChanges(null);
      setTitleRows(null);
      setDecisions({});
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
        Upload the CCMAS document for a programme. Uploading again updates rather than duplicates. An HOD loads their own department&rsquo;s.
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Directorate of ICT, the Super Administrator and HODs">Your office may not upload a course structure.</Note> : null}

      <Panel title="The programme and its document" right="CCMAS structure">
        <PBody>
          <Field id="cu-prog" label="Programme" hint="The programme these courses belong to">
            <SearchSelect id="cu-prog" value={programme} placeholder="Search a programme…"
              options={programmes.map((p) => ({ value: p.code, label: `${p.name}${p.facultyName ? ` · ${p.facultyName}` : ""}` }))}
              onChange={(v) => { setProgramme(v); setLoaded(null); if (preview) void readPlacements(preview, v); }} />
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
          <div className="sub2 mt-2">Applies to <b>all sessions</b>. Status: C core, R required, E elective, G or GST for General Studies, EPS for Entrepreneurship Studies (a Classification column of GST or EPS works too).</div>
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
          <div className="sub2 mb-2">Registration shows a course only once it is <b>offered</b> for the session. Offers every uploaded course of the semester; safe to run again.</div>
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
          <div className="sub2 mb-2">Register these programmes first, then upload again.</div>
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
            <div className="tablewrap" tabIndex={0} style={{ maxHeight: 320, overflowY: "auto", border: "1px solid var(--line)", borderRadius: "var(--r-md)" }}>
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
            <div className="tablewrap" tabIndex={0} style={{ maxHeight: 260, overflowY: "auto", border: "1px solid var(--line)", borderRadius: "var(--r-md)" }}>
              <table className="tbl--data">
                <thead><tr><th>Code</th><th>Title</th><th>Units</th><th>Status</th><th>Level</th><th>Sem</th></tr></thead>
                <tbody>
                  {preview.slice(0, 200).map((r, i) => (
                    <tr key={i}><td className="tnum">{r.code}</td><td>{r.title}</td><td className="tnum">{r.units}</td><td>{r.status}</td><td className="tnum">{r.level ?? "—"}</td><td className="tnum">{r.semester ?? "—"}</td></tr>
                  ))}
                </tbody>
              </table>
            </div>
            {placements && placements.placements.length ? (
              <div className="mt-3">
                <Note kind="info" title="GST and EPS: what loading this does">
                  {[
                    placements.counts.toGst ? `${placements.counts.toGst} course${placements.counts.toGst === 1 ? "" : "s"} to the GST office` : null,
                    placements.counts.toEps ? `${placements.counts.toEps} to the EPS office` : null,
                    placements.counts.noOffice ? `${placements.counts.noOffice} marked general that no office holds` : null,
                    placements.counts.backToDepartment ? `${placements.counts.backToDepartment} back to their department` : null,
                    placements.counts.keptWithOffice ? `${placements.counts.keptWithOffice} the file marks departmental but an office holds — left with the office` : null,
                    placements.counts.keptWithDepartment ? `${placements.counts.keptWithDepartment} the file marks G but an office gave back — left with the department` : null,
                    placements.counts.otherOffice ? `${placements.counts.otherOffice} the file says EPS but the GST office holds — left with the GST office` : null,
                  ].filter(Boolean).join(" · ")}. The offices are told and confirm it.
                </Note>
                <div className="tablewrap" tabIndex={0} style={{ maxHeight: 260, overflowY: "auto", border: "1px solid var(--line)", borderRadius: "var(--r-md)" }}>
                  <table className="tbl--data">
                    <thead><tr><th>Code</th><th>Title</th><th>Programme</th><th>The file says</th><th>What loading does</th></tr></thead>
                    <tbody>
                      {placements.placements.map((p) => (
                        <tr key={p.code}><td className="tnum">{p.code}</td><td>{p.title}{p.department ? <div className="sub2">{p.department}</div> : null}</td><td className="tnum">{p.programme}</td><td>{statusWord(p.status)}</td><td className="sub2">{changeWord(p)}</td></tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            ) : null}
            {unitChanges && unitChanges.rows.length ? (
              <div className="mt-3">
                <Note kind="info" title="Units: what loading this does">
                  {[
                    unitChanges.counts.programmeOwn ? `${unitChanges.counts.programmeOwn} existing course${unitChanges.counts.programmeOwn === 1 ? "" : "s"} taken by the programme at the file's units, its own` : null,
                    unitChanges.counts.backToCourse ? `${unitChanges.counts.backToCourse} back to the course's own units` : null,
                  ].filter(Boolean).join(" · ")}. A course&rsquo;s own units stay as they are, so every other programme keeps what it takes; the programme&rsquo;s students not yet scored follow.
                </Note>
                <div className="tablewrap" tabIndex={0} style={{ maxHeight: 260, overflowY: "auto", border: "1px solid var(--line)", borderRadius: "var(--r-md)" }}>
                  <table className="tbl--data">
                    <thead><tr><th>Code</th><th>Title</th><th>Programme</th><th>Level</th><th>Now</th><th>The file says</th><th>What loading does</th></tr></thead>
                    <tbody>
                      {unitChanges.rows.map((u) => (
                        <tr key={`${u.programme}-${u.level}-${u.code}`}>
                          <td className="tnum">{u.code}</td><td>{u.title}{u.department ? <div className="sub2">{u.department}</div> : null}</td>
                          <td className="tnum">{u.programme}</td><td className="tnum">{u.level}</td><td className="tnum">{u.nowUnits}</td><td className="tnum">{u.fileUnits}</td>
                          <td>{u.change === "PROGRAMME_OWN"
                            ? `This programme takes it at ${u.fileUnits} unit${u.fileUnits === 1 ? "" : "s"}; the course stays at ${u.courseUnits}`
                            : `Back to the course's ${u.courseUnits} unit${u.courseUnits === 1 ? "" : "s"}`}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            ) : null}
            {titleChoices.length ? (
              <div className="mt-3">
                <Note kind={undecided ? "bad" : "info"} title={`Same code, different title — ${titleChoices.length} course${titleChoices.length === 1 ? "" : "s"}${undecided ? `, ${undecided} to choose` : ""}`}>
                  The pool already holds these codes under other titles, and one code may carry more than one course. For each, choose whether
                  the file&rsquo;s row is the same course (it keeps the title the pool holds) or a separate course under the same code (created with
                  the file&rsquo;s title for this upload&rsquo;s curriculum, with its own classes and results). Nothing is merged and no title is written over.
                  <div className="row row--inline row--tight mt-2">
                    <Btn kind="ghost" size="sm" onClick={() => decideAll("SAME")}>All: the same course</Btn>
                    <Btn kind="ghost" size="sm" onClick={() => decideAll("SEPARATE")}>All: separate courses</Btn>
                  </div>
                </Note>
                <div className="tablewrap" tabIndex={0} style={{ maxHeight: 320, overflowY: "auto", border: "1px solid var(--line)", borderRadius: "var(--r-md)" }}>
                  <table className="tbl--data">
                    <thead><tr><th>Code</th><th>Title in the file</th><th>Held under the code</th><th>Programme</th><th>Choice</th></tr></thead>
                    <tbody>
                      {titleChoices.map((t) => {
                        const d = decisions[t.key];
                        return (
                          <tr key={t.key}>
                            <td className="tnum">{t.code}</td>
                            <td>{t.title}</td>
                            <td>{t.held.map((h) => <div key={h.code} className="sub2">{courseLabel(h.code, h.title, h.curriculum)}{h.curriculum && !h.variant ? ` (${h.curriculum})` : ""}</div>)}</td>
                            <td className="tnum sub2">{t.programmes.join(", ")}</td>
                            <td>
                              <select className="ctl" aria-label={`Choice for ${t.code} ${t.title}`} value={!d ? "" : d.choice === "SEPARATE" ? "SEPARATE" : `SAME:${d.sameAs}`}
                                onChange={(e) => { const v = e.target.value; setDecisions((x) => ({ ...x, [t.key]: v === "SEPARATE" ? { choice: "SEPARATE" } : { choice: "SAME", sameAs: v.slice(5) } })); }}>
                                <option value="" disabled>Choose…</option>
                                {t.held.map((h) => <option key={h.code} value={`SAME:${h.code}`}>The same course as {courseLabel(h.code, h.title, h.curriculum)}</option>)}
                                <option value="SEPARATE">A separate course under {t.code}</option>
                              </select>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              </div>
            ) : null}
            <div className="row mt-3">
              <Btn kind="primary" size="md" disabled={busy || !may || undecided > 0} onClick={() => void upload()}>{busy ? "Loading…" : `Load ${preview.length} courses`}</Btn>
              <Btn kind="ghost" size="md" disabled={busy} onClick={() => { setPreview(null); setPlacements(null); setUnitChanges(null); setTitleRows(null); setDecisions({}); }}>Cancel</Btn>
              {undecided > 0 ? <span className="sub2">Choose for the {undecided} course{undecided === 1 ? "" : "s"} under &ldquo;Same code, different title&rdquo; first.</span> : null}
            </div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
