"use client";
/** The old portal's NELFUND payments reconciled onto the wallet (V327): the Bursary uploads the old portal's export, sees the columns
 *  mapped, runs a dry run or stages the rows (matched to current students by strong identifiers only, judged by status, amount and
 *  session), reads the counts, and applies — the matched rows become NELFUND credits on the wallets for the session they name, once,
 *  carrying the old reference and date. What cannot be reconciled waits in the queue with its reason for an officer to match on
 *  evidence or reject. */
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { csvRows, xlsxRows } from "@/lib/xlsx";
import type { Problem } from "@/lib/api";
import { detectLegacyMapping, legacyHeaderRowIndex, legacyRowsOf, type LegacyRow } from "@/lib/legacy-gst-import";
import { METHOD_WORD, NEL_CODE_WORD, NEL_STATUS_WORD, NELFUND_FIELDS, candidatesOf, dayOf, naira, num, whenAt,
  type NelfundImportView, type NelfundLegacyPage, type NelfundLegacyRow, type NelfundRowDetail, type NelfundRowsPage } from "@/lib/legacy-nelfund";

type Tab = "upload" | "queue" | "search" | "imports";
const MAX_BYTES = 20 * 1024 * 1024;
const BASE = "/api/bff/api/v1/nelfund/legacy";

async function post<T>(path: string, body: unknown, reason: string): Promise<T | null> {
  const r = await fetch(`${BASE}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return null; }
  return j as T;
}

const REPORT_HEAD = ["S/N", "Old reference", "Transaction ID", "Old student ID", "Student", "Number", "Amount", "Paid", "Session", "Old status", "Matched by", "Status", "Wallet reference", "Posted by", "Posted", "Finding"];
const reportRow = (r: NelfundLegacyRow, i: number) => [i + 1, r.source_reference ?? "", r.source_transaction_id ?? "", r.source_student_id ?? "", r.surname ? `${r.surname}, ${r.other_names}` : r.student_name ?? "",
  r.number ?? r.matric_no ?? "", r.amount == null ? "" : Number(r.amount), r.paid_at ? dayOf(r.paid_at) : r.paid_at_text ?? "", r.session ?? "", r.legacy_status ?? "",
  r.match_method ? METHOD_WORD[r.match_method] ?? r.match_method : "", (NEL_STATUS_WORD[r.status] ?? [r.status])[0], r.wallet_reference ?? "", r.posted_by_name ?? r.posted_office ?? "", r.posted_at ? dayOf(r.posted_at) : "",
  r.reason_code ? `${NEL_CODE_WORD[r.reason_code] ?? r.reason_code}${r.reason ? `: ${r.reason}` : ""}` : r.override_reason ?? ""];

function RowsTable({ rows, onOpen, offset = 0 }: { rows: NelfundLegacyRow[]; onOpen: (r: NelfundLegacyRow) => void; offset?: number }) {
  return (
    <DTable noPrint pageSize={50} cols={["S/N|num", "Old reference", "Identifiers on the row", "Amount|num", "Paid", "Session|mid", "Old status|mid", "Student", "Status|mid", "Finding", "|num"]} rows={rows.map((r, i) => [
      <span key="n" className="tnum sub2">{offset + i + 1}</span>,
      <span key="r"><b className="tnum">{r.source_reference ?? r.source_transaction_id}</b>{r.source_transaction_id && r.source_reference ? <div className="sub2 tnum">{r.source_transaction_id}</div> : null}</span>,
      <span key="i" className="sub2 tnum">{[r.matric_no, r.jamb_no, r.application_no, r.source_student_id].filter(Boolean).join(" · ") || "—"}{r.student_name ? <div>{r.student_name}</div> : null}</span>,
      <span key="a" className="tnum">{naira(r.amount)}</span>,
      <span key="d" className="tnum sub2">{r.paid_at ? dayOf(r.paid_at) : r.paid_at_text ?? "—"}</span>,
      <span key="s" className="tnum">{r.session ?? "—"}</span>,
      <Pil key="ls" kind={r.normalized_status === "SUCCESS" ? "ok" : r.normalized_status === "PENDING" ? "warn" : "bad"} title={r.legacy_status ?? ""}>{r.legacy_status ?? r.normalized_status}</Pil>,
      <span key="st">{r.surname ? <><b>{r.surname}, {r.other_names}</b><div className="sub2 tnum">{r.number} · {r.match_method ? METHOD_WORD[r.match_method] ?? r.match_method : ""}</div></> : <span className="sub2">—</span>}</span>,
      <Pil key="rs" kind={(NEL_STATUS_WORD[r.status] ?? ["", "grey"])[1]}>{(NEL_STATUS_WORD[r.status] ?? [r.status])[0]}</Pil>,
      <span key="f" className="sub2">{r.reason_code ? <b>{NEL_CODE_WORD[r.reason_code] ?? r.reason_code}</b> : r.wallet_reference ? <span className="tnum">{r.wallet_reference}</span> : ""}{r.reason ? <div>{r.reason}</div> : null}</span>,
      <Btn key="o" kind="ghost" size="sm" onClick={() => onOpen(r)}>Open</Btn>,
    ])} texts={rows.map((r) => `${r.source_reference ?? ""} ${r.source_transaction_id ?? ""} ${r.matric_no ?? ""} ${r.surname ?? ""} ${r.status} ${r.reason_code ?? ""}`)} />
  );
}

function RowModal({ id, canAct, onClose, onChanged }: { id: string; canAct: boolean; onClose: () => void; onChanged: () => void }) {
  const [row, setRow] = useState<NelfundRowDetail | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [q, setQ] = useState("");
  const [found, setFound] = useState<{ id: string; name: string; number: string; jamb_reg_no: string | null; programme_code: string; level: number }[]>([]);
  const [picked, setPicked] = useState<string>("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const load = useCallback(async () => {
    const r = await fetch(`${BASE}/rows/${id}`);
    const j = await r.json().catch(() => null);
    if (!r.ok) { setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
    setRow(j as NelfundRowDetail);
  }, [id]);
  useEffect(() => { const t = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(t); }, [load]);
  useEffect(() => {
    const t = window.setTimeout(async () => {
      if (q.trim().length < 3) { setFound([]); return; }
      const r = await fetch(`${BASE}/students?q=${encodeURIComponent(q.trim())}`);
      if (r.ok) setFound(await r.json());
    }, 300);
    return () => window.clearTimeout(t);
  }, [q]);
  async function act(action: "match" | "reject") {
    if (!row) return;
    setBusy(true);
    try {
      const j = await post<NelfundRowDetail>(`/rows/${row.id}/${action}`, { studentId: action === "match" ? picked || null : null, reason: reason.trim() },
        `${action === "match" ? "Match" : "Reject"} old-portal NELFUND payment ${row.source_reference ?? row.source_transaction_id}`);
      if (j) { notify((NEL_STATUS_WORD[j.status] ?? [j.status])[0]); setRow(j); setReason(""); onChanged(); }
    } finally { setBusy(false); }
  }
  const open = row && (row.status === "REQUIRES_REVIEW" || row.status === "UNMATCHED" || row.status === "MATCHED");
  const cands = row ? candidatesOf(row) : [];
  return (
    <Modal title={row ? `${row.source_reference ?? row.source_transaction_id} · ${naira(row.amount)} · ${row.session ?? "no session"}` : "Old-portal NELFUND payment"} sub={row ? `${row.import_reference} · row ${row.row_no}` : ""} wide onClose={onClose}>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!row ? <div className="sub2">Loading…</div> : (
        <>
          <div className="row row--inline row--tight mb-2">
            <Pil kind={(NEL_STATUS_WORD[row.status] ?? ["", "grey"])[1]}>{(NEL_STATUS_WORD[row.status] ?? [row.status])[0]}</Pil>
            {row.reason_code ? <Pil kind="warn">{NEL_CODE_WORD[row.reason_code] ?? row.reason_code}</Pil> : null}
            {row.match_method ? <Pil kind={row.match_confidence === "HIGH" ? "ok" : "info"}>{METHOD_WORD[row.match_method] ?? row.match_method} · {row.match_confidence}</Pil> : null}
          </div>
          {row.reason ? <Note kind={row.status === "POSTED" ? "ok" : "info"} title={NEL_CODE_WORD[row.reason_code ?? ""] ?? "Finding"}>{row.reason}</Note> : null}
          <KvGrid cls="grid--4" pairs={[
            ["Old reference", <span key="a" className="tnum">{row.source_reference ?? "—"}</span>], ["Transaction ID", <span key="b" className="tnum">{row.source_transaction_id ?? "—"}</span>],
            ["Payment date (original)", row.paid_at ? whenAt(row.paid_at) : row.paid_at_text ?? "—"], ["Session", row.session ?? "—"],
            ["Identifiers on the row", [row.matric_no, row.jamb_no, row.application_no, row.source_student_id].filter(Boolean).join(" · ") || "—"], ["Name on the row", row.student_name ?? "—"],
            ["Old status", row.legacy_status ?? "—"], ["On the wallet as", row.wallet_reference ? <span key="w" className="tnum">{row.wallet_reference} · {row.wallet_session}</span> : "—"],
          ]} />
          {row.student_id ? <KvGrid cls="grid--3" pairs={[["Current student", <b key="s">{row.surname}, {row.other_names}</b>], ["Number", <span key="n" className="tnum">{row.number}</span>], ["Programme · level", `${row.programme_code} · ${row.level}`]]} /> : null}
          {cands.length ? (
            <Panel title={row.status === "UNMATCHED" ? "Suggestions by name — not a match until an officer verifies" : "Candidate students"}>
              <DTable cols={["Student", "Number", "Programme", "How", "|num"]} rows={cands.map((c) => [
                <b key="n">{c.name}</b>, <span key="m" className="tnum">{c.number}</span>, <span key="p" className="sub2">{c.programme}</span>, <span key="h" className="sub2">{METHOD_WORD[c.method] ?? c.method.replace(/_/g, " ").toLowerCase()}</span>,
                canAct && open ? <Btn key="u" kind={picked === c.student_id ? "primary" : "ghost"} size="sm" onClick={() => setPicked(c.student_id)}>{picked === c.student_id ? "Selected" : "Select"}</Btn> : <span key="u" />])} />
            </Panel>
          ) : null}
          {canAct && open ? (
            <Panel title="Resolve" right={<Pil kind="bad">On the record in your name</Pil>}>
              <PBody>
                {row.status !== "MATCHED" || !row.student_id ? (
                  <>
                    <Field id="nm-q" label="Find the verified student" hint="Number, JAMB number or name; the row's own identifiers must not name somebody else"><input id="nm-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} /></Field>
                    {found.length ? <DTable cols={["Student", "Number", "JAMB", "Programme", "|num"]} rows={found.map((s) => [<b key="n">{s.name}</b>, <span key="m" className="tnum">{s.number}</span>, <span key="j" className="tnum sub2">{s.jamb_reg_no ?? "—"}</span>, <span key="p" className="sub2">{s.programme_code} · {s.level}</span>,
                      <Btn key="u" kind={picked === s.id ? "primary" : "ghost"} size="sm" onClick={() => setPicked(s.id)}>{picked === s.id ? "Selected" : "Select"}</Btn>])} /> : null}
                  </>
                ) : null}
                <Field id="nm-reason" label="Reason / supporting reference" required hint="The Fund's schedule, the receipt, the memo — what verified it"><textarea id="nm-reason" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
                <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
                  {picked ? <Btn kind="primary" disabled={busy || !reason.trim()} onClick={() => void act("match")}>Match to the selected student</Btn> : null}
                  <Btn kind="urgent" disabled={busy || !reason.trim()} onClick={() => void act("reject")}>Reject</Btn>
                </div>
                <div className="sub2 mt-1">A matched row is posted to the wallet when the import is applied. A name is never a match on its own; the identifiers on the row must not name another student.</div>
              </PBody>
            </Panel>
          ) : null}
          {row.override_reason ? <div className="sub2 mt-1">Resolved {whenAt(row.resolved_at)} by {row.resolved_office ?? "the office"}: {row.override_reason}</div> : null}
          <details className="mt-2"><summary className="sub2">The row as the old portal exported it</summary><pre className="sub2" style={{ whiteSpace: "pre-wrap" }}>{row.raw}</pre></details>
        </>
      )}
    </Modal>
  );
}

export function LegacyNelfund({ data, canAct, session }: { data: NelfundLegacyPage; canAct: boolean; session: string }) {
  const router = useRouter();
  const [tab, setTab] = useState<Tab>("upload");
  const [busy, setBusy] = useState(false);
  const [phase, setPhase] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const [grid, setGrid] = useState<{ header: string[]; rows: string[][] } | null>(null);
  const [mapping, setMapping] = useState<Record<string, number>>({});
  const [fallbackSession, setFallbackSession] = useState<string>(session);
  const [imp, setImp] = useState<NelfundImportView | null>(null);
  const [show, setShow] = useState<string>("ALL");
  const [open, setOpen] = useState<string | null>(null);
  const [filters, setFilters] = useState({ status: "OPEN", session: "", q: "" });
  const [page, setPage] = useState(1);
  const [list, setList] = useState<NelfundRowsPage | null>(null);
  const s = data.summary;
  const missingRequired = NELFUND_FIELDS.filter((f) => f.required && mapping[f.key] === undefined && !(f.key === "session" && fallbackSession));
  const rowsIn = (): LegacyRow[] => (grid ? legacyRowsOf([grid.header, ...grid.rows], 0, mapping, { session: fallbackSession }) : []);

  async function readFile(file: File) {
    setProblem(null); setImp(null);
    if (file.size > MAX_BYTES) { setProblem({ status: 400, title: "That file is larger than 20 MB." }); return; }
    setBusy(true); setPhase(`Reading ${file.name}…`);
    try {
      const cells = /\.csv$/i.test(file.name) ? csvRows(await file.text()) : await xlsxRows(await file.arrayBuffer());
      const hi = legacyHeaderRowIndex(cells);
      const header = (cells[hi] ?? []).map((c) => String(c ?? ""));
      const kept = cells.slice(hi + 1).filter((r) => r.some((c) => String(c ?? "").trim()));
      setGrid({ header, rows: kept.map((r) => r.map((c) => String(c ?? ""))) });
      setMapping(detectLegacyMapping(header));
      setFileName(file.name);
      if (!kept.length) setProblem({ status: 400, title: "No payment rows were found under the header." });
    } catch (e) { setProblem({ status: 400, title: "The file could not be read.", detail: e instanceof Error ? e.message : String(e) }); }
    finally { setBusy(false); setPhase(null); }
  }

  async function stage(dryRun: boolean) {
    const rows = rowsIn();
    if (!rows.length) { setProblem({ status: 400, title: "No payment rows to stage." }); return; }
    setBusy(true); setProblem(null);
    setPhase(`${dryRun ? "Dry run" : "Staging"}: ${rows.length} rows matched to students by their identifiers, judged by status, amount and session, checked against the wallets…`);
    try {
      const j = await post<NelfundImportView>("/imports", { rows, fileName, session: fallbackSession || null, dryRun }, `${dryRun ? "Dry run of" : "Stage"} ${rows.length} old-portal NELFUND payments from ${fileName ?? "a file"}`);
      if (j) { setImp(j); setShow("ALL"); if (!dryRun) router.refresh(); }
    } finally { setBusy(false); setPhase(null); }
  }

  async function apply(id: string) {
    setBusy(true); setPhase("Posting: each matched row becomes one NELFUND credit on the student's wallet for its session…");
    try {
      const j = await post<NelfundImportView>(`/imports/${id}/apply`, {}, `Post old-portal NELFUND payments ${imp?.import.reference ?? id} to the wallets`);
      if (j) { setImp(j); notify(`${num(j.applied?.posted)} payment${j.applied?.posted === 1 ? "" : "s"} posted to wallets (${naira(j.applied?.amount)})`); router.refresh(); }
    } finally { setBusy(false); setPhase(null); }
  }

  const loadList = useCallback(async () => {
    const p = new URLSearchParams();
    for (const [k, v] of Object.entries(filters)) if (v) p.set(k, v);
    p.set("page", String(page)); p.set("size", "100");
    const r = await fetch(`${BASE}/rows?${p.toString()}`);
    const j = await r.json().catch(() => null);
    if (!r.ok) { setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
    setList(j as NelfundRowsPage);
  }, [filters, page]);
  useEffect(() => { if (tab !== "queue" && tab !== "search") return; const t = window.setTimeout(() => void loadList(), filters.q ? 300 : 0); return () => window.clearTimeout(t); }, [tab, loadList, filters.q]);

  async function exportRows(scope: { status?: string; title: string; file: string }) {
    setBusy(true);
    try {
      const p = new URLSearchParams();
      if (scope.status) p.set("status", scope.status);
      if (filters.session) p.set("session", filters.session);
      p.set("size", "500");
      const r = await fetch(`${BASE}/rows?${p.toString()}`);
      const j = (await r.json()) as NelfundRowsPage;
      if (!r.ok) throw new Error((j as unknown as Problem).title ?? r.statusText);
      const body = j.rows.map(reportRow);
      downloadBlob(await brandedXlsx(scope.title, REPORT_HEAD, body, { sheetName: "NELFUND reconciliation", serial: docSerial("NELREC"), sub: `${filters.session || "every session"} · ${j.rows.length} of ${j.total} row${j.total === 1 ? "" : "s"}` }), scope.file);
    } catch (e) { notifyProblem({ status: 500, title: "The report could not be built", detail: e instanceof Error ? e.message : String(e) }); }
    finally { setBusy(false); }
  }

  const importRows = imp ? imp.rows.filter((r) => show === "ALL" || r.status === show) : [];

  return (
    <>
      <Tiles items={[
        ["OLD-PORTAL RECORDS", num(s.total_rows), null, `${naira(s.amount_received)} successful`],
        ["POSTED TO WALLETS", num(s.posted), "var(--green-ink)", `${naira(s.amount_posted)} · ${num(s.students_posted)} students`],
        ["MATCHED, NOT POSTED", num(s.matched), s.matched ? "var(--chrome)" : null, "Awaiting apply"],
        ["REQUIRES REVIEW · UNMATCHED", `${num(s.requires_review)} · ${num(s.unmatched)}`, Number(s.requires_review) + Number(s.unmatched) ? "var(--red-ink)" : null, `${naira(s.amount_review)} waiting on an officer`],
        ["DUPLICATE · REJECTED", `${num(s.duplicates)} · ${num(s.rejected)}`, null, "Already on a wallet · failed, reversed, no session"],
      ]} cls="grid--5" />
      <Tabs label="Old-portal NELFUND" value={tab} onChange={(k) => setTab(k as Tab)} items={[
        { id: "upload", label: "Upload & post" }, { id: "queue", label: "Exception queue", count: num(Number(s.requires_review) + Number(s.unmatched)) },
        { id: "search", label: "Search" }, { id: "imports", label: "Imports", count: num(data.imports.length) },
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {phase ? <Note kind="info" title="Working…">{phase}</Note> : null}

      {tab === "upload" ? (
        <>
          <Panel title="Old-portal NELFUND payment export" right={canAct ? <label className={`btn btn--primary btn--sm${busy ? " is-disabled" : ""}`} style={{ cursor: busy ? "default" : "pointer" }}>Upload Excel / CSV<input type="file" accept=".xlsx,.xls,.csv" style={{ display: "none" }} disabled={busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void readFile(f); e.target.value = ""; }} /></label> : null}>
            <PBody>
              <div className="sub2">Columns read by name: transaction id, payment reference, the old portal&rsquo;s student id, matriculation number, JAMB number, application number, name, amount, payment date, session and status. A row is matched to a current student by those identifiers in that order — never by name alone. Only a successful payment of an amount for a known session is posted; it goes onto the wallet as NELFUND funding of <b>that</b> session, dated when it was paid, with the old reference kept. The same reference is never staged or posted twice.</div>
              <div className="row row--inline row--tight mt-2"><Field id="nl-ses" label="Session for rows that name none" hint="YYYY/YYYY; a row's own session wins, then the session its date falls in"><input id="nl-ses" className="ctl" style={{ maxWidth: 140 }} value={fallbackSession} onChange={(e) => setFallbackSession(e.target.value)} /></Field></div>
            </PBody>
          </Panel>
          {grid ? (
            <Panel title={`${fileName} · ${num(grid.rows.length)} rows · columns mapped`} right={canAct ? <span className="row row--inline row--tight"><Btn kind="secondary" disabled={busy || missingRequired.length > 0} onClick={() => void stage(true)}>Dry run</Btn><Btn kind="primary" disabled={busy || missingRequired.length > 0} onClick={() => void stage(false)}>Stage</Btn></span> : null}>
              <PBody>
                {missingRequired.length ? <Note kind="bad" title="A required column is not mapped">{missingRequired.map((f) => f.label).join(", ")}: choose the column, or give the session above.</Note> : null}
                <div className="grid grid--4">
                  {NELFUND_FIELDS.map((f) => (
                    <Field key={f.key} id={`nl-${f.key}`} label={f.label} required={f.required}>
                      <select id={`nl-${f.key}`} className="ctl" value={mapping[f.key] ?? ""} onChange={(e) => { const m = { ...mapping }; if (e.target.value === "") delete m[f.key]; else m[f.key] = Number(e.target.value); setMapping(m); }}>
                        <option value="">— not in the file —</option>
                        {grid.header.map((h, i) => <option key={i} value={i}>{h || `Column ${i + 1}`}</option>)}
                      </select>
                    </Field>
                  ))}
                </div>
                <div className="sub2 mt-2">A dry run matches and judges without writing anything; staging keeps the rows and their judgements so the queue can be worked, and still credits no wallet. Posting is the Bursary&rsquo;s word, below.</div>
              </PBody>
            </Panel>
          ) : null}
          {imp ? (
            <Panel title={`${imp.dryRun ? "Dry run" : imp.import.reference} · ${imp.import.file_name ?? ""}`} right={<span className="row row--inline row--tight">
              <select className="ctl" value={show} onChange={(e) => setShow(e.target.value)}>
                <option value="ALL">Every row ({num(imp.total)})</option><option value="MATCHED">Would post ({num(imp.summary.matched)})</option><option value="POSTED">Posted ({num(imp.summary.posted)})</option>
                <option value="REQUIRES_REVIEW">Requires review ({num(imp.summary.requires_review)})</option><option value="UNMATCHED">Unmatched ({num(imp.summary.unmatched)})</option><option value="DUPLICATE">Duplicate ({num(imp.summary.duplicates)})</option><option value="REJECTED">Rejected ({num(imp.summary.rejected)})</option>
              </select>
              {canAct && !imp.dryRun && imp.import.status === "STAGED" && Number(imp.summary.matched) > 0 ? <Btn kind="go" disabled={busy} onClick={() => void apply(imp.import.id)}>Post {num(imp.summary.matched)} to the wallets</Btn> : null}
              {canAct && imp.dryRun ? <Btn kind="go" disabled={busy} onClick={() => void stage(false)}>Stage these rows</Btn> : null}
            </span>}>
              <Tiles items={[
                ["ROWS", num(imp.staging?.total_rows ?? imp.total), null, `${num(imp.staging?.staged ?? imp.total)} staged · ${num(imp.staging?.already_staged ?? 0)} already staged · ${num(imp.staging?.skipped ?? 0)} without an id`],
                [imp.dryRun ? "WOULD POST" : imp.import.status === "APPLIED" ? "POSTED" : "WILL POST", num(imp.import.status === "APPLIED" ? imp.summary.posted : imp.summary.matched), "var(--green-ink)", naira(imp.import.status === "APPLIED" ? imp.summary.amount_posted : imp.summary.amount_review)],
                ["REQUIRES REVIEW", num(imp.summary.requires_review), imp.summary.requires_review ? "var(--red-ink)" : null, "Identifiers point to more than one student"],
                ["UNMATCHED", num(imp.summary.unmatched), imp.summary.unmatched ? "var(--red-ink)" : null, "No reliable student"],
                ["DUPLICATE", num(imp.summary.duplicates), null, "Already on a wallet"],
                ["REJECTED", num(imp.summary.rejected), null, "Failed, reversed, no amount, no session"],
              ]} cls="grid--6" />
              {imp.dryRun ? <PBody><Note kind="info" title="Nothing was written">This was a dry run: the counts above are what staging would produce; no row, no judgement and no wallet credit was kept.</Note></PBody> : null}
              {imp.applied ? <PBody><Note kind="ok" title={`${num(imp.applied.posted)} payment${imp.applied.posted === 1 ? "" : "s"} posted · ${naira(imp.applied.amount)}`}>Each is a NELFUND credit on its student&rsquo;s wallet for the session the row names, dated when it was paid, carrying the old reference. The student is told.</Note></PBody> : null}
              <RowsTable rows={importRows} onOpen={(r) => { if (!imp.dryRun) setOpen(r.id); }} />
            </Panel>
          ) : null}
        </>
      ) : null}

      {tab === "queue" || tab === "search" ? (
        <>
          <Panel title={tab === "queue" ? "Exception queue — an officer decides" : "Search the staged payments"} right={<Btn kind="secondary" size="sm" disabled={busy} onClick={() => void exportRows({ status: tab === "queue" ? "OPEN" : filters.status || undefined, title: "Old-portal NELFUND payment reconciliation", file: "nelfund-legacy-reconciliation.xlsx" })}>Excel</Btn>}>
            <PBody>
              <div className="grid grid--3">
                <Field id="nq-status" label="Status"><select id="nq-status" className="ctl" value={filters.status} onChange={(e) => { setFilters({ ...filters, status: e.target.value }); setPage(1); }}>
                  <option value="OPEN">Requires review + unmatched</option><option value="">Every status</option>{Object.entries(NEL_STATUS_WORD).map(([k, w]) => <option key={k} value={k}>{w[0]}</option>)}</select></Field>
                <Field id="nq-session" label="Session"><input id="nq-session" className="ctl" value={filters.session} onChange={(e) => { setFilters({ ...filters, session: e.target.value }); setPage(1); }} placeholder="Every session" /></Field>
                <Field id="nq-q" label="Search" hint="Old reference, transaction id, matric, JAMB, application number, name, wallet reference or amount"><input id="nq-q" className="ctl" value={filters.q} onChange={(e) => { setFilters({ ...filters, q: e.target.value }); setPage(1); }} /></Field>
              </div>
            </PBody>
          </Panel>
          <Panel title={`${list ? num(list.total) : "…"} payment${list?.total === 1 ? "" : "s"}`} right={list && list.total > list.size ? <span className="row row--inline row--tight sub2"><Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</Btn>Page {page} of {Math.ceil(list.total / list.size)}<Btn kind="ghost" size="sm" disabled={page * list.size >= list.total} onClick={() => setPage(page + 1)}>Next</Btn></span> : null}>
            {list ? (list.rows.length ? <RowsTable rows={list.rows} offset={(page - 1) * list.size} onOpen={(r) => setOpen(r.id)} /> : <PBody><div className="sub2">Nothing for these filters.</div></PBody>) : <PBody><div className="sub2">Loading…</div></PBody>}
          </Panel>
        </>
      ) : null}

      {tab === "imports" ? (
        <Panel title="Imports" right={<span className="sub2">Every run, its reference, who, the counts, and whether it was posted</span>}>
          {data.imports.length ? <DTable cols={["Reference", "File", "Uploaded", "Rows|num", "Staged|num", "Posted|num", "Review|num", "Unmatched|num", "Duplicate|num", "Rejected|num", "Amount|num", "Status|mid", "|num"]} rows={data.imports.map((i) => [
            <b key="r" className="tnum">{i.reference}</b>, <span key="f" className="sub2">{i.file_name ?? "—"}{i.session ? <div className="tnum">{i.session}</div> : null}</span>,
            <span key="u" className="sub2">{i.uploaded_by_name ?? i.uploader_office}<div className="tnum">{whenAt(i.uploaded_at)}</div></span>, <span key="t" className="tnum">{num(i.total_rows)}</span>, <span key="s" className="tnum">{num(i.staged)}</span>,
            <span key="c" className="tnum ink-green">{num(i.posted)}</span>, <span key="v" className={`tnum${Number(i.requires_review) ? " ink-red" : ""}`}>{num(i.requires_review)}</span>, <span key="n" className={`tnum${Number(i.unmatched) ? " ink-red" : ""}`}>{num(i.unmatched)}</span>,
            <span key="d" className="tnum">{num(i.duplicates)}</span>, <span key="j" className="tnum">{num(i.rejected)}</span>, <span key="a" className="tnum">{naira(i.posted_amount)}</span>,
            <Pil key="st" kind={i.status === "APPLIED" ? "ok" : "warn"}>{i.status === "APPLIED" ? `Posted ${dayOf(i.applied_at)}` : "Staged"}</Pil>,
            <span key="o" className="row row--inline row--tight">{canAct && Number(i.matched) > 0 ? <Btn kind="go" size="sm" disabled={busy} onClick={() => void apply(i.id)}>Post {num(i.matched)}</Btn> : null}</span>,
          ])} /> : <PBody><div className="sub2">No import yet.</div></PBody>}
        </Panel>
      ) : null}

      {open ? <RowModal id={open} canAct={canAct} onClose={() => setOpen(null)} onChanged={() => { void loadList(); router.refresh(); }} /> : null}
    </>
  );
}
