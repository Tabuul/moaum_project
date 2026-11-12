"use client";

/**
 * Old-portal transfers (V727). The old portal's inter-departmental transfer payments of the current exercise — the form, the
 * provisional letter and the transfer, which count toward the one fee the Bursary states — each read on the student's own record and
 * counted toward their application, awaiting one, used by a transfer the old portal approved and this portal restored, or unmatched
 * with the reason; a payment once counted toward an application stays with it, whatever became of it. An officer of the Academic
 * Office, the Registry, the Bursary or ICT decides any of them (count it toward one of the student's applications, not counted,
 * reject, or release a decision back to the rule), with a reason, and re-runs the reconciliation. The scope says from which date the payments count and which
 * items. The old portal's applications come in from its export: read here as the other uploads are, checked row by row, then
 * loaded (the rows that can be loaded alone, if asked). The loads and the reconciliation report are read from the records as they
 * stand, never estimated. Nothing here moves money or re-posts a payment.
 */
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { roleLabel } from "@/lib/offices";
import { csvRows, xlsxRows } from "@/lib/xlsx";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil, RoleLine, Tabs, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import {
  CHECK_WORDS, DECISIONS, DECISION_WORDS, ITEM_KIND_WORDS, LEGACY_STATUSES, LEGACY_STATUS_WORDS, LIVE_STATES, countBy, leftOut, naira, readLegacyTransferSheet, snakeKeys,
  type Decision, type LegacyRow,
} from "@/lib/transfer-fees";

const BASE = "/api/bff/api/v1/transfers/legacy";
/** who decides a payment, re-runs the reconciliation and states the scope (people.decide_legacy_transfer_payment) */
const DECIDERS = ["academic", "registrar", "dregistrar", "bursar", "ict", "super"];
/** who loads the old portal's applications (people.legacy_transfer_upload_commit) */
const LOADERS = ["academic", "registrar", "dregistrar", "ict", "super"];
const MAX_ROWS = 2000;

const vzNum = (n: number | string | null | undefined) => Number(n ?? 0).toLocaleString("en-GB");
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

export interface LegacyScope {
  countsFrom: string | null; setAt?: string | null; setBy?: string | null; setOffice?: string | null; reason?: string | null;
  items: { item: string; kind: string; counts: boolean; reason?: string | null }[];
}
export interface LegacyLoad {
  id: string; filename: string | null; rows_read: number; loaded: number; attached: number; left_out: number; committed_at: string; committed_office: string | null;
  committed_by_name?: string | null;
}
export type LegacyReport = Record<string, number | string | null | Record<string, number>>;

interface CheckRow { row_no: number; legacy_ref: string | null; matric_no: string | null; student_id: string | null; to_programme_code: string | null; stage: string | null;
  session: string | null; status: string; reason: string | null; application_id: string | null; name?: string | null; from_programme?: string | null; to_programme?: string | null }
interface CommitRow { row_no: number; legacy_ref: string | null; status: string; reason: string | null; application_id: string | null; linked_payments: number | null }
interface Commit { loadId: string; rows: CommitRow[]; loaded: number; attached: number; leftOut: number }
/** a transfer application of the student (GET /transfers) a payment may be counted toward */
interface Application { id: string; student_id: string; to_programme: string; state: string; stageLabel?: string; session: string; applied_at: string; legacy_ref?: string | null }

const STAGE_WORDS: Record<string, string> = { APPLIED: "Applied", FROM_OK: "Current HOD approved", TO_OK: "New HOD approved", REG_OK: "Registry approved" };
/** an application's state as the desk words it */
const APP_STATE: Record<string, string> = {
  APPLIED: "With current department", FROM_OK: "With new department", TO_OK: "With Registrar", REG_OK: "With Academic office", RECOMMENDED: "Recommended",
  APPROVED: "Approved", EFFECTED: "Completed", DECLINED: "Declined", WITHDRAWN: "Withdrawn", NOT_RECOMMENDED: "Not recommended",
};
const appState = (r: LegacyRow) => { const st = r.application_state ?? r.state; return st ? APP_STATE[st] ?? st : null; };
/** the applications a payment cannot be counted toward (people.decide_legacy_transfer_payment: LEGACY_TRANSFER_CLOSED) */
const CLOSED_STATES = ["DECLINED", "WITHDRAWN", "NOT_RECOMMENDED"];

/** a figure that applies itself when chosen */
function Door({ label, n, sub, on, onClick, colour }: { label: string; n: string; sub: string; on: boolean; onClick: () => void; colour?: string }) {
  return (
    <button type="button" className="tile stat-tile" onClick={onClick} aria-pressed={on}
      style={{ textAlign: "left", font: "inherit", border: on ? "2px solid var(--chrome)" : undefined }}>
      <div className="eyebrow">{label}</div>
      <div className="n tnum" style={colour ? { color: colour } : undefined}>{n}</div>
      <div className="c">{sub}</div>
    </button>
  );
}

const rec = (v: unknown): Record<string, number> => (v && typeof v === "object" ? (v as Record<string, number>) : {});
const figure = (r: LegacyReport | null, k: string): number => Number((r?.[k] as number | string | null | undefined) ?? 0);

export function OldPortalTransfers({ rows, counts, matching, status, search, initialTab, scope, scopeProblem, loads, loadsProblem, report, reportProblem, actingOffice }: {
  /** matching: how many rows the status and search select (the list sends the first of them) */
  rows: LegacyRow[]; counts: Record<string, number>; matching: number; status: string; search: string; initialTab: string;
  scope: LegacyScope | null; scopeProblem: Problem | null; loads: LegacyLoad[] | null; loadsProblem: Problem | null;
  report: LegacyReport | null; reportProblem: Problem | null; actingOffice: string | null;
}) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const o = actingOffice ?? "";
  const mayDecide = DECIDERS.includes(o);
  const mayLoad = LOADERS.includes(o);
  const [tab, setTab] = useState<"payments" | "upload" | "loads" | "report" | "scope">(
    (["payments", "upload", "loads", "report", "scope"] as const).find((t) => t === initialTab) ?? "payments");
  const [q, setQ] = useState(search);
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  // the decision
  const [open, setOpen] = useState<LegacyRow | null>(null);
  const [decision, setDecision] = useState<Decision>("LINK");
  const [appId, setAppId] = useState("");
  const [note, setNote] = useState("");
  const [apps, setApps] = useState<Application[] | null>(null);

  // the scope
  const [from, setFrom] = useState(scope?.countsFrom?.slice(0, 10) ?? "");
  const [scopeWhy, setScopeWhy] = useState("");

  // the upload
  const [file, setFile] = useState<string | null>(null);
  const [sheet, setSheet] = useState<{ rows: Record<string, string>[]; lines: number[] } | null>(null);
  const [checked, setChecked] = useState<CheckRow[] | null>(null);
  const [partial, setPartial] = useState(false);
  const [done, setDone] = useState<Commit | null>(null);

  const total = Object.values(counts).reduce((a, b) => a + (Number(b) || 0), 0);
  const line = (n: number) => sheet?.lines[n - 1] ?? n;
  const checkCounts = useMemo(() => countBy(checked ?? []), [checked]);
  const bad = (checked ?? []).filter((r) => leftOut(r.status)).length;
  const loadable = (checked ?? []).filter((r) => r.status === "NEW" || r.status === "ATTACH").length;

  async function call<T>(path: string, method: "GET" | "POST" | "PUT", body: unknown, reason: string | null, key: string): Promise<T | null> {
    setBusy(key);
    setProblem(null);
    try {
      const headers: Record<string, string> = {};
      if (body !== undefined) headers["Content-Type"] = "application/json";
      if (reason) headers["X-Reason"] = reasonHeader(reason);
      const r = await fetch(`${BASE}${path}`, { method, cache: "no-store", headers, body: body === undefined ? undefined : JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        const p = (j ?? { status: r.status, title: r.statusText }) as Problem;
        setProblem(p);
        notifyProblem(p);
        return null;
      }
      // an answer with no body is a success too
      return (j ?? {}) as T;
    } catch {
      const p: Problem = { status: 0, title: "The portal could not be reached. Check the connection and try again." };
      setProblem(p);
      notifyProblem(p);
      return null;
    } finally {
      setBusy(null);
    }
  }

  const filterTo = (next: { status?: string; search?: string }) => {
    const p = new URLSearchParams();
    const s = next.status ?? status;
    const t = next.search ?? search;
    if (s) p.set("status", s);
    if (t) p.set("search", t);
    queryNav(`/transfers/old-portal${p.toString() ? `?${p}` : ""}`);
  };

  async function rerun() {
    const j = await call<{ statuses?: Record<string, number> }>("/reconcile", "POST", {}, "Old-portal transfer payments reconciled again", "rerun");
    if (!j) return;
    const parts = Object.entries(j.statuses ?? {}).map(([k, n]) => `${LEGACY_STATUS_WORDS[k]?.[0] ?? k}: ${n}`);
    setSaid(`Reconciled again${parts.length ? ` — ${parts.join(" · ")}` : ""}`);
    notify("The old portal's transfer payments reconciled again");
    router.refresh();
  }

  async function startDecision(r: LegacyRow) {
    setOpen(r);
    setDecision("LINK");
    // the application it counts toward while a payment may still be counted toward it, else the student's live one
    setAppId((r.application_id && !CLOSED_STATES.includes(r.application_state ?? "") ? r.application_id : null) ?? r.live_application_id ?? "");
    setNote("");
    if (apps === null) {
      try {
        const res = await fetch("/api/bff/api/v1/transfers", { cache: "no-store" });
        const j = await res.json().catch(() => null);
        setApps(res.ok ? ((j?.rows ?? []) as Application[]) : []);
      } catch {
        setApps([]);
      }
    }
  }

  const theirs = useMemo(() => (open && apps ? apps.filter((a) => a.student_id === open.student_id && !CLOSED_STATES.includes(a.state)) : []), [open, apps]);

  async function decide() {
    if (!open) return;
    const j = await call<{ status?: string }>(`/${open.payment_id}/decision`, "POST", { decision, application: decision === "LINK" ? appId || null : null, note: note.trim() },
      `Old-portal transfer payment ${open.payref ?? open.payment_id}: ${DECISION_WORDS[decision][0]} — ${note.trim()}`, "decide");
    if (!j) return;
    const now = j.status ? (LEGACY_STATUS_WORDS[j.status]?.[0] ?? j.status) : "decided";
    setSaid(`${open.name ?? open.matric_no ?? "The student"}'s payment ${open.payref ?? ""}: ${now}`);
    notify(`Decision recorded — ${now}`);
    setOpen(null);
    router.refresh();
  }

  async function saveScope() {
    const j = await call<unknown>("/scope", "PUT", { countsFrom: from, reason: scopeWhy.trim() }, `Old-portal transfer payments count from ${from}: ${scopeWhy.trim()}`, "scope");
    if (j === null) return;
    setScopeWhy("");
    setSaid(`Old-portal transfer payments now count from ${day(from)}; the list is reconciled again`);
    notify("The scope stated and the list reconciled again");
    router.refresh();
  }

  async function read(f: File) {
    setDone(null); setChecked(null); setSheet(null); setPartial(false); setProblem(null);
    let grid: string[][];
    try {
      grid = /\.csv$/i.test(f.name) ? csvRows(await f.text()) : await xlsxRows(await f.arrayBuffer());
    } catch {
      const p: Problem = { status: 400, title: "That file could not be read", detail: "Save the old portal's export as .xlsx or .csv and choose it again." };
      setProblem(p); notifyProblem(p); return;
    }
    const got = readLegacyTransferSheet(grid.map((r) => r.map((c) => String(c ?? ""))));
    setFile(f.name);
    if (got.problem) { const p: Problem = { status: 400, title: "That file could not be read", detail: got.problem }; setProblem(p); notifyProblem(p); return; }
    if (got.rows.length > MAX_ROWS) {
      const p: Problem = { status: 400, title: `The file has ${vzNum(got.rows.length)} rows`, detail: `Up to ${vzNum(MAX_ROWS)} rows are loaded at a time: split the file and load each part.` };
      setProblem(p); notifyProblem(p); return;
    }
    setSheet(got);
    const j = await call<{ rows?: Record<string, unknown>[] }>("/upload/check", "POST", { rows: got.rows }, `Old portal's transfer export checked (${f.name})`, "check");
    if (j) setChecked((j.rows ?? []).map((x) => snakeKeys<CheckRow>(x)));
  }

  async function commit() {
    if (!sheet || !checked) return;
    const j = await call<Commit>("/upload", "POST", { rows: sheet.rows, filename: file, partial },
      `Old portal's transfer applications loaded (${file ?? "file"}, ${sheet.rows.length} rows${partial ? ", the rows that can be loaded alone" : ""})`, "commit");
    if (!j) return;
    setDone({ ...j, rows: (j.rows ?? []).map((x) => snakeKeys<CommitRow>(x as unknown as Record<string, unknown>)) });
    notify(`${vzNum(j.loaded)} loaded as applications, ${vzNum(j.attached)} joined an application here, ${vzNum(j.leftOut)} left out`);
    router.refresh();
  }

  async function downloadList() {
    const head = ["Student", "Matric number", "Item", "Amount", "Paid on", "Old payment number", "Status", "Reason", "Application", "Decided"];
    const body = rows.map((r) => [r.name ?? "—", r.matric_no ?? "—", r.item, Number(r.amount), r.paid_on ?? "—", r.payref ?? "—",
      LEGACY_STATUS_WORDS[r.status]?.[0] ?? r.status, r.reason ?? "", r.application_id ? [r.to_programme, appState(r)].filter(Boolean).join(" · ") || "Linked" : "—",
      r.decided_at ? `${roleLabel(r.decided_office)} · ${day(r.decided_at)} · ${r.decided_note ?? ""}` : "By the rule"]);
    const blob = await brandedXlsx("OLD-PORTAL INTER-DEPARTMENTAL TRANSFER PAYMENTS", head, body, { sheetName: "Old-portal transfers", serial: docSerial("OPT"),
      sub: `${status ? LEGACY_STATUS_WORDS[status]?.[0] ?? status : "Every status"}${search ? ` · search "${search}"` : ""}`,
      meta: [["Status", status ? LEGACY_STATUS_WORDS[status]?.[0] ?? status : "Every status"], ["Search", search || "None"], ["Rows", vzNum(rows.length)]] });
    downloadBlob(blob, `old-portal-transfers${status ? `-${status.toLowerCase().replace(/_/g, "-")}` : ""}.xlsx`);
  }

  async function downloadReport() {
    if (!report) return;
    const lines: [string, string, string | number, string][] = REPORT_ROWS.map(([section, label, key, money, sub]) =>
      [section, label, money ? Number(report[key] ?? 0) : figure(report, key), subOf(sub, report)]);
    for (const [k, n] of Object.entries(rec(report.unmatchedByReason))) lines.push(["Unmatched payments by reason", k, Number(n), ""]);
    for (const [k, n] of Object.entries(rec(report.legacyUnmatchedByStatus))) lines.push(["Old-portal applications not loaded", CHECK_WORDS[k]?.[0] ?? k, Number(n), ""]);
    const blob = await brandedXlsx("OLD-PORTAL TRANSFER RECONCILIATION REPORT", ["Section", "Figure", "Value", "What it means"], lines, { sheetName: "Reconciliation", serial: docSerial("OPR"),
      meta: [["Old-portal payments count from", report.countsFrom ? day(String(report.countsFrom)) : "—"], ["Transfer fee as stated now", report.fee == null ? "Not stated" : naira(report.fee as number)]] });
    downloadBlob(blob, "old-portal-transfer-reconciliation.xlsx");
  }

  return (
    <>
      <PageHead title="Old-portal transfers"
        description={`Inter-departmental transfer payments made on the old portal${scope?.countsFrom ? ` from ${day(scope.countsFrom)}` : ""}, each counted toward the student's application here, waiting for one, or unmatched with the reason; and the old portal's applications, loaded from its export. A payment counts once, toward one application, as the Bursary's fee stands now; nothing here moves money.`}
        actions={<LinkBtn kind="ghost" href="/transfers/fees">Transfer fees</LinkBtn>} />
      <RoleLine allowed={DECIDERS.filter((x) => x !== "super")} actingOffice={actingOffice} canAct={mayDecide} action="Deciding old-portal transfer payments" />
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Tabs look="line" label="Old-portal transfers" value={tab} onChange={setTab} items={[
        { id: "payments", label: "Payments", count: total || undefined },
        { id: "upload", label: "Load the old portal's applications" },
        { id: "loads", label: "Loads", count: loads?.length || undefined },
        { id: "report", label: "Reconciliation report" },
        { id: "scope", label: "Scope" },
      ]} />

      {tab === "payments" ? (
        <>
          <div className="grid grid--4" role="group" aria-label="Old-portal transfer payments by status">
            <Door label="Every payment" n={vzNum(total)} sub="Read from the old portal's records" on={!status} onClick={() => filterTo({ status: "" })} />
            {LEGACY_STATUSES.map((s) => (
              <Door key={s} label={LEGACY_STATUS_WORDS[s][0]} n={vzNum(counts[s] ?? 0)} sub={STATUS_SUB[s]} on={status === s}
                onClick={() => filterTo({ status: status === s ? "" : s })}
                colour={counts[s] ? (LEGACY_STATUS_WORDS[s][1] === "bad" ? "var(--red-ink)" : LEGACY_STATUS_WORDS[s][1] === "ok" ? "var(--green-ink)" : undefined) : undefined} />
            ))}
          </div>

          <div className="scope" aria-label="Filters">
            <div className="scope__f"><Field id="opt-status" label="Status">
              <select id="opt-status" className="ctl" value={status} onChange={(e) => filterTo({ status: e.target.value })}>
                <option value="">Every status</option>
                {LEGACY_STATUSES.map((s) => <option key={s} value={s}>{LEGACY_STATUS_WORDS[s][0]}{counts[s] ? ` (${counts[s]})` : ""}</option>)}
              </select>
            </Field></div>
            <div className="scope__f grow"><Field id="opt-q" label="Search">
              <form className="scope__search" onSubmit={(e) => { e.preventDefault(); filterTo({ search: q.trim() }); }}>
                <input id="opt-q" className="ctl" value={q} maxLength={80} onChange={(e) => setQ(e.target.value)} placeholder="Search by matriculation number, name or old payment number" />
                <Btn kind="primary" type="submit">Search</Btn>
                <Btn kind="ghost" onClick={() => { setQ(""); filterTo({ status: "", search: "" }); }}>Reset</Btn>
              </form>
            </Field></div>
          </div>

          <Panel title="Old-portal transfer payments" right={
            <span className="row row--inline row--tight">
              <span>{matching > rows.length ? `The first ${vzNum(rows.length)} of ${vzNum(matching)}` : `${vzNum(rows.length)} shown`}</span>
              {rows.length ? <Btn kind="ghost" size="sm" busyLabel="Preparing Excel…" onClick={() => downloadList()}>Download</Btn> : null}
              {mayDecide ? <Btn kind="secondary" size="sm" busy={busy === "rerun"} busyLabel="Reconciling…" disabled={busy !== null} onClick={() => void rerun()}>Re-run the reconciliation</Btn> : null}
            </span>}>
            {rows.length ? (
              <DTable cols={["Student", "Matric number", "Item", "Amount|num", "Paid on", "Old payment number", "Status", "Reason", "Application", "Decided", "|num"]} rows={rows.map((r) => [
                <Two key="s" a={r.name ?? "No student record"} b={r.programme ?? ""} />,
                <span key="m" className="tnum">{r.matric_no ?? "—"}</span>,
                <span key="i">{r.item}<div className="sub2">{ITEM_KIND_WORDS[r.item_kind] ?? r.item_kind}{r.session_label ? ` · ${r.session_label}` : ""}</div></span>,
                <span key="a" className="tnum">{naira(r.amount)}</span>,
                <span key="d" className="tnum sub2">{day(r.paid_on)}{r.channel ? <div className="sub2">{r.channel}</div> : null}</span>,
                <span key="p" className="tnum">{r.payref ?? "—"}{r.reference ? <div className="sub2">{r.reference}</div> : null}{r.archived ? <div><Pil kind="warn">Archived for review</Pil></div> : null}</span>,
                <span key="st"><Pil kind={LEGACY_STATUS_WORDS[r.status]?.[1] ?? "grey"}>{LEGACY_STATUS_WORDS[r.status]?.[0] ?? r.status}</Pil>
                  {r.match_method ? <div className="sub2">{MATCH_WORDS[r.match_method] ?? r.match_method}</div> : null}</span>,
                <span key="r" className="sub2">{r.reason ?? "—"}{r.moved_hint ? <div><Pil kind="warn">Moved before — a transfer or a swap</Pil></div> : null}</span>,
                <span key="ap" className="sub2">{r.application_id
                  ? <>{r.to_programme ? <b>{r.to_programme}</b> : "An application"}{appState(r) ? <div>{appState(r)}</div> : null}{r.legacy_ref ? <div className="tnum">{r.legacy_ref}</div> : null}</>
                  : "—"}</span>,
                <span key="dc" className="sub2">{r.decided_at ? <>{r.decided_by_name ?? roleLabel(r.decided_office)} · {day(r.decided_at)}{r.decided_note ? <div>{r.decided_note}</div> : null}</> : "By the rule"}</span>,
                mayDecide ? <Btn key="go" kind="ghost" size="sm" disabled={busy !== null} onClick={() => void startDecision(r)}>Decide</Btn> : <span key="go" />,
              ])} texts={rows.map((r) => `${r.name ?? ""} ${r.matric_no ?? ""} ${r.payref ?? ""} ${r.item} ${r.reason ?? ""}`)} />
            ) : <PBody><div className="sub2">No old-portal transfer payment matches{status || search ? " the filters" : ""}.</div></PBody>}
          </Panel>
          <div className="sub2">A payment is matched on the student&rsquo;s own record only: the record answers to the matriculation number the payment names, it carries an
            old-portal payment number, the record is active and no duplicate, it was paid on or after the date the scope states, and its item counts. A payment once
            counted toward an application stays with it, whatever became of the application (completed, declined or withdrawn) — an officer moves it with a decision.
            Otherwise it counts toward the application the old portal&rsquo;s export names it for, else the student&rsquo;s live application; one paid before a transfer
            the old portal approved and this portal restored is used by that transfer, never a credit for another; with none it waits for an application. An
            officer&rsquo;s decision is kept and the reconciliation never runs over it; released, the payment follows the rule again.</div>
        </>
      ) : null}

      {tab === "upload" ? (
        <>
          <Note kind="info" title="The old portal's transfer applications, continued here">
            Each row of the old portal&rsquo;s export becomes an application at the stage the old portal reached, in the current session — never a second one: a student
            with an application here has the old record joined to it, and the application moves on to the stage the old portal reached — with the old reference, the date
            applied, the approvals and documents kept as received. The payment numbers it names count toward it when they are the student&rsquo;s own. The file is
            checked first; nothing is written until you load it.
          </Note>
          {!mayLoad ? <Note kind="info" title="View only">The Academic Office, the Registry and ICT load the old portal&rsquo;s applications.</Note> : null}
          <Panel title="1 · Choose the old portal's export">
            <PBody>
              <div className="sub2 mb-3">Columns read by their headings, wherever the header row sits: the old reference (Reference, Application No), the Matriculation
                Number, the programme moved to (code or name), the programme left (optional), the stage reached (Applied, HOD, New HOD, Registry), the Session (optional:
                an application of the current exercise continues in the current session whatever the old portal&rsquo;s label), the date applied (day first; one before the
                date the scope states is left out), the Approvals, the Documents, the payment numbers (several, separated by commas) and the Reason. Up to
                {" "}{vzNum(MAX_ROWS)} rows at a time.</div>
              <label className={`btn btn--ghost btn--sm${!mayLoad || busy !== null ? " is-disabled" : ""}`} style={{ cursor: mayLoad ? "pointer" : "not-allowed" }}>
                {busy === "check" ? "Checking…" : "Choose the file (.xlsx or .csv)"}
                <input type="file" accept=".xlsx,.csv" style={{ display: "none" }} disabled={!mayLoad || busy !== null}
                  onChange={(e) => { const f = e.target.files?.[0]; if (f) void read(f); e.target.value = ""; }} />
              </label>
              {file ? <span className="sub2" style={{ marginLeft: 8 }}>{file}{sheet ? ` · ${vzNum(sheet.rows.length)} row${sheet.rows.length === 1 ? "" : "s"} read` : ""}</span> : null}
            </PBody>
          </Panel>

          {checked ? (
            <Panel title="2 · What each row would become" right={`${vzNum(checked.length)} row${checked.length === 1 ? "" : "s"} checked`}>
              <PBody>
                <Tiles cls="grid--4" items={[
                  ["Loaded as applications", vzNum(checkCounts.NEW ?? 0), checkCounts.NEW ? "var(--green-ink)" : null, "At the stage the old portal reached"],
                  ["Join an application here", vzNum(checkCounts.ATTACH ?? 0), checkCounts.ATTACH ? "var(--green-ink)" : null, "One application a student"],
                  ["Already loaded", vzNum(checkCounts.EXISTS ?? 0), null, "Left as they are"],
                  ["Cannot be loaded", vzNum(bad), bad ? "var(--red-ink)" : null, "Each with the reason below"],
                ]} />
              </PBody>
              <DTable cols={["Line|num", "Old reference", "Student", "From → To", "Stage", "Session", "Status", "Reason"]} rows={checked.map((r) => [
                <span key="n" className="tnum sub2">{line(r.row_no)}</span>,
                <span key="r" className="tnum">{r.legacy_ref ?? "—"}</span>,
                <Two key="m" a={r.name ?? "—"} b={r.matric_no ?? ""} />,
                <span key="t"><span className="sub2">{r.from_programme ?? "—"}</span><div><b>→ {r.to_programme ?? r.to_programme_code ?? "—"}</b></div></span>,
                <span key="s" className="sub2">{r.stage ? STAGE_WORDS[r.stage] ?? r.stage : "—"}</span>,
                <span key="se" className="tnum sub2">{r.session ?? "—"}</span>,
                <Pil key="st" kind={CHECK_WORDS[r.status]?.[1] ?? "grey"}>{CHECK_WORDS[r.status]?.[0] ?? r.status}</Pil>,
                <span key="w" className="sub2">{r.reason ?? ""}</span>,
              ])} texts={checked.map((r) => `${r.legacy_ref ?? ""} ${r.matric_no ?? ""} ${r.name ?? ""} ${r.status} ${r.reason ?? ""}`)} />
            </Panel>
          ) : null}

          {checked && mayLoad ? (
            <Panel title="3 · Load the applications">
              <PBody>
                {done ? (
                  <>
                    <Note kind={done.leftOut ? "info" : "ok"} title={`${vzNum(done.loaded)} loaded as applications · ${vzNum(done.attached)} joined an application here · ${vzNum(done.leftOut)} left out`}>
                      Each row is kept with what became of it, under the load in Loads. The old-portal payments the rows name count toward the applications now.
                    </Note>
                    <DTable cols={["Line|num", "Old reference", "Status", "Reason", "Payments counted|num"]} rows={done.rows.map((r) => [
                      <span key="n" className="tnum sub2">{line(r.row_no)}</span>,
                      <span key="r" className="tnum">{r.legacy_ref ?? "—"}</span>,
                      <Pil key="s" kind={CHECK_WORDS[r.status]?.[1] ?? "grey"}>{CHECK_WORDS[r.status]?.[0] ?? r.status}</Pil>,
                      <span key="w" className="sub2">{r.reason ?? ""}</span>,
                      <span key="p" className="tnum">{r.linked_payments ?? 0}</span>,
                    ])} />
                  </>
                ) : (
                  <>
                    {bad ? (
                      <label className="row row--tight" style={{ alignItems: "center", gap: 8 }}>
                        <input type="checkbox" className="chk" checked={partial} onChange={(e) => setPartial(e.target.checked)} />
                        <span>Load the rows that can be loaded; the {vzNum(bad)} that cannot are left out and kept with the reason</span>
                      </label>
                    ) : null}
                    <div className="row row--tight mt-2" style={{ gap: 8, alignItems: "center" }}>
                      <Btn kind="primary" busy={busy === "commit"} busyLabel="Loading…" disabled={busy !== null || !loadable || (bad > 0 && !partial)} onClick={() => void commit()}>
                        {`Load ${vzNum(loadable)} application${loadable === 1 ? "" : "s"}`}
                      </Btn>
                      <span className="sub2">{bad && !partial ? "Correct the rows that cannot be loaded and choose the file again, or load the others alone." : "Each row is checked again as it is loaded."}</span>
                    </div>
                  </>
                )}
              </PBody>
            </Panel>
          ) : null}
        </>
      ) : null}

      {tab === "loads" ? (
        loads ? (
          <Panel title="Loads of the old portal's export" right={`${vzNum(loads.length)} · the latest first`}>
            {loads.length ? (
              <DTable cols={["Loaded", "File", "Rows read|num", "Loaded|num", "Joined|num", "Left out|num", "By"]} rows={loads.map((l) => [
                <span key="w" className="tnum sub2">{when(l.committed_at)}</span>,
                <span key="f">{l.filename ?? "—"}</span>,
                <span key="r" className="tnum">{vzNum(l.rows_read)}</span>,
                <span key="l" className="tnum">{vzNum(l.loaded)}</span>,
                <span key="a" className="tnum">{vzNum(l.attached)}</span>,
                <span key="o" className="tnum">{vzNum(l.left_out)}</span>,
                <span key="b" className="sub2">{l.committed_by_name ?? roleLabel(l.committed_office)}</span>,
              ])} texts={loads.map((l) => `${l.filename ?? ""} ${l.committed_office ?? ""}`)} />
            ) : <PBody><div className="sub2">The old portal&rsquo;s export has not been loaded yet.</div></PBody>}
          </Panel>
        ) : loadsProblem ? <ProblemNotice problem={loadsProblem} /> : null
      ) : null}

      {tab === "report" ? (
        report ? (
          <>
            <div className="row row--between" style={{ alignItems: "center" }}>
              <div className="sub2">Read from the records as they stand. Old-portal payments count from {report.countsFrom ? <b>{day(String(report.countsFrom))}</b> : "—"};
                the fee as the Bursary states it now is <b>{report.fee == null ? "not stated" : naira(report.fee as number)}</b>.</div>
              <Btn kind="ghost" size="sm" busyLabel="Preparing Excel…" onClick={() => downloadReport()}>Download the report</Btn>
            </div>
            {SECTIONS.map((title) => {
              const figures = REPORT_ROWS.filter((x) => x[0] === title);
              return (
                <Panel key={title} title={title}>
                  <PBody>
                    <Tiles cls={gridFor(figures.length)} items={figures.map(([, label, key, money, sub]) =>
                      [label, money ? naira(report[key] as number) : vzNum(figure(report, key)), null, subOf(sub, report)] as [string, string, null, string])} />
                  </PBody>
                  {title === "Old-portal transfer payments" && Object.keys(rec(report.unmatchedByReason)).length ? (
                    <DTable noPrint cols={["Unmatched — the reason", "Payments|num"]} rows={Object.entries(rec(report.unmatchedByReason)).map(([k, n]) => [
                      <span key="k">{k}</span>, <span key="n" className="tnum">{vzNum(n)}</span>])} />
                  ) : null}
                  {title === "The old portal's applications" && Object.keys(rec(report.legacyUnmatchedByStatus)).length ? (
                    <DTable noPrint cols={["Not loaded — why", "Applications|num"]} rows={Object.entries(rec(report.legacyUnmatchedByStatus)).map(([k, n]) => [
                      <Pil key="k" kind={CHECK_WORDS[k]?.[1] ?? "grey"}>{CHECK_WORDS[k]?.[0] ?? k}</Pil>, <span key="n" className="tnum">{vzNum(n)}</span>])} />
                  ) : null}
                </Panel>
              );
            })}
          </>
        ) : reportProblem ? <ProblemNotice problem={reportProblem} /> : null
      ) : null}

      {tab === "scope" ? (
        scope ? (
          <>
            <Panel title="Which old-portal payments count" right={scope.setAt ? `Stated ${when(scope.setAt)}${scope.setBy || scope.setOffice ? ` by ${scope.setBy ?? roleLabel(scope.setOffice)}` : ""}` : undefined}>
              <PBody>
                <KvGrid cls="grid--2" pairs={[["Payments made from", scope.countsFrom ? day(scope.countsFrom) : "—"], ["Why", scope.reason ?? "—"]]} />
              </PBody>
              <DTable noPrint cols={["The old portal's item", "Kind", "Counts toward the transfer fee"]} rows={(scope.items ?? []).map((it) => [
                <span key="i">{it.item}{it.reason ? <div className="sub2">{it.reason}</div> : null}</span>,
                <span key="k" className="sub2">{ITEM_KIND_WORDS[it.kind] ?? it.kind}</span>,
                <Pil key="c" kind={it.counts ? "ok" : "grey"}>{it.counts ? "Counts" : "Does not count — listed for the Bursary"}</Pil>,
              ])} />
            </Panel>
            {mayDecide ? (
              <Panel title="Change the date">
                <PBody>
                  <div className="sub2 mb-3">Payments made before the date are listed as before the current exercise and count toward nothing. A change re-runs the
                    reconciliation; an officer&rsquo;s decision stands.</div>
                  <div className="grid grid--2">
                    <Field id="opt-from" label="Payments count from">
                      <input id="opt-from" type="date" className="ctl" value={from} onChange={(e) => setFrom(e.target.value)} />
                    </Field>
                    <Field id="opt-why" label="Reason" required hint="Ten characters at least; kept with the scope">
                      <input id="opt-why" className="ctl" maxLength={600} value={scopeWhy} onChange={(e) => setScopeWhy(e.target.value)} />
                    </Field>
                  </div>
                  <div className="mt-2">
                    <Btn kind="primary" busy={busy === "scope"} busyLabel="Stating the date…" disabled={busy !== null || !from || from === scope.countsFrom?.slice(0, 10) || scopeWhy.trim().length < 10}
                      onClick={() => void saveScope()}>State the date and reconcile again</Btn>
                  </div>
                </PBody>
              </Panel>
            ) : null}
          </>
        ) : scopeProblem ? <ProblemNotice problem={scopeProblem} /> : null
      ) : null}

      {open ? (
        <Modal wide title={`Decide ${open.name ?? open.matric_no ?? "the student"}'s old-portal payment`}
          sub={`${open.item} · ${naira(open.amount)} · ${open.payref ?? "no old payment number"}`}
          onClose={() => setOpen(null)}
          foot={<>
            <Btn kind="ghost" onClick={() => setOpen(null)}>Cancel</Btn>
            <Btn kind="primary" busy={busy === "decide"} busyLabel="Recording…"
              disabled={busy !== null || note.trim().length < 10 || (decision === "LINK" && !appId) || (decision === "RELEASE" && !open.decided_at)}
              onClick={() => void decide()}>Record the decision</Btn>
          </>}>
          <KvGrid cls="grid--4" pairs={[
            ["Student", open.name ?? "—"], ["Matric number", open.matric_no ?? "—"], ["Paid on", day(open.paid_on)], ["Status", LEGACY_STATUS_WORDS[open.status]?.[0] ?? open.status],
            ["Item", ITEM_KIND_WORDS[open.item_kind] ?? open.item_kind], ["Amount", naira(open.amount)], ["Old payment number", open.payref ?? "—"],
            ["Decided", open.decided_at ? `${roleLabel(open.decided_office)} · ${day(open.decided_at)}` : "By the rule"],
          ]} />
          {open.reason ? <div className="sub2 mt-2">{open.reason}</div> : null}
          {open.status === "USED" ? (
            <Note kind="info" title="Used by a transfer the old portal approved">
              The payment paid for the transfer the old portal approved and this portal restored; it is not a credit for another transfer. Count it toward an
              application only when the record shows it did not pay for that transfer, and say so in the reason.
            </Note>
          ) : open.application_id && open.application_state && !LIVE_STATES.includes(open.application_state) ? (
            <Note kind="info" title={`Counted toward an application now ${(appState(open) ?? open.application_state).toLowerCase()}`}>
              A payment once counted toward an application stays with it, whatever became of the application; a decision here moves it.
            </Note>
          ) : null}
          <div role="radiogroup" aria-label="Decision" className="mt-2" style={{ display: "grid", gap: 6 }}>
            {DECISIONS.map((d) => {
              const off = d === "RELEASE" && !open.decided_at;
              return (
                <label key={d} className="row row--tight" style={{ alignItems: "flex-start", gap: 8, opacity: off ? 0.55 : 1 }}>
                  <input type="radio" name="opt-decision" checked={decision === d} disabled={off} onChange={() => setDecision(d)} />
                  <span><b>{DECISION_WORDS[d][0]}</b><div className="sub2">{off ? "Only a payment an officer decided is released." : DECISION_WORDS[d][1]}</div></span>
                </label>
              );
            })}
          </div>
          {decision === "LINK" ? (
            <Field id="opt-app" label="The student's application">
              {apps === null ? <div className="sub2">Reading the student&rsquo;s applications…</div>
                : theirs.length ? (
                  <select id="opt-app" className="ctl" value={appId} onChange={(e) => setAppId(e.target.value)}>
                    <option value="">Choose an application…</option>
                    {theirs.map((a) => <option key={a.id} value={a.id}>{`${a.to_programme} — ${a.stageLabel ?? a.state} · ${a.session} · applied ${day(a.applied_at)}${a.legacy_ref ? ` · old portal ${a.legacy_ref}` : ""}`}</option>)}
                  </select>
                ) : <div className="sub2">The student has no application here that stands. The payment waits for one: it is counted when the student applies or the old portal&rsquo;s application is loaded.</div>}
            </Field>
          ) : null}
          <Field id="opt-note" label="Reason" required hint="Ten characters at least; kept with the decision and shown on the list">
            <textarea id="opt-note" className="ctl" rows={3} maxLength={600} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}

const STATUS_SUB: Record<string, string> = {
  LINKED: "Counted toward the student's application",
  AWAITING_APPLICATION: "Counted once the student applies",
  USED: "Paid for a transfer the old portal approved, restored here",
  UNMATCHED: "Not counted: the reason is on the row",
  NOT_COUNTED: "An item that does not count, or decided so",
  OUT_OF_SCOPE: "Paid before the date the scope states",
  REJECTED: "Decided never to count",
};

const MATCH_WORDS: Record<string, string> = {
  IMPORT_MATRIC_PAYREF: "Matched on the record and the payment number",
  OLD_PORTAL_EXPORT: "Named by the old portal's export",
  MANUAL: "By an officer",
};

/** what a figure means: a sentence, or one that names a companion figure the report returns */
type Sub = string | ((r: LegacyReport) => string);
const subOf = (sub: Sub, r: LegacyReport): string => (typeof sub === "function" ? sub(r) : sub);
const plural = (n: number, one: string, many: string) => `${vzNum(n)} ${n === 1 ? one : many}`;
/** a section's tiles in rows of four, or of three when they fall so evenly */
const gridFor = (n: number) => (n % 4 === 0 ? "grid--4" : n % 3 === 0 ? "grid--3" : "grid--4");

/** the report's figures: section, label, key, whether money, what it means — every figure the server's (people.legacy_transfer_report),
 *  never estimated here */
const REPORT_ROWS: [string, string, string, boolean, Sub][] = [
  ["The old portal's applications", "Loads", "loads", false, "Uploads of the old portal's export"],
  ["The old portal's applications", "Named in the uploads", "legacyApplicationsIdentified", false, "Old references read"],
  ["The old portal's applications", "Continued here", "legacyApplicationsMatched", false, "Loaded, or joined to an application"],
  ["The old portal's applications", "Not loaded", "legacyApplicationsUnmatched", false, "By the last word on each, below"],
  ["Old-portal transfer payments", "Read", "paymentsRead", false, "On the reconciliation list"],
  ["Old-portal transfer payments", "Counted toward an application", "paymentsLinked", false, "Linked"],
  ["Old-portal transfer payments", "Awaiting an application", "paymentsAwaitingApplication", false, "Counted once the student applies"],
  ["Old-portal transfer payments", "Used by a restored transfer", "paymentsUsed", false, "Paid for a transfer the old portal approved, restored here; no credit for another"],
  ["Old-portal transfer payments", "Unmatched", "paymentsUnmatched", false, "By reason, below"],
  ["Old-portal transfer payments", "Not counted", "paymentsNotCounted", false, "An item that does not count, or decided so"],
  ["Old-portal transfer payments", "Before the current exercise", "paymentsOutOfScope", false, "Paid before the date the scope states"],
  ["Old-portal transfer payments", "Rejected", "paymentsRejected", false, "Decided never to count"],
  ["Old-portal transfer payments", "Decided by an officer", "paymentsDecided", false, "Kept; the rule never runs over them"],
  ["Students who paid on the old portal", "Students", "students", false, "Payments counted or awaiting an application"],
  ["Students who paid on the old portal", "Paid the fee in full", "studentsPaidInFull", false, "Exactly the fee as stated now"],
  ["Students who paid on the old portal", "Paid above the fee", "studentsPaidOverFee", false, "No refund is made by the portal"],
  ["Students who paid on the old portal", "Paid half the fee", "studentsPaidHalf", false, "Half the fee as stated now"],
  ["Students who paid on the old portal", "Paid another part", "studentsOtherPartial", false, "Less than the fee as stated now, not half"],
  ["Students who paid on the old portal", "Collected on the old portal", "oldPortalCollected", true, "What these students paid"],
  ["Students who paid on the old portal", "Above the fee", "oldPortalExcess", true, "Paid beyond the fee"],
  ["Students who paid on the old portal", "Still owed on their applications", "outstandingOldPortalPayers", true, (r) => figure(r, "payerApplicationsLive")
    ? `On ${plural(figure(r, "payerApplicationsLive"), "live application", "live applications")} of theirs, after every verified payment here and on the old portal`
    : "None of them has a live application here"],
  ["Students awaiting an application", "Students", "studentsAwaitingApplication", false, "Paid on the old portal, no application here yet"],
  ["Students awaiting an application", "Their credit", "creditAwaitingApplication", true, "Counts toward the fee once they apply"],
  ["Students awaiting an application", "Owed when they apply", "owedWhenTheyApply", true, (r) => figure(r, "studentsOwingWhenTheyApply")
    ? `By ${plural(figure(r, "studentsOwingWhenTheyApply"), "student", "students")}: the fee as stated now less their credit; nothing is owed before they apply`
    : "No student among them will owe; nothing is owed before they apply"],
  ["Live applications", "Live", "applicationsLive", false, "Applied and not yet completed"],
  ["Live applications", "Nothing paid", "applicationsNotPaid", false, "The current HOD waits for a payment"],
  ["Live applications", "Part paid", "applicationsPartPaid", false, "A balance owed"],
  ["Live applications", "Awaiting payment", "applicationsAwaitingPayment", false, "Held for a payment at their desk"],
  ["Live applications", "Awaiting a desk", "applicationsAwaitingApproval", false, "Paid enough for the desk they sit at"],
  ["Live applications", "Outstanding", "outstandingApplications", true, "The balances of the live applications"],
];
const SECTIONS = [...new Set(REPORT_ROWS.map((r) => r[0]))];
