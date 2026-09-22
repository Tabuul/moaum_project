"use client";

/** bBudget — proto/part…: commitment accounting. Budget is consumed at approval, not at
 *  payment: an approved (cleared) voucher commits its amount immediately. */
import { useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Bar, Field, Modal, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface BudgetRow { cost_centre: string; budget: number; committed: number; spent: number; available: number }
export interface BudgetView { year: number; rows: BudgetRow[] }
/** the income and expenditure statement for the year, read off the general ledger (V145) */
export interface Statement {
  year: number; lines: { section: string; code: string; name: string; amount: number }[];
  totals: { income: number; expense: number; surplus: number };
  budget: { budget: number; committed: number; spent: number; available: number };
}

export function Budget({ d, ie, actingOffice }: { d: BudgetView; ie?: Statement | null; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["bursar", "super"].includes(actingOffice ?? "");
  const [add, setAdd] = useState(false);
  const [f, setF] = useState({ costCentre: "", amount: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const totalBudget = d.rows.reduce((a, r) => a + Number(r.budget), 0);
  const totalCommitted = d.rows.reduce((a, r) => a + Number(r.committed), 0);
  const totalSpent = d.rows.reduce((a, r) => a + Number(r.spent), 0);
  const overspent = d.rows.filter((r) => Number(r.available) < 0).length;

  async function set() {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch("/api/bff/api/v1/expenditure/budget", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Budget for ${f.costCentre}`) }, body: JSON.stringify({ costCentre: f.costCentre, year: d.year, amount: Number(f.amount) }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return; }
      setSaid(`Budget set for ${f.costCentre}`); notify(`Budget set for ${f.costCentre}`); setAdd(false); setF({ costCentre: "", amount: "" }); router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="Commitment accounting — budget is consumed at approval, not at payment">
        An approved voucher reduces the available balance immediately, before the money leaves. That is what stops a cost centre committing money it has already promised elsewhere. Available is the budget less what is committed and what is spent.
      </Note>

      {said ? <Note kind="ok" title={said} /> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <div className="card"><div className="card__body" style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "flex-end" }}>
        <div className="field" style={{ minWidth: 140 }}><label htmlFor="bg-year">Financial year</label>
          <select id="bg-year" className="ctl tnum" value={d.year} onChange={(e) => router.push(`/finance/budget?year=${e.target.value}`)}>
            {[d.year + 1, d.year, d.year - 1, d.year - 2].map((y) => <option key={y} value={y}>{y}</option>)}
          </select></div>
        <div style={{ flexGrow: 1 }} />
        {may ? <button className="btn btn--primary" onClick={() => { setF({ costCentre: "", amount: "" }); setErr(null); setAdd(true); }}>+ Set a cost centre&rsquo;s budget</button> : null}
      </div></div>

      <Tiles items={[
        ["Budget", money(totalBudget), null, `${d.rows.length} cost centre${d.rows.length === 1 ? "" : "s"}`],
        ["Committed", money(totalCommitted), totalCommitted ? "var(--chrome)" : null, "Approved, not yet paid"],
        ["Spent", money(totalSpent), null, "Paid out"],
        ["Over budget", String(overspent), overspent ? "var(--red-ink)" : "var(--green-ink)", overspent ? "Further requisitions refused" : "All within budget"],
      ]} />

      <Panel title="Budget performance by cost centre" right={`Financial year ${d.year}`}>
        {d.rows.length ? (
          <DTable cols={["Cost centre", "Budget|mid", "Committed|mid", "Spent|mid", "Available|mid", "Utilisation|num"]} rows={d.rows.map((r) => {
            const used = Number(r.committed) + Number(r.spent);
            const pct = Number(r.budget) ? Math.round((100 * used) / Number(r.budget)) : (used ? 100 : 0);
            return [
              <strong key="c">{r.cost_centre}</strong>,
              <span className="tnum" key="b">{money(Number(r.budget))}</span>,
              <span className="tnum" key="cm">{money(Number(r.committed))}</span>,
              <span className="tnum" key="sp">{money(Number(r.spent))}</span>,
              <span className="tnum" key="av" style={{ fontWeight: 600, color: Number(r.available) < 0 ? "var(--red-ink)" : undefined }}>{money(Number(r.available))}</span>,
              <span key="u" style={{ display: "flex", alignItems: "center", gap: 8 }}><Bar pct={Math.min(100, pct)} colour={pct >= 100 ? "var(--red)" : pct >= 85 ? "var(--chrome)" : "var(--green)"} /><span className="tnum sub2">{pct}%</span></span>,
            ];
          })} texts={d.rows.map((r) => r.cost_centre)} />
        ) : <PBody><div className="sub2">No budget is set for {d.year}, and no voucher has been raised against a cost centre. Set a cost centre&rsquo;s budget to begin.</div></PBody>}
      </Panel>

      {ie ? (() => {
        const income = ie.lines.filter((l) => String(l.section).toUpperCase() === "INCOME");
        const expense = ie.lines.filter((l) => String(l.section).toUpperCase() !== "INCOME");
        const surplus = Number(ie.totals.surplus);
        const cell = (v: number | null, bold = false, red = false) => <span className="tnum" style={{ fontWeight: bold ? 600 : undefined, color: red ? "var(--red-ink)" : undefined }}>{v == null ? "—" : money(v)}</span>;
        const rows: ReactNode[][] = [
          ...income.map((l) => [<span key="n" style={{ paddingLeft: 12 }}>{l.name}</span>, cell(null), cell(Number(l.amount)), cell(null)]),
          [<strong key="n">Total income</strong>, cell(null), cell(Number(ie.totals.income), true), cell(null)],
          ...expense.map((l) => [<span key="n" style={{ paddingLeft: 12 }}>{l.name}</span>, cell(null), cell(Number(l.amount)), cell(null)]),
          [<strong key="n">Total expenditure</strong>, cell(Number(ie.budget.budget), true), cell(Number(ie.totals.expense), true), cell(Number(ie.budget.budget) - Number(ie.totals.expense), true, Number(ie.budget.budget) - Number(ie.totals.expense) < 0)],
          [<strong key="n">{surplus >= 0 ? "Surplus for the year" : "Deficit for the year"}</strong>, cell(null), cell(surplus, true, surplus < 0), cell(null)],
        ];
        return (
          <Panel title="Income and expenditure" right={`Financial year ${ie.year} · against budget`}>
            {ie.lines.length ? (
              <>
                <DTable cols={["", "Budget|num", "Actual|num", "Variance|num"]} rows={rows}
                  texts={[...income.map((l) => l.name), "Total income", ...expense.map((l) => l.name), "Total expenditure", surplus >= 0 ? "Surplus for the year" : "Deficit for the year"]} />
                <PBody><div className="sub2">Income and expenditure are read off the general ledger&rsquo;s income and expense accounts for the year. The budget is the cost-centre budget the Bursary set; the variance is what remains of it against actual expenditure. Income is not budgeted in the portal, so its budget column is blank.</div></PBody>
              </>
            ) : <PBody><div className="sub2">No income or expense has been posted to the ledger for {ie.year} yet.</div></PBody>}
          </Panel>
        );
      })() : null}

      <Note kind="bad" title="A cost centre with nothing available has its next requisition refused at budget check">
        Commitment accounting is the point: the money an approved voucher will pay is gone from the available balance the moment it is approved, not when it is paid, so a second commitment against the same money cannot slip through in the gap.
      </Note>

      {add ? (
        <Modal title="Set a cost centre's budget" sub={`Financial year ${d.year}`} onClose={() => setAdd(false)}
          foot={<><Btn kind="ghost" onClick={() => setAdd(false)}>Cancel</Btn><span style={{ flexGrow: 1 }} /><Btn kind="primary" disabled={busy || !f.costCentre.trim() || !(Number(f.amount) >= 0)} onClick={() => void set()}>Set the budget</Btn></>}>
          {err ? <ProblemNotice problem={err} /> : null}
          <Field id="bg-cc" label="Cost centre" hint="The name vouchers use, e.g. Faculty of Science, ICT Directorate"><input id="bg-cc" className="ctl" value={f.costCentre} onChange={(e) => setF({ ...f, costCentre: e.target.value })} autoComplete="off" /></Field>
          <Field id="bg-amt" label="Budget (₦)"><input id="bg-amt" className="ctl tnum" value={f.amount} inputMode="decimal" onChange={(e) => setF({ ...f, amount: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
