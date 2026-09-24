"use client";

/**
 * The Bursary's books. A double-entry general ledger over the cash the finance
 * desk already records: confirmed payments, paid refunds and paid vouchers post
 * themselves (Sync), the Bursar posts opening balances and adjustments by hand,
 * and the ledger yields a trial balance, an income & expenditure account and a
 * balance sheet. A posted journal is never edited — a mistake is reversed.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, RoleLine, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Account { code: string; name: string; type: string; normal_side: string; parent_code: string | null; postable: boolean; active: boolean }
export interface IeRow { section: string; code: string | null; name: string; amount: number }
export interface Overview { cash: number; ie: IeRow[]; unposted: { payments: number; refunds: number; vouchers: number }; journals: number; yearStart: string }
export interface TbRow { code: string; name: string; type: string; debit: number; credit: number }
export interface TrialBalance { asOf: string; rows: TbRow[]; debit: number; credit: number; balanced: boolean }
export interface Statement { from?: string; to?: string; asOf?: string; rows: IeRow[] }
export interface JLine { account: string; name: string; debit: number; credit: number; narration: string | null }
export interface Journal { id: string; journal_no: number; entry_date: string; memo: string; source: string; source_type: string | null; status: string; total: number; lines: JLine[] }
export interface LedgerRow { entry_date: string; journal_no: number; memo: string; narration: string | null; debit: number; credit: number; balance: number }

const naira = (n: number | string | null | undefined) => n == null ? "—" : `₦${Number(n).toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const today = () => new Date().toISOString().slice(0, 10);

type Tab = "overview" | "trial" | "ie" | "bs" | "journals" | "ledger";
const TABS: [Tab, string][] = [["overview", "Overview"], ["trial", "Trial balance"], ["ie", "Income & expenditure"], ["bs", "Balance sheet"], ["journals", "Journal book"], ["ledger", "Account ledger"]];

interface DraftLine { account: string; debit: string; credit: string; narration: string }
const emptyLine = (): DraftLine => ({ account: "", debit: "", credit: "", narration: "" });

export function Accounting({ overview, chart, trial, ie, bs, journals, actingOffice }: {
  overview: Overview; chart: Account[]; trial: TrialBalance; ie: Statement; bs: Statement; journals: Journal[]; actingOffice: string | null;
}) {
  const router = useRouter();
  const may = actingOffice === "bursar" || actingOffice === "super";
  const [tab, setTab] = useState<Tab>("overview");
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [posting, setPosting] = useState(false);
  const [reversing, setReversing] = useState<Journal | null>(null);
  const [expanded, setExpanded] = useState<string | null>(null);

  // manual journal draft
  const [jDate, setJDate] = useState(today());
  const [jMemo, setJMemo] = useState("");
  const [jLines, setJLines] = useState<DraftLine[]>([emptyLine(), emptyLine()]);
  const [reason, setReason] = useState("");

  // account ledger
  const [ledAccount, setLedAccount] = useState("");
  const [ledFrom, setLedFrom] = useState("");
  const [ledTo, setLedTo] = useState("");
  const [ledger, setLedger] = useState<{ account: { code: string; name: string }; rows: LedgerRow[] } | null>(null);

  const postable = chart.filter((a) => a.postable);
  const jDr = jLines.reduce((n, l) => n + (Number(l.debit) || 0), 0);
  const jCr = jLines.reduce((n, l) => n + (Number(l.credit) || 0), 0);
  const balanced = jDr > 0 && Math.abs(jDr - jCr) < 0.005;

  async function call(key: string, path: string, body: unknown, reasonText: string): Promise<boolean> {
    setBusy(key); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/finance/accounting${path}`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reasonText) }, body: JSON.stringify(body ?? {}),
      });
      if (!r.ok) { setProblem(await r.json().catch(() => ({ status: r.status, title: "The request was refused." }))); return false; }
      notify(reasonText);
      router.refresh();
      return true;
    } catch { setProblem({ status: 0, title: "The network dropped the request." }); return false; }
    finally { setBusy(null); }
  }

  async function loadLedger() {
    if (!ledAccount) return;
    setBusy("ledger"); setProblem(null);
    try {
      const qs = new URLSearchParams({ account: ledAccount });
      if (ledFrom) qs.set("from", ledFrom);
      if (ledTo) qs.set("to", ledTo);
      const r = await fetch(`/api/bff/api/v1/finance/accounting/ledger?${qs.toString()}`);
      if (!r.ok) { setProblem(await r.json().catch(() => ({ status: r.status, title: "Could not load the ledger." }))); return; }
      setLedger(await r.json());
    } catch { setProblem({ status: 0, title: "The network dropped the request." }); }
    finally { setBusy(null); }
  }

  const surplus = overview.ie.find((r) => r.section === "SURPLUS")?.amount ?? 0;
  const income = overview.ie.find((r) => r.section === "INCOME_TOTAL")?.amount ?? 0;
  const expense = overview.ie.find((r) => r.section === "EXPENSE_TOTAL")?.amount ?? 0;
  const unposted = overview.unposted.payments + overview.unposted.refunds + overview.unposted.vouchers;

  return (
    <>
      <RoleLine allowed={["bursar"]} actingOffice={actingOffice} canAct={may} action="Keeping the books — posting, journals and reversals" />
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Tiles items={[
        ["Cash & bank on the books", naira(overview.cash), null, "Collections + disbursements + cash"],
        ["Income this year", naira(income), "var(--green-ink)", `Since ${overview.yearStart}`],
        ["Expenditure this year", naira(expense), null, `Since ${overview.yearStart}`],
        ["Surplus / (deficit)", naira(surplus), surplus < 0 ? "var(--red-ink)" : "var(--green-ink)", `${overview.journals} journal${overview.journals === 1 ? "" : "s"} posted`],
      ]} />

      {unposted > 0 ? (
        <Note kind="info" title={`${unposted} transaction${unposted === 1 ? "" : "s"} not yet on the books`}
          action={<Btn kind="primary" disabled={!may || busy !== null} onClick={() => void call("sync", "/sync", {}, "Ledger sync: posted confirmed payments, paid refunds and paid vouchers")}>{busy === "sync" ? "Posting…" : "Post them now"}</Btn>}>
          {overview.unposted.payments} payment{overview.unposted.payments === 1 ? "" : "s"}, {overview.unposted.refunds} refund{overview.unposted.refunds === 1 ? "" : "s"} and {overview.unposted.vouchers} voucher{overview.unposted.vouchers === 1 ? "" : "s"} are confirmed or paid but not yet posted. Posting is safe to run any time — each transaction posts once.
        </Note>
      ) : (
        <Note kind="ok" title="The books are up to date">Every confirmed payment, paid refund and paid voucher is on the ledger. Run Sync again whenever new ones are confirmed.</Note>
      )}

      <div style={{ display: "flex", gap: 6, flexWrap: "wrap", margin: "12px 0" }}>
        {TABS.map(([t, label]) => <Btn key={t} kind={tab === t ? "primary" : "ghost"} onClick={() => setTab(t)}>{label}</Btn>)}
        <span className="grow" />
        {may ? <Btn kind="go" disabled={busy !== null} onClick={() => { setJDate(today()); setJMemo(""); setJLines([emptyLine(), emptyLine()]); setPosting(true); }}>New journal</Btn> : null}
        {may ? <Btn kind="ghost" disabled={busy !== null} onClick={() => void call("sync", "/sync", {}, "Ledger sync from the accounting screen")}>{busy === "sync" ? "Syncing…" : "Sync"}</Btn> : null}
      </div>

      {tab === "overview" ? (
        <Panel title="The books at a glance">
          <PBody>
            <div className="sub2">The accounting module keeps a proper set of double-entry books over the money the finance desk records. Money enters the ledger automatically when a payment is confirmed, a refund is paid, or a voucher is paid; the Bursar posts opening balances and adjustments by hand. Use the tabs above for the trial balance and the financial statements. Everything is cash-basis: income is recognised when received, expenditure when paid.</div>
          </PBody>
          <DTable cols={["Account", "Type", "|num"]} rows={chart.map((a) => [
            <span key="n" style={{ paddingLeft: a.parent_code ? 16 : 0 }}>{a.postable ? a.name : <strong>{a.name}</strong>} <span className="sub2">{a.code}</span></span>,
            <span className="sub2" key="t">{a.type[0] + a.type.slice(1).toLowerCase()}</span>,
            <span className="sub2" key="s">{a.normal_side === "D" ? "Debit" : "Credit"}</span>,
          ])} />
        </Panel>
      ) : null}

      {tab === "trial" ? (
        <Panel title={`Trial balance — as at ${trial.asOf}`} right={<Pil kind={trial.balanced ? "ok" : "bad"}>{trial.balanced ? "In balance" : "Out of balance"}</Pil>}>
          <DTable cols={["Account", "Debit|num", "Credit|num"]} rows={[
            ...trial.rows.map((r) => [
              <span key="n">{r.name} <span className="sub2">{r.code}</span></span>,
              <span className="tnum" key="d">{r.debit ? naira(r.debit) : ""}</span>,
              <span className="tnum" key="c">{r.credit ? naira(r.credit) : ""}</span>,
            ]),
            [<strong key="n">Total</strong>, <strong className="tnum" key="d">{naira(trial.debit)}</strong>, <strong className="tnum" key="c">{naira(trial.credit)}</strong>],
          ]} />
          {!trial.rows.length ? <PBody><div className="sub2">No postings yet. Run Sync to bring the cash records onto the books.</div></PBody> : null}
        </Panel>
      ) : null}

      {tab === "ie" ? (
        <Panel title={`Income & expenditure — ${ie.from} to ${ie.to}`}>
          <DTable cols={["", "Amount|num"]} rows={statementRows(ie.rows, "ie")} />
        </Panel>
      ) : null}

      {tab === "bs" ? (
        <Panel title={`Balance sheet — as at ${bs.asOf}`}>
          <DTable cols={["", "Amount|num"]} rows={statementRows(bs.rows, "bs")} />
        </Panel>
      ) : null}

      {tab === "journals" ? (
        <Panel title="Journal book" right={`${journals.length} shown`}>
          <DTable cols={["No.", "Date", "Narrative", "Amount|num", "|num"]} rows={journals.map((j) => [
            <span key="no" className="tnum">#{j.journal_no}</span>,
            <span key="d" className="sub2 tnum">{j.entry_date}</span>,
            <span key="m">{j.memo} {j.source === "AUTO" ? <Pil kind="grey">Auto</Pil> : <Pil kind="info">Manual</Pil>}{j.status === "REVERSED" ? <Pil kind="bad">Reversed</Pil> : null}</span>,
            <span key="t" className="tnum">{naira(j.total)}</span>,
            <span key="x" style={{ display: "flex", gap: 6, justifyContent: "flex-end" }}>
              <Btn kind="ghost" onClick={() => setExpanded(expanded === j.id ? null : j.id)}>{expanded === j.id ? "Hide" : "Lines"}</Btn>
              {may && j.status === "POSTED" ? <Btn kind="ghost" disabled={busy !== null} onClick={() => { setReason(""); setReversing(j); }}>Reverse</Btn> : null}
            </span>,
          ])} />
          {expanded ? (() => {
            const j = journals.find((x) => x.id === expanded);
            if (!j) return null;
            return (
              <PBody>
                <div className="sub2 mb-2">Journal #{j.journal_no} — {j.memo}</div>
                <DTable cols={["Account", "Debit|num", "Credit|num"]} rows={j.lines.map((l) => [
                  <span key="a">{l.name} <span className="sub2">{l.account}</span>{l.narration ? <span className="sub2"> · {l.narration}</span> : null}</span>,
                  <span key="d" className="tnum">{l.debit ? naira(l.debit) : ""}</span>,
                  <span key="c" className="tnum">{l.credit ? naira(l.credit) : ""}</span>,
                ])} />
              </PBody>
            );
          })() : null}
          {!journals.length ? <PBody><div className="sub2">No journals in this period.</div></PBody> : null}
        </Panel>
      ) : null}

      {tab === "ledger" ? (
        <Panel title="Account ledger">
          <PBody>
            <div className="row row--end">
              <div className="field" style={{ minWidth: 240, margin: 0 }}><label htmlFor="led-a">Account</label>
                <select id="led-a" className="ctl" value={ledAccount} onChange={(e) => setLedAccount(e.target.value)}>
                  <option value="">Choose an account…</option>
                  {postable.map((a) => <option key={a.code} value={a.code}>{a.code} — {a.name}</option>)}
                </select>
              </div>
              <div className="field" style={{ minWidth: 140, margin: 0 }}><label htmlFor="led-f">From</label><input id="led-f" type="date" className="ctl tnum" value={ledFrom} onChange={(e) => setLedFrom(e.target.value)} /></div>
              <div className="field" style={{ minWidth: 140, margin: 0 }}><label htmlFor="led-t">To</label><input id="led-t" type="date" className="ctl tnum" value={ledTo} onChange={(e) => setLedTo(e.target.value)} /></div>
              <Btn kind="primary" disabled={!ledAccount || busy !== null} onClick={() => void loadLedger()}>{busy === "ledger" ? "Loading…" : "Show"}</Btn>
            </div>
          </PBody>
          {ledger ? (
            <DTable cols={["Date", "No.", "Narrative", "Debit|num", "Credit|num", "Balance|num"]} rows={ledger.rows.map((r) => [
              <span key="d" className="sub2 tnum">{r.entry_date}</span>,
              <span key="no" className="tnum">#{r.journal_no}</span>,
              <span key="m">{r.narration || r.memo}</span>,
              <span key="dr" className="tnum">{r.debit ? naira(r.debit) : ""}</span>,
              <span key="cr" className="tnum">{r.credit ? naira(r.credit) : ""}</span>,
              <span key="b" className="tnum">{naira(r.balance)}</span>,
            ])} />
          ) : null}
          {ledger && !ledger.rows.length ? <PBody><div className="sub2">No movement on {ledger.account.name} in this period.</div></PBody> : null}
        </Panel>
      ) : null}

      {posting ? (
        <Modal title="Post a journal" sub="A balanced entry — opening balances, an adjustment, a correction" onClose={() => setPosting(false)}
          foot={<><Btn kind="ghost" onClick={() => setPosting(false)}>Cancel</Btn><span className="grow" />
            <span className="sub2 tnum" style={{ alignSelf: "center", color: balanced ? "var(--green-ink)" : "var(--red-ink)" }}>Dr {naira(jDr)} · Cr {naira(jCr)}</span>
            <Btn kind="go" disabled={!balanced || !jMemo.trim() || busy !== null} onClick={async () => {
              const ok = await call("journal", "/journals", {
                date: jDate, memo: jMemo.trim(),
                lines: jLines.filter((l) => l.account && (Number(l.debit) > 0 || Number(l.credit) > 0)).map((l) => ({
                  account: l.account, debit: Number(l.debit) || 0, credit: Number(l.credit) || 0, narration: l.narration || undefined,
                })),
              }, `Manual journal posted: ${jMemo.trim()}`);
              if (ok) setPosting(false);
            }}>{busy === "journal" ? "Posting…" : "Post the journal"}</Btn></>}>
          <div className="grid grid--2">
            <Field id="j-date" label="Date"><input id="j-date" type="date" className="ctl tnum" value={jDate} onChange={(e) => setJDate(e.target.value)} /></Field>
            <Field id="j-memo" label="Narrative"><input id="j-memo" className="ctl" value={jMemo} onChange={(e) => setJMemo(e.target.value)} placeholder="e.g. Opening balances 2025/2026" /></Field>
          </div>
          {jLines.map((l, i) => (
            <div key={i} style={{ display: "flex", gap: 6, alignItems: "flex-end", marginBottom: 6, flexWrap: "wrap" }}>
              <div className="field" style={{ flex: "2 1 180px", margin: 0 }}><label>Account</label>
                <select className="ctl" value={l.account} onChange={(e) => setJLines(jLines.map((x, k) => k === i ? { ...x, account: e.target.value } : x))}>
                  <option value="">Choose…</option>
                  {postable.map((a) => <option key={a.code} value={a.code}>{a.code} — {a.name}</option>)}
                </select>
              </div>
              <div className="field" style={{ flex: "1 1 100px", margin: 0 }}><label>Debit</label><input className="ctl tnum" inputMode="decimal" value={l.debit} onChange={(e) => setJLines(jLines.map((x, k) => k === i ? { ...x, debit: e.target.value, credit: e.target.value ? "" : x.credit } : x))} /></div>
              <div className="field" style={{ flex: "1 1 100px", margin: 0 }}><label>Credit</label><input className="ctl tnum" inputMode="decimal" value={l.credit} onChange={(e) => setJLines(jLines.map((x, k) => k === i ? { ...x, credit: e.target.value, debit: e.target.value ? "" : x.debit } : x))} /></div>
              <Btn kind="ghost" disabled={jLines.length <= 2} onClick={() => setJLines(jLines.filter((_, k) => k !== i))}>✕</Btn>
            </div>
          ))}
          <Btn kind="ghost" onClick={() => setJLines([...jLines, emptyLine()])}>Add a line</Btn>
          {!balanced && jDr + jCr > 0 ? <div className="sub2" style={{ marginTop: 8, color: "var(--red-ink)" }}>Debits must equal credits before you can post.</div> : null}
        </Modal>
      ) : null}

      {reversing ? (
        <Modal title={`Reverse journal #${reversing.journal_no}`} sub={reversing.memo} onClose={() => setReversing(null)}
          foot={<><Btn kind="ghost" onClick={() => setReversing(null)}>Cancel</Btn><span className="grow" />
            <Btn kind="urgent" disabled={!reason.trim() || busy !== null} onClick={async () => {
              const ok = await call("reverse", `/journals/${reversing.id}/reverse`, { reason: reason.trim() }, `Journal #${reversing.journal_no} reversed`);
              if (ok) setReversing(null);
            }}>{busy === "reverse" ? "Reversing…" : "Post the reversal"}</Btn></>}>
          <Note kind="bad" title="A reversal, not a delete">A mirror journal is posted that cancels this one; both stay on the record. The original is marked reversed.</Note>
          <Field id="rev-why" label="Reason" hint="Why this entry is being reversed"><input id="rev-why" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}

const SECTION_LABEL: Record<string, string> = {
  ASSET: "Assets", LIABILITY: "Liabilities", EQUITY: "Fund",
  INCOME: "Income", EXPENSE: "Expenditure",
};
const TOTAL_ROW = new Set(["INCOME_TOTAL", "EXPENSE_TOTAL", "SURPLUS", "ASSET_TOTAL", "FUNDS_TOTAL"]);

function statementRows(rows: IeRow[], kind: "ie" | "bs"): React.ReactNode[][] {
  const order = kind === "ie" ? ["INCOME", "INCOME_TOTAL", "EXPENSE", "EXPENSE_TOTAL", "SURPLUS"] : ["ASSET", "ASSET_TOTAL", "LIABILITY", "EQUITY", "FUNDS_TOTAL"];
  const out: React.ReactNode[][] = [];
  const seen = new Set<string>();
  for (const sec of order) {
    if (TOTAL_ROW.has(sec)) {
      const r = rows.find((x) => x.section === sec);
      if (r) out.push([<strong key="n">{r.name}</strong>, <strong key="a" className="tnum">{naira(r.amount)}</strong>]);
      continue;
    }
    const group = rows.filter((x) => x.section === sec);
    if (!group.length || seen.has(sec)) continue;
    seen.add(sec);
    out.push([<span key="h" className="sub2" style={{ textTransform: "uppercase", letterSpacing: ".04em" }}>{SECTION_LABEL[sec] ?? sec}</span>, <span key="a" />]);
    for (const r of group) out.push([<span key="n" style={{ paddingLeft: 16 }}>{r.name}{r.code ? <span className="sub2"> {r.code}</span> : null}</span>, <span key="a" className="tnum">{naira(r.amount)}</span>]);
  }
  return out;
}
