import Link from "next/link";
import { api } from "@/lib/api";
import type { BankCredit, PaymentsDesk } from "@/lib/bursary";
import { OUTCOME, when } from "@/lib/bursary";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { money } from "@/lib/format";

export const dynamic = "force-dynamic";

/** t/reconcile — the gateway's word against the ledger: matched, exceptions, and where each resolves */
export default async function ReconcilePage() {
  const [me, gw, credits] = await Promise.all([api<Me>("/api/v1/iam/me"), api<PaymentsDesk>("/api/v1/payments/bursary"), api<BankCredit[]>("/api/v1/finance/bank-credits?state=open")]);
  if (!gw.ok) {
    return <Shell route="t/reconcile" me={me.ok ? me.data : null}><ProblemNotice problem={gw.problem} /></Shell>;
  }
  const events = gw.data.events;
  const settled = events.filter((e) => e.outcome === "SETTLED");
  const settledAmount = settled.reduce((n, e) => n + Number(e.amount ?? 0), 0);
  const exceptions = events.filter((e) => ["UNKNOWN_REFERENCE", "SHORT_PAID", "BAD_SIGNATURE", "GATEWAY_ERROR"].includes(e.outcome) && !e.resolved_at);
  const exceptionAmount = exceptions.reduce((n, e) => n + Number(e.amount ?? 0), 0);
  const open = credits.ok ? credits.data : [];
  return (
    <Shell route="t/reconcile" me={me.ok ? me.data : null}>
      <Tiles items={[
        ["Gateway settled", money(settledAmount), null, `${settled.length} event${settled.length === 1 ? "" : "s"} posted, last 200`],
        ["Matched", `${events.length ? Math.round((100 * (events.length - exceptions.length)) / events.length) : 100}%`, "var(--green-ink)", "Events the portal could post or safely ignore"],
        ["Exceptions", String(exceptions.length + open.length), exceptions.length + open.length ? "var(--red-ink)" : null, `${money(exceptionAmount)} at the gateways · ${open.length} bank credit${open.length === 1 ? "" : "s"}`],
        ["Hanging", String(gw.data.hanging.length), gw.data.hanging.length ? "var(--red-ink)" : null, "Checkouts with nothing confirmed"],
      ]} />
      <Panel title="Exceptions requiring action" right="Every exception is cleared before the period closes">
        {exceptions.length + open.length ? (
          <DTable cols={["Reference", "Amount|num", "Payer", "Exception", "Resolution|num"]} rows={[
            ...exceptions.map((e) => [
              <span className="tnum" key="r">{e.reference ?? "—"}</span>,
              <span className="tnum" key="a" style={{ fontWeight: 600 }}>{e.amount === null ? "—" : money(Number(e.amount))}</span>,
              <span className="sub2" key="p" style={{ textTransform: "capitalize" }}>{e.gateway} · {when(e.received_at)}</span>,
              <span key="x"><strong>{OUTCOME[e.outcome]?.[0] ?? e.outcome}</strong><div className="sub2">{e.outcome === "UNKNOWN_REFERENCE" ? "Bank branch or another institution's code — or generated and abandoned" : e.outcome === "SHORT_PAID" ? "Amount differs from the reference — a part payment needs a reference for the part" : e.outcome === "BAD_SIGNATURE" ? "Discarded at the signature; nothing read from it" : "The gateway did not answer for the reference"}</div></span>,
              <Link key="l" href="/finance/hanging" className="btn btn--primary btn--sm">Investigate</Link>,
            ]),
            ...open.map((c) => [
              <span className="tnum" key="r">{c.instrument}</span>,
              <span className="tnum" key="a" style={{ fontWeight: 600 }}>{money(Number(c.amount))}</span>,
              <Two key="p" a={c.payer ?? "Not identified"} b={c.bank} />,
              <span key="x"><strong>Bank branch payment, no reference quoted</strong><div className="sub2">{c.state === "PROPOSED" ? `Proposed against ${c.proposed_reference}; awaiting a second officer` : "Recorded as it came; awaiting a proposal"}</div></span>,
              <Link key="l" href="/finance/exceptions" className="btn btn--primary btn--sm">{c.state === "PROPOSED" ? "Approve" : "Investigate"}</Link>,
            ]),
          ]} />
        ) : <PBody><div className="sub2">Nothing to reconcile: every gateway event posted or was resolved, and no bank credit waits.</div></PBody>}
      </Panel>
      <Panel title="The other exception types, and how each resolves">
        <DTable cols={["Exception", "What it means", "Resolution", "Approvals|num"]} rows={[
          [<Two key="a" a="Settled at the gateway, not posted internally" b="The common one" />, <span className="sub2" key="b">The callback never arrived</span>, <span className="sub2" key="c">The sweep asks the gateway every ten minutes and posts what it answers</span>, <span className="sub2" key="d">None — automatic</span>],
          [<Two key="a" a="Duplicate event" b="The gateway sent it twice" />, <span className="sub2" key="b">Two callbacks for one reference</span>, <span className="sub2" key="c">The second finds the reference confirmed and does nothing</span>, <span className="sub2" key="d">None</span>],
          [<Two key="a" a="Amount differs from the reference" b="Short paid" />, <span className="sub2" key="b">Less than the reference asks</span>, <span className="sub2" key="c">Logged and left open; a reference for the amount received is generated and the gateway asked again</span>, <span className="sub2" key="d">None</span>],
          [<Two key="a" a="No reference quoted" b="Bank counter" />, <span className="sub2" key="b">Teller slip only</span>, <span className="sub2" key="c">Recorded, proposed and approved on the exceptions desk</span>, <span className="sub2" key="d">Two</span>],
          [<Two key="a" a="Forged callback" b="Bad signature" />, <span className="sub2" key="b">Not from the gateway</span>, <span className="sub2" key="c">Discarded at the signature and logged; resolved on the record</span>, <span className="sub2" key="d">One, to close it</span>],
        ]} />
      </Panel>
      <Note kind="info" title="A payment is confirmed by the gateway or the bank, never by the browser">
        The candidate&rsquo;s browser may never return from the payment page. Two independent paths therefore converge on one idempotent settlement: the gateway&rsquo;s signed callback, and the sweep that asks the gateway about every open checkout. Whichever arrives first settles the payment; the second finds it already settled and does nothing. {events.some((e) => e.outcome === "ALREADY_SETTLED") ? <Pil kind="ok">Seen happening in this log</Pil> : null}
      </Note>
    </Shell>
  );
}
