"use client";

/** Bulk course allocation (V321): the official template with the register's lecturers, courses, programmes, departments
 *  and sessions as reference sheets; a file read and mapped column by column; every row validated against the register
 *  before anything is written; the preview with its counts; the import of the valid rows on confirmation, under a key so
 *  a second press cannot allocate twice; the error report with the original row numbers; the history of imports. */
import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { csvRows, xlsxRows } from "@/lib/xlsx";
import { xlsx, type Cell } from "@/lib/xlsx-write";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { getInstitution } from "@/lib/document/institution-client";

import { FIELDS, detectMapping, headerRowIndex, rowsOf, type RowIn } from "@/lib/allocation-import";
export type { RowIn };

export interface Finding {
  row: number; staffId: string; lecturer: string; department: string; courseCode: string; course: string; courseDepartment: string; programme: string;
  level?: number | null; session: string; semester?: number | null; role: string; status: "VALID" | "WARNING" | "ERROR" | "DUPLICATE" | "EXISTING" | string;
  codes: string[]; messages: string[]; action?: string | null;
}
export interface Summary { total: number; valid: number; warnings: number; errors: number; duplicates: number; existing: number; willImport: number }
export interface Validation { summary: Summary; rows: Finding[] }
export interface ImportResult { id: string; reference: string; status: string; repeated: boolean; imported: number; summary: Summary; rows: Finding[] }
export interface ImportRecord {
  id: string; reference: string; file_name: string | null; session: string; semester: number | null; scope_dept: string | null; uploader_office: string;
  uploaded_at: string; uploaded_by: string | null; total_rows: number; valid_rows: number; imported: number; existing: number; skipped: number; errors: number; warnings: number; status: string;
}

const STATUS_PILL: Record<string, "ok" | "warn" | "bad" | "info" | "grey"> = { VALID: "ok", WARNING: "warn", ERROR: "bad", DUPLICATE: "bad", EXISTING: "info" };
const semName = (n: number | null | undefined) => (n === 1 ? "First" : n === 2 ? "Second" : n === 3 ? "Third" : "—");
const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });

export function BulkUpload({ dept, deptName, session, semester, imports, canImport }: {
  dept: string; deptName: string; session: string; semester: number; imports: ImportRecord[]; canImport: boolean;
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

  const rowsIn = (): RowIn[] => (grid ? rowsOf([grid.header, ...grid.rows], 0, mapping, { session, semester: String(semester) }).map((r, i) => ({ ...r, row: grid.rowNumbers[i] ?? r.row })) : []);
  const missingRequired = FIELDS.filter((f) => f.required && mapping[f.key] === undefined && !(f.key === "session" || f.key === "semester"));

  async function post<T>(path: string, body: unknown, reason: string): Promise<T | null> {
    const r = await fetch(`/api/bff/api/v1/allocation${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
    const j = await r.json().catch(() => null);
    if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return null; }
    return j as T;
  }

  /** the official template, with reference sheets read from the register as it stands now */
  async function downloadTemplate() {
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
      const depts: Cell[][] = facs.flatMap((f) => f.departments.map((d) => [d.code, d.name, f.name]));
      const progs: Cell[][] = facs.flatMap((f) => f.departments.flatMap((d) => d.programmes.filter((p) => !p.archived).map((p) => [p.code, p.name, d.name])));
      const crs: Cell[][] = (Array.isArray(courses) ? courses : []).map((c: { code: string; title: string; units?: number; semester?: number; level?: number; deptName?: string; dept_name?: string; deptCode?: string; dept_code?: string }) =>
        [c.code, c.title, c.deptName ?? c.dept_name ?? c.deptCode ?? c.dept_code ?? "", c.units ?? "", c.semester ?? "", c.level ?? ""]);
      const sess: Cell[][] = (Array.isArray(sessions) ? sessions : []).map((s: { name: string; state?: string; semesters?: number }) => [s.name, s.state ?? "", s.semesters ?? 2]);
      const lects: Cell[][] = (Array.isArray(lecturers) ? lecturers : []).map((l: { staff_number?: string | null; name: string; department?: string | null }) => [l.staff_number ?? "", l.name, l.department ?? ""]);
      const example: Cell[] = [lects[0]?.[0] ?? "STF001", lects[0]?.[1] ?? "SURNAME, Given Names", lects[0]?.[2] ?? deptName, crs[0]?.[0] ?? "ACC 401", crs[0]?.[1] ?? "Course title as on the catalogue", deptName, progs[0]?.[0] ?? "", crs[0]?.[5] ?? "", session, semester, "Lecturer", ""];
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
  async function validate(opts: { allowOverload: boolean; replaceExisting: boolean } = { allowOverload, replaceExisting }) {
    const rows = rowsIn();
    if (!rows.length) { setProblem({ status: 400, title: "No allocation rows to validate." }); return; }
    setBusy(true); setProblem(null); setResult(null);
    setPhase(`Validating ${rows.length} rows: lecturers, departments, courses, programmes, sessions, semesters, offerings, duplicates…`);
    try {
      const v = await post<Validation>("/import/validate", { rows, options: opts, fileName }, `${rows.length} allocation rows validated`);
      if (v) { setValidation(v); setImportKey(crypto.randomUUID()); setShow(v.summary.errors ? "ERROR" : "ALL"); }
    } finally { setBusy(false); setPhase(null); }
  }

  async function doImport() {
    const rows = rowsIn();
    if (!validation || !importKey || !rows.length) return;
    setBusy(true); setProblem(null);
    setPhase(`Importing ${validation.summary.willImport} allocation${validation.summary.willImport === 1 ? "" : "s"}…`);
    try {
      const r = await post<ImportResult>("/import", { rows, options: { allowOverload, replaceExisting }, fileName, importKey }, `${validation.summary.willImport} allocations imported from ${fileName ?? "a file"}`);
      if (r) { setResult(r); setValidation(null); notify(`${r.reference}: ${r.imported} allocation${r.imported === 1 ? "" : "s"} made`); router.refresh(); }
    } finally { setBusy(false); setPhase(null); }
  }

  async function errorReport(rows: Finding[], reference: string) {
    const bad = rows.filter((r) => r.status !== "VALID");
    const head = ["Original row", "Staff ID", "Lecturer", "Department", "Course code", "Course", "Session", "Semester", "Role", "Status", "Error", "Recommended action"];
    const body = bad.map((r) => [r.row, r.staffId, r.lecturer, r.department, r.courseCode, r.course, r.session, semName(r.semester), r.role, r.status, r.messages.join("; "), r.action ?? ""]);
    downloadBlob(await brandedXlsx("Course allocation import — error report", head, body, { sheetName: "Errors", serial: reference, sub: fileName ?? "", noSerialColumn: true }), `allocation-import-errors-${reference.replace(/[\\/]/g, "-")}.xlsx`);
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

  return (
    <>
      <Panel title="Bulk upload — course allocation from a spreadsheet" right={<span className="row row--inline row--tight"><Btn kind="ghost" disabled={!!phase} onClick={() => void downloadTemplate()}>{phase?.startsWith("Building") ? "Building…" : "Download template"}</Btn>
        <Btn kind="primary" disabled={!canImport || !!phase || busy} onClick={() => file.current?.click()}>Upload Excel / CSV</Btn>
        <input ref={file} type="file" accept=".xlsx,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,text/csv" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) void readFile(f); e.target.value = ""; }} /></span>}>
        <PBody>
          <div className="t-sm" style={{ lineHeight: 1.6 }}>
            Download the template, fill the <b>Allocations</b> sheet (Staff ID, Course code, Session and Semester are required; the Lecturers, Courses, Programmes, Departments and Sessions sheets are the register as it stands), upload it, read the check, then import the valid rows.
            Every row is judged against the register: the lecturer and their department, the course and its department, the programme and level it is offered to, the session, the semester, the offering, duplicates in the file and allocations already on record. Nothing is written until you press Import. The file never creates or changes a lecturer, a course, a programme, a session or a semester.
          </div>
          {phase ? <div className="row row--inline row--tight mt-2"><span className="spinner" aria-hidden /> <span className="sub2">{phase}</span></div> : null}
          {problem ? <div className="mt-2"><ProblemNotice problem={problem} /></div> : null}
        </PBody>
        {grid && !validation && !result ? (
          <PBody>
            <div className="eyebrow">{fileName} · {grid.rows.length} row{grid.rows.length === 1 ? "" : "s"} · columns mapped</div>
            <div className="sub2 mt-1">Each system field reads the column named beside it; change one if the file names it differently. Session and Semester fall back to the bar&rsquo;s {session}, {semName(semester).toLowerCase()} semester when the file leaves them blank.</div>
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
              <Btn kind="go" disabled={busy || !validation.summary.willImport || !canImport} onClick={() => void doImport()}>{busy ? "Importing…" : `Import ${validation.summary.willImport} valid record${validation.summary.willImport === 1 ? "" : "s"}`}</Btn>
              <Btn kind="ghost" disabled={busy} onClick={() => { setValidation(null); setGrid(null); setFileName(null); }}>Cancel</Btn>
            </div>
            {validation.summary.errors + validation.summary.duplicates ? <div className="sub2 mt-2">{validation.summary.willImport} record{validation.summary.willImport === 1 ? "" : "s"} will be imported; {validation.summary.errors + validation.summary.duplicates} will not. Correct them in the file and upload it again afterwards.</div> : null}
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
            {result.repeated ? <Note kind="info" title="This file was imported already">The same import was submitted twice; the record made the first time is shown and nothing was allocated again.</Note> : null}
            <div className="row">
              {result.summary.errors + result.summary.duplicates ? <Btn kind="primary" onClick={() => void errorReport(result.rows, result.reference)}>Download error report</Btn> : null}
              <Btn kind="ghost" onClick={() => { setResult(null); setGrid(null); setFileName(null); }}>Done</Btn>
            </div>
            <div className="sub2 mt-2">Each lecturer allocated is told by e-mail and sees the course on their teaching page; the score sheet opens in the lead&rsquo;s name once the examination session is open, and the result pipeline reads the same allocation.</div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Import history" right={imports.length ? `${imports.length} import${imports.length === 1 ? "" : "s"}` : "No import yet"}>
        {imports.length ? (
          <DTable cols={["Reference", "File", "Uploaded", "Session", "Rows|mid", "Imported|mid", "Existing|mid", "Errors|mid", "Status|mid", "|num"]} rows={imports.map((i) => [
            <b className="tnum" key="r">{i.reference}</b>,
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
