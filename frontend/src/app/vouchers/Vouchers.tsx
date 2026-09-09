"use client";

/** tPaymentVoucher / tPrePayment — proto/part…: the Bursary raises a voucher, it advances
 *  one desk at a time through Internal Audit, a query blocks it, and it returns to the Bursary
 *  to pay. BR-006 forbids any person acting twice in its chain. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Voucher {
  id: string; reference: string; title: string; kind: string; source: string; cost_centre: string | null; payee: string;
  amount: number; stage: string; raised_at: string; paid_at: string | null; rejected_why: string | null;
  raised_by_name: string | null; raised_by_me: boolean; query_open: boolean; i_acted: boolean;
  open_query_id: string | null; open_query_finding: string | null; open_query_to: string | null;
}

const STAGE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  WITH_DIRECTOR: ["info", "With the Director of Audit"], WITH_DEPUTY: ["info", "With the Deputy Director"],
  WITH_AUDITOR: ["info", "With the auditor"], CLEARED: ["warn", "Cleared — to pay"], PAID: ["ok", "Paid"], REJECTED: ["grey", "Rejected"],
};
const AUDIT_STAGES = ["WITH_DIRECTOR", "WITH_DEPUTY", "WITH_AUDITOR"];
const KINDS = ["SALARY", "CONTRACT", "OVERHEAD", "CLAIM", "GRANT"];
const SOURCES = ["IGR", "SUBVENTION", "TETFUND", "GRANT", "OTHER"];

export function Vouchers({ vouchers, actingOffice }: { vouchers: Voucher[]; actingOffice: string | null }) {
  const router = useRouter();
  const isBursar = ["bursar", "super"].includes(actingOffice ?? "");
  const isAudit = ["audit", "deputyaudit", "super"].includes(actingOffice ?? "");
  const [add, setAdd] = useState(false);
  const [f, setF] = useState({ title: "", kind: "CONTRACT", source: "IGR", costCentre: "", payee: "", amount: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const onDesk = vouchers.filter((v) => AUDIT_STAGES.includes(v.stage)).length;
  const blocked = vouchers.filter((v) => v.query_open).length;
  const toPay = vouchers.filter((v) => v.stage === "CLEARED").length;

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/expenditure/vouchers${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return null; }
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind={blocked ? "bad" : "info"} title={blocked ? `${blocked} voucher${blocked === 1 ? "" : "s"} cannot move while a query stands` : "Every University payment passes Internal Audit before money moves"}>
        A voucher advances one desk at a time: the Bursary raises it, the Director signs, the Deputy signs, an auditor attests, and it returns to the Bursary to pay. A query is a finding sent to a named office, and the voucher waits where it is until it is answered. No person may act twice in its chain, however many offices they hold.
      </Note>

      {said ? <Note kind="ok" title={said} /> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <Tiles items={[
        ["On the audit desk", String(onDesk), null, "Awaiting a signature"],
        ["Queries open", String(blocked), blocked ? "var(--red-ink)" : "var(--green-ink)", blocked ? "Payment blocked" : "Nothing outstanding"],
        ["Cleared, to pay", String(toPay), toPay ? "var(--chrome)" : null, "Back with the Bursary"],
        ["All", String(vouchers.length), null, "Newest 300"],
      ]} />

      {isBursar ? <div><button className="btn btn--primary" onClick={() => { setF({ title: "", kind: "CONTRACT", source: "IGR", costCentre: "", payee: "", amount: "" }); setErr(null); setAdd(true); }}>+ Raise a voucher</button></div> : null}

      <Panel title="Payment vouchers" right="Bursary raises → Director → Deputy → auditor → back to the Bursary">
        {vouchers.length ? (
          <DTable cols={["Voucher", "What it is", "Amount|num", "Stage", "Action|num"]} rows={vouchers.map((v) => [
            <span className="tnum" key="r">{v.reference}</span>,
            <Two key="w" a={v.title} b={`${v.kind.charAt(0)}${v.kind.slice(1).toLowerCase()} · ${v.source} · ${v.payee}`} />,
            <b className="tnum" key="a">{money(Number(v.amount))}</b>,
            <span key="s"><Pil kind={v.query_open ? "bad" : STAGE[v.stage]?.[0] ?? "grey"}>{v.query_open ? "Query open" : STAGE[v.stage]?.[1] ?? v.stage}</Pil>{v.rejected_why ? <div className="sub2">{v.rejected_why}</div> : null}{v.open_query_finding ? <div className="sub2">{v.open_query_finding} → {v.open_query_to}</div> : null}</span>,
            <span key="ac" style={{ display: "inline-flex", gap: 6, flexWrap: "wrap" }}>
              {v.query_open && v.open_query_id ? <Btn kind="primary" disabled={busy} onClick={() => { const a = window.prompt("Answer the query. It is recorded and lets the voucher move again."); if (a) void send(`/queries/${v.open_query_id}/answer`, { answer: a }, `Answer query on ${v.reference}`).then((j) => { if (j) setSaid(`Query on ${v.reference} answered`); }); }}>Answer query</Btn> : null}
              {isAudit && !v.query_open && AUDIT_STAGES.includes(v.stage) && !v.i_acted && !v.raised_by_me ? <Btn kind="go" disabled={busy} onClick={() => { const n = window.prompt("A note on this signature (optional). Leave blank to just sign.") ?? ""; void send(`/${v.id}/advance`, { note: n }, `Advance ${v.reference}`).then((j) => { if (j) setSaid(`${v.reference} advanced`); }); }}>Sign &amp; advance</Btn> : null}
              {isAudit && !v.query_open && AUDIT_STAGES.includes(v.stage) ? <Btn kind="ghost" disabled={busy} onClick={() => { const fnd = window.prompt("The finding (what is wrong or missing):"); if (!fnd) return; const to = window.prompt("Sent to which office? e.g. Bursary, Works"); if (!to) return; void send(`/${v.id}/query`, { finding: fnd, sentTo: to }, `Query on ${v.reference}`).then((j) => { if (j) setSaid(`Query raised on ${v.reference}`); }); }}>Query</Btn> : null}
              {isAudit && AUDIT_STAGES.includes(v.stage) ? <Btn kind="ghost" disabled={busy} onClick={() => { const w = window.prompt("Reject this voucher. The reason is recorded."); if (w) void send(`/${v.id}/reject`, { why: w }, `Reject ${v.reference}`); }}>Reject</Btn> : null}
              {isBursar && v.stage === "CLEARED" && !v.query_open ? <Btn kind="primary" disabled={busy} onClick={() => { if (window.confirm(`Pay ${v.reference} (${money(Number(v.amount))} to ${v.payee})? Record this once the money has left.`)) void send(`/${v.id}/pay`, {}, `Pay ${v.reference}`).then((j) => { if (j) setSaid(`${v.reference} recorded paid`); }); }}>Mark paid</Btn> : null}
              {v.i_acted && AUDIT_STAGES.includes(v.stage) ? <span className="sub2">You have acted on this one</span> : null}
            </span>,
          ])} texts={vouchers.map((v) => `${v.reference} ${v.title} ${v.payee}`)} />
        ) : <PBody><div className="sub2">No voucher has been raised. The Bursary raises one for a payment, and it passes Internal Audit before any money moves.</div></PBody>}
      </Panel>

      <Note kind="bad" title="BR-006 applies to a voucher exactly as it applies to a mark">
        The officer who prepared or authorised a voucher may not audit it, and no person may act twice in its chain, however many offices they hold. It is the same constraint on the same act table, keyed on the person and not the office. The ninth check on a contract voucher — the site visit — is attested by the auditor in their own name, because a portal cannot evidence a person standing on a site.
      </Note>

      {add ? (
        <Modal title="Raise a voucher" sub="It goes to Internal Audit before it can be paid" onClose={() => setAdd(false)}
          foot={<><Btn kind="ghost" onClick={() => setAdd(false)}>Cancel</Btn><span style={{ flexGrow: 1 }} />
            <Btn kind="primary" disabled={busy || !f.title.trim() || !f.payee.trim() || !(Number(f.amount) > 0)} onClick={async () => { const j = await send("", { title: f.title, kind: f.kind, source: f.source, costCentre: f.costCentre || null, payee: f.payee, amount: Number(f.amount) }, `Raise voucher for ${f.payee}`); if (j) { setSaid(`Voucher ${j.reference} raised — with the Director of Audit`); setAdd(false); } }}>Raise it</Btn></>}>
          {err ? <ProblemNotice problem={err} /> : null}
          <Field id="pv-title" label="What it is for"><input id="pv-title" className="ctl" value={f.title} onChange={(e) => setF({ ...f, title: e.target.value })} placeholder="TetFund laboratory block — first certificate" autoComplete="off" /></Field>
          <div className="grid grid--2">
            <Field id="pv-payee" label="Payee"><input id="pv-payee" className="ctl" value={f.payee} onChange={(e) => setF({ ...f, payee: e.target.value })} autoComplete="off" /></Field>
            <Field id="pv-amount" label="Amount (₦)"><input id="pv-amount" className="ctl tnum" value={f.amount} inputMode="decimal" onChange={(e) => setF({ ...f, amount: e.target.value })} /></Field>
          </div>
          <div className="grid grid--3">
            <Field id="pv-kind" label="Kind"><select id="pv-kind" className="ctl" value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value })}>{KINDS.map((k) => <option key={k} value={k}>{k.charAt(0) + k.slice(1).toLowerCase()}</option>)}</select></Field>
            <Field id="pv-source" label="Source"><select id="pv-source" className="ctl" value={f.source} onChange={(e) => setF({ ...f, source: e.target.value })}>{SOURCES.map((s) => <option key={s} value={s}>{s}</option>)}</select></Field>
            <Field id="pv-cc" label="Cost centre" hint="Optional"><input id="pv-cc" className="ctl" value={f.costCentre} onChange={(e) => setF({ ...f, costCentre: e.target.value })} autoComplete="off" /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
