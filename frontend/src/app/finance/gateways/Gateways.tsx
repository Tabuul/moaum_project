"use client";

/** tGateways — proto/part18.html: the gateways wired, a secret never read back, the webhook log, a test checkout (V037). */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { OUTCOME, when, type PaymentsDesk } from "@/lib/bursary";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export function Gateways({ d, paid, actingOffice }: { d: PaymentsDesk; paid: string | null; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["bursar", "ict", "admin", "super"].includes(actingOffice ?? "");
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const [test, setTest] = useState({ number: "MOAUM/MTC/24/9903", amount: "100", gateway: d.gateways.find((g) => g.on)?.gateway ?? "paystack" });
  const [ref, setRef] = useState("");
  const on = d.gateways.filter((g) => g.on);
  const t = d.tiles;
  const apiBase = d.portalUrl.replace("moaum-portal", "moaum-api");

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/payments${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      router.refresh();
      return j;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="A secret key is written on the API service and never read back">
        Keys live in the service&rsquo;s variables (MOAUM_PAYSTACK_SECRET, MOAUM_FLUTTERWAVE_SECRET, MOAUM_FLUTTERWAVE_HASH), not in the database and not in a file in the repository. This screen says whether a key is set and whether it is a test or a live key; it cannot show the key.
      </Note>
      {paid ? <Note kind="ok" title={`Back from the gateway with ${paid}`} action={<Btn kind="primary" disabled={busy} onClick={async () => { const j = await send("/verify", { reference: paid }, `Verified ${paid} with the gateway`); if (j) setSaid(`The gateway says: ${j.outcome}`); }}>Ask the gateway now</Btn>}>The webhook confirms it on its own; the log below shows the event when it lands. Or ask the gateway directly.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}
      <Tiles items={[
        ["Gateways live", String(on.length), on.length ? "var(--green-ink)" : "var(--red-ink)", on.length ? on.map((g) => `${g.gateway} · ${g.mode.toLowerCase()}`).join(", ") : "Set a secret to wire one"],
        ["Events today", String(t.today), null, `${money(Number(t.settled_today))} settled today`],
        ["Settled, all time", String(t.settled), "var(--green-ink)", "Posted from a gateway's word, verified"],
        ["Exceptions open", String(t.exceptions), Number(t.exceptions) ? "var(--red-ink)" : null, `${t.bad_signatures} bad signature${Number(t.bad_signatures) === 1 ? "" : "s"} discarded`],
      ]} />
      <Panel title="Configured gateways" right="Test or live is read from the key's own prefix">
        <DTable cols={["Gateway", "Mode|mid", "Channels", "Webhook address", "Status|num"]} rows={d.gateways.map((g) => [
          <strong key="g" style={{ textTransform: "capitalize" }}>{g.gateway}</strong>,
          g.on ? <Pil kind={g.mode === "LIVE" ? "ok" : "info"} key="m">{g.mode === "LIVE" ? "Live" : "Test"}</Pil> : <Pil kind="grey" key="m">Off</Pil>,
          <span className="sub2" key="c">{g.channels}</span>,
          <span className="tnum sub2" key="w">{apiBase}{g.webhook}</span>,
          g.on ? (g.gateway === "flutterwave" && !g.hash ? <Pil kind="bad" key="s">Secret set, hash missing — webhooks refused</Pil> : <Pil kind="ok" key="s">Wired</Pil>) : <Pil kind="grey" key="s">Not wired</Pil>,
        ])} />
        <PBody>
          <KvGrid cls="grid--2" pairs={[
            ["Paystack", "Settings → API Keys & Webhooks: set the webhook URL above; the secret key signs every event (x-paystack-signature). Test keys start sk_test_."],
            ["Flutterwave", "Settings → Webhooks: set the URL above and a secret hash; put the same hash in MOAUM_FLUTTERWAVE_HASH. Test keys start FLWSECK_TEST."],
            ["Return address", `${d.portalUrl}/student/fees?paid=… — the student's browser comes back here; the money is confirmed by the webhook or by verification, never by the browser.`],
            ["The reconciler", "Every ten minutes the portal asks the gateway about every checkout opened in the last three days with nothing confirmed behind it, and posts what the gateway answers."],
          ]} />
        </PBody>
      </Panel>
      {may ? (
        <Panel title="Test the gateway" right="A small reference for a demo student, opened on the gateway">
          <PBody>
            <div className="grid grid--3">
              <Field id="tg-num" label="Student" hint="A demo student's matriculation number."><input id="tg-num" className="ctl tnum" value={test.number} onChange={(e) => setTest({ ...test, number: e.target.value })} /></Field>
              <Field id="tg-amt" label="Amount" hint="₦100 is enough."><input id="tg-amt" className="ctl tnum" value={test.amount} onChange={(e) => setTest({ ...test, amount: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
              <Field id="tg-gw" label="Gateway"><select id="tg-gw" className="ctl" value={test.gateway} onChange={(e) => setTest({ ...test, gateway: e.target.value })}>{d.gateways.map((g) => <option key={g.gateway} value={g.gateway} disabled={!g.on}>{g.gateway}{g.on ? ` (${g.mode.toLowerCase()})` : " — not wired"}</option>)}</select></Field>
            </div>
            <div style={{ display: "flex", gap: 9, flexWrap: "wrap", alignItems: "center" }}>
              <Btn kind="primary" disabled={busy || !on.length || !test.number.trim()} onClick={async () => { const j = await send("/test-checkout", { number: test.number, amount: Number(test.amount) || 100, gateway: test.gateway }, `Gateway test checkout for ${test.number}`); if (j?.url) window.location.href = String(j.url); }}>Open a test checkout</Btn>
              <span className="sub2">Pay with the gateway&rsquo;s test card; the webhook lands in the log below, and the reference shows as settled. The purpose is &ldquo;Gateway test&rdquo;, which counts for nothing against the student&rsquo;s fees.</span>
            </div>
            <div className="grid grid--2">
              <Field id="tg-ref" label="Ask about a reference" hint="Any reference this portal generated."><input id="tg-ref" className="ctl tnum" value={ref} onChange={(e) => setRef(e.target.value)} placeholder="MOAUM-FEE-…" /></Field>
              <div style={{ display: "flex", gap: 8, alignItems: "flex-end", paddingBottom: 14 }}>
                <Btn kind="ghost" disabled={busy || !ref.trim()} onClick={async () => { const j = await send("/verify", { reference: ref }, `Verified ${ref} with the gateway`); if (j) setSaid(`${ref}: ${j.outcome}${j.said ? ` (${j.said})` : ""}`); }}>Verify with the gateway</Btn>
                <Btn kind="ghost" disabled={busy} onClick={async () => { if (await send("/sweep", {}, "Reconciliation sweep run by hand")) setSaid("The sweep ran; hanging payments were asked about"); }}>Run the sweep now</Btn>
              </div>
            </div>
          </PBody>
        </Panel>
      ) : null}
      <Panel title="Webhook and verification log" right="Every event the portal received, signature good or bad">
        {d.events.length ? (
          <DTable cols={["When|mid", "Gateway", "Event", "Reference", "Amount|num", "Signature|mid", "Result|num"]} rows={d.events.map((e) => [
            <span className="sub2 tnum" key="w">{when(e.received_at)}</span>,
            <span key="g" style={{ textTransform: "capitalize" }}>{e.gateway}<div className="sub2">{e.source.toLowerCase()}</div></span>,
            <span className="sub2" key="e">{e.event ?? "—"}{e.status ? ` · ${e.status}` : ""}</span>,
            <span className="tnum sub2" key="r">{e.reference ?? "—"}{e.gateway_ref ? <div className="sub2">{e.gateway_ref}</div> : null}</span>,
            <span className="tnum" key="a">{e.amount === null ? "—" : money(Number(e.amount))}</span>,
            e.signature_ok ? <Pil kind="ok" key="s">Valid</Pil> : <Pil kind="bad" key="s">Invalid</Pil>,
            <span key="o"><Pil kind={OUTCOME[e.outcome]?.[1] ?? "grey"}>{OUTCOME[e.outcome]?.[0] ?? e.outcome}</Pil>{e.resolved_at ? <div className="sub2">Resolved: {e.resolution} · {e.resolved_by_name ?? ""}</div> : ["UNKNOWN_REFERENCE", "SHORT_PAID", "BAD_SIGNATURE", "GATEWAY_ERROR"].includes(e.outcome) && may ? <div><Btn kind="ghost" disabled={busy} onClick={async () => { const why = window.prompt("How was it resolved? It goes on the record."); if (why && await send(`/events/${e.id}/resolve`, { resolution: why }, `Gateway event resolved: ${why}`)) setSaid("Resolved"); }}>Resolve</Btn></div> : null}</span>,
          ])} texts={d.events.map((e) => `${e.gateway} ${e.reference ?? ""} ${e.outcome}`)} />
        ) : <PBody><div className="sub2">No event has reached the portal yet. Open a test checkout above and pay with the gateway&rsquo;s test card.</div></PBody>}
      </Panel>
      <Note kind="info" title="A callback is a hint, not an instruction">The portal never credits a student because a gateway said so without keeping what it said. A forged callback is discarded at the signature and logged; a short payment is logged and left open; and on the student&rsquo;s &ldquo;check again&rdquo; the portal asks the gateway itself what the reference settled for.</Note>
    </>
  );
}
