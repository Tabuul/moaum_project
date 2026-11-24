"use client";

/** Old-portal PG applicants migrated (V675): download a template built from the PG application this portal holds, upload the
 *  filled file (sent and checked on the server a chunk at a time, nothing written but the check), read the preview and the error
 *  report, map an old programme, import what is ready with real progress, and follow the fees, documents and history. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { xlsxWorkbook } from "@/lib/xlsx";
import { xlsx, type XlsxLogo } from "@/lib/xlsx-write";
import { loadCrest } from "@/lib/xlsx";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import {
  ACTION, BATCH_STATE, HISTORY_HEAD, MATCH, MIGRATION_STATUS, REPORT_HEAD, RESULT, VERDICT, firstProblem, historyLines, kindWord, mayConfirmNew,
  progressWords, ranges, readFile, reportLines, sha256Hex, stateWord, templateSheets,
  type BatchLine, type Kind, type MigrationRow, type Summary, type TemplateData,
} from "@/lib/pg-migration";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, RoleLine, Tabs, Tiles, Two } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { fileAsBase64, migGet, migPost } from "./mig-call";

export interface Figures {
  legacyApplicants: number; migrated: number; pending: number; offered: number; accepted: number; screened: number; students: number;
  duplicates: number; conflicts: number; review: number; errors: number; documentsMissing: number; unmappedProgrammes: number;
  feesUnderReview: number; schoolFeesForBursary: number; batches: number; openBatches: number;
}
export interface ListPage { view: string; total: number; limit: number; offset: number; rows: Record<string, unknown>[] }

/* V679: and the Director of ICT and the Database Operators (an operator over the whole University; the server holds the scope) */
const MIGRATORS = ["pgschool", "pgsecretary", "academic", "ict", "dbops", "super"];
const FEE_DECIDERS = ["pgsecretary", "bursar", "super"];
const HOME = "/admissions/postgraduate/migration";
const SCHOOL = "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI";
const s = (v: unknown) => (v == null ? "" : String(v));
const n = (v: unknown) => Number(v ?? 0);
const when = (v: unknown) => (v ? new Date(String(v)).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const naira = (v: unknown) => `₦${Number(v ?? 0).toLocaleString("en-GB")}`;

type Tab = "upload" | "batch" | "mapping" | "fees" | "documents" | "history" | "find";

export function PgMigration({ office, figures, problem, batches, batch, view, list }: {
  office: string | null; figures: Figures | null; problem: Problem | null; batches: BatchLine[]; batch: Summary | null; view: string | null; list: ListPage | null;
}) {
  const router = useRouter();
  const [tab, setTab] = useState<Tab>(batch ? "batch" : view === "fees" ? "fees" : view === "documents" ? "documents" : "upload");
  const mayMigrate = MIGRATORS.includes(office ?? "");
  const f = figures;
  const tile = (label: string, value: number | undefined, caption: string, v: string, warn = false): [string, string, string | null, string, string] =>
    [label, String(value ?? 0), warn && n(value) ? "var(--chrome)" : null, caption, `${HOME}?view=${v}`];
  return (
    <>
      <RoleLine allowed={["pgschool", "pgsecretary", "academic", "ict", "dbops", "registrar", "dregistrar", "bursar"]} actingOffice={office}
        action="Migrating old-portal PG applicants" />
      <Note kind="info" title="Old applicants are migrated, never made to apply again">
        Each keeps the old portal&rsquo;s application number beside this portal&rsquo;s own, and both find them. An applicant admitted on the old portal
        comes in admitted. Nothing is written until a file is checked: you read what each row would do, and why not, before you import it.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {f ? (
        <Tiles cls="grid--4" items={[
          tile("Total legacy applicants", f.legacyApplicants, "Migrated, linked or in a file", "migrated"),
          tile("Migrated applicants", f.migrated, "Old number kept beside the new", "migrated"),
          tile("Pending migration", f.pending, "Checked, ready, not imported", "pending"),
          tile("Admitted applicants", f.offered, "Offer stands, not yet accepted", "offered"),
          tile("Accepted applicants", f.accepted, "Offer accepted", "accepted"),
          tile("Screened applicants", f.screened, "Cleared on the old portal", "screened"),
          tile("Active PG students", f.students, "On the register", "students"),
          tile("Duplicate applicants", f.duplicates, "Repeated in a file", "duplicates", true),
          tile("Conflicts", f.conflicts, "Identity or decision differs", "conflicts", true),
          tile("Requires review", f.review, "Not matched with confidence", "review", true),
          tile("Missing documents", f.documentsMissing, "Old reference, no file yet", "documents", true),
          tile("Unmapped programmes", f.unmappedProgrammes, "Old programme names to map", "review", true),
        ]} />
      ) : null}
      {view && list ? <ViewPanel view={view} list={list} onClose={() => router.push(HOME)} /> : null}

      <Tabs<Tab> label="PG migration" value={tab} onChange={setTab} items={[
        { id: "upload", label: "Upload" },
        { id: "batch", label: "Current batch", disabled: !batch },
        { id: "mapping", label: "Programme mapping", count: f?.unmappedProgrammes || undefined },
        { id: "fees", label: "Old-portal fees", count: f?.feesUnderReview || undefined },
        { id: "documents", label: "Documents", count: f?.documentsMissing || undefined },
        { id: "history", label: "Migration history" },
        { id: "find", label: "Find an applicant" },
      ]} />

      {tab === "upload" ? <UploadPanel mayMigrate={mayMigrate} onDone={(id) => { router.push(`${HOME}?batch=${id}`); setTab("batch"); }} /> : null}
      {tab === "batch" && batch ? <BatchPanel key={batch.id + batch.state + batch.imported} b={batch} mayMigrate={mayMigrate} refresh={() => router.refresh()} /> : null}
      {tab === "mapping" ? <MappingPanel mayMigrate={mayMigrate} /> : null}
      {tab === "fees" ? <FeesPanel office={office} /> : null}
      {tab === "documents" ? <DocumentsPanel mayMigrate={mayMigrate} /> : null}
      {tab === "history" ? <HistoryPanel batches={batches} /> : null}
      {tab === "find" ? <FindPanel /> : null}
    </>
  );
}

/* ── the two uploads: the template, then the file sent and checked ───────────────────────────────────────────────────── */
function UploadPanel({ mayMigrate, onDone }: { mayMigrate: boolean; onDone: (batchId: string) => void }) {
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  const [notifyApplicants, setNotifyApplicants] = useState(true);
  const [warn, setWarn] = useState<string | null>(null);

  async function template(kind: Kind) {
    const t = await migGet<TemplateData>(`/template?kind=${kind}`);
    if (!t.ok) { notifyProblem(t.problem); return; }
    const logo: XlsxLogo | null = await loadCrest().catch(() => null);
    const title = kind === "ADMITTED" ? "ADMITTED PG APPLICANT MIGRATION TEMPLATE" : "PG APPLICANT MIGRATION TEMPLATE";
    const book = xlsx(templateSheets(t.data, title, SCHOOL), { logo: logo ?? undefined });
    downloadBlob(new Blob([book as BlobPart], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }), `${title}.xlsx`);
  }

  async function upload(kind: Kind, file: File) {
    setErr(null); setWarn(null);
    if (!/\.xlsx$/i.test(file.name)) { setErr({ status: 422, title: "That file type is not accepted", detail: "Upload the filled template as an Excel workbook (.xlsx)." }); return; }
    if (file.size > 15 * 1024 * 1024) { setErr({ status: 422, title: "The file is too large", detail: "A migration file is at most 15 MB; split a larger one." }); return; }
    setBusy("Reading the file…");
    try {
      const buf = await file.arrayBuffer();
      const t = await migGet<TemplateData>(`/template?kind=${kind}`);
      if (!t.ok) { setErr(t.problem); return; }
      const read = readFile(await xlsxWorkbook(buf), t.data.columns);
      if (read.missing.length) {
        setErr({ status: 422, title: "The file is not the template", detail: `It has no column for: ${read.missing.join(", ")}. Download the template and copy the old portal's data into it.` });
        return;
      }
      if (!read.rows.length) { setErr({ status: 422, title: "The file has no applicants", detail: "Fill one row per applicant under the header." }); return; }
      if (read.rows.length > 20000) { setErr({ status: 422, title: "The file is too long", detail: `${read.rows.length.toLocaleString("en-GB")} rows; a migration file holds up to 20,000. Split it.` }); return; }
      if (read.unknown.length) setWarn(`Columns not read (not on the template): ${read.unknown.join(", ")}.`);
      const sha = await sha256Hex(buf);
      const opened = await migPost<Summary>("/batches", { kind, fileName: file.name, sha256: sha, rows: read.rows.length, tell: notifyApplicants },
        `PG migration upload: ${file.name}`);
      if (!opened.ok) { setErr(opened.problem); return; }
      const b = opened.data;
      if (b.importedBefore) notify(`This file was imported before (${b.importedBefore}); importing it again changes nothing already on record.`, "info", 8000);
      for (const [from, to] of ranges(read.rows.length, 500)) {
        setBusy(progressWords("upload", from - 1, read.rows.length));
        const r = await migPost(`/batches/${b.id}/rows`, { first: from, rows: read.rows.slice(from - 1, to) }, `PG migration ${b.reference}: rows ${from}–${to}`);
        if (!r.ok) { setErr(r.problem); return; }
      }
      for (const [from, to] of ranges(read.rows.length, 1000)) {
        setBusy(progressWords("check", from - 1, read.rows.length));
        const r = await migPost(`/batches/${b.id}/check`, { from, to }, `PG migration ${b.reference}: check`);
        if (!r.ok) { setErr(r.problem); return; }
      }
      notify(`${b.reference}: ${read.rows.length.toLocaleString("en-GB")} rows checked. Nothing is written until you import.`);
      onDone(b.id);
    } catch (e) {
      setErr({ status: 422, title: "The file could not be read", detail: e instanceof Error ? e.message : String(e) });
    } finally {
      setBusy(null);
    }
  }

  const card = (kind: Kind, title: string, what: string) => (
    <Panel title={title}>
      <PBody>
        <p className="sub2">{what}</p>
        <div className="row row--inline">
          <Btn kind="secondary" onClick={() => template(kind)}>Download {kind === "ADMITTED" ? "admitted PG applicant" : "PG applicant"} migration template</Btn>
          {mayMigrate ? (
            <label className={`btn btn--primary btn--sm${busy ? " is-disabled" : ""}`}>
              Upload filled template
              <input type="file" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" hidden disabled={!!busy}
                onChange={(e) => { const fl = e.target.files?.[0]; e.target.value = ""; if (fl) void upload(kind, fl); }} />
            </label>
          ) : null}
        </div>
      </PBody>
    </Panel>
  );
  return (
    <>
      {busy ? <Note kind="info" title={busy}>The rows go to the server a chunk at a time; the count is the rows it has taken.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      {warn ? <Note kind="info" title="Some columns were not read">{warn}</Note> : null}
      <div className="grid grid--2">
        {card("APPLICANTS", "PG applicant migration", "Applicants not admitted on the old portal: submitted, recommended or not admitted. Each gets this portal's application number; the old one is kept beside it.")}
        {card("ADMITTED", "PG admitted applicant migration", "Applicants admitted on the old portal, with the admission, the acceptance, the screening and the school fees as the old portal recorded them. They come in admitted, never to apply again.")}
      </div>
      {mayMigrate ? (
        <label className="row row--inline sub2" style={{ marginTop: 8 }}>
          <input type="checkbox" checked={notifyApplicants} onChange={(e) => setNotifyApplicants(e.target.checked)} />
          Tell each migrated applicant once, by email and SMS, their new and old application numbers and how to sign in (never a password)
        </label>
      ) : <Note kind="info" title="Read only">The School of Postgraduate Studies, its Secretary and the Academic Office upload and import.</Note>}
    </>
  );
}

/* ── a batch: the preview, the rows, the error report, the import ──────────────────────────────────────────────────── */
const FILTERS: [string, string][] = [["ALL", "All rows"], ["PROBLEMS", "Not plainly ready"], ["READY", "Ready"], ["WARNING", "Ready, with a note"],
  ["DUPLICATE_IN_FILE", "Duplicates"], ["CONFLICT", "Conflicts"], ["REQUIRES_REVIEW", "Requires review"], ["ERROR", "Errors"],
  ["CREATED", "Created"], ["UPDATED", "Updated"], ["RECONCILED", "Reconciled"], ["LINKED", "Linked"], ["UNCHANGED", "Already on record"],
  ["SKIPPED", "Not imported"], ["FAILED", "Failed"]];

function BatchPanel({ b, mayMigrate, refresh }: { b: Summary; mayMigrate: boolean; refresh: () => void }) {
  const [status, setStatus] = useState("PROBLEMS");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(0);
  const [rows, setRows] = useState<{ total: number; rows: MigrationRow[] } | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  const [confirm, setConfirm] = useState(false);
  const [abandon, setAbandon] = useState(false);
  const [reason, setReason] = useState("");
  const [newRow, setNewRow] = useState<MigrationRow | null>(null);
  const [live, setLive] = useState<Summary>(b);
  const open = b.state === "CHECKED" || b.state === "IMPORTING";

  async function load(st = status, pg = page, query = q) {
    const r = await migGet<{ total: number; rows: MigrationRow[] }>(`/batches/${b.id}/rows?status=${st}&page=${pg}&size=50${query.trim() ? `&q=${encodeURIComponent(query.trim())}` : ""}`);
    if (r.ok) setRows(r.data); else setErr(r.problem);
  }
  if (rows === null && !err) void load();

  async function recheck() {
    setErr(null);
    for (const [from, to] of ranges(b.rowsExpected, 1000)) {
      setBusy(progressWords("check", from - 1, b.rowsExpected));
      const r = await migPost<Summary>(`/batches/${b.id}/check`, { from, to }, `PG migration ${b.reference}: checked again`);
      if (!r.ok) { setErr(r.problem); setBusy(null); return; }
      setLive(r.data);
    }
    setBusy(null); notify("Checked again."); refresh(); void load();
  }

  async function importAll() {
    setConfirm(false); setErr(null);
    for (const [from, to] of ranges(b.rowsExpected, 250)) {
      setBusy(progressWords("import", from - 1, b.rowsExpected));
      const r = await migPost<Summary>(`/batches/${b.id}/import`, { from, to }, `PG migration ${b.reference}: import`);
      if (!r.ok) { setErr(r.problem); setBusy(null); refresh(); return; }
      setLive(r.data);
    }
    const fin = await migPost<Summary>(`/batches/${b.id}/finish`, {}, `PG migration ${b.reference}: finished`);
    setBusy(null);
    if (!fin.ok) { setErr(fin.problem); refresh(); return; }
    setLive(fin.data);
    notify(`${b.reference} imported: ${fin.data.created} created, ${fin.data.updated + fin.data.reconciled} updated, ${fin.data.linked} linked, ${fin.data.skipped} not imported.`);
    refresh(); void load("PROBLEMS", 0);
  }

  async function report() {
    const r = await migGet<MigrationRow[]>(`/batches/${b.id}/report`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    const blob = await brandedXlsx("PG migration error report", REPORT_HEAD, reportLines(r.data), { sheetName: "Errors", serial: docSerial("PGMIG"), sub: `${b.reference} · ${b.fileName}`, noSerialColumn: true });
    downloadBlob(blob, `${b.reference.replace(/\//g, "-")} error report.xlsx`);
  }

  async function setAside() {
    const r = await migPost<Summary>(`/batches/${b.id}/abandon`, { reason }, `PG migration ${b.reference} set aside: ${reason}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    setAbandon(false); notify(`${b.reference} set aside; nothing more is imported from it.`); refresh();
  }

  async function confirmNew() {
    if (!newRow) return;
    const r = await migPost(`/rows/${newRow.id}/new`, { reason }, `PG migration row ${newRow.row_no}: a new applicant`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    setNewRow(null); setReason(""); notify("Confirmed: a new applicant."); refresh(); void load();
  }

  const L = live;
  const st = BATCH_STATE[L.state] ?? [L.state, "grey"];
  return (
    <>
      <Panel title={<>{L.reference} · {kindWord(L.kind)}</>} right={<Pil kind={st[1]}>{st[0]}</Pil>}>
        <PBody>
          <div className="sub2">{L.fileName} · uploaded {when(L.startedAt)} by {L.startedBy ?? "—"} · {L.notify ? "applicants told once on import" : "applicants not told"}</div>
          {L.abandonedReason ? <Note kind="info" title="Set aside">{L.abandonedReason}</Note> : null}
        </PBody>
        <Tiles cls="grid--5" items={[
          ["Total rows", L.rowsExpected.toLocaleString("en-GB"), null, `${L.checked.toLocaleString("en-GB")} checked`],
          ["New applicants", String(L.newApplicants), null, "Will be created"],
          ["Existing applicants", String(L.existingApplicants), null, "Found here: updated, never made twice"],
          ["Admitted applicants", String(L.admitted), null, "Admitted on the old portal"],
          ["Already students", String(L.alreadyStudents), null, "Linked, not admitted again"],
          ["Duplicates", String(L.duplicates), L.duplicates ? "var(--chrome)" : null, "Repeated in the file"],
          ["Conflicts", String(L.conflicts), L.conflicts ? "var(--chrome)" : null, "Identity or decision differs"],
          ["Programmes not mapped", String(L.programmesNotMapped), L.programmesNotMapped ? "var(--chrome)" : null, "Map them, then check again"],
          ["Missing required data", String(L.missingData), L.missingData ? "var(--chrome)" : null, "Correct and upload again"],
          ["Ready to import", String(L.readyToImport), L.readyToImport ? "var(--green-ink)" : null, `${L.creates} create · ${L.updates} update · ${L.reconciles} reconcile · ${L.links} link`],
        ]} />
        <PBody>
          <div className="sub2">The dry run would also record {L.proposedFees} old-portal fee{L.proposedFees === 1 ? "" : "s"} and {L.proposedDocuments} document reference{L.proposedDocuments === 1 ? "" : "s"}.
            {L.imported ? <> Imported so far: {L.created} created, {L.updated} updated, {L.reconciled} reconciled, {L.linked} linked, {L.unchanged} already on record, {L.skipped} not imported, {L.failed} failed; {L.feesPosted} fee{L.feesPosted === 1 ? "" : "s"} posted, {L.feesUnderReview} held for review.</> : null}
          </div>
          {busy ? <Note kind="info" title={busy}>Each chunk is committed on the server as it goes; the count is the rows done.</Note> : null}
          {err ? <ProblemNotice problem={err} /> : null}
          <div className="row row--inline" style={{ marginTop: 8 }}>
            <Btn kind="secondary" onClick={report}>Download error report</Btn>
            {mayMigrate && L.state === "CHECKED" ? <Btn kind="ghost" onClick={recheck} disabled={!!busy}>Check again</Btn> : null}
            {mayMigrate && open ? <Btn kind="primary" onClick={() => setConfirm(true)} disabled={!!busy}>{L.state === "IMPORTING" ? "Continue the import" : `Import ${L.readyToImport.toLocaleString("en-GB")} ready rows`}</Btn> : null}
            {mayMigrate && (open || L.state === "STAGING") ? <Btn kind="ghost" onClick={() => { setReason(""); setAbandon(true); }} disabled={!!busy}>Set aside</Btn> : null}
          </div>
        </PBody>
      </Panel>

      <Panel title="Rows" right={<span className="row row--inline row--tight">
        <select className="ctl" aria-label="Show rows" value={status} onChange={(e) => { setStatus(e.target.value); setPage(0); void load(e.target.value, 0); }}>
          {FILTERS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
        </select>
        <input className="ctl" aria-label="Search rows" placeholder="Old number, name or email" value={q} onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") { setPage(0); void load(status, 0, q); } }} />
      </span>}>
        {rows && rows.rows.length ? (
          <DTable pageSize={0}
            cols={["Row|num", "Applicant", "Old / new application no.", "Programme", "Session|mid", "Admission status", "Match", "Status|mid", "Error / warning", "Proposed action", "|num"]}
            rows={rows.rows.map((r) => {
              const v = r.result ? RESULT[r.result] ?? [r.result, "grey"] : VERDICT[r.verdict ?? ""] ?? [r.verdict ?? "—", "grey"];
              const p = firstProblem(r);
              return [
                <span key="n" className="tnum">{r.row_no}{r.sheet_row ? <div className="sub2">sheet {r.sheet_row}</div> : null}</span>,
                <Two key="a" a={r.applicant ?? "—"} b={r.email ?? ""} />,
                <Two key="no" a={r.legacy_no ?? "—"} b={r.application_no ?? r.student_no ?? (r.action === "CREATE" ? "a new number on import" : "")} />,
                <Two key="p" a={r.programme_name ?? r.programme_given ?? r.programme_code_given ?? "—"} b={[r.department_name ?? r.department_given, r.faculty_name ?? r.faculty_given].filter(Boolean).join(" · ")} />,
                <span key="s" className="tnum">{r.session ?? "—"}</span>,
                <Two key="st" a={stateWord(r.target_state)} b={r.status_given ?? ""} />,
                <span key="m">{MATCH[r.match ?? ""] ?? "—"}</span>,
                <Pil key="v" kind={v[1]}>{v[0]}</Pil>,
                <span key="e" className="sub2">{p ? <>{p.message}{p.fix ? <div><i>{p.fix}</i></div> : null}</> : r.result_note ?? ""}</span>,
                <span key="ac">{r.result && r.result !== "SKIPPED" && r.result !== "FAILED" ? ACTION[r.action ?? ""] ?? "—"
                  : ["READY", "WARNING"].includes(r.verdict ?? "") && !r.result ? ACTION[r.action ?? ""] ?? "—" : <i className="sub2">Not imported</i>}</span>,
                mayConfirmNew(r) && mayMigrate ? <Btn key="b" kind="ghost" size="sm" onClick={() => { setReason(""); setNewRow(r); }}>A new applicant</Btn>
                  : r.application_id ? <LinkBtn key="b" href={`/admissions/postgraduate/applications/${r.application_id}`}>Open</LinkBtn> : <span key="b" />,
              ];
            })}
          />
        ) : <PBody><div className="sub2">{rows ? "No row in this view." : "Reading the rows…"}</div></PBody>}
        {rows && rows.total > 50 ? (
          <PBody>
            <div className="row row--inline">
              <Btn kind="ghost" size="sm" disabled={page === 0} onClick={() => { const pg = page - 1; setPage(pg); void load(status, pg); }}>Previous</Btn>
              <span className="sub2">Page {page + 1} of {Math.ceil(rows.total / 50)} · {rows.total.toLocaleString("en-GB")} rows</span>
              <Btn kind="ghost" size="sm" disabled={(page + 1) * 50 >= rows.total} onClick={() => { const pg = page + 1; setPage(pg); void load(status, pg); }}>Next</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>

      {confirm ? (
        <Modal title={`Import ${L.reference}`} onClose={() => setConfirm(false)}
          foot={<><Btn kind="ghost" onClick={() => setConfirm(false)}>Cancel</Btn><Btn kind="primary" onClick={importAll}>Import</Btn></>}>
          <p>{L.readyToImport.toLocaleString("en-GB")} ready rows are imported: {L.creates} applicants created, {L.updates + L.reconciles} updated or moved forward to where the old portal had them, {L.links} linked to students already on the register.
            The rest ({(L.duplicates + L.conflicts + L.review + L.errors).toLocaleString("en-GB")}) are not imported and stay in the error report.</p>
          <p className="sub2">Each row is checked again as it is imported. Nobody, no admission, no student and no payment is made twice; importing the same file again changes nothing already on record.</p>
        </Modal>
      ) : null}
      {abandon ? (
        <Modal title={`Set aside ${L.reference}`} onClose={() => setAbandon(false)}
          foot={<><Btn kind="ghost" onClick={() => setAbandon(false)}>Cancel</Btn><Btn kind="primary" onClick={setAside} disabled={reason.trim().length < 5}>Set aside</Btn></>}>
          <p className="sub2">What was imported stays; nothing more is imported from this upload. The upload is kept in the history.</p>
          <Field id="ab-why" label="Why" required><textarea id="ab-why" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
      {newRow ? (
        <Modal title={`Row ${newRow.row_no}: a new applicant`} onClose={() => setNewRow(null)}
          foot={<><Btn kind="ghost" onClick={() => setNewRow(null)}>Cancel</Btn><Btn kind="primary" onClick={confirmNew} disabled={reason.trim().length < 10}>Confirm a new applicant</Btn></>}>
          <p>{firstProblem(newRow)?.message}</p>
          <Field id="nw-why" label="How you know this is another person" required hint="At least ten characters; kept with the row.">
            <textarea id="nw-why" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}

/* ── old programmes mapped to this portal's ──────────────────────────────────────────────────────────────────────────── */
interface MapData {
  mappings: { id: string; legacy_code: string | null; legacy_name: string; programme_code: string; programme_name: string; department: string; faculty: string;
    specialisation: string | null; state: string; reason: string; mapped_at: string; mapped_by: string | null; withdrawn_reason: string | null }[];
  unmapped: { legacy_code: string | null; legacy_name: string | null; department: string | null; faculty: string | null; rows: number; batches: string }[];
  programmes: { code: string; name: string; award: string | null; department: string; faculty: string }[];
  specialisations: { id: string; programme_code: string; name: string }[];
}
function MappingPanel({ mayMigrate }: { mayMigrate: boolean }) {
  const [d, setD] = useState<MapData | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  const [form, setForm] = useState<{ code: string; name: string; programme: string; spec: string; reason: string } | null>(null);
  const [withdraw, setWithdraw] = useState<{ id: string; reason: string } | null>(null);
  async function load() { const r = await migGet<MapData>("/programme-map"); if (r.ok) setD(r.data); else setErr(r.problem); }
  if (d === null && !err) void load();
  async function save() {
    if (!form) return;
    const r = await migPost("/programme-map", { legacyCode: form.code || null, legacyName: form.name || null, programme: form.programme, specialisationId: form.spec || null, reason: form.reason },
      `Old programme "${form.name || form.code}" mapped to ${form.programme}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    setForm(null); notify("Mapped. Check the open batches again to read their rows."); void load();
  }
  async function unmap() {
    if (!withdraw) return;
    const r = await migPost(`/programme-map/${withdraw.id}/withdraw`, { reason: withdraw.reason }, `Old programme mapping withdrawn: ${withdraw.reason}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    setWithdraw(null); notify("Withdrawn."); void load();
  }
  return (
    <>
      {err ? <ProblemNotice problem={err} /> : null}
      <Panel title="Old programmes not found here" right={<span className="sub2">Mapped once, read by every later import; no programme is ever created</span>}>
        {d && d.unmapped.length ? (
          <DTable cols={["Old programme", "Old code", "Department / faculty the file named", "Rows|num", "Uploads", "|num"]}
            rows={d.unmapped.map((u, i) => [
              <b key="n">{u.legacy_name ?? "—"}</b>, <span key="c" className="tnum">{u.legacy_code ?? "—"}</span>,
              <span key="d" className="sub2">{[u.department, u.faculty].filter(Boolean).join(" · ") || "—"}</span>,
              <span key="r" className="tnum">{u.rows}</span>, <span key="b" className="sub2">{u.batches}</span>,
              mayMigrate ? <Btn key="m" kind="secondary" size="sm" onClick={() => setForm({ code: u.legacy_code ?? "", name: u.legacy_name ?? "", programme: "", spec: "", reason: "" })}>Map</Btn> : <span key={`m${i}`} />,
            ])} />
        ) : <PBody><div className="sub2">{d ? "Every old programme in the open uploads is found here." : "Reading…"}</div></PBody>}
      </Panel>
      <Panel title="Mappings" right={mayMigrate ? <Btn kind="ghost" size="sm" onClick={() => setForm({ code: "", name: "", programme: "", spec: "", reason: "" })}>Map an old programme</Btn> : undefined}>
        {d && d.mappings.length ? (
          <DTable cols={["Old programme", "This portal's programme", "Faculty / department", "Reason", "Mapped", "State|mid", "|num"]}
            rows={d.mappings.map((m) => [
              <Two key="o" a={m.legacy_name} b={m.legacy_code ?? ""} />, <Two key="p" a={m.programme_name} b={[m.programme_code, m.specialisation].filter(Boolean).join(" · ")} />,
              <span key="f" className="sub2">{m.faculty} · {m.department}</span>, <span key="r" className="sub2">{m.state === "WITHDRAWN" ? `Withdrawn: ${m.withdrawn_reason}` : m.reason}</span>,
              <Two key="w" a={when(m.mapped_at)} b={m.mapped_by ?? ""} />, <Pil key="s" kind={m.state === "APPROVED" ? "ok" : "grey"}>{m.state === "APPROVED" ? "In force" : "Withdrawn"}</Pil>,
              mayMigrate && m.state === "APPROVED" ? <Btn key="x" kind="ghost" size="sm" onClick={() => setWithdraw({ id: m.id, reason: "" })}>Withdraw</Btn> : <span key="x" />,
            ])} />
        ) : <PBody><div className="sub2">{d ? "No old programme has been mapped yet." : "Reading…"}</div></PBody>}
      </Panel>
      {form && d ? (
        <Modal title="Map an old programme" onClose={() => setForm(null)} wide
          foot={<><Btn kind="ghost" onClick={() => setForm(null)}>Cancel</Btn><Btn kind="primary" onClick={save} disabled={!form.programme || form.reason.trim().length < 5 || !(form.name.trim() || form.code.trim())}>Map</Btn></>}>
          <div className="grid grid--2">
            <Field id="mp-name" label="Old programme name" required><input id="mp-name" className="ctl" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} /></Field>
            <Field id="mp-code" label="Old programme code" hint="If the old portal gave one"><input id="mp-code" className="ctl" value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} /></Field>
            <Field id="mp-prog" label="This portal's programme" required full>
              <SearchSelect id="mp-prog" value={form.programme} onChange={(v) => setForm({ ...form, programme: v, spec: "" })} placeholder="Choose the postgraduate programme"
                options={d.programmes.map((p) => ({ value: p.code, label: `${p.name}${p.award ? ` (${p.award})` : ""}`, sub: `${p.code} · ${p.department} · ${p.faculty}` }))} />
            </Field>
            {d.specialisations.some((x) => x.programme_code === form.programme) ? (
              <Field id="mp-spec" label="Specialisation" hint="If the old programme was one">
                <select id="mp-spec" className="ctl" value={form.spec} onChange={(e) => setForm({ ...form, spec: e.target.value })}>
                  <option value="">None</option>
                  {d.specialisations.filter((x) => x.programme_code === form.programme).map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
                </select>
              </Field>
            ) : null}
            <Field id="mp-why" label="Why it is this programme" required full><textarea id="mp-why" className="ctl" rows={3} value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
      {withdraw ? (
        <Modal title="Withdraw the mapping" onClose={() => setWithdraw(null)}
          foot={<><Btn kind="ghost" onClick={() => setWithdraw(null)}>Cancel</Btn><Btn kind="primary" onClick={unmap} disabled={withdraw.reason.trim().length < 5}>Withdraw</Btn></>}>
          <p className="sub2">Applicants already migrated keep their programme; later imports no longer read this mapping.</p>
          <Field id="wd-why" label="Why" required><textarea id="wd-why" className="ctl" rows={3} value={withdraw.reason} onChange={(e) => setWithdraw({ ...withdraw, reason: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </>
  );
}

/* ── fees paid on the old portal ─────────────────────────────────────────────────────────────────────────────────────── */
function FeesPanel({ office }: { office: string | null }) {
  const [d, setD] = useState<ListPage | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  const [act, setAct] = useState<{ row: Record<string, unknown>; verify: boolean; note: string } | null>(null);
  const mayDecide = FEE_DECIDERS.includes(office ?? "");
  async function load() { const r = await migGet<ListPage>("/list?view=fees&size=200"); if (r.ok) setD(r.data); else setErr(r.problem); }
  if (d === null && !err) void load();
  async function decide() {
    if (!act) return;
    const r = await migPost(`/fees/${s(act.row.id)}/decide`, { verify: act.verify, note: act.note },
      `Old-portal fee ${s(act.row.legacy_reference)} ${act.verify ? "verified" : "rejected"}: ${act.note}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    setAct(null); notify(act.verify ? "Verified and posted; the applicant is told." : "Rejected."); void load();
  }
  const kindWords: Record<string, string> = { APPLICATION: "Application fee", ACCEPTANCE: "Acceptance fee", SCHOOL_FEES: "School fees" };
  return (
    <>
      <Note kind="info" title="An application fee marked Paid on the old portal clears on its own; the rest wait for an officer">
        A Paid application fee is posted when it is imported, provided the old portal&apos;s own status says it was paid, its amount reaches the session&apos;s application fee, its reference is on no other
        ledger of the portal and was not rejected by an officer, and the applicant has paid the fee nowhere else. One that fails a check is held below with its
        reason: the applicant is not asked to pay it again meanwhile, and the Bursary or the PG Secretary — not the officer who uploaded it — verifies it
        against the bank or the gateway, or rejects it. A fee the old portal marked Verified is posted as before, and an acceptance fee the old portal did not
        verify is always held for an officer. School fees are never posted here: the Bursary loads them through its old-portal payments upload, and they read
        as on record once it has.
      </Note>
      {err ? <ProblemNotice problem={err} /> : null}
      <Panel title="Old-portal fees to settle" right={<span className="sub2">{d ? `${d.total} in all` : ""}</span>}>
        {d && d.rows.length ? (
          <DTable cols={["Fee", "Applicant", "Old / new number", "Old reference", "Amount|num", "Paid on|mid", "Stated", "Standing|mid", "|num"]}
            rows={d.rows.map((r) => [
              <span key="k">{kindWords[s(r.kind)] ?? s(r.kind)}</span>, <Two key="a" a={s(r.name)} b={s(r.student_no)} />,
              <Two key="n" a={s(r.legacy_application_no)} b={s(r.application_no)} />, <span key="r" className="tnum">{s(r.legacy_reference)}</span>,
              <span key="m" className="tnum">{naira(r.amount)}</span>, <span key="p" className="tnum">{s(r.paid_on) || "—"}</span>, <span key="st" className="sub2">{s(r.stated_status) || "—"}</span>,
              r.state === "FOR_BURSARY" ? <Pil key="s" kind={r.on_record ? "ok" : "warn"}>{r.on_record ? "On record" : "For the Bursary's upload"}</Pil> : <span key="s"><Pil kind="warn">Requires review</Pil>{r.hold_reason ? <div className="sub2">{s(r.hold_reason)}</div> : null}</span>,
              r.state === "REQUIRES_REVIEW" && mayDecide ? (
                <span key="b" className="row row--inline row--tight">
                  <Btn kind="secondary" size="sm" disabled={!!r.uploaded_by_me} title={r.uploaded_by_me ? "You uploaded it: another officer verifies it" : undefined} onClick={() => setAct({ row: r, verify: true, note: "" })}>Verify</Btn>
                  <Btn kind="ghost" size="sm" disabled={!!r.uploaded_by_me} onClick={() => setAct({ row: r, verify: false, note: "" })}>Reject</Btn>
                </span>
              ) : <span key="b" />,
            ])} />
        ) : <PBody><div className="sub2">{d ? "No old-portal fee waits." : "Reading…"}</div></PBody>}
      </Panel>
      {act ? (
        <Modal title={`${act.verify ? "Verify" : "Reject"} ${s(act.row.legacy_reference)}`} onClose={() => setAct(null)}
          foot={<><Btn kind="ghost" onClick={() => setAct(null)}>Cancel</Btn><Btn kind="primary" onClick={decide} disabled={act.note.trim().length < 5}>{act.verify ? "Verify and post" : "Reject"}</Btn></>}>
          <p>{kindWords[s(act.row.kind)]} of {naira(act.row.amount)} for {s(act.row.name)} ({s(act.row.application_no) || s(act.row.legacy_application_no)}).</p>
          <Field id="fee-note" label={act.verify ? "What was checked" : "Why it is rejected"} required hint={act.verify ? "The bank statement or the gateway's record." : undefined}>
            <textarea id="fee-note" className="ctl" rows={3} value={act.note} onChange={(e) => setAct({ ...act, note: e.target.value })} />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}

/* ── the old portal's documents ──────────────────────────────────────────────────────────────────────────────────────── */
function DocumentsPanel({ mayMigrate }: { mayMigrate: boolean }) {
  const [d, setD] = useState<ListPage | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  async function load() { const r = await migGet<ListPage>("/list?view=documents&size=200"); if (r.ok) setD(r.data); else setErr(r.problem); }
  if (d === null && !err) void load();
  async function attach(row: Record<string, unknown>, file: File) {
    const base64 = await fileAsBase64(file);
    const r = await migPost(`/documents/${s(row.id)}/file`, { filename: file.name, contentType: file.type || "application/pdf", base64 },
      `Old-portal ${s(row.label)} attached for ${s(row.application_no)}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    notify("Attached to the application."); void load();
  }
  return (
    <>
      {err ? <ProblemNotice problem={err} /> : null}
      <Panel title="Documents not yet migrated" right={<span className="sub2">MIGRATION_DOCUMENT_MISSING until the file is attached</span>}>
        {d && d.rows.length ? (
          <DTable cols={["Document", "Applicant", "Old / new number", "Old document id or file", "Upload", "|num"]}
            rows={d.rows.map((r) => [
              <span key="l">{s(r.label)}</span>, <Two key="a" a={s(r.name)} b={s(r.student_no)} />, <Two key="n" a={s(r.legacy_application_no)} b={s(r.application_no)} />,
              <span key="r" className="tnum">{s(r.legacy_ref)}</span>, <span key="b" className="sub2">{s(r.batch_reference)}</span>,
              mayMigrate && r.application_id ? (
                <label key="f" className="btn btn--secondary btn--sm">Attach file
                  <input type="file" hidden accept={r.kind === "PASSPORT" ? "image/jpeg,image/png" : "application/pdf"}
                    onChange={(e) => { const fl = e.target.files?.[0]; e.target.value = ""; if (fl) void attach(r, fl); }} />
                </label>
              ) : <span key="f" className="sub2">{r.application_id ? "" : "A student's: kept with their records"}</span>,
            ])} />
        ) : <PBody><div className="sub2">{d ? "Every old document reference has its file." : "Reading…"}</div></PBody>}
      </Panel>
    </>
  );
}

/* ── the history ─────────────────────────────────────────────────────────────────────────────────────────────────────── */
function HistoryPanel({ batches }: { batches: BatchLine[] }) {
  async function download() {
    const blob = await brandedXlsx("PG migration history", HISTORY_HEAD, historyLines(batches), { sheetName: "History", serial: docSerial("PGMIG") });
    downloadBlob(blob, "PG migration history.xlsx");
  }
  return (
    <Panel title="PG migration history" right={batches.length ? <Btn kind="ghost" size="sm" onClick={download}>Download Excel</Btn> : undefined}>
      {batches.length ? (
        <DTable cols={["S/N|num", "Batch reference", "Source", "File", "Total rows|num", "Created|num", "Updated|num", "Admitted|num", "Reconciled|num", "Duplicates|num", "Errors|num", "Started", "Completed", "Imported by", "Status|mid", "|num"]}
          rows={batches.map((b, i) => {
            const st = BATCH_STATE[b.state] ?? [b.state, "grey"];
            return [
              <span key="sn" className="tnum sub2">{i + 1}</span>, <span key="r" className="tnum">{b.reference}</span>, <span key="k">{kindWord(b.kind)}</span>,
              <span key="f" className="sub2">{b.file_name}</span>, <span key="t" className="tnum">{b.rows_expected}</span>, <span key="c" className="tnum">{b.created}</span>,
              <span key="u" className="tnum">{b.updated}</span>, <span key="a" className="tnum">{b.admitted}</span>, <span key="rc" className="tnum">{b.reconciled}</span>,
              <span key="d" className="tnum">{b.duplicates}</span>, <span key="e" className="tnum">{b.errors + b.failed}</span>,
              <span key="s" className="sub2">{when(b.started_at)}</span>, <span key="cp" className="sub2">{when(b.completed_at)}</span>, <span key="by">{b.started_by ?? "—"}</span>,
              <Pil key="st" kind={st[1]}>{st[0]}</Pil>, <LinkBtn key="o" href={`${HOME}?batch=${b.id}`}>Open</LinkBtn>,
            ];
          })}
          texts={batches.map((b) => `${b.reference} ${b.file_name} ${b.started_by ?? ""} ${b.state}`)} />
      ) : <PBody><div className="sub2">No migration has been uploaded yet.</div></PBody>}
    </Panel>
  );
}

/* ── find an applicant by either number ──────────────────────────────────────────────────────────────────────────────── */
function FindPanel() {
  const [q, setQ] = useState("");
  const [rows, setRows] = useState<Record<string, unknown>[] | null>(null);
  async function find() {
    const r = await migGet<Record<string, unknown>[]>(`/find?q=${encodeURIComponent(q.trim())}`);
    if (r.ok) setRows(r.data); else notifyProblem(r.problem);
  }
  return (
    <Panel title="Find an applicant" right={<span className="sub2">The new or the old application number, matriculation or admission number, JAMB number, email, phone or name</span>}>
      <PBody>
        <div className="row row--inline">
          <input className="ctl" style={{ maxWidth: 360 }} aria-label="Find an applicant by number, email, phone or name" placeholder="e.g. PG/26/000456 or PGOLD/2025/00872" value={q} onChange={(e) => setQ(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter" && q.trim().length >= 3) void find(); }} />
          <Btn kind="primary" onClick={find} disabled={q.trim().length < 3}>Find</Btn>
        </div>
      </PBody>
      {rows ? (rows.length ? (
        <DTable cols={["Applicant", "New application no.", "Old application no.", "Programme", "Session|mid", "Standing", "Student no.", "|num"]}
          rows={rows.map((r, i) => [
            <Two key="n" a={s(r.name)} b={s(r.email)} />, <span key="a" className="tnum">{s(r.application_no) || "—"}</span>,
            <span key="l" className="tnum">{s(r.legacy_application_no) || "—"}</span>, <Two key="p" a={s(r.programme_name)} b={s(r.programme_code)} />,
            <span key="s" className="tnum">{s(r.session)}</span>, <span key="st">{r.kind === "STUDENT" ? `Student · ${s(r.state).toLowerCase()}` : stateWord(s(r.state))}</span>,
            <span key="m" className="tnum">{s(r.matric_no) || s(r.admission_no) || "—"}</span>,
            r.application_id ? <LinkBtn key="o" href={`/admissions/postgraduate/applications/${s(r.application_id)}`}>Open</LinkBtn> : <span key={`o${i}`} />,
          ])} />
      ) : <PBody><div className="sub2">No applicant or student matches.</div></PBody>) : null}
    </Panel>
  );
}

/* ── the records behind a figure ─────────────────────────────────────────────────────────────────────────────────────── */
const VIEW_TITLE: Record<string, string> = {
  migrated: "Migrated applicants", offered: "Admitted applicants (offer stands)", accepted: "Accepted applicants", screened: "Screened on the old portal",
  students: "Active PG students migrated", pending: "Pending migration", duplicates: "Duplicate applicants", conflicts: "Conflicts", review: "Requires review",
  errors: "Errors", documents: "Missing documents", fees: "Old-portal fees",
};
function ViewPanel({ view, list, onClose }: { view: string; list: ListPage; onClose: () => void }) {
  const apps = ["migrated", "offered", "accepted", "screened", "students"].includes(view);
  const rows = ["pending", "duplicates", "conflicts", "review", "errors"].includes(view);
  return (
    <Panel title={VIEW_TITLE[view] ?? view} right={<span className="row row--inline row--tight"><span className="sub2">{list.total} in all</span><Btn kind="ghost" size="sm" onClick={onClose}>Close</Btn></span>}>
      {list.rows.length ? apps ? (
        <DTable cols={["Applicant", "New application no.", "Old application no.", "Programme", "Session|mid", "Standing", "Student no.", "Batch", "|num"]}
          rows={list.rows.map((r) => [
            <span key="n">{s(r.name)}</span>, <span key="a" className="tnum">{s(r.application_no)}</span>, <span key="l" className="tnum">{s(r.legacy_application_no)}</span>,
            <span key="p">{s(r.programme_name)}</span>, <span key="s" className="tnum">{s(r.session)}</span>, <span key="st">{stateWord(s(r.state))}</span>,
            <span key="m" className="tnum">{s(r.matric_no) || s(r.admission_no) || "—"}</span>, <span key="b" className="sub2">{s(r.batch_reference)}</span>,
            <LinkBtn key="o" href={`/admissions/postgraduate/applications/${s(r.application_id)}`}>Open</LinkBtn>,
          ])} />
      ) : rows ? (
        <DTable cols={["Old application no.", "Applicant", "Upload", "Row|num", "Status|mid", "Why", "|num"]}
          rows={list.rows.map((r) => {
            const v = r.result === "FAILED" ? RESULT.FAILED : VERDICT[s(r.verdict)] ?? [s(r.verdict), "grey"];
            return [
              <span key="l" className="tnum">{s(r.legacy_no)}</span>, <span key="a">{s(r.applicant)}</span>, <span key="b" className="sub2">{s(r.batch_reference)}</span>,
              <span key="r" className="tnum">{s(r.row_no)}</span>, <Pil key="v" kind={v[1] as "ok"}>{v[0]}</Pil>, <span key="w" className="sub2">{s(r.problem) || s(r.result_note)}</span>,
              <LinkBtn key="o" href={`${HOME}?batch=${s(r.batch_id)}`}>Open upload</LinkBtn>,
            ];
          })} />
      ) : (
        <PBody><div className="sub2">Open the {view === "fees" ? "Old-portal fees" : "Documents"} tab below.</div></PBody>
      ) : <PBody><div className="sub2">None.</div></PBody>}
    </Panel>
  );
}

export { MIGRATION_STATUS };
