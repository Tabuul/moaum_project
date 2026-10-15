"use client";

/** Bulk course allocation (V321): a file read and mapped column by column; every row validated against the register
 *  before anything is written; the preview with its counts; the import of the valid rows on confirmation, under a key so
 *  a second press cannot allocate twice; the error report with the original row numbers; the history of imports.
 *  V478: the template is a department's, issued from the register — the faculty, department, kind of programme, session and
 *  semester chosen first; its classes, current lecturers and the department's lecturers written in, the lecturer chosen from a
 *  list — and its upload is checked against the template the portal issued, whatever the file says. */
import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { csvRows, xlsxRows, xlsxWorkbook } from "@/lib/xlsx";
import { xlsx } from "@/lib/xlsx-write";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { getInstitution } from "@/lib/document/institution-client";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { readTemplate, semesterWord, templateSheets, typeWord, type IssuedTemplate, type ProgrammeType, type ReadTemplate, type TemplateSummary } from "@/lib/allocation-template";

import { FIELDS, detectMapping, headerRowIndex, rowsOf, type RowIn } from "@/lib/allocation-import";
export type { RowIn };

export interface Finding {
  row: number; staffId: string; lecturer: string; department: string; courseCode: string; course: string; courseDepartment: string; programme: string;
  level?: number | null; session: string; semester?: number | null; role: string; status: "VALID" | "WARNING" | "ERROR" | "DUPLICATE" | "EXISTING" | string;
  codes: string[]; messages: string[]; action?: string | null;
}
export interface Summary { total: number; valid: number; warnings: number; errors: number; duplicates: number; existing: number; willImport: number }
/** V478: template — the department template the file came from, and a newer one issued since for the same context */
export interface Validation { summary: Summary; rows: Finding[]; template?: { reference: string; deptName: string; programmeType: string; session: string; semester: number; newer: string | null } | null }
export interface ImportResult { id: string; reference: string; status: string; repeated: boolean; imported: number; summary: Summary; rows: Finding[] }
export interface ImportRecord {
  id: string; reference: string; file_name: string | null; session: string; semester: number | null; scope_dept: string | null; uploader_office: string;
  uploaded_at: string; uploaded_by: string | null; total_rows: number; valid_rows: number; imported: number; existing: number; skipped: number; errors: number; warnings: number; status: string;
  /** V478 */ template_reference?: string | null; programme_type?: string | null; ticket?: string | null;
}
/** V478: the faculties, departments and sessions the acting office may issue templates for */
interface TemplateOptions { faculties: { code: string; name: string }[]; departments: { code: string; name: string; faculty_code: string | null }[];
  sessions: { name: string; state: string; semesters: number }[]; current: string | null; types: ProgrammeType[] }
interface RecentTemplate { id: string; reference: string; dept_code: string; dept_name: string | null; programme_type: string; session: string; semester: number;
  issued_at: string; issued_by: string | null; issued_office: string; classes: number; lecturers: number; uploads: number; imported: number; ticket: string | null }
const PICK_FIRST = "Select faculty, department, session and semester before downloading the template.";

const STATUS_PILL: Record<string, "ok" | "warn" | "bad" | "info" | "grey"> = { VALID: "ok", WARNING: "warn", ERROR: "bad", DUPLICATE: "bad", EXISTING: "info" };
const semName = (n: number | null | undefined) => (n === 1 ? "First" : n === 2 ? "Second" : n === 3 ? "Third" : "—");
const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });

export function BulkUpload({ dept, deptName, session, semester, imports, canImport, templateOnly = false, ticketInitial = "" }: {
  dept: string; deptName: string; session: string; semester: number; imports: ImportRecord[]; canImport: boolean;
  /** V478: the School's page — a department's postgraduate template only, no other file */
  templateOnly?: boolean;
  ticketInitial?: string;
}) {
  const router = useRouter();
  const file = useRef<HTMLInputElement>(null);
  const [phase, setPhase] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const [grid, setGrid] = useState<{ header: string[]; rows: string[][]; rowNumbers: number[] } | null>(null);
  const [mapping, setMapping] = useState<Record<string, number>>({});
  const [validation, setValidation] = useState<Validation | null>(null);
  const [importKey, setImportKey] = useState<string | null>(null);
  const [allowOverload, setAllowOverload] = useState(false);
  const [replaceExisting, setReplaceExisting] = useState(false);
  const [show, setShow] = useState<"ALL" | "ERROR" | "WARNING" | "EXISTING" | "DUPLICATE" | "VALID">("ALL");
  const [result, setResult] = useState<ImportResult | null>(null);
  const [busy, setBusy] = useState(false);
  /* V478: the department template — what may be chosen, what is chosen, what it would carry, the templates issued, the file read */
  const tplFile = useRef<HTMLInputElement>(null);
  const [opts, setOpts] = useState<TemplateOptions | null>(null);
  const [sel, setSel] = useState({ type: "UNDERGRADUATE" as ProgrammeType, fac: "", dept: dept || "", session: session || "", semester: semester ? String(semester) : "" });
  const [preview, setPreview] = useState<{ summary: TemplateSummary } | null>(null);
  const [recent, setRecent] = useState<RecentTemplate[]>([]);
  const [ticket, setTicket] = useState(ticketInitial);
  const [tpl, setTpl] = useState<ReadTemplate | null>(null);
  const chosen = !!(sel.fac && sel.dept && sel.session && sel.semester);

  const loadRecent = useCallback(async () => {
    const r = await fetch("/api/bff/api/v1/allocation/templates?limit=10", { cache: "no-store" });
    const j = await r.json().catch(() => []);
    setRecent(r.ok && Array.isArray(j) ? (j as RecentTemplate[]) : []);
  }, []);

  useEffect(() => {
    let live = true;
    void (async () => {
      const r = await fetch("/api/bff/api/v1/allocation/template/options", { cache: "no-store" });
      const o = (await r.json().catch(() => null)) as TemplateOptions | null;
      if (!live || !r.ok || !o) return;
      setOpts(o);
      setSel((s) => {
        const d = o.departments.find((x) => x.code === s.dept);
        return { ...s, type: o.types.includes(s.type) ? s.type : o.types[0], dept: d ? s.dept : "", fac: d?.faculty_code ?? s.fac,
          session: s.session || o.current || "", semester: s.semester || "1" };
      });
      await loadRecent();
    })();
    return () => { live = false; };
  }, [loadRecent]);

  // the department summary: what the template would carry now, read when the choice is complete
  useEffect(() => {
    if (!chosen) { void Promise.resolve().then(() => setPreview(null)); return; }
    let live = true;
    const qs = new URLSearchParams({ dept: sel.dept, session: sel.session, semester: sel.semester, programmeType: sel.type });
    void fetch(`/api/bff/api/v1/allocation/template/context?${qs.toString()}`, { cache: "no-store" }).then(async (r) => {
      const j = await r.json().catch(() => null);
      if (!live) return;
      if (r.ok && j) setPreview(j as { summary: TemplateSummary }); else { setPreview(null); if (j) notifyProblem(j as Problem); }
    });
    return () => { live = false; };
  }, [chosen, sel.dept, sel.session, sel.semester, sel.type]);

  /** the template, issued and recorded by the server, built into a workbook here */
  async function downloadDeptTemplate() {
    if (!chosen) { notifyProblem({ status: 400, title: PICK_FIRST }); return; }
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/allocation/template", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Course allocation template downloaded: ${sel.dept} ${sel.session} semester ${sel.semester}`) },
        body: JSON.stringify({ dept: sel.dept, session: sel.session, semester: Number(sel.semester), programmeType: sel.type, ticket: ticket.trim() || null }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok || !j) { const p = (j as Problem) ?? { status: r.status, title: "Unable to generate template. Please try again." }; setProblem(p); notifyProblem(p); return; }
      const t = j as IssuedTemplate;
      const inst = await getInstitution();
      const on = new Date().toLocaleString("en-GB", { day: "numeric", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit" });
      const book = xlsx(templateSheets(t, inst.name, on));
      downloadBlob(new Blob([book.buffer as ArrayBuffer], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }),
        `${inst.shortName} course allocation ${t.context.deptCode} ${t.context.session.replace("/", "-")} S${t.context.semester} ${t.context.reference}.xlsx`);
      notify(`Template downloaded successfully: ${t.context.reference}`);
      await loadRecent();
    } catch {
      notifyProblem({ status: 500, title: "Unable to generate template. Please try again." });
    }
  }

  /** a completed department template: its context read from the file, checked by the server against the template it issued */
  async function takeTemplate(read: ReadTemplate, name: string) {
    setProblem(null); setValidation(null); setResult(null); setImportKey(null); setGrid(null);
    setFileName(name);
    if (opts && !sel.dept) {
      const d = opts.departments.find((x) => x.code === read.context.dept);
      setSel({ type: (read.context.programmeType as ProgrammeType) || sel.type, fac: d?.faculty_code ?? "", dept: read.context.dept, session: read.context.session, semester: String(read.context.semester) });
    }
    setTpl(read);
    if (!read.rows.length) { setProblem({ status: 400, title: "No lecturer is chosen in this template.", detail: `${read.blank} class${read.blank === 1 ? "" : "es"} left blank: nothing to allocate.` }); return; }
    await validate({ allowOverload, replaceExisting }, read);
  }

  function templateBody(read: ReadTemplate) {
    const pick = sel.dept ? sel : { type: read.context.programmeType, dept: read.context.dept, session: read.context.session, semester: String(read.context.semester) };
    return {
      reference: read.context.reference, dept: pick.dept, session: pick.session, semester: Number(pick.semester), programmeType: pick.type,
      fileDept: read.context.dept, fileSession: read.context.session, fileSemester: read.context.semester, fileProgrammeType: read.context.programmeType,
    };
  }

  const rowsIn = (): RowIn[] => (tpl ? tpl.rows : grid ? rowsOf([grid.header, ...grid.rows], 0, mapping, { session, semester: String(semester) }).map((r, i) => ({ ...r, row: grid.rowNumbers[i] ?? r.row })) : []);
  const missingRequired = FIELDS.filter((f) => f.required && mapping[f.key] === undefined && !(f.key === "session" || f.key === "semester"));

  async function post<T>(path: string, body: unknown, reason: string): Promise<T | null> {
    const r = await fetch(`/api/bff/api/v1/allocation${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
    const j = await r.json().catch(() => null);
    if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return null; }
    return j as T;
  }

  /** the generic template (V321), kept for a file of the same columns made elsewhere; the department's template is the one offered */
  async function downloadGenericTemplate() {
    setPhase("Building the template from the register…");
    setProblem(null);
    try {
      const [inst, structure, courses, sessions, lecturers] = await Promise.all([
        getInstitution(),
        fetch("/api/bff/api/v1/ref/structure").then((r) => r.json()).catch(() => ({ faculties: [] })),
        fetch(`/api/bff/api/v1/ref/courses?dept=${encodeURIComponent(dept)}`).then((r) => r.json()).catch(() => []),
        fetch("/api/bff/api/v1/ref/sessions").then((r) => r.json()).catch(() => []),
        fetch(`/api/bff/api/v1/allocation/lecturers?dept=${encodeURIComponent(dept)}&session=${encodeURIComponent(session)}&semester=${semester}&all=true`).then((r) => r.json()).catch(() => []),
      ]);
      const facs = (structure?.faculties ?? []) as { code: string; name: string; departments: { code: string; name: string; programmes: { code: string; name: string; archived?: boolean }[] }[] }[];
      const depts: string[][] = facs.flatMap((f) => f.departments.map((d) => [d.code, d.name, f.name]));
      const progs: string[][] = facs.flatMap((f) => f.departments.flatMap((d) => d.programmes.filter((p) => !p.archived).map((p) => [p.code, p.name, d.name])));
      const crs: (string | number)[][] = (Array.isArray(courses) ? courses : []).map((c: { code: string; title: string; units?: number; semester?: number; level?: number; deptName?: string; dept_name?: string; deptCode?: string; dept_code?: string }) =>
        [c.code, c.title, c.deptName ?? c.dept_name ?? c.deptCode ?? c.dept_code ?? "", c.units ?? "", c.semester ?? "", c.level ?? ""]);
      const sess: (string | number)[][] = (Array.isArray(sessions) ? sessions : []).map((s: { name: string; state?: string; semesters?: number }) => [s.name, s.state ?? "", s.semesters ?? 2]);
      const lects: string[][] = (Array.isArray(lecturers) ? lecturers : []).map((l: { staff_number?: string | null; name: string; department?: string | null }) => [l.staff_number ?? "", l.name, l.department ?? ""]);
      const example: (string | number)[] = [lects[0]?.[0] ?? "STF001", lects[0]?.[1] ?? "SURNAME, Given Names", lects[0]?.[2] ?? deptName, crs[0]?.[0] ?? "ACC 401", crs[0]?.[1] ?? "Course title as on the catalogue", deptName, progs[0]?.[0] ?? "", crs[0]?.[5] ?? "", session, semester, "Lecturer", ""];
      const book = xlsx([
        ["Allocations", [FIELDS.map((f) => f.label + (f.required ? " *" : "")), example, FIELDS.map(() => "")], { headerRows: [0] }],
        ["Instructions", [
          ["Bulk course allocation — how to fill the Allocations sheet"],
          [""],
          ["Required", "Staff ID, Course code, Session and Semester. Everything else helps the check or chooses a role."],
          ["Staff ID", "The staff number on the teaching staff register. It names the lecturer; the name column is only checked against it, never used to find a lecturer."],
          ["Course code", "As on the catalogue, e.g. ACC 401. The title is checked against the catalogue and never changes it."],
          ["Lecturer department / Course department", "Optional; given, they must agree with the register, or the row is refused. Use the department's code or its name."],
          ["Programme / Level", "Optional; given, the course must be on the programme's structure at that level."],
          ["Session", "2026/2027. The session must be on the academic calendar."],
          ["Semester", "1, 2, First or Second. The course must be offered in that session and semester (registration opened, or the offering added by the Academic Office)."],
          ["Role", "Lecturer (the lead, who owns the score sheet — the default), Co-lecturer, or Second examiner."],
          ["Cross-department", "YES to allocate a course of another department to this lecturer, as the allocation desk's option does. GST and other service courses need no YES."],
          ["Duplicates", "The same lecturer, course, session, semester and role twice in the file: the second row is refused. An allocation already on record is reported and left as it is."],
          ["Load", "A lead above 12 units in a semester is refused unless the import allows overloads; an overload is on the record and reported to the Dean."],
          ["What never happens", "The file never creates a lecturer, a course, a programme, a session or a semester, and never changes a department or a title. Create and correct those on their own desks first."],
          [""],
          ["Delete the example row before uploading. The reference sheets are read from the register as it stands at download."],
        ]],
        ["Lecturers", [["Staff ID", "Name", "Departments"], ...lects], { headerRows: [0] }],
        ["Courses", [["Course code", "Title", "Department", "Units", "Semester", "Level"], ...crs], { headerRows: [0] }],
        ["Programmes", [["Programme code", "Programme", "Department"], ...progs], { headerRows: [0] }],
        ["Departments", [["Department code", "Department", "Faculty"], ...depts], { headerRows: [0] }],
        ["Sessions", [["Session", "State", "Semesters"], ...sess], { headerRows: [0] }],
      ]);
      downloadBlob(new Blob([book.buffer as ArrayBuffer], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }), `${inst.shortName} course allocation template ${session.replace("/", "-")}.xlsx`);
    } finally {
      setPhase(null);
    }
  }

  /** the file read into a grid, its columns mapped to the system's fields */
  async function readFile(f: File) {
    setProblem(null); setValidation(null); setResult(null); setImportKey(null);
    setFileName(f.name);
    setPhase("Reading the file…");
    try {
      if (f.size > 20_000_000) { setProblem({ status: 400, title: "The file is larger than 20 MB." }); return; }
      const buf = await f.arrayBuffer();
      const head = new Uint8Array(buf.slice(0, 2));
      const isWorkbook = (head[0] === 0x50 && head[1] === 0x4b) || /\.xlsx$/i.test(f.name);
      if (!isWorkbook && !/\.csv$/i.test(f.name)) { setProblem({ status: 400, title: "Upload the template as an Excel workbook (.xlsx), or a CSV with the same columns." }); return; }
      // V478: a department template is read by its own sheets and checked against the template the portal issued
      if (isWorkbook) {
        const read = readTemplate(await xlsxWorkbook(buf));
        if (read) { setPhase(null); await takeTemplate(read, f.name); return; }
      }
      if (templateOnly) { setProblem({ status: 400, title: "Upload a department course allocation template downloaded from this page." }); return; }
      const cells = (isWorkbook ? await xlsxRows(buf) : csvRows(new TextDecoder("utf-8").decode(buf))).map((row) => row.map((c) => String(c ?? "").trim()));
      const hi = headerRowIndex(cells);
      const header = cells[hi] ?? [];
      const kept = cells.slice(hi + 1).map((r, i) => ({ r, n: hi + i + 2 })).filter((x) => x.r.some((c) => c !== ""));
      setGrid({ header, rows: kept.map((x) => x.r), rowNumbers: kept.map((x) => x.n) });
      setMapping(detectMapping(header));
      if (!kept.length) setProblem({ status: 400, title: "No allocation rows were found under the header." });
    } catch {
      setProblem({ status: 400, title: `${f.name} could not be read as a spreadsheet.` });
    } finally {
      setPhase(null);
    }
  }

  /** the options as they stand, or the ones just changed: a tick re-validates with the new value, not the stale state */
  async function validate(options: { allowOverload: boolean; replaceExisting: boolean } = { allowOverload, replaceExisting }, read: ReadTemplate | null = tpl) {
    const rows = read ? read.rows : rowsIn();
    if (!rows.length) { setProblem({ status: 400, title: "No allocation rows to validate." }); return; }
    setBusy(true); setProblem(null); setResult(null);
    setPhase(read ? `Validating template ${read.context.reference}: ${rows.length} rows against the register and the template…`
      : `Validating ${rows.length} rows: lecturers, departments, courses, programmes, sessions, semesters, offerings, duplicates…`);
    try {
      const v = await post<Validation>("/import/validate", { rows, options, fileName, template: read ? templateBody(read) : null, ticket: ticket.trim() || null },
        `${rows.length} allocation rows validated${read ? ` from template ${read.context.reference}` : ""}`);
      if (v) { setValidation(v); setImportKey(crypto.randomUUID()); setShow(v.summary.errors ? "ERROR" : "ALL"); }
    } finally { setBusy(false); setPhase(null); }
  }

  async function doImport() {
    const rows = rowsIn();
    if (!validation || !importKey || !rows.length) return;
    setBusy(true); setProblem(null);
    setPhase(`Importing ${validation.summary.willImport} allocation${validation.summary.willImport === 1 ? "" : "s"}…`);
    try {
      const r = await post<ImportResult>("/import", { rows, options: { allowOverload, replaceExisting }, fileName, importKey, template: tpl ? templateBody(tpl) : null, ticket: ticket.trim() || null },
        `${validation.summary.willImport} allocations imported from ${fileName ?? "a file"}${tpl ? ` (template ${tpl.context.reference})` : ""}`);
      if (r) { setResult(r); setValidation(null); notify(`Course allocation template imported successfully: ${r.reference}, ${r.imported} allocation${r.imported === 1 ? "" : "s"} made`); router.refresh(); void loadRecent(); }
    } finally { setBusy(false); setPhase(null); }
  }

  async function errorReport(rows: Finding[], reference: string) {
    const bad = rows.filter((r) => r.status !== "VALID");
    const head = ["Row number", "Course code", "Course", "Programme", "Lecturer", "Staff ID", "Session", "Semester", "Role", "Status", "Error type", "Error message", "Correction required"];
    const body = bad.map((r) => [r.row, r.courseCode, r.course, r.programme, r.lecturer, r.staffId, r.session, semName(r.semester), r.role, r.status, r.codes.join(", "), r.messages.join("; "), r.action ?? ""]);
    downloadBlob(await brandedXlsx("Course allocation import — error report", head, body, { sheetName: "Errors", serial: reference, sub: fileName ?? "" }), `allocation-import-errors-${reference.replace(/[\\/]/g, "-")}.xlsx`);
  }

  async function historyReport(rec: ImportRecord) {
    const r = await fetch(`/api/bff/api/v1/allocation/imports/${rec.id}`);
    const j = await r.json().catch(() => null);
    if (!r.ok || !j) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    await errorReport((j.findings ?? []) as Finding[], rec.reference);
  }

  const shown = validation ? validation.rows.filter((r) => show === "ALL" || r.status === show) : [];
  const findingRow = (r: Finding) => [
    <span className="tnum" key="r">{r.row}</span>,
    <span key="l"><b>{r.lecturer || "—"}</b><div className="sub2 tnum">{r.staffId}</div></span>,
    <span className="sub2" key="d">{r.department || "—"}</span>,
    <span key="c"><b className="tnum">{r.courseCode}</b><div className="sub2">{r.course}</div></span>,
    <span className="sub2 tnum" key="s">{r.session} · {semName(r.semester)}</span>,
    <span className="sub2" key="ro">{r.role.replace(/_/g, " ").toLowerCase()}</span>,
    <Pil key="st" kind={STATUS_PILL[r.status] ?? "grey"}>{r.status}</Pil>,
    <span key="m" className="t-sm">{r.messages.length ? r.messages.map((m, i) => <div key={i}>{m}</div>) : <span className="sub2">—</span>}{r.action ? <div className="sub2">{r.action}</div> : null}</span>,
  ];

  const depts = (opts?.departments ?? []).filter((d) => !sel.fac || d.faculty_code === sel.fac);
  const s = preview?.summary;
  return (
    <>
      <Panel title="Course allocation template — one department" right={<span className="row row--inline row--tight">
        <Btn kind="primary" busyLabel="Generating template…" disabled={!opts || busy} onClick={() => downloadDeptTemplate()}>Download course allocation template</Btn>
        <Btn kind="go" disabled={!canImport || !!phase || busy} onClick={() => tplFile.current?.click()}>{phase && tpl ? "Uploading…" : "Upload completed template"}</Btn>
        <input ref={tplFile} type="file" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) void readFile(f); e.target.value = ""; }} />
      </span>}>
        <PBody>
          <div className="row">
            <Field id="tpl-type" label="Programme type" style={{ flex: "0 1 170px" }}>
              <select id="tpl-type" className="ctl" value={sel.type} disabled={(opts?.types.length ?? 0) < 2} onChange={(e) => setSel({ ...sel, type: e.target.value as ProgrammeType })}>
                {(opts?.types ?? ["UNDERGRADUATE"]).map((t) => <option key={t} value={t}>{typeWord(t)}</option>)}
              </select></Field>
            <Field id="tpl-fac" label="Faculty" style={{ flex: "1 1 200px" }}>
              <SearchSelect id="tpl-fac" value={sel.fac} placeholder="Search a faculty…" options={(opts?.faculties ?? []).map((f) => ({ value: f.code, label: f.name }))}
                onChange={(v) => setSel({ ...sel, fac: v, dept: "" })} /></Field>
            <Field id="tpl-dept" label="Department" style={{ flex: "1 1 220px" }}>
              <SearchSelect id="tpl-dept" value={sel.dept} placeholder={sel.fac ? "Search a department…" : "Choose the faculty first"} disabled={!sel.fac}
                options={depts.map((d) => ({ value: d.code, label: d.name }))} onChange={(v) => setSel({ ...sel, dept: v })} /></Field>
            <Field id="tpl-session" label="Academic session" style={{ flex: "0 1 150px" }}>
              <SearchSelect id="tpl-session" value={sel.session} placeholder="Session…" options={(opts?.sessions ?? []).map((x) => ({ value: x.name, label: `${x.name}${x.state === "CURRENT" ? " (current)" : ""}` }))}
                onChange={(v) => setSel({ ...sel, session: v })} /></Field>
            <Field id="tpl-sem" label="Semester" style={{ flex: "0 1 150px" }}>
              <select id="tpl-sem" className="ctl" value={sel.semester} onChange={(e) => setSel({ ...sel, semester: e.target.value })}>
                <option value="">Semester…</option>
                {Array.from({ length: opts?.sessions.find((x) => x.name === sel.session)?.semesters ?? 2 }, (_, i) => i + 1).map((n) => <option key={n} value={String(n)}>{semesterWord(n)}</option>)}
              </select></Field>
            <Field id="tpl-ticket" label="Support ticket (optional)" style={{ flex: "0 1 170px" }}>
              <input id="tpl-ticket" className="ctl tnum" value={ticket} maxLength={60} placeholder="TICK-2026-00123" onChange={(e) => setTicket(e.target.value)} autoComplete="off" /></Field>
          </div>
          {!chosen ? <div className="sub2 mt-2">{PICK_FIRST}</div> : s ? (
            <div className="mt-2">
              <Tiles cls="grid--4" items={[
                ["Department", depts.find((d) => d.code === sel.dept)?.name ?? sel.dept, null, `${opts?.faculties.find((f) => f.code === sel.fac)?.name ?? ""} · ${typeWord(sel.type)}`],
                ["Courses", String(s.classes), null, `${s.open} with a class open in ${sel.session} · ${s.unallocated} without a lead`],
                ["Lecturers", String(s.lecturers), null, "Of the department, to choose from"],
                ["Existing allocations", String(s.allocations), null, `${s.programmes} programme${s.programmes === 1 ? "" : "s"} of this kind`],
              ]} />
              <div className="sub2">The template is built from the register now: these classes with their lecturers on record, the department&rsquo;s lecturers as a list, and its {typeWord(sel.type).toLowerCase()} programmes. The upload is checked against the template&rsquo;s own department, session and semester, whatever the file says.</div>
            </div>
          ) : <div className="row row--inline row--tight mt-2"><span className="spinner" aria-hidden /> <span className="sub2">Reading the department from the register…</span></div>}
          {tpl && !validation && !result ? <Note kind="info" title={`Template ${tpl.context.reference}`}>{tpl.rows.length} row{tpl.rows.length === 1 ? "" : "s"} with a lecturer chosen{tpl.blank ? ` · ${tpl.blank} class${tpl.blank === 1 ? "" : "es"} left blank and left as they are` : ""}.</Note> : null}
        </PBody>
        {recent.length ? (
          <DTable pageSize={0} noPrint cols={["Template ref", "Department", "Type|mid", "Session", "Generated by", "Date", "Uploads|mid", "Imported|mid", "Ticket"]} rows={recent.map((t) => [
            <b className="tnum" key="r">{t.reference}</b>, <span key="d">{t.dept_name ?? t.dept_code}</span>, <span key="t" className="sub2">{typeWord(t.programme_type)}</span>,
            <span key="s" className="tnum">{t.session} · {semName(t.semester)}</span>, <span key="b" className="sub2">{t.issued_by ?? ""} ({t.issued_office})</span>,
            <span key="w" className="tnum sub2">{when(t.issued_at)}</span>, <span key="u" className="tnum">{t.uploads}</span>, <span key="i" className="tnum">{t.imported}</span>,
            <span key="k" className="tnum sub2">{t.ticket ?? ""}</span>,
          ])} />
        ) : null}
      </Panel>

      <Panel title={templateOnly ? "Upload progress" : "Bulk upload — course allocation from any spreadsheet"} right={templateOnly ? undefined : <span className="row row--inline row--tight">
        <Btn kind="ghost" disabled={!!phase} busyLabel="Building…" onClick={() => downloadGenericTemplate()}>Blank template (any department)</Btn>
        <Btn kind="primary" disabled={!canImport || !!phase || busy} onClick={() => file.current?.click()}>Upload Excel / CSV</Btn>
        <input ref={file} type="file" accept=".xlsx,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,text/csv" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) void readFile(f); e.target.value = ""; }} /></span>}>
        <PBody>
          <div className="t-sm" style={{ lineHeight: 1.6 }}>
            {templateOnly ? "Upload the department's completed template above; it is checked against the register and the template before anything is written."
              : <>A department&rsquo;s template above is the way to allocate: everything the register knows is written in. A file of the blank template&rsquo;s columns made elsewhere is read here, its columns matched by name (Staff ID, Course code, Session and Semester required). Nothing is written until you press Import.</>}
          </div>
          {phase ? <div className="row row--inline row--tight mt-2"><span className="spinner" aria-hidden /> <span className="sub2">{phase}</span></div> : null}
          {problem ? <div className="mt-2"><ProblemNotice problem={problem} /></div> : null}
        </PBody>
        {grid && !validation && !result ? (
          <PBody>
            <div className="eyebrow">{fileName} · {grid.rows.length} row{grid.rows.length === 1 ? "" : "s"} · columns mapped</div>
            <div className="sub2 mt-1">Blank Session and Semester read {session}, {semName(semester).toLowerCase()} semester.</div>
            <div className="grid grid--3 mt-2">
              {FIELDS.map((f) => (
                <div key={f.key} className="field">
                  <label htmlFor={`map-${f.key}`}>{f.label}{f.required ? <span className="ink-red"> *</span> : null}</label>
                  <select id={`map-${f.key}`} className="ctl" value={mapping[f.key] ?? -1} onChange={(e) => { const v = Number(e.target.value); setMapping((m) => { const n = { ...m }; if (v < 0) delete n[f.key]; else n[f.key] = v; return n; }); }}>
                    <option value={-1}>— not in the file —</option>
                    {grid.header.map((h, i) => <option key={i} value={i}>{h || `Column ${i + 1}`}</option>)}
                  </select>
                </div>
              ))}
            </div>
            {missingRequired.length ? <Note kind="bad" title={`The file lacks ${missingRequired.map((f) => f.label).join(", ")}`}>Map the column that carries it, or add it to the file.</Note> : null}
            <div className="row mt-3">
              <Btn kind="go" disabled={busy || missingRequired.length > 0 || !grid.rows.length} onClick={() => void validate()}>{busy ? "Validating…" : `Validate ${grid.rows.length} row${grid.rows.length === 1 ? "" : "s"}`}</Btn>
              <Btn kind="ghost" onClick={() => { setGrid(null); setFileName(null); setProblem(null); }}>Cancel</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>

      {validation ? (
        <Panel title={`Import preview · ${fileName ?? ""}`} right="Nothing has been written">
          {validation.template ? (
            <PBody>
              <div className="sub2">Template <b className="tnum">{validation.template.reference}</b> · {validation.template.deptName} · {typeWord(validation.template.programmeType)} · {validation.template.session} · {semName(validation.template.semester)} semester{tpl?.blank ? ` · ${tpl.blank} class${tpl.blank === 1 ? "" : "es"} left blank` : ""}</div>
              {validation.template.newer ? <Note kind="info" title={`A newer template, ${validation.template.newer}, was issued since`}>This file&rsquo;s rows are checked against the register as it stands now; anything changed since it was downloaded is shown below.</Note> : null}
            </PBody>
          ) : null}
          <Tiles cls="grid--4" items={[
            ["Rows", String(validation.summary.total), null, "In the file"],
            ["Will be imported", String(validation.summary.willImport), validation.summary.willImport ? "var(--green-ink)" : "var(--red-ink)", `${validation.summary.valid} valid · ${validation.summary.warnings} with a warning`],
            ["Will not", String(validation.summary.errors + validation.summary.duplicates), validation.summary.errors + validation.summary.duplicates ? "var(--red-ink)" : null, `${validation.summary.errors} error${validation.summary.errors === 1 ? "" : "s"} · ${validation.summary.duplicates} duplicate${validation.summary.duplicates === 1 ? "" : "s"} in the file`],
            ["Already on record", String(validation.summary.existing), "var(--chrome)", "Left as they are"],
          ]} />
          <PBody>
            <div className="row">
              <label className="row row--inline row--tight"><input type="checkbox" checked={allowOverload} disabled={busy} onChange={(e) => { setAllowOverload(e.target.checked); void validate({ allowOverload: e.target.checked, replaceExisting }); }} /> Allow overloads above 12 units (on the record, reported to the Dean)</label>
              <label className="row row--inline row--tight"><input type="checkbox" checked={replaceExisting} disabled={busy} onChange={(e) => { setReplaceExisting(e.target.checked); void validate({ allowOverload, replaceExisting: e.target.checked }); }} /> Replace existing leads and second examiners named in the file</label>
              <span className="sub2">Changing an option re-validates the file.</span>
              <Btn kind="ghost" disabled={busy} onClick={() => void validate()}>Re-validate</Btn>
            </div>
            <div className="row mt-2">
              <select className="ctl" style={{ maxWidth: 220 }} value={show} onChange={(e) => setShow(e.target.value as typeof show)}>
                <option value="ALL">Every row ({validation.summary.total})</option>
                <option value="ERROR">Errors ({validation.summary.errors})</option>
                <option value="WARNING">Warnings ({validation.summary.warnings})</option>
                <option value="DUPLICATE">Duplicates in the file ({validation.summary.duplicates})</option>
                <option value="EXISTING">Already on record ({validation.summary.existing})</option>
                <option value="VALID">Valid ({validation.summary.valid})</option>
              </select>
              <span className="grow" />
              {validation.summary.errors + validation.summary.duplicates ? <Btn kind="ghost" onClick={() => void errorReport(validation.rows, `${docSerial("ALC")}`)}>Download error report</Btn> : null}
              <Btn kind="go" disabled={busy || !validation.summary.willImport || !canImport} onClick={() => void doImport()}>{busy ? "Importing…" : validation.summary.errors + validation.summary.duplicates ? `Import valid records only (${validation.summary.willImport})` : `Import ${validation.summary.willImport} record${validation.summary.willImport === 1 ? "" : "s"}`}</Btn>
              <Btn kind="ghost" disabled={busy} onClick={() => { setValidation(null); setGrid(null); setFileName(null); setTpl(null); }}>Cancel import</Btn>
            </div>
            {validation.summary.errors + validation.summary.duplicates ? <div className="sub2 mt-2">{validation.summary.willImport} record{validation.summary.willImport === 1 ? "" : "s"} will be imported; {validation.summary.errors + validation.summary.duplicates} will not.</div> : null}
          </PBody>
          <DTable cols={["Row|mid", "Lecturer", "Department", "Course", "Session", "Role", "Status|mid", "Findings"]} rows={shown.map(findingRow)} texts={shown.map((r) => `${r.row} ${r.lecturer} ${r.staffId} ${r.courseCode} ${r.course} ${r.status} ${r.codes.join(" ")}`)} pageSize={25} noPrint />
        </Panel>
      ) : null}

      {result ? (
        <Panel title={`Import ${result.repeated ? "already made" : "completed"} · ${result.reference}`} right={<Pil kind={result.status === "COMPLETED" ? "ok" : result.status === "NOTHING_TO_IMPORT" ? "bad" : "warn"}>{result.status.replace(/_/g, " ")}</Pil>}>
          <Tiles cls="grid--4" items={[
            ["Imported", String(result.imported), result.imported ? "var(--green-ink)" : "var(--red-ink)", "Allocations made"],
            ["Already on record", String(result.summary.existing), "var(--chrome)", "Left as they were"],
            ["Not imported", String(result.summary.errors + result.summary.duplicates), result.summary.errors + result.summary.duplicates ? "var(--red-ink)" : null, "Errors and duplicates"],
            ["Rows", String(result.summary.total), null, fileName ?? ""],
          ]} />
          <PBody>
            {result.repeated ? <Note kind="info" title="This file was imported already">Nothing was allocated again.</Note> : null}
            <div className="row">
              {result.summary.errors + result.summary.duplicates ? <Btn kind="primary" onClick={() => void errorReport(result.rows, result.reference)}>Download error report</Btn> : null}
              <Btn kind="ghost" onClick={() => { setResult(null); setGrid(null); setFileName(null); setTpl(null); }}>Done</Btn>
            </div>
            <div className="sub2 mt-2">Each lecturer allocated is told by e-mail.</div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Import history" right={imports.length ? `${imports.length} import${imports.length === 1 ? "" : "s"}` : "No import yet"}>
        {imports.length ? (
          <DTable cols={["Reference", "File", "Uploaded", "Session", "Rows|mid", "Imported|mid", "Existing|mid", "Errors|mid", "Status|mid", "|num"]} rows={imports.map((i) => [
            <span key="r"><b className="tnum">{i.reference}</b>{i.template_reference ? <div className="sub2 tnum">{i.template_reference}{i.programme_type ? ` · ${typeWord(i.programme_type)}` : ""}</div> : null}{i.ticket ? <div className="sub2 tnum">Ticket {i.ticket}</div> : null}</span>,
            <span className="sub2" key="f">{i.file_name ?? "—"}</span>,
            <span key="u"><span className="sub2">{i.uploaded_by ?? i.uploader_office}</span><div className="sub2 tnum">{when(i.uploaded_at)} · {i.uploader_office}</div></span>,
            <span className="tnum" key="s">{i.session}{i.semester ? ` · ${semName(i.semester)}` : ""}</span>,
            <span className="tnum" key="t">{i.total_rows}</span>,
            <span className="tnum" key="i">{i.imported}</span>,
            <span className="tnum" key="e">{i.existing}</span>,
            <span className={`tnum${i.errors ? " ink-red b600" : ""}`} key="x">{i.errors}</span>,
            <Pil key="st" kind={i.status === "COMPLETED" ? "ok" : i.status === "NOTHING_TO_IMPORT" ? "bad" : "warn"}>{i.status.replace(/_/g, " ").toLowerCase()}</Pil>,
            <Btn key="a" kind="ghost" onClick={() => void historyReport(i)}>Error report</Btn>,
          ])} texts={imports.map((i) => `${i.reference} ${i.file_name ?? ""} ${i.session} ${i.status}`)} />
        ) : <PBody><div className="sub2">Imports made from this desk appear here with their reference, counts and error report.</div></PBody>}
      </Panel>
    </>
  );
}
