"use client";

/** pTenders — proto/part…: a procurement's method is set by its value; bids are scored on a
 *  technical threshold before price; the lowest responsive bid wins unless the Board records why. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Tender {
  id: string; reference: string; subject: string; cost_centre: string | null; estimate: number; method: string;
  technical_threshold: number; stage: string; opened_at: string; awarded_why: string | null; cancelled_why: string | null;
  bids: number; responsive: number; awarded_to: string | null; awarded_price: number | null;
}
export interface Bid { id: string; bidder: string; price: number; technical_score: number | null; responsive: boolean | null; reason: string | null; rank: number | null }

const STAGE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  ADVERTISED: ["info", "Advertised — taking bids"], EVALUATED: ["warn", "Evaluated — to award"], AWARDED: ["ok", "Awarded"], CANCELLED: ["grey", "Cancelled"],
};
const METHOD: Record<string, string> = { QUOTATION: "Quotation", RESTRICTED: "Restricted tender", OPEN: "Open competitive bidding" };

export function Tenders({ tenders, selected, bids, actingOffice }: { tenders: Tender[]; selected: string; bids: Bid[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["bursar", "super"].includes(actingOffice ?? "");
  const [add, setAdd] = useState(false);
  const [f, setF] = useState({ subject: "", costCentre: "", estimate: "", threshold: "70" });
  const [addBid, setAddBid] = useState(false);
  const [b, setB] = useState({ bidder: "", price: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const tender = tenders.find((t) => t.id === selected) ?? null;

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/expenditure/tenders${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
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
      <Note kind="info" title="A procurement's method is set by its value, and the lowest bid is not automatically the winner">
        Under ₦2.5m goes to quotation, ₦2.5m to ₦25m to a restricted tender, above ₦25m to open competitive bidding. Bids are scored on a technical threshold before price is looked at; a bid below the threshold or with an invalid clearance is not responsive, and the reason is recorded. Award goes to the lowest responsive bid unless the Board records why it does not.
      </Note>

      {said ? <Note kind="ok" title={said} /> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <Tiles items={[
        ["Open tenders", String(tenders.filter((t) => t.stage === "ADVERTISED" || t.stage === "EVALUATED").length), null, "Taking or evaluating bids"],
        ["Awarded", String(tenders.filter((t) => t.stage === "AWARDED").length), "var(--green-ink)", "On the record"],
        ["All", String(tenders.length), null, "Newest 300"],
        ["", may ? "" : "Read only", null, ""],
      ]} />

      {may ? <div><button className="btn btn--primary" onClick={() => { setF({ subject: "", costCentre: "", estimate: "", threshold: "70" }); setErr(null); setAdd(true); }}>+ Open a tender</button></div> : null}

      <Panel title="Tenders" right="Method by value · technical threshold before price">
        {tenders.length ? (
          <DTable cols={["Reference", "Subject", "Estimate|num", "Method", "Bids|mid", "Stage", "|num"]} rows={tenders.map((t) => [
            <span className="tnum" key="r">{t.reference}</span>,
            <Two key="s" a={t.subject} b={t.cost_centre ?? ""} />,
            <b className="tnum" key="e">{money(Number(t.estimate))}</b>,
            <span className="sub2" key="m">{METHOD[t.method] ?? t.method}</span>,
            <span className="tnum" key="b">{t.bids}{t.responsive ? ` · ${t.responsive} ok` : ""}</span>,
            <span key="st"><Pil kind={STAGE[t.stage]?.[0] ?? "grey"}>{STAGE[t.stage]?.[1] ?? t.stage}</Pil>{t.awarded_to ? <div className="sub2">{t.awarded_to} · {money(Number(t.awarded_price))}</div> : null}</span>,
            <Btn key="a" kind={selected === t.id ? "primary" : "ghost"} onClick={() => router.push(`/finance/tenders?t=${t.id}`)}>{selected === t.id ? "Open" : "Evaluate"}</Btn>,
          ])} texts={tenders.map((t) => `${t.reference} ${t.subject}`)} />
        ) : <PBody><div className="sub2">No tender has been opened. Open one for a procurement above the quotation threshold.</div></PBody>}
      </Panel>

      {tender ? (
        <Panel title={`${tender.reference} — ${tender.subject}`} right={`${METHOD[tender.method] ?? tender.method} · estimate ${money(Number(tender.estimate))} · threshold ${tender.technical_threshold}%`}>
          <PBody>
            {tender.stage === "ADVERTISED" && may ? <div style={{ marginBottom: 8 }}><Btn kind="ghost" onClick={() => { setB({ bidder: "", price: "" }); setErr(null); setAddBid(true); }}>+ Record a bid</Btn></div> : null}
            {bids.length ? (
              <DTable cols={["Bidder", "Technical|mid", "Bid price|num", "Responsive|mid", "Rank|mid", "Action|num"]} rows={bids.map((bd) => [
                <strong key="b">{bd.bidder}</strong>,
                <span className="tnum" key="t">{bd.technical_score ?? "—"}</span>,
                <span className="tnum" key="p">{money(Number(bd.price))}</span>,
                bd.responsive === true ? <Pil kind="ok" key="r">Yes</Pil> : bd.responsive === false ? <Pil kind="bad" key="r">No{bd.reason ? ` — ${bd.reason}` : ""}</Pil> : <span className="sub2" key="r">Not scored</span>,
                <span className="tnum" key="rk">{bd.rank ? <strong>{bd.rank}</strong> : "—"}</span>,
                <span key="a" style={{ display: "inline-flex", gap: 6, flexWrap: "wrap" }}>
                  {may && (tender.stage === "ADVERTISED" || tender.stage === "EVALUATED") ? <Btn kind="ghost" disabled={busy} onClick={() => { const ts = window.prompt("Technical score out of 100 (blank = not evaluated):", bd.technical_score?.toString() ?? ""); if (ts === null) return; const t = ts.trim() === "" ? null : Number(ts); const resp = t !== null && t >= tender.technical_threshold; let reason: string | null = null; if (!resp) { reason = window.prompt("Why is it not responsive? (e.g. below threshold, tax clearance expired)"); if (!reason) return; } void send(`/bids/${bd.id}/score`, { technical: t, responsive: resp, reason }, `Score bid on ${tender.reference}`).then((j) => { if (j) setSaid("Bid scored"); }); }}>Score</Btn> : null}
                  {may && tender.stage === "EVALUATED" && bd.responsive === true ? <Btn kind="go" disabled={busy} onClick={() => { const lower = bids.some((o) => o.responsive === true && Number(o.price) < Number(bd.price)); let why: string | null = ""; if (lower) { why = window.prompt("A lower responsive bid exists. Why is this one awarded?"); if (!why) return; } if (window.confirm(`Award ${tender.reference} to ${bd.bidder} at ${money(Number(bd.price))}?`)) void send(`/${tender.id}/award`, { bid: bd.id, why }, `Award ${tender.reference}`).then((j) => { if (j) setSaid(`${tender.reference} awarded to ${bd.bidder}`); }); }}>Award</Btn> : null}
                </span>,
              ])} texts={bids.map((bd) => bd.bidder)} />
            ) : <div className="sub2">No bid recorded yet.</div>}
            {tender.awarded_why ? <Note kind="info" title="Why this award, and not the lowest bid">{tender.awarded_why}</Note> : null}
            {may && tender.stage !== "AWARDED" && tender.stage !== "CANCELLED" ? <div style={{ marginTop: 8 }}><Btn kind="ghost" disabled={busy} onClick={() => { const w = window.prompt("Cancel this tender. The reason is recorded."); if (w) void send(`/${tender.id}/cancel`, { why: w }, `Cancel ${tender.reference}`); }}>Cancel the tender</Btn></div> : null}
          </PBody>
        </Panel>
      ) : null}

      {add ? (
        <Modal title="Open a tender" sub="Its method is set from the estimate" onClose={() => setAdd(false)}
          foot={<><Btn kind="ghost" onClick={() => setAdd(false)}>Cancel</Btn><span style={{ flexGrow: 1 }} /><Btn kind="primary" disabled={busy || !f.subject.trim() || !(Number(f.estimate) > 0)} onClick={async () => { const j = await send("", { subject: f.subject, costCentre: f.costCentre || null, estimate: Number(f.estimate), threshold: Number(f.threshold) || 70 }, `Open tender: ${f.subject}`); if (j) { setSaid(`Tender ${j.reference} opened`); setAdd(false); } }}>Open it</Btn></>}>
          {err ? <ProblemNotice problem={err} /> : null}
          <Field id="tn-subject" label="What is being procured"><input id="tn-subject" className="ctl" value={f.subject} onChange={(e) => setF({ ...f, subject: e.target.value })} placeholder="40 desktop computers" autoComplete="off" /></Field>
          <div className="grid grid--3">
            <Field id="tn-est" label="Estimate (₦)"><input id="tn-est" className="ctl tnum" value={f.estimate} inputMode="decimal" onChange={(e) => setF({ ...f, estimate: e.target.value })} /></Field>
            <Field id="tn-cc" label="Cost centre" hint="Optional"><input id="tn-cc" className="ctl" value={f.costCentre} onChange={(e) => setF({ ...f, costCentre: e.target.value })} autoComplete="off" /></Field>
            <Field id="tn-th" label="Technical threshold (%)"><input id="tn-th" className="ctl tnum" value={f.threshold} inputMode="numeric" onChange={(e) => setF({ ...f, threshold: e.target.value })} /></Field>
          </div>
          {Number(f.estimate) > 0 ? <div className="sub2">Method: <b>{Number(f.estimate) < 2500000 ? "Quotation" : Number(f.estimate) <= 25000000 ? "Restricted tender" : "Open competitive bidding"}</b></div> : null}
        </Modal>
      ) : null}

      {addBid && tender ? (
        <Modal title={`Record a bid on ${tender.reference}`} sub="Sealed until opening; recorded here after" onClose={() => setAddBid(false)}
          foot={<><Btn kind="ghost" onClick={() => setAddBid(false)}>Cancel</Btn><span style={{ flexGrow: 1 }} /><Btn kind="primary" disabled={busy || !b.bidder.trim() || !(Number(b.price) > 0)} onClick={async () => { const j = await send(`/${tender.id}/bids`, { bidder: b.bidder, price: Number(b.price) }, `Bid on ${tender.reference}`); if (j) { setSaid("Bid recorded"); setAddBid(false); } }}>Record it</Btn></>}>
          {err ? <ProblemNotice problem={err} /> : null}
          <div className="grid grid--2">
            <Field id="bd-bidder" label="Bidder"><input id="bd-bidder" className="ctl" value={b.bidder} onChange={(e) => setB({ ...b, bidder: e.target.value })} autoComplete="off" /></Field>
            <Field id="bd-price" label="Bid price (₦)"><input id="bd-price" className="ctl tnum" value={b.price} inputMode="decimal" onChange={(e) => setB({ ...b, price: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
