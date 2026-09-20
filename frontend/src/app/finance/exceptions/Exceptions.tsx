"use client";

/** staffException and tCashDesk — proto/part15, part48: a bank credit with no reference is recorded as it came, proposed by one officer, approved by another, then posted (V037). */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import type { BankCredit } from "@/lib/bursary";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Gate, Gates, day, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export function Exceptions({ credits, state, gatewayExceptions, actingOffice }: { credits: BankCredit[]; state: string; gatewayExceptions: number; actingOffice: string | null }) {
  const router = useRouter();
  const may = actingOffice === "bursar" || actingOffice === "super";
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const [c, setC] = useState({ receivedOn: "", bank: "", instrument: "", amount: "", payer: "", note: "" });
  const [prop, setProp] = useState<Record<string, { reference: string; why: string }>>({});
  const open = credits.filter((x) => x.state === "UNMATCHED" || x.state === "PROPOSED");
  const openAmount = open.reduce((n, x) => n + Number(x.amount), 0);

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/finance${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind={open.length ? "bad" : "ok"} title={open.length ? `${money(openAmount)} is sitting in the University's account and belongs to somebody` : "No bank credit waits to be attributed"}>
        {open.length ? "A payment the University cannot attribute is worse than a payment it never received: a student has paid, believes they have paid, and may be blocked from registering. The clock on this exception is the registration deadline, not the accounting period." : "Money that arrives at a bank counter with no reference quoted is recorded here as it came, and posted only when two officers have agreed where it belongs."}
        {gatewayExceptions ? <> {gatewayExceptions} gateway event{gatewayExceptions === 1 ? "" : "s"} also need{gatewayExceptions === 1 ? "s" : ""} a person — see <Link href="/finance/hanging">hanging payments</Link>.</> : null}
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}
      <Tiles items={[
        ["Open", String(open.length), open.length ? "var(--red-ink)" : null, money(openAmount)],
        ["Proposed, awaiting a second officer", String(open.filter((x) => x.state === "PROPOSED").length), null, "The proposer cannot approve"],
        ["Posted", String(credits.filter((x) => x.state === "POSTED").length), "var(--green-ink)", state === "open" ? "Shown under Posted" : "In this view"],
        ["Cash ceiling", money(1000), null, "Cash below it at the counter; a draft above it"],
      ]} />
      <div className="card"><div className="card__body" style={{ flexDirection: "row", gap: 8 }}>
        {[["open", "Open"], ["posted", "Posted"], ["all", "All"]].map(([k, l]) => <Link key={k} href={`/finance/exceptions?state=${k}`} className={`btn btn--sm ${state === k ? "btn--primary" : "btn--ghost"}`}>{l}</Link>)}
      </div></div>
      <Panel title="Bank credits" right="Recorded as they came; the bank record is never altered">
        {credits.length ? (
          <DTable cols={["Received|mid", "Instrument", "Payer named", "Amount|num", "State", "Resolution|num"]} rows={credits.map((x) => [
            <span className="sub2 tnum" key="d">{day(x.received_on)}</span>,
            <Two key="i" a={`${x.bank} · ${x.instrument}`} b={`${x.note ?? ""}${x.recorded_by_name ? ` · recorded by ${x.recorded_by_name}` : ""}`} />,
            <span key="p">{x.payer ?? <span className="sub2">Not named</span>}</span>,
            <b className="tnum" key="a">{money(Number(x.amount))}</b>,
            <span key="s">{x.state === "POSTED" ? <Pil kind="ok">Posted to {x.posted_reference}</Pil> : x.state === "PROPOSED" ? <Pil kind="info">Proposed</Pil> : x.state === "REVERSED" ? <Pil kind="grey">Reversed</Pil> : <Pil kind="bad">Unmatched</Pil>}
              {x.state === "PROPOSED" ? <div className="sub2">{x.proposed_reference} ({x.reference_amount !== null ? money(Number(x.reference_amount)) : ""}) — {x.proposed_why} · {x.proposed_by_name}</div> : null}
              {x.state === "POSTED" ? <div className="sub2">Proposed by {x.proposed_by_name}, approved by {x.approved_by_name} · {day(x.approved_at)}</div> : null}
              {x.rejected_why ? <div className="sub2">Last proposal rejected: {x.rejected_why}</div> : null}</span>,
            <span key="r" style={{ display: "flex", gap: 6, flexWrap: "wrap", justifyContent: "flex-end" }}>
              {may && x.state === "UNMATCHED" ? <>
                <input className="ctl tnum" style={{ width: 170 }} placeholder="Reference to post to" value={prop[x.id]?.reference ?? ""} onChange={(e) => setProp({ ...prop, [x.id]: { reference: e.target.value, why: prop[x.id]?.why ?? "" } })} />
                <input className="ctl" style={{ width: 200 }} placeholder="On what evidence" value={prop[x.id]?.why ?? ""} onChange={(e) => setProp({ ...prop, [x.id]: { reference: prop[x.id]?.reference ?? "", why: e.target.value } })} />
                <Btn kind="primary" disabled={busy || !prop[x.id]?.reference || !prop[x.id]?.why} onClick={async () => { if (await send(`/bank-credits/${x.id}/propose`, prop[x.id], `Bank credit ${x.instrument} proposed against ${prop[x.id].reference}`)) setSaid("Proposed — a second officer approves"); }}>Propose</Btn>
              </> : null}
              {may && x.state === "PROPOSED" ? (x.proposed_by_me ? <Pil kind="info">Your proposal — another officer approves</Pil> : <><Btn kind="go" disabled={busy} onClick={async () => { const j = await send(`/bank-credits/${x.id}/approve`, {}, `Bank credit ${x.instrument} approved and posted to ${x.proposed_reference}`); if (j) setSaid(`Posted: ${j.outcome}`); }}>Approve and post</Btn><Btn kind="ghost" disabled={busy} onClick={async () => { const why = window.prompt("Why is the proposal rejected?"); if (why && await send(`/bank-credits/${x.id}/reject`, { why }, `Bank credit proposal rejected: ${why}`)) setSaid("Rejected; the credit is open again"); }}>Reject</Btn></>) : null}
            </span>,
          ])} texts={credits.map((x) => `${x.bank} ${x.instrument} ${x.payer ?? ""} ${x.proposed_reference ?? ""}`)} />
        ) : <PBody><div className="sub2">No bank credit in this view.</div></PBody>}
      </Panel>
      {may ? (
        <Panel title="Record a bank credit" right="The cash office: a draft or a counter credit, as the bank shows it">
          <PBody>
            <div className="grid grid--3">
              <Field id="bc-on" label="Received on"><input id="bc-on" className="ctl" type="date" value={c.receivedOn} onChange={(e) => setC({ ...c, receivedOn: e.target.value })} /></Field>
              <Field id="bc-bank" label="Bank"><input id="bc-bank" className="ctl" value={c.bank} onChange={(e) => setC({ ...c, bank: e.target.value })} placeholder="Zenith Bank, Makurdi" /></Field>
              <Field id="bc-ins" label="Teller slip or draft number"><input id="bc-ins" className="ctl tnum" value={c.instrument} onChange={(e) => setC({ ...c, instrument: e.target.value })} placeholder="BR/44821" /></Field>
              <Field id="bc-amt" label="Amount"><input id="bc-amt" className="ctl tnum" value={c.amount} onChange={(e) => setC({ ...c, amount: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
              <Field id="bc-payer" label="Payer named on the slip"><input id="bc-payer" className="ctl" value={c.payer} onChange={(e) => setC({ ...c, payer: e.target.value })} /></Field>
              <Field id="bc-note" label="Note"><input id="bc-note" className="ctl" value={c.note} onChange={(e) => setC({ ...c, note: e.target.value })} /></Field>
            </div>
            <div><Btn kind="ghost" disabled={busy || !c.bank.trim() || !c.instrument.trim() || !Number(c.amount)} onClick={async () => { if (await send("/bank-credits", { ...c, receivedOn: c.receivedOn || null, amount: Number(c.amount), payer: c.payer || null, note: c.note || null }, `Bank credit ${c.instrument} recorded`)) { setSaid("Recorded, unmatched"); setC({ receivedOn: "", bank: "", instrument: "", amount: "", payer: "", note: "" }); } }}>Record the credit</Btn></div>
          </PBody>
        </Panel>
      ) : null}
      <Panel title="Why it is a posting, never an edit">
        <PBody>
          <Gates>
            <Gate state="done" title="The bank record is never altered" sub="It is evidence. The posting is a new entry that references it." />
            <Gate state="done" title="Two people, recorded separately" sub="Proposer and approver, and never the same person — the database refuses the second click." />
            <Gate state="done" title="The reason is stored with the entry" sub="On the credit, permanently, with the proposer's name." />
            <Gate state="done" title="The student is told what changed" sub="The posting is the same confirmation every payment passes, and it sends the receipt." last />
          </Gates>
        </PBody>
      </Panel>
    </>
  );
}
