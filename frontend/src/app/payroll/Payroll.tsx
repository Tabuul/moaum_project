"use client";

/** tPayroll — the monthly pay run: built over the active establishment, approved by a
 *  second officer, then marked paid. Each payslip is a snapshot of the components and
 *  the statutory deductions (pension and PAYE). Nothing here is deleted. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { Btn, Ico, LinkBtn, Note, Panel, PBody, Pil, RoleLine, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface PayRun {
  id: string; period: string; state: string; staff_count: number; gross_total: number; deduction_total: number; net_total: number;
  note: string | null; built_at: string; approved_at: string | null; paid_at: string | null; cancelled_why: string | null;
  built_by_name: string | null; approved_by_name: string | null; built_by_me: boolean;
}
export interface Payslip {
  staff_no: string; name: string; grade: string; step: number; category: string;
  basic: number; allowances: number; gross: number; pension: number; paye: number; other_deductions: number; net: number;
  bank_name: string | null; account_last4: string | null;
}
export interface RunDetail { run: PayRun; payslips: Payslip[] }

const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  DRAFT: ["warn", "Draft — awaiting approval"], APPROVED: ["info", "Approved, to pay"], PAID: ["ok", "Paid"], CANCELLED: ["grey", "Cancelled"],
};

function monthLabel(period: string): string {
  const d = new Date(period);
  return d.toLocaleDateString("en-GB", { month: "long", year: "numeric" });
}

export function Payroll({ runs, detail, actingOffice }: { runs: PayRun[]; detail: RunDetail | null; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["hrm", "super"].includes(actingOffice ?? "");
  const [period, setPeriod] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const drafts = runs.filter((r) => r.state === "DRAFT").length;
  const toPay = runs.filter((r) => r.state === "APPROVED").length;

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/payroll${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  const d = detail;

  return (
    <>
      <RoleLine allowed={["hrm"]} actingOffice={actingOffice} canAct={may} action="Building and approving payroll" />
      <Note kind="info" title="A payroll is built by one officer and approved by another">
        The run is computed over the active establishment: each payslip is a snapshot of the grade&rsquo;s components and the statutory deductions — the employee&rsquo;s 8% pension and PAYE after the consolidated relief. The officer who builds a run cannot approve it, and only an approved run is marked paid.
      </Note>
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <Tiles items={[
        ["Runs", String(runs.length), null, "All months"],
        ["Awaiting approval", String(drafts), drafts ? "var(--red-ink)" : null, "A second officer must agree"],
        ["Approved, to pay", String(toPay), toPay ? "var(--chrome)" : null, "Ready to disburse"],
        ["Last net paid", runs.find((r) => r.state === "PAID") ? money(Number(runs.find((r) => r.state === "PAID")!.net_total)) : "—", "var(--green-ink)", runs.find((r) => r.state === "PAID") ? monthLabel(runs.find((r) => r.state === "PAID")!.period) : "None yet"],
      ]} />

      {may ? (
        <Panel title="Build a run" right="Over everyone active on the establishment">
          <PBody>
            <div className="grid grid--3">
              <Field id="pr-period" label="Month"><input id="pr-period" className="ctl" type="month" value={period} onChange={(e) => setPeriod(e.target.value)} /></Field>
              <Field id="pr-note" label="Note" hint="Optional"><input id="pr-note" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} placeholder="Regular monthly salary" /></Field>
            </div>
            <div><Btn kind="primary" disabled={busy || !period} onClick={async () => { const j = await send("/runs", { period, note: note || null }, `Build payroll for ${period}`); if (j) { setSaid(`${j.staff_count} payslips built — gross ${money(Number(j.gross_total))}, net ${money(Number(j.net_total))}`); setPeriod(""); setNote(""); } }}>Build the run</Btn></div>
            <div className="sub2 mt-2">A month is run once. If the establishment changes after a run is built, cancel it and build again.</div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Pay runs" right={may ? undefined : "You are reading these runs"}>
        {runs.length ? (
          <DTable cols={["Month|mid", "Staff|num", "Gross|num", "Deductions|num", "Net|num", "Stage", "Action|num"]} rows={runs.map((r) => [
            <Link key="m" href={`/payroll?run=${r.id}`} className="tnum b600">{monthLabel(r.period)}</Link>,
            <span className="tnum" key="c">{r.staff_count}</span>,
            <span className="tnum" key="g">{money(Number(r.gross_total))}</span>,
            <span className="tnum sub2" key="d">{money(Number(r.deduction_total))}</span>,
            <b className="tnum" key="n">{money(Number(r.net_total))}</b>,
            <span key="s"><Pil kind={STATE[r.state]?.[0] ?? "grey"}>{STATE[r.state]?.[1] ?? r.state}</Pil>{r.built_by_name ? <div className="sub2">Built by {r.built_by_me ? "you" : r.built_by_name}</div> : null}{r.cancelled_why ? <div className="sub2">{r.cancelled_why}</div> : null}</span>,
            <span key="ac" className="row row--inline row--tight row--right">
              <Link href={`/payroll?run=${r.id}`} className="btn btn--ghost btn--sm btn--icon" title={`View ${monthLabel(r.period)} pay run`} aria-label={`View ${monthLabel(r.period)} pay run`}><Ico name="eye" size={16} /></Link>
              {may && r.state === "DRAFT" && !r.built_by_me ? <Btn kind="go" disabled={busy} onClick={() => void send(`/runs/${r.id}/approve`, {}, `Approve payroll ${monthLabel(r.period)}`).then((j) => { if (j) setSaid(`${monthLabel(r.period)} approved`); })}>Approve</Btn> : null}
              {may && r.state === "DRAFT" && r.built_by_me ? <Btn kind="ghost" disabled>Awaiting another approver</Btn> : null}
              {may && r.state === "APPROVED" ? <Btn kind="primary" disabled={busy} onClick={() => { if (window.confirm(`Mark ${monthLabel(r.period)} paid? Record this once the salaries have been disbursed.`)) void send(`/runs/${r.id}/pay`, {}, `Payroll ${monthLabel(r.period)} paid`).then((j) => { if (j) setSaid(`${monthLabel(r.period)} recorded paid`); }); }}>Mark paid</Btn> : null}
              {may && (r.state === "DRAFT" || r.state === "APPROVED") ? <Btn kind="ghost" disabled={busy} onClick={() => { const w = window.prompt("Why is this run cancelled? The reason is recorded."); if (w && w.trim()) void send(`/runs/${r.id}/cancel`, { why: w.trim() }, `Cancel payroll ${monthLabel(r.period)}`).then((j) => { if (j) setSaid(`${monthLabel(r.period)} cancelled`); }); }}>Cancel</Btn> : null}
            </span>,
          ])} texts={runs.map((r) => `${monthLabel(r.period)} ${r.state}`)} />
        ) : <PBody><div className="sub2">No pay run yet. Build the first month above.</div></PBody>}
      </Panel>

      {d ? (
        <Panel title={`Payslips · ${monthLabel(d.run.period)}`} right={<LinkBtn href="/payroll" kind="ghost">← All runs</LinkBtn>}>
          <div style={{ padding: "0 var(--s-4)" }}>
            <Tiles cls="grid--4" items={[
              ["Staff", String(d.run.staff_count), null, STATE[d.run.state]?.[1] ?? d.run.state],
              ["Gross", money(Number(d.run.gross_total)), null, "Basic and allowances"],
              ["Deductions", money(Number(d.run.deduction_total)), null, "Pension and PAYE"],
              ["Net", money(Number(d.run.net_total)), "var(--green-ink)", "To disburse"],
            ]} />
          </div>
          {d.payslips.length ? (
            <DTable cols={["Staff", "Grade|mid", "Basic|num", "Allowances|num", "Gross|num", "Pension|num", "PAYE|num", "Net|num"]} rows={d.payslips.map((s) => [
              <Two key="p" a={s.name} b={s.staff_no} />,
              <span className="sub2" key="g">{s.grade} · {s.step}<div className="sub2">{s.category === "ACADEMIC" ? "Academic" : "Non-academic"}</div></span>,
              <span className="tnum sub2" key="b">{money(Number(s.basic))}</span>,
              <span className="tnum sub2" key="a">{money(Number(s.allowances))}</span>,
              <span className="tnum" key="gr">{money(Number(s.gross))}</span>,
              <span className="tnum sub2" key="pe">{money(Number(s.pension))}</span>,
              <span className="tnum sub2" key="pa">{money(Number(s.paye))}</span>,
              <b className="tnum" key="n">{money(Number(s.net))}</b>,
            ])} texts={d.payslips.map((s) => `${s.name} ${s.staff_no} ${s.grade}`)} />
          ) : <PBody><div className="sub2">This run has no payslips — no staff were active on the establishment when it was built.</div></PBody>}
        </Panel>
      ) : null}
    </>
  );
}
