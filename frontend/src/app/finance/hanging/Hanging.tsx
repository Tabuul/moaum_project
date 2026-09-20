"use client";

/** tHanging — proto/part48.html: a payment that succeeded at the gateway has succeeded; the portal asks the gateway, not the student (V037). */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { OUTCOME, when, type PaymentsDesk } from "@/lib/bursary";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export function Hanging({ d, actingOffice }: { d: PaymentsDesk; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["bursar", "ict", "admin", "super"].includes(actingOffice ?? "");
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const settledBySweep = d.events.filter((e) => e.source === "SWEEP" && e.outcome === "SETTLED").length;
  const settledByVerify = d.events.filter((e) => e.source === "VERIFY" && e.outcome === "SETTLED").length;
  const needsPerson = d.events.filter((e) => ["UNKNOWN_REFERENCE", "SHORT_PAID", "GATEWAY_ERROR"].includes(e.outcome) && !e.resolved_at);

  async function verify(reference: string) {
    setBusy(reference);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/payments/verify", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Hanging payment ${reference} verified with the gateway`) }, body: JSON.stringify({ reference }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setSaid(`${reference}: ${j.outcome}${j.said ? ` (${j.said})` : ""}`);
      notify(`${reference}: ${j.outcome}`);
      router.refresh();
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <Note kind="info" title="A payment that succeeded at the gateway has succeeded">
        The portal&rsquo;s record is a copy; the gateway&rsquo;s is the fact. When the two disagree the portal is wrong, and the student is not the party who should have to prove it. <b>There is no upload-your-evidence form on this page, and that is the design.</b> The portal asks the gateway.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record; the student is told when a settlement posts.</Note> : null}
      <Tiles items={[
        ["Hanging now", String(d.hanging.length), d.hanging.length ? "var(--red-ink)" : null, "Checkout opened, nothing confirmed, last three days"],
        ["Resolved without a person", String(settledBySweep + settledByVerify), "var(--green-ink)", `${settledBySweep} by the sweep, ${settledByVerify} on request`],
        ["Needs a person", String(needsPerson.length), needsPerson.length ? "var(--red-ink)" : null, "Unknown reference, short paid, or the gateway silent"],
        ["The sweep", "Every 10 min", null, "Runs whether or not this page is open"],
      ]} />
      <Panel title="Hanging at a gateway" right="Oldest first · the sweep asks about each after five minutes, up to twelve times">
        {d.hanging.length ? (
          <DTable cols={["Opened|mid", "Payer", "Reference", "Gateway", "Amount|num", "Asked|mid", "|num"]} rows={d.hanging.map((h) => [
            <span className="sub2 tnum" key="o">{when(h.opened_at)}<div className="sub2">{h.minutes} min ago</div></span>,
            <Two key="p" a={h.payer ?? "—"} b={h.number ?? h.kind} />,
            <span className="tnum sub2" key="r">{h.reference}</span>,
            <span key="g" style={{ textTransform: "capitalize" }}>{h.gateway}</span>,
            <b className="tnum" key="a">{h.amount === null ? "—" : money(Number(h.amount))}</b>,
            <span className="sub2 tnum" key="c">{h.checks ? `${h.checks}× · last ${when(h.checked_at)}` : "not yet"}</span>,
            may ? <Btn key="v" kind="primary" disabled={busy !== null} onClick={() => void verify(h.reference)}>{busy === h.reference ? "Asking…" : "Ask the gateway"}</Btn> : <span className="sub2" key="v">—</span>,
          ])} texts={d.hanging.map((h) => `${h.reference} ${h.payer ?? ""} ${h.number ?? ""}`)} />
        ) : <PBody><div className="sub2">Nothing is hanging: every checkout opened in the last three days is confirmed, or was never paid.</div></PBody>}
      </Panel>
      <Panel title="Needs a person" right="What the sweep could not resolve on its own">
        {needsPerson.length ? (
          <DTable cols={["When|mid", "Gateway", "Reference", "Amount|num", "Why it hung", "|num"]} rows={needsPerson.map((e) => [
            <span className="sub2 tnum" key="w">{when(e.received_at)}</span>,
            <span key="g" style={{ textTransform: "capitalize" }}>{e.gateway}</span>,
            <span className="tnum sub2" key="r">{e.reference ?? "—"}</span>,
            <span className="tnum" key="a">{e.amount === null ? "—" : money(Number(e.amount))}</span>,
            <span key="o"><Pil kind={OUTCOME[e.outcome]?.[1] ?? "grey"}>{OUTCOME[e.outcome]?.[0] ?? e.outcome}</Pil><div className="sub2">{e.outcome === "UNKNOWN_REFERENCE" ? "Generated and abandoned, paid against another institution's code, or forged — the desk officer chooses; the portal does not guess." : e.outcome === "SHORT_PAID" ? "Less than the reference asks; applied as nothing, left open. A part payment needs a reference for the part." : "The gateway did not answer for this reference."}</div></span>,
            may ? <Btn key="x" kind="ghost" disabled={busy !== null} onClick={async () => { const why = window.prompt("How was it resolved? It goes on the record."); if (!why) return; const r = await fetch(`/api/bff/api/v1/payments/events/${e.id}/resolve`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Gateway event resolved: ${why}`) }, body: JSON.stringify({ resolution: why }) }); if (r.ok) { setSaid("Resolved"); notify("Gateway event resolved"); router.refresh(); } }}>Resolve</Btn> : <span className="sub2" key="x">—</span>,
          ])} />
        ) : <PBody><div className="sub2">Nothing waits on a person.</div></PBody>}
      </Panel>
      <Note kind="ok" title="The student is told, not left to notice">Every settlement — by webhook, by the sweep, or on request — sends the receipt by email and SMS on the spot, and the student&rsquo;s fees page shows it.</Note>
    </>
  );
}
