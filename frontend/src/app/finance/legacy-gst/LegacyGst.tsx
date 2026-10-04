"use client";
/** t/legacygst — old-portal GST payments reconciled into the GST/EPS entitlement (V323). The Bursary uploads the old portal's export, sees the
 *  columns mapped, runs a dry run or stages the rows (matched to current students by strong identifiers only, validated against that session's
 *  fee and the ledger), reads the counts, and applies — the validated rows go onto the one ledger as confirmed GST references carrying the old
 *  reference and date. What cannot be reconciled waits here with its reason: an officer matches it to a verified student, reconciles it with an
 *  override reason, relabels the school-fees row the same money already sits on, or rejects it. The totals that must agree are on the first tab. */
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { csvRows, xlsxRows } from "@/lib/xlsx";
import type { Problem } from "@/lib/api";
import { LEGACY_FIELDS, detectLegacyMapping, legacyHeaderRowIndex, legacyRowsOf, type LegacyRow } from "@/lib/legacy-gst-import";
import { CODE_WORD, METHOD_WORD, STATUS_WORD, dayOf, naira, num, whenAt, type Candidate, type ImportView, type LegacyRowView, type LegacySummaryPage, type RowDetail, type RowsPage } from "@/lib/legacy-gst";

type Tab = "overview" | "upload" | "queue" | "search" | "imports";
const MAX_BYTES = 20 * 1024 * 1024;

async function post<T>(path: string, body: unknown, reason: string): Promise<T | null> {
  const r = await fetch(`/api/bff/api/v1/finance/legacy-gst${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return null; }
  return j as T;
}

const REPORT_HEAD = ["S/N", "Legacy reference", "Transaction ID", "Legacy student ID", "Current student ID", "Student name", "Matric No", "Payment type", "Amount", "Payment date", "Session", "Legacy status", "Match method", "Reconciliation status", "Current entitlement (ledger reference)", "Reconciled by", "Reconciled date", "Reason / exception"];
const reportRow = (r: LegacyRowView, i: number) => [i + 1, r.source_reference ?? "", r.source_transaction_id ?? "", r.source_student_id ?? "", r.student_id ?? "", r.surname ? `${r.surname}, ${r.other_names}` : r.student_name ?? "",
  r.number ?? r.matric_no ?? "", r.payment_type ?? "", r.amount == null ? "" : Number(r.amount), r.paid_at ? dayOf(r.paid_at) : r.paid_at_text ?? "", r.session ?? "", r.legacy_status ?? "",
  r.match_method ? METHOD_WORD[r.match_method] ?? r.match_method : "", (STATUS_WORD[r.status] ?? [r.status])[0], r.ledger_reference ?? "", r.reconciled_by_name ?? r.reconciled_office ?? "", r.reconciled_at ? dayOf(r.reconciled_at) : "",
  r.reason_code ? `${CODE_WORD[r.reason_code] ?? r.reason_code}${r.reason ? `: ${r.reason}` : ""}` : r.override_reason ?? ""];

function RowsTable({ rows, onOpen, offset = 0 }: { rows: LegacyRowView[]; onOpen: (r: LegacyRowView) => void; offset?: number }) {
  return (
    <DTable noPrint pageSize={50} cols={["S/N|num", "Legacy reference", "Identifiers on the row", "Type|mid", "Amount|num", "Paid", "Session|mid", "Legacy status|mid", "Student", "Status|mid", "Finding", "|num"]} rows={rows.map((r, i) => [
      <span key="n" className="tnum sub2">{offset + i + 1}</span>,
      <span key="r"><b className="tnum">{r.source_reference ?? r.source_transaction_id}</b>{r.source_transaction_id && r.source_reference ? <div className="sub2 tnum">{r.source_transaction_id}</div> : null}</span>,
      <span key="i" className="sub2 tnum">{[r.matric_no, r.jamb_no, r.application_no, r.source_student_id].filter(Boolean).join(" · ") || "—"}{r.student_name ? <div>{r.student_name}</div> : null}</span>,
      <span key="t" className="sub2">{r.payment_type ?? "—"}{r.maps_to ? "" : r.payment_type ? <div className="ink-red">not a GST type</div> : null}</span>,
      <span key="a" className="tnum">{naira(r.amount)}</span>,
      <span key="d" className="tnum sub2">{r.paid_at ? dayOf(r.paid_at) : r.paid_at_text ?? "—"}</span>,
      <span key="s" className="tnum">{r.session ?? "—"}</span>,
      <Pil key="ls" kind={r.normalized_status === "SUCCESS" ? "ok" : r.normalized_status === "PENDING" ? "warn" : "bad"} title={r.legacy_status ?? ""}>{r.legacy_status ?? r.normalized_status}</Pil>,
      <span key="st">{r.surname ? <><b>{r.surname}, {r.other_names}</b><div className="sub2 tnum">{r.number} · {r.match_method ? METHOD_WORD[r.match_method] ?? r.match_method : ""}</div></> : <span className="sub2">—</span>}</span>,
      <Pil key="rs" kind={(STATUS_WORD[r.status] ?? ["", "grey"])[1]}>{(STATUS_WORD[r.status] ?? [r.status])[0]}</Pil>,
      <span key="f" className="sub2">{r.reason_code ? <b>{CODE_WORD[r.reason_code] ?? r.reason_code}</b> : r.ledger_reference ? <span className="tnum">{r.ledger_reference}</span> : ""}{r.reason ? <div>{r.reason}</div> : null}</span>,
      <Btn key="o" kind="ghost" size="sm" onClick={() => onOpen(r)}>Open</Btn>,
    ])} texts={rows.map((r) => `${r.source_reference ?? ""} ${r.source_transaction_id ?? ""} ${r.matric_no ?? ""} ${r.surname ?? ""} ${r.status} ${r.reason_code ?? ""}`)} />
  );
}

function RowModal({ id, canAct, onClose, onChanged }: { id: string; canAct: boolean; onClose: () => void; onChanged: () => void }) {
  const [d, setD] = useState<RowDetail | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [q, setQ] = useState("");
  const [found, setFound] = useState<{ id: string; number: string; surname: string; other_names: string; programme: string; level: number; jamb_reg_no: string | null }[]>([]);
  const [picked, setPicked] = useState<string>("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const load = useCallback(async () => {
    const r = await fetch(`/api/bff/api/v1/finance/legacy-gst/rows/${id}`);
    const j = await r.json().catch(() => null);
    if (!r.ok) { setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
    setD(j as RowDetail);
  }, [id]);
  useEffect(() => { const t = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(t); }, [load]);
  useEffect(() => {
    const t = window.setTimeout(async () => {
      if (q.trim().length < 3) { setFound([]); return; }
      const r = await fetch(`/api/bff/api/v1/finance/legacy-gst/students?q=${encodeURIComponent(q.trim())}`);
      if (r.ok) setFound(await r.json());
    }, 300);
    return () => window.clearTimeout(t);
  }, [q]);
  const row = d?.row;
  async function act(action: "match" | "reconcile" | "relabel" | "reject") {
    if (!row) return;
    setBusy(true);
    try {
      const j = await post<RowDetail>(`/rows/${row.id}/${action}`, { studentId: action === "match" ? picked || null : null, reason: reason.trim() }, `${action.charAt(0).toUpperCase() + action.slice(1)} old-portal GST payment ${row.source_reference ?? row.source_transaction_id}: ${reason.trim()}`);
      if (j) { notify(`${(STATUS_WORD[j.row.status] ?? [j.row.status])[0]}`); setD(j); setReason(""); onChanged(); }
    } finally { setBusy(false); }
  }
  const open = row && (row.status === "REQUIRES_REVIEW" || row.status === "UNMATCHED" || row.status === "MATCHED");
  return (
    <Modal title={row ? `${row.source_reference ?? row.source_transaction_id} · ${naira(row.amount)} · ${row.session ?? "no session"}` : "Old-portal payment"} sub={row ? `${row.import_reference} · row ${row.row_no} · ${row.payment_type ?? "no type"} · ${row.legacy_status ?? "no status"}` : undefined} wide onClose={onClose}>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!d || !row ? <div className="sub2">Loading…</div> : (
        <>
          <div className="row row--inline row--tight mb-2">
            <Pil kind={(STATUS_WORD[row.status] ?? ["", "grey"])[1]}>{(STATUS_WORD[row.status] ?? [row.status])[0]}</Pil>
            {row.reason_code ? <Pil kind="warn">{CODE_WORD[row.reason_code] ?? row.reason_code}</Pil> : null}
            {row.match_method ? <Pil kind={row.match_confidence === "HIGH" ? "ok" : "info"}>{METHOD_WORD[row.match_method] ?? row.match_method} · {row.match_confidence}</Pil> : null}
          </div>
          {row.reason ? <Note kind={row.status === "RECONCILED" ? "ok" : "info"} title={CODE_WORD[row.reason_code ?? ""] ?? "Finding"}>{row.reason}</Note> : null}
          <KvGrid cls="grid--4" pairs={[
            ["Legacy reference", <span key="a" className="tnum">{row.source_reference ?? "—"}</span>], ["Transaction ID", <span key="b" className="tnum">{row.source_transaction_id ?? "—"}</span>],
            ["Gateway", `${row.gateway ?? "—"}${row.gateway_reference ? ` · ${row.gateway_reference}` : ""}`], ["Payment date (original)", row.paid_at ? whenAt(row.paid_at) : row.paid_at_text ?? "—"],
            ["Identifiers on the row", [row.matric_no, row.jamb_no, row.application_no, row.source_student_id].filter(Boolean).join(" · ") || "—"], ["Name on the row", row.student_name ?? "—"],
            ["Payment type", `${row.payment_type ?? "—"}${row.maps_to ? ` → ${row.maps_to} fee` : " (not a GST type)"}`], ["Fee for that session", row.fee_amount == null ? "not stated" : naira(row.fee_amount)],
          ]} />
          {row.student_id ? (
            <Panel title="Current student" right={d.standing ? <Pil kind={d.standing.entitled ? "ok" : "bad"}>{d.standing.state.replace(/_/g, " ")}</Pil> : null}>
              <PBody>
                <KvGrid cls="grid--4" pairs={[["Student", <b key="s">{row.surname}, {row.other_names}</b>], ["Number", <span key="n" className="tnum">{row.number}</span>], ["Programme · level", `${row.programme_code} · ${row.level}`],
                  ["Entitlement now", d.standing ? `${d.standing.state.replace(/_/g, " ")}${d.standing.source ? ` · ${d.standing.source === "LEGACY_PORTAL" ? "old portal" : "this portal"}` : ""}` : "—"]]} />
                {d.ledger?.length ? <DTable cols={["Ledger reference", "Purpose", "Amount|num", "Confirmed", "Channel|mid"]} rows={d.ledger.map((l) => [
                  <span key="r" className="tnum">{l.reference}{row.payment_reference_id === l.id ? <Pil kind="ok" className="ml-1">this payment</Pil> : null}</span>, <span key="p">{l.purpose}</span>, <span key="a" className="tnum">{naira(l.amount)}</span>,
                  <span key="c" className="tnum sub2">{dayOf(l.confirmed_at)}</span>, <span key="ch" className="sub2">{l.channel ?? "—"}</span>])} /> : <div className="sub2">No confirmed payment on the ledger for this student and session.</div>}
              </PBody>
            </Panel>
          ) : null}
          {row.candidates?.length ? (
            <Panel title={row.status === "UNMATCHED" ? "Suggestions by name — not a match until an officer verifies" : "Candidate students"}>
              <DTable cols={["Student", "Number", "Programme", "How", "|num"]} rows={row.candidates.map((c: Candidate) => [
                <b key="n">{c.name}</b>, <span key="m" className="tnum">{c.number}</span>, <span key="p" className="sub2">{c.programme}</span>, <span key="h" className="sub2">{METHOD_WORD[c.method] ?? c.method.replace(/_/g, " ").toLowerCase()}</span>,
                canAct && open ? <Btn key="u" kind={picked === c.student_id ? "primary" : "ghost"} size="sm" onClick={() => setPicked(c.student_id)}>{picked === c.student_id ? "Selected" : "Select"}</Btn> : <span key="u" />])} />
            </Panel>
          ) : null}
          {canAct && open ? (
            <Panel title="Resolve" right={<Pil kind="bad">On the record in your name</Pil>}>
              <PBody>
                {row.status !== "MATCHED" || !row.student_id ? (
                  <>
                    <Field id="rm-q" label="Find the verified student" hint="Number, JAMB number or name; the row's own identifiers must not name somebody else"><input id="rm-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} /></Field>
                    {found.length ? <DTable cols={["Student", "Number", "JAMB", "Programme", "|num"]} rows={found.map((s) => [<b key="n">{s.surname}, {s.other_names}</b>, <span key="m" className="tnum">{s.number}</span>, <span key="j" className="tnum sub2">{s.jamb_reg_no ?? "—"}</span>, <span key="p" className="sub2">{s.programme} · {s.level}</span>,
                      <Btn key="u" kind={picked === s.id ? "primary" : "ghost"} size="sm" onClick={() => setPicked(s.id)}>{picked === s.id ? "Selected" : "Select"}</Btn>])} /> : null}
                  </>
                ) : null}
                <Field id="rm-reason" label="Reason / supporting reference" required hint="The bank statement, the receipt, the memo — what verified it"><textarea id="rm-reason" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
                <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
                  {picked ? <Btn kind="primary" disabled={busy || !reason.trim()} onClick={() => void act("match")}>Match to the selected student</Btn> : null}
                  {row.student_id ? <Btn kind="go" disabled={busy || !reason.trim()} onClick={() => void act("reconcile")}>{row.status === "REQUIRES_REVIEW" ? "Reconcile with this override" : "Reconcile"}</Btn> : null}
                  {row.student_id && row.reason_code === "POSSIBLE_RELABEL" ? <Btn kind="secondary" disabled={busy || !reason.trim()} onClick={() => void act("relabel")}>Relabel the school-fees row as the GST fee</Btn> : null}
                  <Btn kind="urgent" disabled={busy || !reason.trim()} onClick={() => void act("reject")}>Reject</Btn>
                </div>
                <div className="sub2 mt-1">Match: the student the old payment belongs to, verified. Reconcile: the payment goes onto the ledger as a confirmed GST reference for that student and session, dated when it was paid; a review finding (amount, fee not stated) needs your override reason. Relabel: the same money already sits on the ledger as school fees from the old portal — it becomes the GST fee instead. Reject: it establishes nothing.</div>
              </PBody>
            </Panel>
          ) : null}
          {row.override_reason ? <div className="sub2 mt-1">Resolved {whenAt(row.resolved_at)} by {row.resolved_office ?? "the office"}: {row.override_reason}</div> : null}
          <details className="mt-2"><summary className="sub2">The row as the old portal exported it</summary><pre className="sub2" style={{ whiteSpace: "pre-wrap" }}>{JSON.stringify(d.raw, null, 1)}</pre></details>
        </>
      )}
    </Modal>
  );
}

export function LegacyGst({ data, canAct, initialTab }: { data: LegacySummaryPage; canAct: boolean; initialTab?: Tab }) {
  const router = useRouter();
  const go = useQueryNav();
  const [tab, setTab] = useState<Tab>(initialTab ?? "overview");
  const [busy, setBusy] = useState(false);
  const [phase, setPhase] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const [grid, setGrid] = useState<{ header: string[]; rows: string[][] } | null>(null);
  const [mapping, setMapping] = useState<Record<string, number>>({});
  const [session, setSession] = useState<string>(data.session ?? "");
  const [imp, setImp] = useState<ImportView | null>(null);
  const [show, setShow] = useState<string>("ALL");
  const [open, setOpen] = useState<string | null>(null);
  const [filters, setFilters] = useState({ status: "OPEN", code: "", session: data.session ?? "", q: "" });
  const [page, setPage] = useState(1);
  const [list, setList] = useState<RowsPage | null>(null);
  const s = data.summary;
  const variance = Number(s.variance);
  const missingRequired = LEGACY_FIELDS.filter((f) => f.required && mapping[f.key] === undefined && !(f.key === "session" && session));

  const rowsIn = (): LegacyRow[] => (grid ? legacyRowsOf([grid.header, ...grid.rows], 0, mapping, { session }) : []);

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
    setPhase(`${dryRun ? "Dry run" : "Staging"}: ${rows.length} rows matched to students, validated against each session's fee and the ledger, checked for duplicates…`);
    try {
      const j = await post<ImportView>("/imports", { rows, fileName, session: session || null, dryRun }, `${dryRun ? "Dry run of" : "Stage"} ${rows.length} old-portal GST payments from ${fileName ?? "a file"}`);
      if (j) { setImp(j); setShow("ALL"); if (!dryRun) router.refresh(); }
    } finally { setBusy(false); setPhase(null); }
  }

  async function apply(id: string) {
    setBusy(true); setPhase("Applying: validated again, written to the ledger, linked…");
    try {
      const j = await post<ImportView>(`/imports/${id}/apply`, {}, `Apply old-portal GST reconciliation ${imp?.import.reference ?? id}`);
      if (j) { setImp(j); notify(`${num(j.applied?.reconciled)} payment${j.applied?.reconciled === 1 ? "" : "s"} reconciled onto the ledger (${naira(j.applied?.amount)})`); router.refresh(); }
    } finally { setBusy(false); setPhase(null); }
  }

  const loadList = useCallback(async () => {
    const p = new URLSearchParams();
    for (const [k, v] of Object.entries(filters)) if (v) p.set(k, v);
    p.set("page", String(page)); p.set("size", "100");
    const r = await fetch(`/api/bff/api/v1/finance/legacy-gst/rows?${p.toString()}`);
    const j = await r.json().catch(() => null);
    if (!r.ok) { setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
    setList(j as RowsPage);
  }, [filters, page]);
  useEffect(() => { if (tab !== "queue" && tab !== "search") return; const t = window.setTimeout(() => void loadList(), filters.q ? 300 : 0); return () => window.clearTimeout(t); }, [tab, loadList, filters.q]);

  async function exportReport(kind: "xlsx" | "pdf", scope: { importId?: string; status?: string; title: string; file: string }) {
    setBusy(true);
    try {
      const p = new URLSearchParams();
      if (scope.importId) p.set("importId", scope.importId);
      if (scope.status) p.set("status", scope.status);
      if (filters.session) p.set("session", filters.session);
      const r = await fetch(`/api/bff/api/v1/finance/legacy-gst/report?${p.toString()}`);
      const rows = (await r.json()) as LegacyRowView[];
      if (!r.ok) throw new Error((rows as unknown as Problem).title ?? r.statusText);
      const body = rows.map(reportRow);
      const sub = `${filters.session || "every session"} · ${rows.length} row${rows.length === 1 ? "" : "s"}`;
      if (kind === "xlsx") downloadBlob(await brandedXlsx(scope.title, REPORT_HEAD, body, { sheetName: "Reconciliation", serial: docSerial("GSTREC"), sub }), scope.file);
      else brandedPrint(scope.title, sub, REPORT_HEAD, body);
    } catch (e) { notifyProblem({ status: 500, title: "The report could not be built", detail: e instanceof Error ? e.message : String(e) }); }
    finally { setBusy(false); }
  }

  const importRows = imp ? imp.rows.filter((r) => show === "ALL" || r.status === show) : [];
  const sessionsHref = (ses: string) => { const p = new URLSearchParams(); if (ses) p.set("session", ses); return `/finance/legacy-gst?${p.toString()}`; };

  return (
    <>
      <PageHead title="Old GST Payments — reconciliation" description="A verified GST payment made on the old portal is a real payment. It is staged here as the old portal recorded it, matched to the current student by strong identifiers only, validated against the GST fee the Bursar stated for that session and against the ledger, and — on your word — written to the same ledger as a confirmed GST reference carrying the old reference and date. The entitlement, the registration gate, the CBT eligibility and every dashboard then read it; nobody is asked to pay again, and nothing is flipped by hand."
        actions={<span className="row row--inline row--tight">
          <label htmlFor="lg-session" className="sub2">Session</label>
          <select id="lg-session" className="ctl" value={data.session ?? ""} onChange={(e) => go(sessionsHref(e.target.value))}><option value="">Every session</option>{data.sessions.filter((x) => x.session).map((x) => <option key={x.session as string} value={x.session as string}>{x.session}</option>)}{data.fees.filter((f) => !data.sessions.some((x) => x.session === f.session)).map((f) => <option key={f.session} value={f.session}>{f.session}</option>)}</select>
        </span>} />
      {variance !== 0 && Number(s.gst_rows) > 0 ? (
        <Note kind="bad" title={`RECONCILIATION REQUIRED · variance ${naira(variance)}`}>Successful old-portal GST payments total {naira(s.legacy_successful_amount)}; {naira(s.reconciled_amount)} is on the ledger. The difference is in the queue: {num(s.requires_review)} requiring review, {num(s.unmatched)} unmatched, {num(s.duplicates)} duplicates, {num(s.rejected)} rejected, {num(s.matched)} matched but not yet applied. The migration is not complete until every one is accounted for.</Note>
      ) : Number(s.gst_rows) > 0 ? <Note kind="ok" title="Totals agree">Every successful old-portal GST payment staged for {data.session ?? "every session"} is either on the ledger or accounted for as a duplicate or a rejection.</Note> : null}
      {!data.fees.length ? <Note kind="bad" title="No GST fee is stated for any session">A payment&rsquo;s amount is judged against the fee the Bursar stated for the session it was paid in. State the fee of each session on Fee Setup → GST fee before applying; until then every row waits with &ldquo;no fee stated for the session&rdquo;.</Note> : null}
      <Tiles items={[
        ["LEGACY RECORDS", num(s.legacy_rows), null, `${num(s.gst_rows)} of a GST type · ${num(s.successful)} successful · ${num(s.failed)} not`],
        ["RECONCILED", num(s.reconciled), "var(--green-ink)", `${num(s.reconciled_students)} students entitled from the old portal`],
        ["MATCHED, NOT APPLIED", num(s.matched), s.matched ? "var(--chrome)" : null, "Validated; awaiting apply"],
        ["REQUIRES REVIEW", num(s.requires_review), s.requires_review ? "var(--red-ink)" : null, "An officer decides"],
        ["UNMATCHED", num(s.unmatched), s.unmatched ? "var(--red-ink)" : null, "No reliable student"],
        ["DUPLICATES · REJECTED", `${num(s.duplicates)} · ${num(s.rejected)}`, null, "Already entitled · failed, reversed, wrong type"],
        ["LEGACY SUCCESSFUL AMOUNT", naira(s.legacy_successful_amount), null, `${naira(s.legacy_amount)} in all`],
        ["RECONCILED AMOUNT", naira(s.reconciled_amount), variance === 0 ? "var(--green-ink)" : "var(--red-ink)", `Variance ${naira(variance)}`],
      ]} />
      <Tabs label="Reconciliation" value={tab} onChange={setTab} items={[
        { id: "overview", label: "Overview" }, { id: "upload", label: "Upload & apply" }, { id: "queue", label: "Exception queue", count: num(Number(s.requires_review) + Number(s.unmatched)) },
        { id: "search", label: "Search" }, { id: "imports", label: "Imports", count: num(data.imports.length) },
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {phase ? <Note kind="info" title="Working…">{phase}</Note> : null}

      {tab === "overview" ? (
        <>
          <div className="grid grid--2">
            <Panel title="Exceptions by category" right={<Btn kind="ghost" size="sm" disabled={busy} onClick={() => void exportReport("xlsx", { status: "OPEN", title: "GST/EPS Payment Exception Report", file: "gst-legacy-exceptions.xlsx" })}>Exception report</Btn>}>
              {data.exceptions.length ? <DTable cols={["Status|mid", "Category", "Rows|num", "Amount|num", "|num"]} rows={data.exceptions.map((x, i) => [
                <Pil key="s" kind={(STATUS_WORD[x.status] ?? ["", "grey"])[1]}>{(STATUS_WORD[x.status] ?? [x.status])[0]}</Pil>, <b key="c">{CODE_WORD[x.code] ?? x.code ?? "—"}</b>,
                <span key="n" className="tnum">{num(x.n)}</span>, <span key="a" className="tnum">{naira(x.amount)}</span>,
                <Btn key={`o${i}`} kind="ghost" size="sm" onClick={() => { setFilters({ ...filters, status: x.status, code: x.code }); setPage(1); setTab("search"); }}>Open</Btn>])} /> : <PBody><div className="sub2">No exception.</div></PBody>}
            </Panel>
            <Panel title="Counts that must agree">
              <PBody><KvGrid cls="grid--2" pairs={[
                ["Legacy successful GST payments", num(s.gst_rows ? s.successful : 0)], ["Reconciled onto the ledger", num(s.reconciled)],
                ["Legacy unique paying students", num(s.legacy_students)], ["Students entitled from the old portal", num(s.reconciled_students)],
                ["Legacy successful amount", naira(s.legacy_successful_amount)], ["Reconciled amount", naira(s.reconciled_amount)],
                ["Variance", <b key="v" className={variance ? "ink-red" : "ink-green"}>{naira(variance)}</b>], ["Students entitled in all (any source)", num(s.entitled_students)],
              ]} />
              <div className="sub2 mt-1">A record counts as reconciled only when a confirmed GST reference carries it on the ledger. Duplicates, rejections and the queue explain every naira of the variance.</div></PBody>
            </Panel>
          </div>
          <div className="grid grid--2">
            <Panel title="By session">
              {data.sessions.length ? <DTable cols={["Session|mid", "Rows|num", "Reconciled|num", "Open|num", "Successful amount|num", "|num"]} rows={data.sessions.map((x) => [
                <span key="s" className="tnum">{x.session ?? "no session"}</span>, <span key="r" className="tnum">{num(x.rows)}</span>, <span key="c" className="tnum ink-green">{num(x.reconciled)}</span>, <span key="o" className={`tnum${x.open ? " ink-red" : ""}`}>{num(x.open)}</span>, <span key="a" className="tnum">{naira(x.amount)}</span>,
                <LinkBtn key="l" kind="ghost" size="sm" href={sessionsHref(x.session ?? "")}>Open</LinkBtn>])} /> : <PBody><div className="sub2">Nothing staged yet. Upload the old portal&rsquo;s GST payment export.</div></PBody>}
            </Panel>
            <Panel title="GST fee stated per session" right={<LinkBtn kind="ghost" size="sm" href="/finance/fees">Fee Setup</LinkBtn>}>
              {data.fees.length ? <DTable cols={["Session|mid", "Fee|num", "Scope"]} rows={data.fees.map((f, i) => [<span key={`s${i}`} className="tnum">{f.session}</span>, <span key={`a${i}`} className="tnum">{naira(f.amount)}</span>, <span key={`c${i}`} className="sub2">{[f.level ? `${f.level} Level` : null, f.entry_mode, f.faculty_code, f.programme_code].filter(Boolean).join(" · ") || "Every student"}</span>])} /> : <PBody><div className="sub2">None stated.</div></PBody>}
            </Panel>
          </div>
          <Panel title="Reports" right={<span className="row row--inline row--tight"><Btn kind="secondary" size="sm" disabled={busy} onClick={() => void exportReport("xlsx", { title: "GST/EPS Legacy Payment Reconciliation Report", file: "gst-legacy-reconciliation.xlsx" })}>Reconciliation report (Excel)</Btn><Btn kind="ghost" size="sm" disabled={busy} onClick={() => void exportReport("pdf", { title: "GST/EPS Legacy Payment Reconciliation Report", file: "" })}>PDF</Btn></span>}>
            <PBody><div className="sub2">The reconciliation report lists every staged payment with its legacy reference, the student it was matched to and how, its validation, the ledger reference it became, who reconciled it and when. The exception report lists what still waits, by category.</div></PBody>
          </Panel>
        </>
      ) : null}

      {tab === "upload" ? (
        <>
          <Panel title="Old-portal GST payment export" right={canAct ? <label className={`btn btn--primary btn--sm${busy ? " is-disabled" : ""}`} style={{ cursor: busy ? "default" : "pointer" }}>Upload Excel / CSV<input type="file" accept=".xlsx,.xls,.csv" style={{ display: "none" }} disabled={busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void readFile(f); e.target.value = ""; }} /></label> : <span className="sub2">The Bursary stages and applies</span>}>
            <PBody>
              <div className="sub2">Columns read by name: transaction id, payment reference, gateway and its reference, the old portal&rsquo;s student id, matriculation number, JAMB number, application number, name, payment type, amount, payment date, session, semester, status. A row needs a transaction id or a reference of its own. Nothing is read as paid unless the old portal says it succeeded; nothing is matched by name.</div>
              <div className="row row--inline row--tight mt-2"><Field id="lg-ses" label="Session for rows that name none" hint="YYYY/YYYY; a row's own session wins"><input id="lg-ses" className="ctl" style={{ maxWidth: 140 }} value={session} onChange={(e) => setSession(e.target.value)} placeholder="2025/2026" /></Field></div>
            </PBody>
          </Panel>
          {grid ? (
            <Panel title={`${fileName} · ${num(grid.rows.length)} rows · columns mapped`} right={canAct ? <span className="row row--inline row--tight"><Btn kind="secondary" disabled={busy || missingRequired.length > 0} onClick={() => void stage(true)}>Dry run</Btn><Btn kind="go" disabled={busy || missingRequired.length > 0} onClick={() => void stage(false)}>Stage {num(rowsIn().length)} rows</Btn></span> : null}>
              <PBody>
                {missingRequired.length ? <Note kind="bad" title="A required column is not mapped">{missingRequired.map((f) => f.label).join(", ")}: choose the column, or give the session above.</Note> : null}
                <div className="grid grid--4">
                  {LEGACY_FIELDS.map((f) => (
                    <Field key={f.key} id={`lg-${f.key}`} label={f.label} required={f.required}>
                      <select id={`lg-${f.key}`} className="ctl" value={mapping[f.key] ?? ""} onChange={(e) => { const m = { ...mapping }; if (e.target.value === "") delete m[f.key]; else m[f.key] = Number(e.target.value); setMapping(m); }}>
                        <option value="">— not in the file —</option>
                        {grid.header.map((h, i) => <option key={i} value={i}>{h || `Column ${i + 1}`}</option>)}
                      </select>
                    </Field>
                  ))}
                </div>
                <div className="sub2 mt-2">A dry run matches and validates without writing anything and shows the counts you would get; staging keeps the rows and their judgements on the record so the queue can be worked, and still writes nothing to the ledger until you apply.</div>
              </PBody>
            </Panel>
          ) : null}
          {imp ? (
            <Panel title={`${imp.dryRun ? "Dry run" : imp.import.reference} · ${imp.import.file_name ?? ""}`} right={<span className="row row--inline row--tight">
              <select className="ctl" value={show} onChange={(e) => setShow(e.target.value)}>
                <option value="ALL">Every row ({num(imp.total)})</option><option value="MATCHED">Would reconcile ({num(imp.summary.matched)})</option><option value="RECONCILED">Reconciled ({num(imp.summary.reconciled)})</option>
                <option value="REQUIRES_REVIEW">Requires review ({num(imp.summary.requires_review)})</option><option value="UNMATCHED">Unmatched ({num(imp.summary.unmatched)})</option><option value="DUPLICATE">Duplicate ({num(imp.summary.duplicates)})</option><option value="REJECTED">Rejected / invalid ({num(imp.summary.rejected)})</option>
              </select>
              {canAct && !imp.dryRun && imp.import.status === "STAGED" && Number(imp.summary.matched) > 0 ? <Btn kind="go" disabled={busy} onClick={() => void apply(imp.import.id)}>Apply reconciliation: {num(imp.summary.matched)} onto the ledger</Btn> : null}
              {canAct && imp.dryRun ? <Btn kind="go" disabled={busy} onClick={() => void stage(false)}>Stage these rows</Btn> : null}
            </span>}>
              <Tiles items={[
                ["ROWS", num(imp.staging?.total_rows ?? imp.total), null, `${num(imp.staging?.staged ?? imp.total)} staged · ${num(imp.staging?.already_staged ?? 0)} already staged · ${num(imp.staging?.skipped ?? 0)} without an id`],
                [imp.dryRun ? "WOULD RECONCILE" : imp.import.status === "APPLIED" ? "RECONCILED" : "WILL RECONCILE", num(imp.import.status === "APPLIED" ? imp.summary.reconciled : imp.summary.matched), "var(--green-ink)", naira(imp.import.status === "APPLIED" ? imp.summary.reconciled_amount : imp.applied?.amount ?? imp.summary.legacy_successful_amount)],
                ["REQUIRES REVIEW", num(imp.summary.requires_review), imp.summary.requires_review ? "var(--red-ink)" : null, "Amount, fee or same money as school fees"],
                ["UNMATCHED", num(imp.summary.unmatched), imp.summary.unmatched ? "var(--red-ink)" : null, "No reliable student"],
                ["DUPLICATE", num(imp.summary.duplicates), null, "Entitlement already held"],
                ["REJECTED / INVALID", num(imp.summary.rejected), null, "Failed, reversed, wrong type, no session"],
              ]} cls="grid--6" />
              {imp.dryRun ? <PBody><Note kind="info" title="Nothing was written">This was a dry run: the counts above are what staging would produce; no row, no judgement and no ledger entry was kept.</Note></PBody> : null}
              {imp.applied ? <PBody><Note kind="ok" title={`${num(imp.applied.reconciled)} payment${imp.applied.reconciled === 1 ? "" : "s"} on the ledger · ${naira(imp.applied.amount)}`}>Each is a confirmed GST reference for its student and session, channel Legacy, carrying the old-portal reference and the original payment date. The students&rsquo; GST &amp; EPS screens, the registration gate, the CBT eligibility and the dashboards read it at once.{imp.applied.duplicates ? ` ${num(imp.applied.duplicates)} became duplicates at the moment of writing.` : ""}</Note></PBody> : null}
              <RowsTable rows={importRows} onOpen={(r) => { if (!imp.dryRun) setOpen(r.id); }} />
            </Panel>
          ) : null}
        </>
      ) : null}

      {tab === "queue" || tab === "search" ? (
        <>
          <Panel title={tab === "queue" ? "Exception queue — an officer decides" : "Search the staged payments"} right={<span className="row row--inline row--tight"><Btn kind="secondary" size="sm" disabled={busy} onClick={() => void exportReport("xlsx", { status: filters.status === "OPEN" ? "OPEN" : filters.status || undefined, title: tab === "queue" ? "GST/EPS Payment Exception Report" : "GST/EPS Legacy Payment Reconciliation Report", file: tab === "queue" ? "gst-legacy-exceptions.xlsx" : "gst-legacy-reconciliation.xlsx" })}>Excel</Btn></span>}>
            <PBody>
              <div className="grid grid--4">
                <Field id="lq-status" label="Status"><select id="lq-status" className="ctl" value={filters.status} onChange={(e) => { setFilters({ ...filters, status: e.target.value }); setPage(1); }}>
                  <option value="OPEN">Requires review + unmatched</option><option value="">Every status</option>{Object.entries(STATUS_WORD).map(([k, w]) => <option key={k} value={k}>{w[0]}</option>)}</select></Field>
                <Field id="lq-code" label="Category"><select id="lq-code" className="ctl" value={filters.code} onChange={(e) => { setFilters({ ...filters, code: e.target.value }); setPage(1); }}><option value="">Every category</option>{Object.entries(CODE_WORD).map(([k, w]) => <option key={k} value={k}>{w}</option>)}</select></Field>
                <Field id="lq-session" label="Session"><input id="lq-session" className="ctl" value={filters.session} onChange={(e) => { setFilters({ ...filters, session: e.target.value }); setPage(1); }} placeholder="Every session" /></Field>
                <Field id="lq-q" label="Search" hint="Legacy reference, transaction id, gateway reference, matric, JAMB, application number, name, ledger reference or amount"><input id="lq-q" className="ctl" value={filters.q} onChange={(e) => { setFilters({ ...filters, q: e.target.value }); setPage(1); }} /></Field>
              </div>
            </PBody>
          </Panel>
          <Panel title={`${list ? num(list.total) : "…"} payment${list?.total === 1 ? "" : "s"}`} right={list && list.total > list.size ? <span className="row row--inline row--tight sub2"><Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</Btn>Page {page} of {Math.ceil(list.total / list.size)}<Btn kind="ghost" size="sm" disabled={page * list.size >= list.total} onClick={() => setPage(page + 1)}>Next</Btn></span> : null}>
            {list ? (list.rows.length ? <RowsTable rows={list.rows} offset={(page - 1) * list.size} onOpen={(r) => setOpen(r.id)} /> : <PBody><div className="sub2">Nothing for these filters.</div></PBody>) : <PBody><div className="sub2">Loading…</div></PBody>}
          </Panel>
        </>
      ) : null}

      {tab === "imports" ? (
        <Panel title="Imports" right={<span className="sub2">Every run, its reference, who, the counts, and whether it was applied</span>}>
          {data.imports.length ? <DTable cols={["Reference", "File", "Uploaded", "Rows|num", "Staged|num", "Reconciled|num", "Review|num", "Unmatched|num", "Duplicate|num", "Rejected|num", "Amount|num", "Status|mid", "|num"]} rows={data.imports.map((i) => [
            <b key="r" className="tnum">{i.reference}</b>, <span key="f" className="sub2">{i.file_name ?? "—"}{i.session ? <div className="tnum">{i.session}</div> : null}</span>,
            <span key="u" className="sub2">{i.uploaded_by_name ?? i.uploader_office}<div className="tnum">{whenAt(i.uploaded_at)}</div></span>, <span key="t" className="tnum">{num(i.total_rows)}</span>, <span key="s" className="tnum">{num(i.staged)}</span>,
            <span key="c" className="tnum ink-green">{num(i.reconciled)}</span>, <span key="v" className={`tnum${Number(i.requires_review) ? " ink-red" : ""}`}>{num(i.requires_review)}</span>, <span key="n" className={`tnum${Number(i.unmatched) ? " ink-red" : ""}`}>{num(i.unmatched)}</span>,
            <span key="d" className="tnum">{num(i.duplicates)}</span>, <span key="j" className="tnum">{num(i.rejected)}</span>, <span key="a" className="tnum">{naira(i.reconciled_amount)}</span>,
            <Pil key="st" kind={i.status === "APPLIED" ? "ok" : "warn"}>{i.status === "APPLIED" ? `Applied ${dayOf(i.applied_at)}` : "Staged"}</Pil>,
            <span key="o" className="row row--inline row--tight">{canAct && i.status === "STAGED" && Number(i.matched) > 0 ? <Btn kind="go" size="sm" disabled={busy} onClick={() => void apply(i.id)}>Apply {num(i.matched)}</Btn> : null}<Btn kind="ghost" size="sm" onClick={() => { setFilters({ status: "", code: "", session: "", q: i.reference }); setPage(1); setTab("search"); }}>Rows</Btn><Btn kind="ghost" size="sm" disabled={busy} onClick={() => void exportReport("xlsx", { importId: i.id, title: `GST/EPS Legacy Payment Reconciliation Report · ${i.reference}`, file: `${i.reference.replace(/\//g, "-")}.xlsx` })}>Report</Btn></span>,
          ])} /> : <PBody><div className="sub2">No import yet.</div></PBody>}
        </Panel>
      ) : null}

      {open ? <RowModal id={open} canAct={canAct} onClose={() => setOpen(null)} onChanged={() => { void loadList(); router.refresh(); }} /> : null}
    </>
  );
}
