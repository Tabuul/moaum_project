"use client";

/** Old-portal preliminary applicants migrated (V737). For each preliminary programme — Preliminary Technology & Industrial Studies
 *  and Preliminary Sciences — a template built from what this portal reads, and an upload sent and checked on the server a chunk
 *  at a time with nothing written but the check; the preview with its figures, its rows and the error report; an explicit
 *  confirmation, then the import with real progress. The programme of an upload is its section's, never the file's. The history
 *  of uploads; the old-portal application fees, held until the Bursary — never the officer who uploaded them — verifies them; the
 *  programme corrected by ICT between the two routes on the same application. What anyone may do is the server's to say. */
import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
import type { Problem } from "@/lib/api";
import { xlsx } from "@/lib/xlsx-write";
import { loadCrest } from "@/lib/xlsx";
import { brandedXlsx, docSerial, downloadBlob, SCHOOL } from "@/lib/exportbrand";
import { getInstitution, institutionLogoUrl } from "@/lib/document/institution-client";
import { useQueryNav } from "@/lib/query-nav";
import { STATE, labelOf, naira, pcall, when } from "@/lib/preliminary";
import { day } from "@/lib/jupeb";
import {
  ACTION, BATCH_STATE, FEE_STATE, HISTORY_HEAD, IMPORT_REPORT_HEAD, MATCH, MAX_BYTES, MAX_ROWS, MIGRATION_API, MIGRATION_HOME, PAYMENT, PRELIM_ROUTES, REPORT_HEAD, RESULT,
  VERDICT, appliedOnWords, feeAmountWords, figuresOf, fileNameOf, firstProblem, historyLine, historyLines, importReportLines, legacyFeeOf, mayConfirmNew, num, pick, progressWords,
  ranges, readFile, reportLines, routeChangeOf, rowLink, rowsOf, sha256Hex, stillToDo, str, templateOf, templateSheets, wordOf, words, type LegacyFee, type MigrationRow,
  type Programme, type RowLinkAccess,
} from "@/lib/prelim-migration";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, RoleLine, Tabs, Tiles, Two, KvGrid } from "@/components/proto/ui";
import { Bar, Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { PrelimProgrammeChange } from "@/components/preliminary/PrelimProgrammeChange";

export interface AccessRoute { route: string; name: string; session: string; fee: unknown; window: unknown }
export interface Access {
  mayMigrate: boolean; mayDecideFees: boolean; mayChangeProgramme: boolean; mayRead: boolean; mayReadCorrections?: boolean; office: string | null; routes: AccessRoute[];
  /** whether the acting office reads the preliminary desk, where a row's application opens */
  mayReadDesk?: boolean;
}
export type Tab = "upload" | "history" | "fees" | "corrections";

const XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
/* V745: what reading the file said — the sheet read, other sheets holding applicants, columns not read — kept for the batch's panel in
   this tab (sessionStorage, by batch id): the upload opens the new batch, whose panel would otherwise never show it */
const READ_NOTE = "prelimmig.read.";
type ReadNote = { sheet: string | null; notes: string[] };
const noSubscription = () => () => {};
const n0 = (v: number) => v.toLocaleString("en-GB");
/** a route's application fee as /access gives it: a sum, or {application, portal, stated} */
function feeWords(v: unknown): string {
  if (typeof v === "number" || typeof v === "string") return naira(v);
  if (v && typeof v === "object") {
    if (pick(v, "stated") === false) return "not stated";
    return naira(num(v, "application", "applicationFee", "application_fee") + num(v, "portal", "portalCharge", "portal_charge") || num(v, "total", "amount"));
  }
  return "—";
}
const windowWords = (v: unknown) => (typeof v === "string" ? v : str(v, "state")).toLowerCase().replace(/_/g, " ");

export function PrelimMigration({ access, office, actorId, batch, batchProblem, view, app, sheet }: {
  access: Access; office: string | null; actorId: string | null; batch: Record<string, unknown> | null; batchProblem: Problem | null; view: Tab | null; app: string | null;
  /** V745: the sheet of the file the upload just sent was read from (?sheet=, set by the upload) */
  sheet: string | null;
}) {
  const go = useQueryNav();
  /* V745: why an import or its finish stopped, kept here: the upload's panel is drawn afresh from the server's batch after each refresh,
     which would otherwise take the notice with it */
  const [batchErr, setBatchErr] = useState<Problem | null>(null);
  const routes = PRELIM_ROUTES.map((r) => (access.routes ?? []).find((x) => x.route === r)).filter((x): x is AccessRoute => !!x);
  const programmes: Programme[] = routes.map((r) => ({ route: r.route, name: r.name }));
  const nameOf = (r: string) => routes.find((x) => x.route === r)?.name ?? r;
  const readsUploads = access.mayRead !== false || access.mayMigrate;
  const readsCorrections = access.mayReadCorrections !== false || access.mayChangeProgramme;
  const links: RowLinkAccess = { desk: access.mayReadDesk === true, change: access.mayChangeProgramme, corrections: readsCorrections, routes: routes.map((r) => r.route) };
  const shown: Tab[] = [...(readsUploads ? ["upload", "history", "fees"] as Tab[] : []), ...(readsCorrections ? ["corrections"] as Tab[] : [])];
  const first: Tab = (view && shown.includes(view) ? view : null) ?? (batch || batchProblem ? "upload" : app && readsCorrections ? "corrections" : access.mayMigrate ? "upload"
    : access.mayDecideFees ? "fees" : access.mayChangeProgramme ? "corrections" : shown[0] ?? "history");
  const [tab, setTab] = useState<Tab>(first);
  if (!shown.length) {
    return (
      <Note kind="info" title="Not on your posting">
        Uploading old-portal preliminary applicants, and changing an applicant&rsquo;s programme, are the Director of ICT&rsquo;s to grant to a support posting
        over the whole University. Ask the Director of ICT.
      </Note>
    );
  }
  return (
    <>
      <RoleLine allowed={["ict", "academic", "dbops", "super"]} actingOffice={office} canAct={access.mayMigrate}
        action="Uploading the old portal's preliminary applicants" />
      <Note kind="info" title="Old applicants are brought across, never made to apply again">
        Each gets this portal&rsquo;s application number, and the old portal&rsquo;s number is kept beside it: either finds the applicant. The programme of an
        upload is the section it is uploaded in. Nothing is written until a file is checked and you confirm the import, and an application fee paid on the old
        portal counts as paid only once the Bursary verifies it.
      </Note>
      <Tabs<Tab> label="Preliminary applicant data migration" value={tab} onChange={setTab} items={([
        { id: "upload", label: "Upload" },
        { id: "history", label: "Import history" },
        { id: "fees", label: "Old-portal fees" },
        { id: "corrections", label: "Programme corrections" },
      ] as { id: Tab; label: string }[]).filter((t) => shown.includes(t.id))} />
      {tab === "upload" ? (
        <>
          {routes.length ? (
            <div className="grid grid--2">
              {routes.map((r) => <UploadCard key={r.route} r={r} programmes={programmes} mayMigrate={access.mayMigrate}
                onDone={(id, read) => go(`${MIGRATION_HOME}?batch=${id}${read ? `&sheet=${encodeURIComponent(read)}` : ""}`)} />)}
            </div>
          ) : <Note kind="info" title="No preliminary programme to upload for">The server named no preliminary programme this office uploads or reads.</Note>}
          {!access.mayMigrate ? (
            <Note kind="info" title="Read only">
              The Director of ICT, the Academic Office, a University-wide Database Operator and an ICT Support agent the Director has authorised upload and import.
            </Note>
          ) : null}
          {batchProblem ? <ProblemNotice problem={batchProblem} /> : null}
          {batch ? <BatchPanel key={[str(batch, "id"), str(batch, "state"), str(batch, "checkedAt"), num(batch, "imported"), num(batch, "ready"), num(batch, "requiresReview")].join("|")}
            b={batch} mayMigrate={access.mayMigrate} links={links} nameOf={nameOf} sheet={sheet} err={batchErr} setErr={setBatchErr}
            refresh={() => go(`${MIGRATION_HOME}?batch=${str(batch, "id")}${sheet ? `&sheet=${encodeURIComponent(sheet)}` : ""}`)} /> : null}
        </>
      ) : null}
      {tab === "history" ? <HistoryPanel routes={routes} current={batch ? str(batch, "id") : null} showCurrent={() => setTab("upload")} /> : null}
      {tab === "fees" ? <FeesPanel routes={routes} mayDecide={access.mayDecideFees} actorId={actorId} /> : null}
      {tab === "corrections" ? <CorrectionsPanel routes={routes} mayChange={access.mayChangeProgramme} app={app} /> : null}
    </>
  );
}

/* ── one programme's upload: the template, the file, the check ─────────────────────────────────────────────────────── */
function UploadCard({ r, programmes, mayMigrate, onDone }: {
  r: AccessRoute; programmes: Programme[]; mayMigrate: boolean; onDone: (batchId: string, sheet: string | null) => void;
}) {
  const [file, setFile] = useState<File | null>(null);
  const [update, setUpdate] = useState(false);
  const [tell, setTell] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [pct, setPct] = useState<number | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  const [warn, setWarn] = useState<string | null>(null);

  async function template() {
    const t = await pcall<unknown>(`${MIGRATION_API}/template?route=${encodeURIComponent(r.route)}`);
    if (!t.ok) { notifyProblem(t.problem); return; }
    const data = templateOf(t.data);
    const inst = await getInstitution().catch(() => null);
    const logo = (inst ? await loadCrest(institutionLogoUrl(inst)).catch(() => null) : null) ?? await loadCrest().catch(() => null);
    const book = xlsx(templateSheets(data, (inst?.name ?? SCHOOL).toUpperCase()), { logo: logo ?? undefined });
    downloadBlob(new Blob([book as BlobPart], { type: XLSX_TYPE }), fileNameOf(r.route, data.fileName));
  }

  function choose(fl: File | null) {
    setErr(null); setWarn(null); setFile(null);
    if (!fl) return;
    if (!/\.xlsx$/i.test(fl.name)) { setErr({ status: 422, title: "That file type is not accepted", detail: "Upload the filled template as an Excel workbook (.xlsx)." }); return; }
    if (fl.size > MAX_BYTES) { setErr({ status: 422, title: "The file is too large", detail: "A migration file is at most 15 MB; split a larger one." }); return; }
    setFile(fl);
  }

  async function upload() {
    if (!file) return;
    setErr(null); setWarn(null);
    setBusy("Reading the file…"); setPct(null);
    try {
      const buf = await file.arrayBuffer();
      const t = await pcall<unknown>(`${MIGRATION_API}/template?route=${encodeURIComponent(r.route)}`);
      if (!t.ok) { setErr(t.problem); return; }
      const read = await readFile(buf, templateOf(t.data), programmes);
      if (read.ambiguous) {
        setErr({ status: 422, title: "Applicants are on more than one sheet", detail: `The sheets ${read.otherSheets.map((s) => `“${s}”`).join(", ")} each have the template's columns and applicant rows, and none is the Applicants sheet. Keep the applicants on the Applicants sheet only, then upload the file again.` });
        return;
      }
      // V745: a file made for the other programme is refused here, before anything is sent
      if (read.wrongProgramme) {
        const w = read.wrongProgramme;
        setErr(w.by === "template"
          ? { status: 422, title: `This is the ${w.name} template`, detail: `The file was made from the ${w.name} template. Upload it in the ${w.name} section; nothing was sent.` }
          : { status: 422, title: `Every applicant in the file names ${w.name}`, detail: `Every row's Programme names ${w.name}. Upload the file in the ${w.name} section, or correct the Programme column; nothing was sent.` });
        return;
      }
      if (read.missing.length) {
        setErr({ status: 422, title: "The file is not the template", detail: `It has no column for: ${read.missing.join(", ")}. Download the ${r.name} template and copy the old portal's data into it.` });
        return;
      }
      if (!read.rows.length) { setErr({ status: 422, title: "The file has no applicants", detail: "Fill one row per applicant under the headings of the Applicants sheet." }); return; }
      if (read.rows.length > MAX_ROWS) { setErr({ status: 422, title: "The file is too long", detail: `${n0(read.rows.length)} rows; a migration file holds up to ${n0(MAX_ROWS)}. Split it.` }); return; }
      const notes = [
        read.otherSheets.length ? `The sheet${read.otherSheets.length === 1 ? "" : "s"} ${read.otherSheets.map((s) => `“${s}”`).join(", ")} also ${read.otherSheets.length === 1 ? "has" : "have"} applicant rows and ${read.otherSheets.length === 1 ? "was" : "were"} not read.` : "",
        read.unknown.length ? `Columns not read (not on the template): ${read.unknown.join(", ")}.` : "",
      ].filter(Boolean);
      setWarn(`Read from the sheet “${read.sheet}”.${notes.length ? ` ${notes.join(" ")}` : ""}`);
      const sha = await sha256Hex(buf);
      const opened = await pcall<Record<string, unknown>>(`${MIGRATION_API}/batches`, "POST",
        { route: r.route, fileName: file.name, sha256: sha, rows: read.rows.length, update, tell }, `${r.name} old-portal applicants uploaded: ${file.name}, sheet ${read.sheet}`);
      if (!opened.ok) { setErr(opened.problem); return; }
      const id = str(opened.data, "id");
      const ref = str(opened.data, "reference");
      const before = words(pick(opened.data, "importedBefore"));
      const beforeOne = str(opened.data, "importedBefore");
      if (before.length || beforeOne) notify(`This file was imported before (${before.length ? before.join(", ") : beforeOne}); importing it again changes nothing already on record.`, "info", 9000);
      const total = read.rows.length;
      for (const [from, to] of ranges(total, 500)) {
        setBusy(progressWords("upload", from - 1, total)); setPct(Math.round(((from - 1) / total) * 50));
        const s = await pcall(`${MIGRATION_API}/batches/${id}/rows`, "POST", { first: from, rows: read.rows.slice(from - 1, to) }, `${ref}: rows ${from} to ${to} sent`);
        if (!s.ok) { setErr(s.problem); return; }
      }
      for (const [from, to] of ranges(total, 1000)) {
        setBusy(progressWords("check", from - 1, total)); setPct(50 + Math.round(((from - 1) / total) * 50));
        const c = await pcall(`${MIGRATION_API}/batches/${id}/check`, "POST", { from, to }, `${ref}: rows ${from} to ${to} checked`);
        if (!c.ok) { setErr(c.problem); return; }
      }
      notify(`${ref}: ${n0(total)} rows of the sheet “${read.sheet}” checked. Nothing is written until you confirm the import.`);
      setFile(null);
      try { window.sessionStorage.setItem(`${READ_NOTE}${id}`, JSON.stringify({ sheet: read.sheet, notes } satisfies ReadNote)); } catch { /* the toast named the sheet */ }
      onDone(id, read.sheet);
    } catch (e) {
      setErr({ status: 422, title: "The file could not be read", detail: e instanceof Error ? e.message : String(e) });
    } finally {
      setBusy(null); setPct(null);
    }
  }

  return (
    <Panel title={r.name} right={<span className="sub2">{r.session}</span>}>
      <PBody>
        <p className="sub2">
          Old-portal applicants of {r.name}, {r.session}. Each is uploaded into {r.name} whatever the file&rsquo;s own &ldquo;Programme&rdquo; column says; a row
          naming the other preliminary programme is a conflict and is not imported. Application fee {feeWords(r.fee)} · applications {windowWords(r.window) || "—"}
          (an upload does not need the window open).
        </p>
        <div className="row row--inline" style={{ flexWrap: "wrap" }}>
          {mayMigrate ? (
            <>
              <Btn kind="secondary" onClick={template}>Download Excel template</Btn>
              <label className={`btn btn--ghost btn--sm${busy ? " is-disabled" : ""}`}>
                Select Excel file
                <input type="file" accept={`.xlsx,${XLSX_TYPE}`} hidden disabled={!!busy}
                  onChange={(e) => { const fl = e.target.files?.[0] ?? null; e.target.value = ""; choose(fl); }} />
              </label>
              <Btn kind="primary" disabled={!file || !!busy} onClick={upload}>Upload and validate</Btn>
            </>
          ) : null}
        </div>
        {file ? <div className="sub2 mt-1">{file.name} · {(file.size / 1024 / 1024).toFixed(2)} MB</div> : null}
        {mayMigrate ? (
          <div className="mt-1">
            <label className="row row--inline sub2">
              <input type="checkbox" checked={update} onChange={(e) => setUpdate(e.target.checked)} disabled={!!busy} />
              Fill in missing details of applicants already here (nothing they or an office entered is overwritten)
            </label>
            <label className="row row--inline sub2">
              <input type="checkbox" checked={tell} onChange={(e) => setTell(e.target.checked)} disabled={!!busy} />
              Tell each applicant once, by email and SMS, both numbers and how to sign in (never a password)
            </label>
          </div>
        ) : null}
        {busy ? (
          <div className="mt-1">
            <div className="sub2">{busy}</div>
            {pct != null ? <Bar pct={pct} /> : null}
          </div>
        ) : null}
        {err ? <ProblemNotice problem={err} /> : null}
        {warn ? <Note kind="info" title="What was read">{warn}</Note> : null}
      </PBody>
    </Panel>
  );
}

/* ── an upload: the preview, the rows, the error report, the import ───────────────────────────────────────────────── */
const FILTERS: [string, string][] = [["", "All rows"], ["problems", "Not plainly ready"], ["READY", "Ready"], ["WARNING", "Ready, with a note"],
  ["DUPLICATE_IN_FILE", "Duplicates in the file"], ["CONFLICT", "Conflicts"], ["REQUIRES_REVIEW", "Requires review"], ["ERROR", "Errors"],
  ["CREATED", "Created"], ["UPDATED", "Updated"], ["RECONCILED", "Reconciled"], ["UNCHANGED", "Already on record"], ["SKIPPED", "Not imported"], ["FAILED", "Failed"]];
const PAGE = 50;

async function downloadReport(id: string, reference: string, sub: string) {
  const r = await pcall<unknown>(`${MIGRATION_API}/batches/${id}/report`);
  if (!r.ok) { notifyProblem(r.problem); return; }
  const lines = reportLines(rowsOf(r.data).rows);
  const blob = await brandedXlsx("Preliminary migration error report", REPORT_HEAD, lines, { sheetName: "Errors", serial: docSerial("PRELIMMIG"), sub, noSerialColumn: true });
  downloadBlob(blob, `${reference.replace(/\//g, "-")} error report.xlsx`);
}

/** V745: the import report — every row of the upload, the old number beside the application number it became or matched, and what
 *  the import did with it */
async function downloadImportReport(id: string, reference: string, sub: string) {
  const r = await pcall<unknown>(`${MIGRATION_API}/batches/${id}/report?scope=all`);
  if (!r.ok) { notifyProblem(r.problem); return; }
  const lines = importReportLines(rowsOf(r.data).rows);
  const blob = await brandedXlsx("Preliminary migration import report", IMPORT_REPORT_HEAD, lines, { sheetName: "Import", serial: docSerial("PRELIMMIG"), sub, noSerialColumn: true });
  downloadBlob(blob, `${reference.replace(/\//g, "-")} import report.xlsx`);
}

/** the rows of an upload whose import failed, every page of them (a failed row keeps the check's action: what is left to create
 *  leaves them out) */
async function failedRowsOf(id: string): Promise<MigrationRow[] | null> {
  const out: MigrationRow[] = [];
  for (let pg = 0; pg < 40; pg++) {
    const r = await pcall<unknown>(`${MIGRATION_API}/batches/${id}/rows?status=FAILED&page=${pg}&size=500`);
    if (!r.ok) return null;
    const x = rowsOf<MigrationRow>(r.data);
    out.push(...x.rows);
    if (!x.rows.length || out.length >= x.total) break;
  }
  return out;
}

function BatchPanel({ b, mayMigrate, links, nameOf, sheet, err, setErr, refresh }: {
  b: Record<string, unknown>; mayMigrate: boolean; links: RowLinkAccess; nameOf: (r: string) => string; sheet: string | null;
  /** the panel's notice, held by the screen so that it outlives the panel's redraw after a refresh (V745) */
  err: Problem | null; setErr: (p: Problem | null) => void; refresh: () => void;
}) {
  const [live, setLive] = useState<Record<string, unknown>>(b);
  const [status, setStatus] = useState("problems");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(0);
  const [rows, setRows] = useState<{ total: number; rows: MigrationRow[] } | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [pct, setPct] = useState<number | null>(null);
  const [failedRows, setFailedRows] = useState<MigrationRow[] | null>(null);
  const [confirm, setConfirm] = useState(false);
  const [read, setRead] = useState(false);
  const [abandon, setAbandon] = useState(false);
  const [reason, setReason] = useState("");
  const [newRow, setNewRow] = useState<MigrationRow | null>(null);
  const id = str(b, "id");
  const L = live;
  const readRaw = useSyncExternalStore(noSubscription, () => { try { return window.sessionStorage.getItem(`${READ_NOTE}${id}`); } catch { return null; } }, () => null);
  const readNote = useMemo<ReadNote | null>(() => { try { return readRaw ? (JSON.parse(readRaw) as ReadNote) : null; } catch { return null; } }, [readRaw]);
  const sheetRead = sheet ?? readNote?.sheet ?? null;
  const F = figuresOf(L);
  const state = str(L, "state");
  const reference = str(L, "reference");
  const route = str(L, "route");
  const name = str(L, "routeName", "route_name") || nameOf(route);
  const file = str(L, "fileName", "file_name", "file");
  const allowUpdate = pick(L, "allowUpdate", "allow_update") === true;
  const tells = pick(L, "notify") !== false;
  const open = state === "CHECKED" || state === "IMPORTING";
  const total = F.rows;
  /* V745: an import already begun counts only the rows still to do */
  const left = stillToDo(F, failedRows);
  const feesOfUpload = F.feesHeld + F.feesVerified + F.feesRejected;

  function fetchRows(st: string, pg: number, query: string) {
    const qs = new URLSearchParams({ page: String(pg), size: String(PAGE) });
    if (st) qs.set("status", st);
    if (query.trim()) qs.set("q", query.trim());
    return pcall<unknown>(`${MIGRATION_API}/batches/${id}/rows?${qs.toString()}`);
  }
  function showRows(r: Awaited<ReturnType<typeof fetchRows>>) { if (r.ok) setRows(rowsOf<MigrationRow>(r.data)); else setErr(r.problem); }
  async function load(st = status, pg = page, query = q) { showRows(await fetchRows(st, pg, query)); }
  useEffect(() => {
    let live = true;
    void fetchRows("problems", 0, "").then((r) => { if (live) showRows(r); });
    // a server that does not count what is left to create: the failed rows read, to leave them out
    if (F.failed && F.newApplicantsToImport == null) void failedRowsOf(id).then((x) => { if (live) setFailedRows(x); });
    return () => { live = false; };
  }, []);   // eslint-disable-line react-hooks/exhaustive-deps -- the first page once; the filters reload it

  const merge = (d: unknown) => { if (d && typeof d === "object" && (pick(d, "reference") || pick(d, "state"))) setLive((x) => ({ ...x, ...(d as Record<string, unknown>) })); };

  async function check() {
    setErr(null);
    for (const [from, to] of ranges(total, 1000)) {
      setBusy(progressWords("check", from - 1, total)); setPct(Math.round(((from - 1) / total) * 100));
      const r = await pcall<unknown>(`${MIGRATION_API}/batches/${id}/check`, "POST", { from, to }, `${reference}: checked again`);
      if (!r.ok) { setErr(r.problem); setBusy(null); setPct(null); return; }
      merge(r.data);
    }
    setBusy(null); setPct(null); notify("Checked again."); refresh(); void load();
  }

  async function importAll() {
    setConfirm(false); setErr(null);
    for (const [from, to] of ranges(total, 250)) {
      setBusy(progressWords("import", from - 1, total)); setPct(Math.round(((from - 1) / total) * 100));
      const r = await pcall<unknown>(`${MIGRATION_API}/batches/${id}/import`, "POST", { from, to }, `${reference}: imported into ${name}`);
      if (!r.ok) { setErr(r.problem); setBusy(null); setPct(null); refresh(); return; }
      merge(r.data);
    }
    const fin = await pcall<unknown>(`${MIGRATION_API}/batches/${id}/finish`, "POST", {}, `${reference}: import finished`);
    setBusy(null); setPct(null);
    if (!fin.ok) { setErr(fin.problem); refresh(); return; }
    merge(fin.data);
    const f = figuresOf(fin.data);
    notify(`${reference} imported into ${name}: ${n0(f.created)} created, ${n0(f.updated + f.reconciled)} updated, ${n0(f.unchanged)} already on record, ${n0(f.notImported)} not imported, ${n0(f.failed)} failed.`);
    refresh(); void load("problems", 0);
  }

  async function setAside() {
    const r = await pcall<unknown>(`${MIGRATION_API}/batches/${id}/abandon`, "POST", { reason: reason.trim() }, `${reference} set aside: ${reason.trim()}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    setAbandon(false); notify(`${reference} set aside; nothing more is imported from it.`); refresh();
  }

  async function confirmNew() {
    if (!newRow) return;
    const r = await pcall<unknown>(`${MIGRATION_API}/rows/${newRow.id}/new`, "POST", { reason: reason.trim() }, `${reference} row ${newRow.row_no}: a new applicant: ${reason.trim()}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    // V745: a row the import had left out for this review is imported there and then; the server says how it went
    const result = newRow.result === "SKIPPED" ? str(r.data, "result") : "";
    setNewRow(null); setReason("");
    notify(result && result !== "SKIPPED" ? `Row ${newRow.row_no}: confirmed as a new applicant and imported (${wordOf(RESULT, result)[0].toLowerCase()}). ${str(r.data, "resultNote")}`.trim()
      : "Confirmed as a new applicant; the row is checked again.");
    refresh(); void load();
  }

  const st = wordOf(BATCH_STATE, state);
  const staged = F.staged || num(L, "rowsStaged");
  return (
    <>
      <Panel title={<>{reference} · {name}</>} right={<Pil kind={st[1]}>{st[0]}</Pil>}>
        <PBody>
          <div className="sub2">{file}{sheetRead ? <>, read from the sheet &ldquo;{sheetRead}&rdquo;</> : null} · uploaded {when(str(L, "startedAt", "started_at"))} by {str(L, "startedBy", "startedByName", "started_by") || "—"}
            {" · "}{allowUpdate ? "missing details of applicants already here are filled in" : "applicants already here only get the old number kept beside their application"}
            {" · "}{tells ? "new applicants are told once" : "applicants are not told"}</div>
          {readNote?.notes.length ? <Note kind="info" title="Not read from the file">{readNote.notes.join(" ")}</Note> : null}
          {str(L, "abandonedReason", "abandoned_reason") ? <Note kind="info" title="Set aside">{str(L, "abandonedReason", "abandoned_reason")}</Note> : null}
          {state === "STAGING" && staged < total ? (
            <Note kind="bad" title="The upload stopped before every row reached the server">
              {n0(staged)} of {n0(total)} rows arrived. Set this upload aside and upload the file again: nothing has been imported from it.
            </Note>
          ) : null}
        </PBody>
        <Tiles items={[
          ["Total rows", n0(total), null, `${n0(F.checked)} checked`],
          ["Valid", n0(F.valid), F.valid ? "var(--green-ink)" : null, "Ready to import"],
          ["Invalid", n0(F.invalid), F.invalid ? "var(--red-ink)" : null, "Errors to correct in the file"],
          ["Existing applicants", n0(F.existing), null, "Already on the portal: never made twice"],
          ["Potential duplicates", n0(F.duplicates), F.duplicates ? "var(--chrome)" : null, "Repeated in the file, or a possible same person"],
          left ? ["New applicants still to create", left.create == null ? "…" : n0(left.create), null, `${n0(F.created)} created so far`]
            : ["New applicants ready", n0(F.newApplicants), null, "Will be created"],
          left ? ["Fees held for the Bursary", n0(feesOfUpload), feesOfUpload ? "var(--chrome)" : null, "Brought in by this upload so far"]
            : ["Fees to hold for the Bursary", n0(F.paymentsToVerify), F.paymentsToVerify ? "var(--chrome)" : null, "Paid on the old portal, held on import"],
          ["Programme conflicts", n0(F.programmeConflicts), F.programmeConflicts ? "var(--red-ink)" : null, "Name the other programme: not imported"],
        ]} />
        {F.imported ? (
          <Tiles cls="grid--6" items={[
            ["Created", n0(F.created), F.created ? "var(--green-ink)" : null, "New applicants"],
            ["Updated", n0(F.updated), null, "Missing details filled in"],
            ["Reconciled", n0(F.reconciled), null, "Old number kept with the application here"],
            ["Already on record", n0(F.unchanged), null, "Nothing to change"],
            ["Not imported", n0(F.notImported), F.notImported ? "var(--chrome)" : null, "Held back by a problem"],
            ["Failed", n0(F.failed), F.failed ? "var(--red-ink)" : null, `${n0(F.feesHeld)} fee${F.feesHeld === 1 ? "" : "s"} held for the Bursary`],
          ]} />
        ) : null}
        <PBody>
          {busy ? <div><div className="sub2">{busy} · each chunk is committed on the server as it goes.</div>{pct != null ? <Bar pct={pct} /> : null}</div> : null}
          {err ? <ProblemNotice problem={err} /> : null}
          <div className="row row--inline" style={{ marginTop: 8, flexWrap: "wrap" }}>
            <Btn kind="secondary" onClick={() => downloadReport(id, reference, `${reference} · ${name} · ${file}`)}>Download error report</Btn>
            {F.imported ? <Btn kind="secondary" onClick={() => downloadImportReport(id, reference, `${reference} · ${name} · ${file}`)}>Download import report</Btn> : null}
            {mayMigrate && (state === "CHECKED" || (state === "STAGING" && staged >= total && total > 0)) ? <Btn kind="ghost" onClick={check} disabled={!!busy}>{state === "STAGING" ? "Check the rows" : "Check again"}</Btn> : null}
            {mayMigrate && open ? <Btn kind="primary" onClick={() => { setRead(false); setConfirm(true); }} disabled={!!busy}>{state === "IMPORTING" ? "Continue the import" : "Confirm import"}</Btn> : null}
            {mayMigrate && (open || state === "STAGING") ? <Btn kind="ghost" onClick={() => { setReason(""); setAbandon(true); }} disabled={!!busy}>Set aside</Btn> : null}
          </div>
        </PBody>
      </Panel>

      <Panel title="Rows" right={<span className="row row--inline row--tight">
        <select className="ctl" aria-label="Show rows" value={status} onChange={(e) => { setStatus(e.target.value); setPage(0); void load(e.target.value, 0); }}>
          {FILTERS.map(([v, l]) => <option key={v || "all"} value={v}>{l}</option>)}
        </select>
        <input className="ctl" aria-label="Search rows" placeholder="Old number, name or email" value={q} onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") { setPage(0); void load(status, 0, q); } }} />
      </span>}>
        {rows && rows.rows.length ? (
          <DTable pageSize={0} noPrint
            cols={["Row|num", "Applicant", "Old / new application no.", "Match", "Status|mid", "Error / warning", "Proposed action", "|num"]}
            rows={rows.rows.map((r) => {
              const v = r.result ? wordOf(RESULT, r.result) : wordOf(VERDICT, r.verdict);
              const p = firstProblem(r);
              const more = (r.problems ?? []).length - (p ? 1 : 0);
              const ready = ["READY", "WARNING"].includes(r.verdict ?? "");
              const link = rowLink(r, route, links);
              return [
                <span key="n" className="tnum">{r.row_no}{r.sheet_row ? <div className="sub2">sheet row {String(r.sheet_row)}</div> : null}</span>,
                <Two key="a" a={r.applicant ?? "—"} b={r.email ?? ""} />,
                <Two key="no" a={r.legacy_no ?? "—"} b={r.application_no ?? (r.action === "CREATE" && !r.result ? "a new number on import" : "")} />,
                <span key="m">{MATCH[r.match ?? ""] ?? "—"}</span>,
                <Pil key="v" kind={v[1]}>{v[0]}</Pil>,
                <span key="e" className="sub2">{p ? <>{p.message}{p.fix ? <div><i>{p.fix}</i></div> : null}{more > 0 ? <div>and {more} more in the error report</div> : null}</> : r.result_note ?? ""}</span>,
                <span key="ac">{r.result === "SKIPPED" || r.result === "FAILED" || (!r.result && !ready) ? <i className="sub2">Not imported</i> : ACTION[r.action ?? ""] ?? "—"}</span>,
                mayConfirmNew(r, state) && mayMigrate ? <Btn key="b" kind="ghost" size="sm" onClick={() => { setReason(""); setNewRow(r); }}>Confirm as new applicant</Btn>
                  : link ? <LinkBtn key="b" href={link}>Open</LinkBtn> : <span key="b" />,
              ];
            })}
          />
        ) : <PBody><div className="sub2">{rows ? "No row in this view." : "Reading the rows…"}</div></PBody>}
        {rows && rows.total > PAGE ? (
          <PBody>
            <div className="row row--inline">
              <Btn kind="ghost" size="sm" disabled={page === 0} onClick={() => { const pg = page - 1; setPage(pg); void load(status, pg); }}>Previous</Btn>
              <span className="sub2">Page {page + 1} of {Math.ceil(rows.total / PAGE)} · {n0(rows.total)} rows</span>
              <Btn kind="ghost" size="sm" disabled={(page + 1) * PAGE >= rows.total} onClick={() => { const pg = page + 1; setPage(pg); void load(status, pg); }}>Next</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>

      {confirm ? (
        <Modal title={`Import ${reference}`} sub={file} onClose={() => setConfirm(false)}
          foot={<><Btn kind="ghost" onClick={() => setConfirm(false)}>Cancel</Btn><Btn kind="primary" disabled={!read} onClick={importAll}>Import</Btn></>}>
          {/* V745: an import already begun counts only the rows still to do; what is imported is said apart */}
          <KvGrid cls="grid--2" pairs={left ? [
            ["Target programme", `${name}${str(L, "session") ? ` · ${str(L, "session")}` : ""}`],
            ["Already imported", `${n0(F.imported)} rows: ${n0(F.created)} created, ${n0(F.updated + F.reconciled)} updated, ${n0(F.unchanged)} already on record, ${n0(F.notImported)} not imported, ${n0(F.failed)} failed`],
            ["Ready rows still to import", n0(left.ready)],
            ["New applicants still to create", left.create == null ? "being counted…" : n0(left.create)],
            ["Applicants already here, still to go through", left.existing == null ? "being counted…" : n0(left.existing)],
            ["Rows still to go that will not import", n0(left.notReady)],
            ["Fees held for the Bursary so far", n0(feesOfUpload)],
          ] : [
            ["Target programme", `${name}${str(L, "session") ? ` · ${str(L, "session")}` : ""}`],
            ["New applicants to create", n0(F.newApplicants)],
            ["Existing applicants to update", allowUpdate ? n0(F.toUpdate)
              : `${n0(F.toUpdate)} (registered here, matched by email: only the old number is kept with the application; no outcome published, no state moved, no fee held)`],
            ["Not imported", n0(F.skipped)],
            ["Invalid (errors)", n0(F.invalid)],
            ["Fees to hold for the Bursary", n0(F.paymentsToVerify)],
          ]} />
          <p className="sub2 mt-1">Each row is checked again as it is imported, and a row that fails is undone alone. Nobody and no payment is made twice; importing the same
            file again changes nothing already on record. An old-portal fee is held until the Bursary verifies it.</p>
          <label className="row row--inline">
            <input type="checkbox" checked={read} onChange={(e) => setRead(e.target.checked)} />
            I have read the preview: import the ready rows into {name}
          </label>
        </Modal>
      ) : null}
      {abandon ? (
        <Modal title={`Set aside ${reference}`} onClose={() => setAbandon(false)}
          foot={<><Btn kind="ghost" onClick={() => setAbandon(false)}>Cancel</Btn><Btn kind="primary" onClick={setAside} disabled={reason.trim().length < 5}>Set aside</Btn></>}>
          <p className="sub2">What was imported stays; nothing more is imported from this upload. The upload is kept in the history.</p>
          <Field id="ab-why" label="Why" required hint="At least five characters."><textarea id="ab-why" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
      {newRow ? (
        <Modal title={`Row ${newRow.row_no}: confirm as a new applicant`} onClose={() => setNewRow(null)}
          foot={<><Btn kind="ghost" onClick={() => setNewRow(null)}>Cancel</Btn><Btn kind="primary" onClick={confirmNew} disabled={reason.trim().length < 10}>Confirm as new applicant</Btn></>}>
          <p>{firstProblem(newRow)?.message}</p>
          <p className="sub2">Nobody is merged on a name or a phone number: confirm only when you know this is another person.</p>
          <Field id="nw-why" label="How you know this is another person" required hint="At least ten characters; kept with the row.">
            <textarea id="nw-why" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}

/* ── the history of uploads ────────────────────────────────────────────────────────────────────────────────────────── */
/* an upload opened here shows on the Upload tab: another one by its address (the screen is keyed by ?batch=), the one already open by
   switching back to it */
function HistoryPanel({ routes, current, showCurrent }: { routes: AccessRoute[]; current: string | null; showCurrent: () => void }) {
  const [route, setRoute] = useState("");
  const [page, setPage] = useState(0);
  const [d, setD] = useState<{ rows: Record<string, unknown>[]; total: number } | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  function fetchPage(r: string, pg: number) {
    const qs = new URLSearchParams({ page: String(pg), size: String(PAGE) });
    if (r) qs.set("route", r);
    return pcall<unknown>(`${MIGRATION_API}/batches?${qs.toString()}`);
  }
  function show(x: Awaited<ReturnType<typeof fetchPage>>) { if (x.ok) { setD(rowsOf(x.data)); setErr(null); } else setErr(x.problem); }
  async function load(r = route, pg = page) { show(await fetchPage(r, pg)); }
  useEffect(() => {
    let live = true;
    void fetchPage("", 0).then((x) => { if (live) show(x); });
    return () => { live = false; };
  }, []);   // eslint-disable-line react-hooks/exhaustive-deps -- the first page once; the filter reloads it
  async function download() {
    if (!d) return;
    const blob = await brandedXlsx("Preliminary applicant data migration history", HISTORY_HEAD, historyLines(d.rows), { sheetName: "History", serial: docSerial("PRELIMMIG"),
      sub: route ? routes.find((x) => x.route === route)?.name ?? route : "Both programmes" });
    downloadBlob(blob, "Preliminary applicant data migration history.xlsx");
  }
  const lines = (d?.rows ?? []).map(historyLine);
  return (
    <Panel title="Import history" right={<span className="row row--inline row--tight">
      <select className="ctl" aria-label="Programme" value={route} onChange={(e) => { setRoute(e.target.value); setPage(0); void load(e.target.value, 0); }}>
        <option value="">Both programmes</option>
        {routes.map((r) => <option key={r.route} value={r.route}>{r.name}</option>)}
      </select>
      {lines.length ? <Btn kind="ghost" size="sm" onClick={download}>Download Excel</Btn> : null}
    </span>}>
      {err ? <PBody><ProblemNotice problem={err} /></PBody> : null}
      {lines.length ? (
        <DTable pageSize={0}
          cols={["Batch reference", "Programme", "File", "Uploaded", "Administrator", "Total rows|num", "Successful|num", "Updated|num", "Not imported|num", "Failed|num", "Fees held|num", "Status|mid", "|num"]}
          rows={lines.map((h) => {
            const s = wordOf(BATCH_STATE, h.state);
            return [
              <span key="r" className="tnum">{h.reference}</span>, <span key="p">{h.routeName}</span>, <span key="f" className="sub2">{h.file}</span>,
              <span key="w" className="sub2">{when(h.startedAt)}</span>, <Two key="by" a={h.by || "—"} b={h.office} />,
              h.rows, h.successful, h.updated, h.skipped, h.failed, h.feesHeld, <Pil key="s" kind={s[1]}>{s[0]}</Pil>,
              <span key="o" className="row row--inline row--tight">
                {h.id && h.id === current ? <Btn kind="ghost" size="sm" onClick={showCurrent}>Open</Btn>
                  : h.id ? <LinkBtn href={`${MIGRATION_HOME}?batch=${h.id}`}>Open</LinkBtn> : null}
                {h.id ? <Btn kind="ghost" size="sm" onClick={() => downloadReport(h.id, h.reference, `${h.reference} · ${h.routeName} · ${h.file}`)}>Errors</Btn> : null}
                {h.id && h.successful + h.skipped + h.failed > 0 ? <Btn kind="ghost" size="sm" onClick={() => downloadImportReport(h.id, h.reference, `${h.reference} · ${h.routeName} · ${h.file}`)}>Import report</Btn> : null}
              </span>,
            ];
          })}
          texts={lines.map((h) => `${h.reference} ${h.file} ${h.by} ${h.routeName} ${h.state}`)} />
      ) : <PBody><div className="sub2">{d ? "No upload yet." : "Reading the history…"}</div></PBody>}
      {d && d.total > PAGE ? (
        <PBody>
          <div className="row row--inline">
            <Btn kind="ghost" size="sm" disabled={page === 0} onClick={() => { const pg = page - 1; setPage(pg); void load(route, pg); }}>Previous</Btn>
            <span className="sub2">Page {page + 1} of {Math.ceil(d.total / PAGE)}</span>
            <Btn kind="ghost" size="sm" disabled={(page + 1) * PAGE >= d.total} onClick={() => { const pg = page + 1; setPage(pg); void load(route, pg); }}>Next</Btn>
          </div>
        </PBody>
      ) : null}
    </Panel>
  );
}

/* ── the old portal's application fees ─────────────────────────────────────────────────────────────────────────────── */
function FeesPanel({ routes, mayDecide, actorId }: { routes: AccessRoute[]; mayDecide: boolean; actorId: string | null }) {
  const [route, setRoute] = useState("");
  const [state, setState] = useState("REQUIRES_REVIEW");
  const [page, setPage] = useState(0);
  const [figures, setFigures] = useState<unknown>(null);
  const [d, setD] = useState<{ rows: LegacyFee[]; total: number } | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  const [act, setAct] = useState<{ fee: LegacyFee; verify: boolean; note: string; reference: string; amount: string } | null>(null);
  function fetchFees(r: string, s: string, pg: number) {
    const fq = new URLSearchParams();
    if (r) fq.set("route", r);
    const qs = new URLSearchParams({ page: String(pg), size: String(PAGE) });
    if (r) qs.set("route", r);
    if (s) qs.set("state", s);
    return Promise.all([pcall<unknown>(`${MIGRATION_API}/fees/figures?${fq.toString()}`), pcall<unknown>(`${MIGRATION_API}/fees?${qs.toString()}`)]);
  }
  function show([f, l]: Awaited<ReturnType<typeof fetchFees>>) {
    if (f.ok) setFigures(f.data);
    if (l.ok) { const x = rowsOf(l.data); setD({ rows: x.rows.map(legacyFeeOf), total: x.total }); setErr(null); } else setErr(l.problem);
  }
  async function load(r = route, s = state, pg = page) { show(await fetchFees(r, s, pg)); }
  useEffect(() => {
    let live = true;
    void fetchFees("", "REQUIRES_REVIEW", 0).then((x) => { if (live) show(x); });
    return () => { live = false; };
  }, []);   // eslint-disable-line react-hooks/exhaustive-deps -- the first page once; the filters reload it
  async function decide() {
    if (!act) return;
    // V745: a fee the file gave no amount for is posted at the amount the Bursary found, else at the programme's stated fee
    const amount = act.verify && !act.fee.amountGiven && act.amount.trim() ? Number(act.amount.replace(/[,\s₦]/g, "")) : null;
    const body = { verify: act.verify, note: act.note.trim(), reference: act.verify && !act.fee.reference ? act.reference.trim() : null, amount };
    const r = await pcall<{ outcome?: string }>(`${MIGRATION_API}/fees/${act.fee.id}/decide`, "POST", body,
      `Old-portal application fee ${act.fee.reference || act.reference.trim()} for ${act.fee.applicationNo} ${act.verify ? "verified" : "not verified"}: ${act.note.trim()}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    setAct(null);
    notify(str(r.data, "outcome") || (act.verify ? "Verified: the fee is posted under the old reference and counted paid; the applicant is told."
      : "Recorded as not verified; the applicant is told to pay on the portal or see the Bursary."));
    void load();
  }
  const amountOk = (v: string) => /^[0-9]{1,10}(\.[0-9]{1,2})?$/.test(v.replace(/[,\s₦]/g, "")) && Number(v.replace(/[,\s₦]/g, "")) > 0;
  const mine = (f: LegacyFee) => f.uploadedByMe || (!!actorId && f.uploadedById === actorId);
  const fg = figures;
  return (
    <>
      <Note kind="info" title="A fee paid on the old portal counts only once the Bursary verifies it">
        An Excel &ldquo;Paid&rdquo; is never proof. Every old-portal application fee is held here: the applicant is not asked to pay again meanwhile, and the Bursary —
        never the officer who uploaded it — checks it against the bank or the gateway, then verifies it (posted under the old reference, or the one the Bursary found) or
        records it as not verified with the reason.
      </Note>
      {fg ? (
        <Tiles cls="grid--5" items={[
          ["Migrated applicants", n0(num(fg, "imported")), null, "From the old portal"],
          ["With a payment reference", n0(num(fg, "withReference")), null, "The old reference given"],
          ["Verified", n0(num(fg, "verified")), "var(--green-ink)", naira(num(fg, "amountVerified"))],
          ["Awaiting verification", n0(num(fg, "unverified")), num(fg, "unverified") ? "var(--chrome)" : null, naira(num(fg, "amountHeld"))],
          ["Not verified", n0(num(fg, "rejected")), null, "With the reason"],
          ["No payment record", n0(num(fg, "noPaymentRecord")), num(fg, "noPaymentRecord") ? "var(--chrome)" : null, "Migrated, nothing paid or held"],
          ["Duplicate references", n0(num(fg, "duplicateReferences")), num(fg, "duplicateReferences") ? "var(--red-ink)" : null, "In a file, or already used"],
          ["For review", n0(num(fg, "forReview")), null, "Awaiting verification or no record"],
        ]} />
      ) : null}
      {err ? <ProblemNotice problem={err} /> : null}
      <Panel title="Old-portal application fees" right={<span className="row row--inline row--tight">
        <select className="ctl" aria-label="Programme" value={route} onChange={(e) => { setRoute(e.target.value); setPage(0); void load(e.target.value, state, 0); }}>
          <option value="">Both programmes</option>
          {routes.map((r) => <option key={r.route} value={r.route}>{r.name}</option>)}
        </select>
        <select className="ctl" aria-label="Standing" value={state} onChange={(e) => { setState(e.target.value); setPage(0); void load(route, e.target.value, 0); }}>
          <option value="REQUIRES_REVIEW">Held for the Bursary</option><option value="VERIFIED">Verified</option><option value="REJECTED">Not verified</option><option value="">All</option>
        </select>
      </span>}>
        {d && d.rows.length ? (
          <DTable pageSize={0}
            cols={["Applicant", "Application no. / old no.", "Programme", "Old reference", "Amount|num", "Paid on|mid", "Stated", "Upload", "Standing", "|num"]}
            rows={d.rows.map((f) => {
              const s = wordOf(FEE_STATE, f.state);
              return [
                <span key="a">{f.name || "—"}</span>, <Two key="n" a={f.applicationNo || "—"} b={f.legacyNo} />, <span key="p">{f.routeName}</span>,
                <Two key="r" a={f.reference || <i>none given</i>} b={f.gatewayReference ? `gateway ${f.gatewayReference}` : ""} />,
                <span key="m" className="tnum">{feeAmountWords(f, naira)}</span>, <span key="d" className="tnum">{f.paidOn || "—"}</span>, <span key="st" className="sub2">{f.statedStatus || "—"}</span>,
                <Two key="b" a={f.batchReference || "—"} b={f.uploadedBy} />,
                <span key="s"><Pil kind={s[1]}>{s[0]}</Pil>{f.decidedAt ? <div className="sub2">{when(f.decidedAt)}{f.decidedBy ? ` · ${f.decidedBy}` : ""}{f.postedReference ? ` · posted as ${f.postedReference}` : ""}{f.note ? ` · ${f.note}` : ""}</div> : null}</span>,
                f.state === "REQUIRES_REVIEW" && mayDecide ? (mine(f) ? <span key="x" className="sub2">You uploaded it: another Bursary officer must verify it</span> : f.mayDecide === false ? <span key="x" /> : (
                  <span key="x" className="row row--inline row--tight">
                    <Btn kind="secondary" size="sm" onClick={() => setAct({ fee: f, verify: true, note: "", reference: "", amount: "" })}>Verify</Btn>
                    <Btn kind="ghost" size="sm" onClick={() => setAct({ fee: f, verify: false, note: "", reference: "", amount: "" })}>Not verified</Btn>
                  </span>
                )) : <span key="x" />,
              ];
            })}
            texts={d.rows.map((f) => `${f.name} ${f.applicationNo} ${f.legacyNo} ${f.reference} ${f.gatewayReference} ${f.batchReference}`)} />
        ) : <PBody><div className="sub2">{d ? "No old-portal fee in this view." : "Reading the fees…"}</div></PBody>}
        {d && d.total > PAGE ? (
          <PBody>
            <div className="row row--inline">
              <Btn kind="ghost" size="sm" disabled={page === 0} onClick={() => { const pg = page - 1; setPage(pg); void load(route, state, pg); }}>Previous</Btn>
              <span className="sub2">Page {page + 1} of {Math.ceil(d.total / PAGE)} · {n0(d.total)} fees</span>
              <Btn kind="ghost" size="sm" disabled={(page + 1) * PAGE >= d.total} onClick={() => { const pg = page + 1; setPage(pg); void load(route, state, pg); }}>Next</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>
      {act ? (
        <Modal title={act.verify ? "Verify the old-portal fee" : "Record the fee as not verified"} sub={`${act.fee.applicationNo}${act.fee.legacyNo ? ` · ${act.fee.legacyNo}` : ""}`} onClose={() => setAct(null)}
          foot={<><Btn kind="ghost" onClick={() => setAct(null)}>Cancel</Btn>
            <Btn kind="primary" onClick={decide} disabled={act.note.trim().length < 5 || (act.verify && !act.fee.reference && !act.reference.trim())
              || (act.verify && !act.fee.amountGiven && !!act.amount.trim() && !amountOk(act.amount))}>{act.verify ? "Verify" : "Not verified"}</Btn></>}>
          <p>{act.fee.amountGiven ? naira(act.fee.amount) : "An amount still to confirm"} for {act.fee.name || act.fee.applicationNo}, {act.fee.routeName}{act.fee.paidOn ? `, paid ${act.fee.paidOn}` : ""}{act.fee.reference ? ` under ${act.fee.reference}` : ""}.</p>
          {act.verify && !act.fee.amountGiven ? (
            <>
              <Note kind="info" title="The file gave no amount">Give the amount the bank statement or the gateway&rsquo;s record shows. Left blank, the fee is posted at the programme&rsquo;s stated application fee.</Note>
              <Field id="fee-amount" label="The amount paid (₦)" hint="As the statement or the gateway's record shows it; the amount posted and receipted.">
                <input id="fee-amount" className="ctl" inputMode="decimal" value={act.amount} onChange={(e) => setAct({ ...act, amount: e.target.value })} />
              </Field>
              {act.amount.trim() && !amountOk(act.amount) ? <p className="sub2">An amount in naira, more than nothing, at most two places after the point.</p> : null}
            </>
          ) : null}
          {act.verify && !act.fee.reference ? (
            <Field id="fee-ref" label="The payment reference you found" required hint="The file gave none: the reference on the bank statement or the gateway's record. It is the reference posted.">
              <input id="fee-ref" className="ctl" value={act.reference} onChange={(e) => setAct({ ...act, reference: e.target.value })} />
            </Field>
          ) : null}
          <Field id="fee-note" label={act.verify ? "What was checked" : "Why it is not verified"} required hint={act.verify ? "The bank statement or the gateway's record; at least five characters." : "The applicant reads that the payment could not be verified; at least five characters."}>
            <textarea id="fee-note" className="ctl" rows={3} value={act.note} onChange={(e) => setAct({ ...act, note: e.target.value })} />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}

/* ── the programme corrected ───────────────────────────────────────────────────────────────────────────────────────── */
function CorrectionsPanel({ routes, mayChange, app }: { routes: AccessRoute[]; mayChange: boolean; app: string | null }) {
  const [q, setQ] = useState("");
  const [found, setFound] = useState<Record<string, unknown>[] | null>(null);
  const [open, setOpen] = useState<string | null>(app);
  const [record, setRecord] = useState<Record<string, unknown> | null>(null);
  const [recordErr, setRecordErr] = useState<Problem | null>(null);
  const [changing, setChanging] = useState(false);
  const [route, setRoute] = useState("");
  const [page, setPage] = useState(0);
  const [history, setHistory] = useState<{ rows: Record<string, unknown>[]; total: number } | null>(null);
  async function find() {
    const r = await pcall<unknown>(`${MIGRATION_API}/find?q=${encodeURIComponent(q.trim())}`);
    if (r.ok) setFound(rowsOf(r.data).rows); else notifyProblem(r.problem);
  }
  const fetchRecord = (id: string) => pcall<Record<string, unknown>>(`${MIGRATION_API}/applicants/${id}`);
  function showRecord(r: Awaited<ReturnType<typeof fetchRecord>>) { if (r.ok) setRecord(r.data); else setRecordErr(r.problem); }
  async function loadRecord(id: string) {
    setRecord(null); setRecordErr(null);
    showRecord(await fetchRecord(id));
  }
  function fetchHistory(r: string, pg: number) {
    const qs = new URLSearchParams({ page: String(pg), size: String(PAGE) });
    if (r) qs.set("route", r);
    return pcall<unknown>(`${MIGRATION_API}/corrections?${qs.toString()}`);
  }
  function showHistory(x: Awaited<ReturnType<typeof fetchHistory>>) { if (x.ok) setHistory(rowsOf(x.data)); else notifyProblem(x.problem); }
  async function loadHistory(r = route, pg = page) { showHistory(await fetchHistory(r, pg)); }
  useEffect(() => {
    let live = true;
    void fetchHistory("", 0).then((x) => { if (live) showHistory(x); });
    if (app) void fetchRecord(app).then((x) => { if (live) showRecord(x); });
    return () => { live = false; };
  }, []);   // eslint-disable-line react-hooks/exhaustive-deps -- once; the acts reload them

  const rec = record;
  const recRoute = str(rec, "route");
  const recName = str(rec, "routeName", "route_name") || routes.find((x) => x.route === recRoute)?.name || recRoute;
  const recMay = pick(rec, "mayChangeProgramme") === true || pick(rec, "may") === true || pick(pick(rec, "may"), "changeProgramme", "change") === true;
  const legacy = pick(rec, "legacy");
  const changes = (Array.isArray(pick(rec, "routeChanges", "changes")) ? (pick(rec, "routeChanges", "changes") as unknown[]) : []).map(routeChangeOf);
  const fee = pick(rec, "fee");
  const pay = wordOf(PAYMENT, str(rec, "feeStatus", "fee_status") || str(fee, "status"));
  const refs = words(pick(rec, "feeReferences", "fee_references") ?? pick(fee, "references"));
  const oldFees = (Array.isArray(pick(fee, "oldPortal")) ? (pick(fee, "oldPortal") as unknown[]) : []).map(legacyFeeOf);
  const target = pick(rec, "target");
  return (
    <>
      <Panel title="Find an applicant" right={<span className="sub2">This portal&rsquo;s application number, the old portal&rsquo;s, the name or the email</span>}>
        <PBody>
          <div className="row row--inline">
            <input className="ctl" style={{ maxWidth: 360 }} aria-label="Find an applicant" placeholder="e.g. APP/26/000123 or the old number" value={q} onChange={(e) => setQ(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter" && q.trim().length >= 3) void find(); }} />
            <Btn kind="primary" onClick={find} disabled={q.trim().length < 3}>Find</Btn>
          </div>
        </PBody>
        {found ? (found.length ? (
          <DTable pageSize={0} noPrint cols={["Applicant", "Application no.", "Old application no.", "Programme", "Session|mid", "Status", "Payment", "|num"]}
            rows={found.map((r) => {
              const id = str(r, "application_id", "applicationId", "id");
              const p = wordOf(PAYMENT, str(r, "fee_status", "feeStatus", "payment"));
              return [
                <span key="n">{str(r, "name", "applicant")}</span>, <span key="a" className="tnum">{str(r, "application_no", "applicationNo") || "—"}</span>,
                <span key="l" className="tnum">{str(r, "legacy_application_no", "legacy_no", "legacyNo") || "—"}</span>,
                <span key="p">{str(r, "route_name", "routeName") || str(r, "route")}</span>, <span key="s" className="tnum">{str(r, "session")}</span>,
                <span key="st">{labelOf(STATE, str(r, "state"))[0]}</span>, <Pil key="f" kind={p[1]}>{p[0]}</Pil>,
                id ? <Btn key="o" kind="secondary" size="sm" onClick={() => { setOpen(id); void loadRecord(id); }}>Open</Btn> : <span key="o" />,
              ];
            })} />
        ) : <PBody><div className="sub2">No preliminary applicant matches.</div></PBody>) : null}
      </Panel>

      {open ? (
        <Panel title={rec ? `${str(rec, "name", "applicant")} · ${str(rec, "applicationNo", "application_no")}` : "The applicant"}
          right={rec && mayChange && recMay ? <Btn kind="primary" size="sm" onClick={() => setChanging(true)}>Change application programme</Btn> : undefined}>
          <PBody>
            {recordErr ? <ProblemNotice problem={recordErr} /> : null}
            {!rec && !recordErr ? <div className="sub2">Reading the record…</div> : null}
            {rec ? (
              <>
                <KvGrid cls="grid--3" pairs={[
                  ["Application number", str(rec, "applicationNo", "application_no") || "—"],
                  ["Old-portal number", str(rec, "legacyNo", "legacy_no", "legacyApplicationNo") || str(legacy, "number", "legacy_application_no") || "—"],
                  ["Programme", recName || "—"],
                  ["Session", str(rec, "session") || "—"],
                  ["Status", labelOf(STATE, str(rec, "state"))[0]],
                  ["Sex / date of birth", `${str(rec, "sex") === "F" ? "Female" : str(rec, "sex") === "M" ? "Male" : "—"} / ${str(rec, "dateOfBirth", "date_of_birth", "dob") || "—"}`],
                  ["Intended programme", [str(target, "name"), str(target, "specialisationName")].filter(Boolean).join(" — ") || "not chosen"],
                  ["Area / group", str(target, "group") || "—"],
                  ["Payment", <span key="p"><Pil kind={pay[1]}>{pay[0]}</Pil>{refs.length ? ` ${refs.join(", ")}` : ""}</span>],
                  ["Old-portal fee", oldFees.length ? oldFees.map((x) => `${x.reference || "no reference"} · ${feeAmountWords(x, naira)} · ${wordOf(FEE_STATE, x.state)[0].toLowerCase()}`).join("; ") : "—"],
                  ["Documents uploaded", String(num(rec, "documents", "documentsCount", "documents_count"))],
                  // V755: the day the desk and the dashboard read (prelim_applied_on); one brought across with no Application Date has none
                  ["Applied on", appliedOnWords(rec, legacy, day)],
                  ["Brought across", legacy ? `${str(legacy, "batchReference", "batch_reference") || "—"}${str(legacy, "migratedAt", "migrated_at") ? ` · ${when(str(legacy, "migratedAt", "migrated_at"))}` : ""}` : "Applied on this portal"],
                ]} />
                {!mayChange || !recMay ? <div className="sub2 mt-1">{str(pick(rec, "refusal"), "message") || (mayChange ? "The programme of this application cannot be changed now." : "The Director of ICT, or an ICT Support agent the Director has authorised, changes the programme.")}</div> : null}
                <h3 className="h4 mt-2">Programme changes</h3>
                {changes.length ? <ChangesTable rows={changes} /> : <div className="sub2">None.</div>}
              </>
            ) : null}
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Programme corrections" right={<select className="ctl" aria-label="Programme" value={route} onChange={(e) => { setRoute(e.target.value); setPage(0); void loadHistory(e.target.value, 0); }}>
        <option value="">Both programmes</option>
        {routes.map((r) => <option key={r.route} value={r.route}>{r.name}</option>)}
      </select>}>
        {history && history.rows.length ? <ChangesTable rows={history.rows.map(routeChangeOf)} withApplicant /> : <PBody><div className="sub2">{history ? "No programme has been corrected yet." : "Reading…"}</div></PBody>}
        {history && history.total > PAGE ? (
          <PBody>
            <div className="row row--inline">
              <Btn kind="ghost" size="sm" disabled={page === 0} onClick={() => { const pg = page - 1; setPage(pg); void loadHistory(route, pg); }}>Previous</Btn>
              <span className="sub2">Page {page + 1} of {Math.ceil(history.total / PAGE)}</span>
              <Btn kind="ghost" size="sm" disabled={(page + 1) * PAGE >= history.total} onClick={() => { const pg = page + 1; setPage(pg); void loadHistory(route, pg); }}>Next</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>

      {changing && open && rec ? (
        <PrelimProgrammeChange applicationId={open} fromRoute={recRoute}
          applicant={{ name: str(rec, "name", "applicant"), applicationNo: str(rec, "applicationNo", "application_no"), legacyNo: str(rec, "legacyNo", "legacy_no") || str(legacy, "number") }}
          onClose={(changed) => { setChanging(false); if (changed) { void loadRecord(open); void loadHistory(); } }} />
      ) : null}
    </>
  );
}

function ChangesTable({ rows, withApplicant }: { rows: ReturnType<typeof routeChangeOf>[]; withApplicant?: boolean }) {
  return (
    <DTable pageSize={withApplicant ? 0 : 10} noPrint={!withApplicant}
      cols={["When", ...(withApplicant ? ["Applicant"] : []), "From", "To", "Reason", "Fee", "Result", "By"]}
      rows={rows.map((c) => {
        const fee = wordOf(PAYMENT, c.feeStatus);
        return [
          <Two key="w" a={when(c.at)} b={c.reference} />,
          ...(withApplicant ? [<Two key="a" a={c.applicationNo || "—"} b={[c.name, c.legacyNo].filter(Boolean).join(" · ")} />] : []),
          <Two key="f" a={c.fromName} b={[c.fromTarget, c.fromState ? labelOf(STATE, c.fromState)[0] : ""].filter(Boolean).join(" · ")} />,
          <Two key="t" a={c.toName} b={c.toState ? labelOf(STATE, c.toState)[0] : ""} />,
          <span key="r" className="sub2">{c.reason}</span>,
          c.feeStatus ? <Pil key="fe" kind={fee[1]}>{fee[0]}</Pil> : <span key="fe">—</span>,
          c.result === "REFUSED" ? <span key="re"><Pil kind="bad">Refused</Pil><div className="sub2">{c.refusal}</div></span> : <Pil key="re" kind="ok">Changed</Pil>,
          <Two key="b" a={c.by || "—"} b={c.office} />,
        ];
      })} />
  );
}
