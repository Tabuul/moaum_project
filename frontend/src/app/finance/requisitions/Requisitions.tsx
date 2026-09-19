"use client";

/** tRequisitions — procurement: the method is set by the value and cannot be overridden,
 *  and a requisition is approved by a second officer. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Req {
  id: string; reference: string; item: string; description: string | null; cost_centre: string; value: number;
  method: string; state: string; note: string | null; raised_at: string; raised_by_name: string | null; raised_by_me: boolean;
}

const METHOD: Record<string, string> = { QUOTATION: "Quotation", RESTRICTED_TENDER: "Restricted tender", OPEN_BIDDING: "Open bidding" };
const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  RAISED: ["warn", "Awaiting approval"], APPROVED: ["info", "Approved"], PO_RAISED: ["info", "PO raised"], CLOSED: ["ok", "Closed"], REJECTED: ["grey", "Rejected"],
};

export function Requisitions({ rows, actingOffice }: { rows: Req[]; actingOffice: string | null }) {
  const router = useRouter();
  const mayRaise = ["bursar", "ict", "registrar", "hrm", "dean", "super"].includes(actingOffice ?? "");
  const mayApprove = ["bursar", "super"].includes(actingOffice ?? "");
  const [f, setF] = useState({ item: "", description: "", costCentre: "", value: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const raised = rows.filter((r) => r.state === "RAISED").length;
  const methodOf = (v: number) => (v < 2500000 ? "QUOTATION" : v <= 25000000 ? "RESTRICTED_TENDER" : "OPEN_BIDDING");

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/expenditure/requisitions${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="The procurement method is set by value, and cannot be overridden">
        Under {money(2500000)} goes to quotation, {money(2500000)}–{money(25000000)} to restricted tender, above {money(25000000)} to open competitive bidding. A requisition is approved by a second officer, never the one who raised it.
      </Note>
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      <Tiles items={[
        ["Awaiting approval", String(raised), raised ? "var(--red-ink)" : null, "A second officer must agree"],
        ["Approved / PO", String(rows.filter((r) => ["APPROVED", "PO_RAISED"].includes(r.state)).length), null, "In procurement"],
        ["Value awaiting", money(rows.filter((r) => r.state === "RAISED").reduce((n, r) => n + Number(r.value), 0)), null, "Raised, not yet approved"],
        ["Requisitions", String(rows.length), null, "All"],
      ]} />
      <Panel title="Requisitions">
        {rows.length ? (
          <DTable cols={["Reference", "Item", "Cost centre", "Value|num", "Method|mid", "Stage", "Action|num"]} rows={rows.map((r) => [
            <span className="tnum" key="r">{r.reference}</span>,
            <Two key="i" a={r.item} b={r.description ?? ""} />,
            <span className="sub2" key="cc">{r.cost_centre}</span>,
            <b className="tnum" key="v">{money(Number(r.value))}</b>,
            <Pil kind="info" key="m">{METHOD[r.method] ?? r.method}</Pil>,
            <span key="s"><Pil kind={STATE[r.state]?.[0] ?? "grey"}>{STATE[r.state]?.[1] ?? r.state}</Pil>{r.raised_by_name ? <div className="sub2">by {r.raised_by_me ? "you" : r.raised_by_name}</div> : null}{r.note ? <div className="sub2">{r.note}</div> : null}</span>,
            <span key="ac" style={{ display: "inline-flex", gap: 6, flexWrap: "wrap", justifyContent: "flex-end" }}>
              {mayApprove && r.state === "RAISED" && !r.raised_by_me ? <Btn kind="go" disabled={busy} onClick={() => void send(`/${r.id}/approve`, {}, `Approve ${r.reference}`).then((j) => { if (j) setSaid(`${r.reference} approved`); })}>Approve</Btn> : null}
              {mayApprove && r.state === "RAISED" && r.raised_by_me ? <Btn kind="ghost" disabled>Awaiting another approver</Btn> : null}
              {mayApprove && r.state === "RAISED" ? <Btn kind="ghost" disabled={busy} onClick={() => { const w = window.prompt("Why is it rejected?"); if (w && w.trim()) void send(`/${r.id}/reject`, { why: w.trim() }, `Reject ${r.reference}`); }}>Reject</Btn> : null}
              {mayApprove && r.state === "APPROVED" ? <Btn kind="primary" disabled={busy} onClick={() => void send(`/${r.id}/po`, {}, `PO for ${r.reference}`)}>Raise PO</Btn> : null}
              {mayApprove && r.state === "PO_RAISED" ? <Btn kind="ghost" disabled={busy} onClick={() => void send(`/${r.id}/close`, {}, `Close ${r.reference}`)}>Close</Btn> : null}
            </span>,
          ])} texts={rows.map((r) => `${r.reference} ${r.item} ${r.cost_centre} ${r.state}`)} />
        ) : <PBody><div className="sub2">No requisition raised.</div></PBody>}
      </Panel>
      {mayRaise ? (
        <Panel title="Raise a requisition" right="The method is shown as you type the value">
          <PBody>
            <div className="grid grid--2">
              <Field id="rq-item" label="Item"><input id="rq-item" className="ctl" value={f.item} onChange={(e) => setF({ ...f, item: e.target.value })} /></Field>
              <Field id="rq-cc" label="Cost centre"><input id="rq-cc" className="ctl" value={f.costCentre} onChange={(e) => setF({ ...f, costCentre: e.target.value })} placeholder="ICT Directorate" /></Field>
            </div>
            <Field id="rq-desc" label="Description" hint="Optional"><input id="rq-desc" className="ctl" value={f.description} onChange={(e) => setF({ ...f, description: e.target.value })} /></Field>
            <Field id="rq-value" label="Value (₦)" hint={f.value && Number(f.value) > 0 ? `Method: ${METHOD[methodOf(Number(f.value))]}` : "Determines the procurement method"}><input id="rq-value" className="ctl tnum" inputMode="decimal" value={f.value} onChange={(e) => setF({ ...f, value: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
            <div><Btn kind="primary" disabled={busy || !f.item.trim() || !f.costCentre.trim() || !(Number(f.value) > 0)} onClick={async () => { const j = await send("", { item: f.item.trim(), description: f.description || null, costCentre: f.costCentre.trim(), value: Number(f.value) }, `Raise requisition for ${f.item.trim()}`); if (j) { setSaid(`Requisition ${j.reference} raised`); setF({ item: "", description: "", costCentre: "", value: "" }); } }}>Raise it</Btn></div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
