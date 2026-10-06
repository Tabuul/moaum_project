"use client";
/** COURSE CATALOGUE RESET & UPLOAD (V338). Two central acts on the course catalogue, for the Directorate of ICT and the
 *  Academic Office:
 *   · the catalogue upload — one row per programme that offers a course, naming the course, the faculty, department and
 *     programme that OWN it, and the faculty, department and programme that OFFER it as CORE or ELECTIVE. Every row is judged
 *     against the register first; only a file with no invalid row is written, in one transaction, one course per code.
 *   · the reset — clears the active catalogue of the University, a faculty, a department or a programme, after an impact
 *     preview, a reason and the typed words RESET COURSES. A course anything hangs on is archived, never deleted;
 *     registrations, results, transcripts, CBT and payments are untouched. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Directory } from "@/lib/catalogue";
import { reasonHeader } from "@/lib/reason";
import { xlsxRows, buildXlsx, csvRows } from "@/lib/xlsx";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface ResetRow {
  id: string; ref: string; scope: string; scope_label: string; reason: string; courses_in_scope: number; bindings_removed: number; offerings_removed: number;
  offerings_kept: number; archived: number; deleted: number; proposals_cancelled: number; programmes_affected: number; departments_affected: number;
  performed_at: string; performed_by: string | null; performed_office: string | null;
}
export interface ImportRow {
  id: string; ref: string; file_name: string | null; rows: number; courses_created: number; courses_updated: number; courses_revived: number; owner_changes: number;
  offerings_created: number; offerings_updated: number; prerequisites: number; imported_at: string; imported_by: string | null; imported_office: string | null;
}
interface Judged {
  n: number; code: string | null; title: string | null; units: number | null; level: number | null; semester: number | null;
  ownerDepartment: string | null; ownerProgramme: string | null; offeringProgramme: string | null; offeringDepartment: string | null; basis: string | null;
  state: "VALID" | "INVALID" | "SKIPPED"; errors: string[]; existing: boolean; revived: boolean; ownerChange: boolean; existingOffering: boolean; remarks: string | null;
}
type Summary = Record<string, number>;
interface Judgement { committed: boolean; ref?: string; summary: Summary; rows: Judged[] }
interface Preview {
  scope: string; label: string; courses: number; bindings: number; programmesAffected: number; departmentsAffected: number; offerings: number;
  offeringsRemoved: number; offeringsKept: number; sessions: string[]; referencedByRegistrations: number; referencedByResults: number;
  toArchive: number; toDelete: number; gstKept: number; pendingProposals: number; activeCourses: number;
}

/** the template's columns, in order: each maps to the field the upload reads */
const COLUMNS: [string, string][] = [
  ["S/N", ""], ["Course Code", "code"], ["Course Title", "title"], ["Units", "units"], ["Course Type", "courseType"], ["Level", "level"], ["Semester", "semester"],
  ["Course Owner Faculty", "ownerFaculty"], ["Course Owner Department", "ownerDepartment"], ["Course Owner Programme", "ownerProgramme"],
  ["Offering Faculty", "offeringFaculty"], ["Offering Department", "offeringDepartment"], ["Offering Programme", "offeringProgramme"], ["Offering Type", "offeringType"],
  ["Status", "status"], ["Academic Session", "session"], ["Description", "description"], ["Prerequisite Course Code", "prerequisite"],
  ["GST/EPS Classification", "classification"], ["Remarks", "remarks"],
];
/** other headings a file may use for the same columns */
const ALIASES: Record<string, string> = {
  "code": "code", "course code": "code", "title": "title", "course title": "title", "unit": "units", "units": "units", "credit units": "units",
  "type": "courseType", "course type": "courseType", "level": "level", "semester": "semester",
  "owner faculty": "ownerFaculty", "course owner faculty": "ownerFaculty", "owner department": "ownerDepartment", "course owner department": "ownerDepartment",
  "owner programme": "ownerProgramme", "course owner programme": "ownerProgramme", "owner program": "ownerProgramme",
  "offering faculty": "offeringFaculty", "offering department": "offeringDepartment", "offering programme": "offeringProgramme", "offering program": "offeringProgramme",
  "offering type": "offeringType", "status": "status", "session": "session", "academic session": "session", "description": "description",
  "prerequisite": "prerequisite", "prerequisites": "prerequisite", "prerequisite course code": "prerequisite", "prerequisite course codes": "prerequisite",
  "gst/eps classification": "classification", "gst/eps": "classification", "classification": "classification", "remarks": "remarks",
  "offering programmes": "offeringProgrammes", "offering types": "offeringTypes",
};
const SUMMARY_TILES: [string, string, string][] = [
  ["Total rows", "total", ""], ["Valid rows", "valid", "ok"], ["Invalid rows", "invalid", "bad"], ["New courses", "newCourses", ""],
  ["Existing courses", "existingCourses", ""], ["Owner changes", "ownerChanges", ""], ["New offerings", "newOfferings", ""], ["Duplicate offerings", "duplicateOfferings", "bad"],
  ["Conflicts", "conflicts", "bad"], ["Owner errors", "ownerErrors", "bad"], ["Programme errors", "programmeErrors", "bad"], ["Department errors", "departmentErrors", "bad"],
  ["Core/Elective errors", "typeErrors", "bad"], ["Prerequisite errors", "prerequisiteErrors", "bad"],
];
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
const asProblem = (j: unknown, r: Response): Problem => (j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText });

/** the file's rows as the upload reads them: the heading row found, each heading mapped, the one-cell list of programmes expanded */
function readRows(grid: string[][]): Record<string, string>[] {
  const headAt = grid.findIndex((r) => r.some((c) => /course\s*code/i.test(String(c ?? ""))));
  if (headAt < 0) return [];
  const keys = grid[headAt].map((h) => ALIASES[String(h ?? "").trim().toLowerCase().replace(/\s+/g, " ")] ?? "");
  const out: Record<string, string>[] = [];
  for (const r of grid.slice(headAt + 1)) {
    const row: Record<string, string> = {};
    keys.forEach((k, i) => { if (k) row[k] = String(r[i] ?? "").trim(); });
    if (!Object.values(row).some(Boolean)) continue;
    // the alternative layout: several offering programmes (and their types) in one cell, one row each
    if (row.offeringProgrammes && !row.offeringProgramme) {
      const progs = row.offeringProgrammes.split(/\s*[;,|]\s*/).filter(Boolean);
      const types = (row.offeringTypes ?? "").split(/\s*[;,|]\s*/).filter(Boolean);
      progs.forEach((pr, i) => {
        const { offeringProgrammes: _p, offeringTypes: _t, ...rest } = row;
        void _p; void _t;
        out.push({ ...rest, offeringProgramme: pr, offeringType: types[i] ?? types[0] ?? row.offeringType ?? "" });
      });
      continue;
    }
    out.push(row);
  }
  return out;
}

export function CatalogueManage({ directory, resets, imports, actingOffice }: { directory: Directory | null; resets: ResetRow[]; imports: ImportRow[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["ict", "academic", "super"].includes(actingOffice ?? "");
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  // the upload
  const [fileName, setFileName] = useState("");
  const [rows, setRows] = useState<Record<string, string>[] | null>(null);
  const [judged, setJudged] = useState<Judgement | null>(null);
  const [committed, setCommitted] = useState<Judgement | null>(null);
  const [onlyErrors, setOnlyErrors] = useState(false);
  // the reset
  const [scope, setScope] = useState<"ALL" | "FACULTY" | "DEPARTMENT" | "PROGRAMME">("DEPARTMENT");
  const [scopeRef, setScopeRef] = useState("");
  const [preview, setPreview] = useState<Preview | null>(null);
  const [reason, setReason] = useState("");
  const [typed, setTyped] = useState("");
  const [done, setDone] = useState<Record<string, unknown> | null>(null);

  const refOptions = scope === "FACULTY" ? (directory?.faculties ?? []).map((f) => ({ value: f.code, label: f.name }))
    : scope === "DEPARTMENT" ? (directory?.departments ?? []).map((d) => ({ value: d.code, label: d.name }))
    : scope === "PROGRAMME" ? (directory?.programmes ?? []).map((p) => ({ value: p.code, label: `${p.name} (${p.code})` }))
    : [];

  async function template() {
    const example = [
      ["1", "CSC 101", "Introduction to Computer Science", "3", "Core", "100", "1", "Physical Sciences", "Computer Science", "B.Sc. Computer Science", "Physical Sciences", "Computer Science", "B.Sc. Computer Science", "CORE", "ACTIVE", "", "", "", "", ""],
      ["2", "CSC 101", "Introduction to Computer Science", "3", "Core", "100", "1", "Physical Sciences", "Computer Science", "B.Sc. Computer Science", "Physical Sciences", "Mathematics", "B.Sc. Mathematics", "ELECTIVE", "ACTIVE", "", "", "", "", "Same course, another programme: one course, two offerings"],
      ["3", "CSC 201", "Computer Programming I", "3", "Core", "200", "1", "Physical Sciences", "Computer Science", "B.Sc. Computer Science", "Physical Sciences", "Computer Science", "B.Sc. Computer Science", "CORE", "ACTIVE", "", "", "CSC 101", "", ""],
    ];
    downloadBlob(buildXlsx(COLUMNS.map(([h]) => h), example, "Catalogue"), "course-catalogue-template.xlsx");
  }

  async function pick(file: File | null) {
    setJudged(null); setCommitted(null); setProblem(null); setRows(null);
    if (!file) return;
    setFileName(file.name);
    const grid = /\.csv$/i.test(file.name) ? csvRows(await file.text()) : await xlsxRows(await file.arrayBuffer());
    const read = readRows(grid);
    if (!read.length) { const p = { status: 400, title: "No row was found under a 'Course Code' heading. Use the template." }; setProblem(p); notifyProblem(p); return; }
    setRows(read);
    await judge(read, false);
  }

  async function judge(list: Record<string, string>[], commit: boolean) {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue/catalogue-import?commit=${commit}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(commit ? `Course catalogue upload ${fileName}` : `Course catalogue upload checked: ${fileName}`) },
        body: JSON.stringify({ rows: list, fileName }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(asProblem(j, r)); notifyProblem(asProblem(j, r)); return; }
      if (commit) { setCommitted(j as Judgement); setJudged(null); setRows(null); notify(`Course catalogue uploaded · ${(j as Judgement).ref}`); router.refresh(); }
      else setJudged(j as Judgement);
    } finally { setBusy(false); }
  }

  async function errorReport() {
    if (!judged) return;
    const bad = judged.rows.filter((x) => x.state !== "VALID");
    const body = bad.map((x, i) => [i + 1, x.n, x.code ?? "", x.title ?? "", x.ownerDepartment ?? "", x.offeringProgramme ?? "", x.basis ?? "", x.state, x.errors.join("; ")]);
    const blob = await brandedXlsx("Course catalogue upload — rows to correct", ["S/N", "Row in file", "Course Code", "Course Title", "Owner Department", "Offering Programme", "Offering Type", "State", "What to correct"], body,
      { sheetName: "Errors", serial: docSerial("CATERR"), sub: fileName });
    downloadBlob(blob, `course-catalogue-errors-${fileName.replace(/\.[^.]+$/, "")}.xlsx`);
  }

  async function previewReset() {
    if (scope !== "ALL" && !scopeRef) { notifyProblem({ status: 400, title: "Choose the faculty, department or programme to reset." }); return; }
    setBusy(true); setProblem(null); setPreview(null); setDone(null);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue/reset/preview?scope=${scope}${scope === "ALL" ? "" : `&ref=${encodeURIComponent(scopeRef)}`}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(asProblem(j, r)); notifyProblem(asProblem(j, r)); return; }
      setPreview(j as Preview);
    } finally { setBusy(false); }
  }

  async function reset() {
    if (!preview) return;
    if (!window.confirm(`Reset ${preview.label}? ${preview.toArchive} course(s) will be archived and ${preview.toDelete} removed. Historical registrations and results are kept.`)) return;
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/catalogue/reset", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Course catalogue reset: ${preview.label} — ${reason.trim()}`) },
        body: JSON.stringify({ scope, ref: scope === "ALL" ? null : scopeRef, reason: reason.trim(), confirm: typed.trim() }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(asProblem(j, r)); notifyProblem(asProblem(j, r)); return; }
      setDone(j as Record<string, unknown>); setPreview(null); setReason(""); setTyped("");
      notify(`Course catalogue reset · ${String((j as Record<string, unknown>).ref)}`);
      router.refresh();
    } finally { setBusy(false); }
  }

  async function exportResets() {
    const body = resets.map((r, i) => [i + 1, r.ref, r.scope_label, r.reason, r.courses_in_scope, r.bindings_removed, r.offerings_removed, r.offerings_kept, r.archived, r.deleted, r.performed_by ?? "", r.performed_office ?? "", when(r.performed_at)]);
    const blob = await brandedXlsx("Course catalogue resets", ["S/N", "Reference", "Scope", "Reason", "Courses", "Bindings ended", "Offerings removed", "Offerings kept", "Archived", "Removed", "By", "Office", "At"], body,
      { sheetName: "Resets", serial: docSerial("CATRST") });
    downloadBlob(blob, "course-catalogue-resets.xlsx");
  }

  const shown = judged ? (onlyErrors ? judged.rows.filter((x) => x.state !== "VALID") : judged.rows) : [];
  const sum = judged?.summary;

  return (
    <>
      <PageHead eyebrow="Course management" title="Course Catalogue Reset & Upload"
        description="Upload the catalogue with each course's owner and the programmes that offer it, and reset a scope of the catalogue safely. Students' registrations, results and transcripts are never touched." />
      {!may ? <Note kind="info" title="For the Directorate of ICT and the Academic Office">The upload and the reset are central acts on the whole catalogue; you may read this page but not act on it.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Panel title="1 · UPLOAD THE COURSE CATALOGUE — OWNERS AND OFFERINGS" right={<Btn kind="secondary" size="sm" onClick={() => void template()}>Download the template</Btn>}>
        <PBody>
          <div className="sub2">
            One row per programme that offers a course. A course offered to five programmes is five rows that name the same course and the same owner &mdash; they become <b>one course</b> with five offerings, each <b>CORE</b> or <b>ELECTIVE</b> for its programme. The owner is the faculty, department and programme responsible for the course. Faculties, departments and programmes are matched by code or name and must already be on the register; nothing is created there. A file may instead list several offering programmes in one cell (&ldquo;Offering Programmes&rdquo;, with &ldquo;Offering Types&rdquo; in the same order); each is read as its own row.
          </div>
          {may ? (
            <div className="row mt-3">
              <input type="file" accept=".xlsx,.csv" disabled={busy} onChange={(e) => void pick(e.target.files?.[0] ?? null)} />
              {rows ? <span className="sub2">{fileName} · {rows.length} row{rows.length === 1 ? "" : "s"} read</span> : null}
            </div>
          ) : null}
        </PBody>
        {judged && sum ? (
          <>
            <PBody>
              <Tiles items={SUMMARY_TILES.map(([label, key, tone]) => [label.toUpperCase(), String(sum[key] ?? 0),
                Number(sum[key] ?? 0) && tone === "bad" ? "var(--red-ink)" : Number(sum[key] ?? 0) && tone === "ok" ? "var(--green-ink)" : null, ""] as [string, string, string | null, string])} cls="grid--4" />
              {Number(sum.invalid) ? (
                <Note kind="bad" title={`${sum.invalid} row${Number(sum.invalid) === 1 ? "" : "s"} must be corrected before anything is written`}>
                  Download the error report, correct those rows in your file and upload it again. Nothing is written while any row is invalid.
                </Note>
              ) : (
                <Note kind="ok" title="Every row is valid">Commit to write {sum.newCourses ?? 0} new course(s), update {sum.existingCourses ?? 0}, and make {sum.newOfferings ?? 0} new offering(s){Number(sum.ownerChanges) ? <>; <b>{sum.ownerChanges} course(s) change owner</b></> : null}.</Note>
              )}
              <div className="row">
                <Btn kind="ghost" size="sm" onClick={() => void errorReport()} disabled={!Number(sum.invalid) && !Number(sum.skipped)}>Download error report</Btn>
                <label className="row row--inline sub2"><input type="checkbox" checked={onlyErrors} onChange={(e) => setOnlyErrors(e.target.checked)} /> Show only rows to correct</label>
                <span className="grow" />
                <Btn kind="go" disabled={busy || !may || Number(sum.invalid) > 0 || !Number(sum.valid)} onClick={() => { if (rows && window.confirm(`Commit ${sum.valid} row(s)? This writes the courses and their offerings in one transaction.`)) void judge(rows, true); }}>{busy ? "Working…" : "Commit import"}</Btn>
              </div>
            </PBody>
            <DTable pageSize={25} cols={["S/N|num", "Row|num", "Course", "Owner", "Offered to", "Type|mid", "Result|mid", "What to correct / note"]}
              rows={shown.map((x, i) => [
                <span key="s" className="tnum sub2">{i + 1}</span>, <span key="r" className="tnum sub2">{x.n}</span>,
                <span key="c"><b className="tnum">{x.code ?? "—"}</b> {x.title ?? ""}<div className="sub2">{x.units ?? "—"} units · {x.level ?? "—"} level · semester {x.semester ?? "—"}</div></span>,
                <span key="o" className="sub2">{x.ownerDepartment ?? "—"}{x.ownerProgramme ? ` · ${x.ownerProgramme}` : ""}{x.ownerChange ? <div><Pil kind="warn">owner changes</Pil></div> : null}</span>,
                <span key="p" className="sub2">{x.offeringProgramme ?? "—"}{x.existingOffering ? " · existing" : ""}</span>,
                <span key="t" style={{ whiteSpace: "nowrap" }}>{x.basis ? <Pil kind={x.basis === "Core" ? "info" : "grey"}>{x.basis.toUpperCase()}</Pil> : "—"}</span>,
                <span key="v" style={{ whiteSpace: "nowrap" }}><Pil kind={x.state === "VALID" ? "ok" : x.state === "SKIPPED" ? "grey" : "bad"}>{x.state}</Pil></span>,
                <span key="e" className="sub2">{x.errors.length ? x.errors.join(" · ") : x.state === "SKIPPED" ? "INACTIVE: not imported" : [x.existing ? (x.revived ? "archived course brought back" : "existing course") : "new course", x.remarks].filter(Boolean).join(" · ")}</span>,
              ])}
              texts={shown.map((x) => `${x.code ?? ""} ${x.title ?? ""} ${x.ownerDepartment ?? ""} ${x.offeringProgramme ?? ""} ${x.errors.join(" ")}`)} />
          </>
        ) : null}
        {committed ? (
          <PBody>
            <Note kind="ok" title={`Uploaded · ${committed.ref}`}>
              {committed.summary.coursesCreated ?? 0} course(s) created, {committed.summary.coursesUpdated ?? 0} updated ({committed.summary.coursesRevived ?? 0} brought back from a reset), {committed.summary.ownerChangesMade ?? 0} owner change(s), {committed.summary.offeringsCreated ?? 0} offering(s) made and {committed.summary.offeringsUpdated ?? 0} updated, {committed.summary.prerequisitesAdded ?? 0} prerequisite(s). Registration builds each student&rsquo;s courses from these offerings.
            </Note>
          </PBody>
        ) : null}
      </Panel>

      <Panel title="2 · RESET THE COURSE CATALOGUE">
        <PBody>
          <div className="sub2">Clears the active catalogue of the scope so a corrected one can be uploaded. Programme offerings of the scope end, an unused course and an unused session offering are removed, and a course that carries any history &mdash; registrations, results, CBT, questions, deferments, old-portal results or a lecturer &mdash; is <b>archived</b>, never deleted. GST/EPS courses are left to their office. A later upload of an archived course brings the same course back.</div>
          <div className="grid grid--3 mt-3">
            <Field id="rs-scope" label="What to reset">
              <select id="rs-scope" className="ctl" value={scope} disabled={!may} onChange={(e) => { setScope(e.target.value as typeof scope); setScopeRef(""); setPreview(null); setDone(null); }}>
                <option value="PROGRAMME">A programme</option>
                <option value="DEPARTMENT">A department</option>
                <option value="FACULTY">A faculty</option>
                <option value="ALL">The whole catalogue</option>
              </select>
            </Field>
            {scope !== "ALL" ? (
              <Field id="rs-ref" label={scope === "FACULTY" ? "Faculty" : scope === "DEPARTMENT" ? "Department" : "Programme"}>
                <SearchSelect id="rs-ref" value={scopeRef} options={refOptions} placeholder={`Search a ${scope.toLowerCase()}…`} disabled={!may}
                  onChange={(v) => { setScopeRef(v); setPreview(null); setDone(null); }} />
              </Field>
            ) : <div />}
            <div style={{ alignSelf: "end" }}><Btn kind="secondary" disabled={busy || !may} onClick={() => void previewReset()}>Preview the impact</Btn></div>
          </div>
        </PBody>
        {preview ? (
          <PBody>
            <Tiles items={[
              ["ACTIVE COURSES IN SCOPE", String(preview.courses), null, preview.label],
              ["PROGRAMME OFFERINGS TO END", String(preview.bindings), null, `${preview.programmesAffected} programme(s), ${preview.departmentsAffected} department(s)`],
              ["SESSION OFFERINGS", String(preview.offerings), null, `${preview.offeringsRemoved} unused removed · ${preview.offeringsKept} kept`],
              ["REFERENCED BY REGISTRATIONS", String(preview.referencedByRegistrations), preview.referencedByRegistrations ? "var(--chrome)" : null, "courses"],
              ["REFERENCED BY RESULTS", String(preview.referencedByResults), preview.referencedByResults ? "var(--chrome)" : null, "courses"],
              ["TO BE ARCHIVED", String(preview.toArchive), null, "kept, with their history"],
              ["SAFE TO REMOVE", String(preview.toDelete), null, "nothing hangs on them"],
              ["GST/EPS KEPT", String(preview.gstKept), null, "left to their office"],
            ]} cls="grid--4" />
            {preview.sessions.length ? <div className="sub2">Sessions with offerings of these courses: {preview.sessions.join(", ")}.</div> : null}
            <Note kind="bad" title="COURSE RESET WILL CLEAR/ARCHIVE THE SELECTED COURSE CATALOGUE CONFIGURATION.">
              HISTORICAL COURSE REGISTRATIONS, RESULTS, TRANSCRIPTS AND ACADEMIC HISTORY WILL NOT BE DELETED. Students of the scope see no courses at registration until the catalogue is uploaded again.
            </Note>
            <Field id="rs-reason" label="Reason for the reset" hint="Recorded on the reset, the audit trail and every binding it ends">
              <textarea id="rs-reason" className="ctl" rows={2} maxLength={2000} value={reason} onChange={(e) => setReason(e.target.value)} />
            </Field>
            <Field id="rs-typed" label="Type RESET COURSES to confirm"><input id="rs-typed" className="ctl" value={typed} onChange={(e) => setTyped(e.target.value)} autoComplete="off" /></Field>
            <div className="row">
              <Btn kind="urgent" disabled={busy || !may || typed.trim() !== "RESET COURSES" || reason.trim().length < 5} onClick={() => void reset()}>{busy ? "Resetting…" : "Reset the course catalogue"}</Btn>
              <Btn kind="ghost" disabled={busy} onClick={() => setPreview(null)}>Cancel</Btn>
            </div>
          </PBody>
        ) : null}
        {done ? (
          <PBody>
            <Note kind="ok" title={`COURSE CATALOGUE RESET · ${String(done.ref)}`}>
              {String(done.label)}: {String(done.bindingsRemoved)} programme offering(s) ended, {String(done.offeringsRemoved)} unused session offering(s) removed, {String(done.archived)} course(s) archived and {String(done.deleted)} removed. No active courses remain in this scope: upload the corrected catalogue above.
            </Note>
          </PBody>
        ) : null}
      </Panel>

      <Panel title="RESETS" right={resets.length ? <Btn kind="ghost" size="sm" onClick={() => void exportResets()}>Excel</Btn> : null}>
        {resets.length ? (
          <DTable pageSize={10} cols={["S/N|num", "Reference", "Scope", "Reason", "Archived|num", "Removed|num", "Offerings ended|num", "By", "At"]}
            rows={resets.map((r, i) => [
              <span key="s" className="tnum sub2">{i + 1}</span>, <b key="r" className="tnum">{r.ref}</b>, <span key="sc">{r.scope_label}</span>, <span key="w" className="sub2">{r.reason}</span>,
              <span key="a" className="tnum">{r.archived}</span>, <span key="d" className="tnum">{r.deleted}</span>, <span key="b" className="tnum">{r.bindings_removed}</span>,
              <span key="by" className="sub2">{r.performed_by ?? ""}{r.performed_office ? ` (${r.performed_office})` : ""}</span>, <span key="t" className="tnum sub2">{when(r.performed_at)}</span>,
            ])} />
        ) : <PBody><div className="sub2">No reset has been done.</div></PBody>}
      </Panel>

      <Panel title="CATALOGUE UPLOADS">
        {imports.length ? (
          <DTable pageSize={10} cols={["S/N|num", "Reference", "File", "Rows|num", "Created|num", "Updated|num", "Owner changes|num", "Offerings made|num", "By", "At"]}
            rows={imports.map((x, i) => [
              <span key="s" className="tnum sub2">{i + 1}</span>, <b key="r" className="tnum">{x.ref}</b>, <span key="f" className="sub2">{x.file_name ?? "—"}</span>,
              <span key="n" className="tnum">{x.rows}</span>, <span key="c" className="tnum">{x.courses_created}</span>, <span key="u" className="tnum">{x.courses_updated}</span>,
              <span key="o" className="tnum">{x.owner_changes}</span>, <span key="m" className="tnum">{x.offerings_created}</span>,
              <span key="b" className="sub2">{x.imported_by ?? ""}{x.imported_office ? ` (${x.imported_office})` : ""}</span>, <span key="t" className="tnum sub2">{when(x.imported_at)}</span>,
            ])} />
        ) : <PBody><div className="sub2">No catalogue has been uploaded with owners and offerings yet.</div></PBody>}
      </Panel>
    </>
  );
}
