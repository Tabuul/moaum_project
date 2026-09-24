import Link from "next/link";
import { api } from "@/lib/api";
import type { BursaryView, PaymentsDesk } from "@/lib/bursary";
import { LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Bar } from "@/components/proto/blocks";
import { money } from "@/lib/format";
import { when } from "@/lib/bursary";

/** rBursar — proto/part17.html, with the ledger's own figures (V037). */
export async function BursarDashboard({ session }: { session: string }) {
  const [v, p] = await Promise.all([api<BursaryView>(`/api/v1/finance/bursary?session=${encodeURIComponent(session)}`), api<PaymentsDesk>("/api/v1/payments/bursary")]);
  if (!v.ok) {
    return <Note kind="bad" title="The Bursary's figures could not be read">{v.problem.detail ?? v.problem.title}</Note>;
  }
  const t = v.data.tiles;
  const exceptions = Number(t.credits_open) + Number(t.gateway_exceptions);
  const gateways = p.ok ? p.data.gateways : [];
  const on = gateways.filter((g) => g.on);
  return (
    <>
      {exceptions ? (
        <Note kind="bad" title={`${exceptions} settlement exception${exceptions === 1 ? " is" : "s are"} open`} action={<><LinkBtn kind="urgent" href="/finance/exceptions">Open the investigation</LinkBtn> <LinkBtn kind="ghost" href="/finance/reconcile">Reconciliation</LinkBtn></>}>
          {Number(t.credits_open) ? `${t.credits_open} bank credit${Number(t.credits_open) === 1 ? "" : "s"} (${money(Number(t.credits_open_amount))}) with no reference quoted. ` : ""}{Number(t.gateway_exceptions) ? `${t.gateway_exceptions} gateway event${Number(t.gateway_exceptions) === 1 ? "" : "s"} the portal could not post. ` : ""}Until each is attributed, a student who has paid may be blocked from registering.
        </Note>
      ) : !t.scheme_in_force ? (
        <Note kind="bad" title="No clearance scheme is in force" action={<LinkBtn kind="urgent" href="/finance/fees">State the scheme</LinkBtn>}>Nothing a payment releases is stated for today, so registration refuses rather than assumes. The recommended scheme is put in force from the fee setup screen.</Note>
      ) : (
        <Note kind="ok" title="No settlement exception is open">Every gateway event posted or was resolved, and no bank credit waits to be attributed.</Note>
      )}
      <Tiles items={[
        ["Collected this session", money(Number(t.fees_collected)), "var(--green-ink)", `School fees, ${v.data.session}`],
        ["Collected today", money(Number(t.today)), null, `${t.today_count} confirmation${Number(t.today_count) === 1 ? "" : "s"}`],
        ["Exceptions open", String(exceptions), exceptions ? "var(--red-ink)" : null, `${t.hanging} hanging at a gateway`],
        ["Gateways live", `${on.length}`, on.length ? "var(--green-ink)" : "var(--red-ink)", on.length ? on.map((g) => `${g.gateway} (${g.mode.toLowerCase()})`).join(", ") : "None wired yet"],
      ]} />
      <div className="grid grid--2">
        <Panel title="Collection by faculty" right={`${v.data.session} · from the register`}>
          {v.data.byFaculty.length ? (
            <DTable cols={["Faculty", "Collected|mid", "Students paid|mid", "Rate|num"]} rows={v.data.byFaculty.map((f) => {
              const rate = Number(f.due) ? Math.min(100, Math.round((100 * Number(f.collected)) / Number(f.due))) : 0;
              return [<span key="f">{f.faculty_name}</span>, <span className="tnum" key="c">{money(Number(f.collected))}</span>, <span className="tnum" key="s">{f.paid_students} of {f.students}</span>, <span key="r" className="row"><Bar pct={rate} colour={rate < 60 ? "var(--red)" : "var(--green)"} /><span className="tnum sub2">{Number(f.due) ? `${rate}%` : "no charge"}</span></span>];
            })} />
          ) : <PBody><div className="sub2">Nobody is enrolled in {v.data.session} yet, so there is nothing to collect against.</div></PBody>}
        </Panel>
        <Panel title="The desk" right="What waits on the Bursary">
          <DTable cols={["Item", "Detail", "Status|num"]} rows={[
            [<Two key="a" a="Fee schedule and scheme" b={`${t.schedule_items} item${Number(t.schedule_items) === 1 ? "" : "s"} for ${v.data.session}`} />, <Link key="l" href="/finance/fees">Fee setup</Link>, t.scheme_in_force ? <Pil kind="ok" key="s">Scheme in force</Pil> : <Pil kind="bad" key="s">No scheme</Pil>],
            [<Two key="a" a="References awaiting confirmation" b="Bank transfers the Bursary confirms by hand" />, <Link key="l" href="/finance/fees">Confirm</Link>, <Pil kind={Number(t.references_open) ? "info" : "ok"} key="s">{t.references_open} open</Pil>],
            [<Two key="a" a="Hanging at a gateway" b="Checkouts opened, nothing confirmed" />, <Link key="l" href="/finance/hanging">Hanging payments</Link>, <Pil kind={Number(t.hanging) ? "bad" : "ok"} key="s">{t.hanging}</Pil>],
            [<Two key="a" a="Bank credits" b="No reference quoted" />, <Link key="l" href="/finance/exceptions">Investigate</Link>, <Pil kind={Number(t.credits_open) ? "bad" : "ok"} key="s">{t.credits_open} open</Pil>],
            [<Two key="a" a="NELFUND" b="Remittances and suspense" />, <Link key="l" href="/finance/nelfund">NELFUND desk</Link>, <Pil kind="info" key="s">Open</Pil>],
            [<Two key="a" a="Held scripts" b="Students who sat a paper unregistered; the mark waits on their fees" />, <Link key="l" href="/finance/held-scripts">Who owes</Link>, <Pil kind="info" key="s">Open</Pil>],
          ]} />
        </Panel>
      </div>
      <Note kind="info" title="No academic transaction completes while money is owed">The clearance gate is checked inside the transaction, at the moment a student tries to register, sit, graduate or order a transcript. That is why a payment that cannot be attributed is an urgent matter rather than an accounting one.</Note>
      <Panel title="Recent confirmations" right={<LinkBtn kind="ghost" href="/finance/payments">Query all payments</LinkBtn>}>
        {v.data.recent.length ? (
          <DTable cols={["When", "Payer", "Purpose", "Channel", "Amount|num", "Receipt|num"]} rows={v.data.recent.map((r) => [<span className="tnum sub2" key="w">{when(r.confirmed_at)}</span>, <Two key="p" a={r.payer} b={r.number} />, <span className="sub2" key="u">{r.purpose}</span>, <span className="sub2" key="c">{r.channel}</span>, <b className="tnum" key="a">{money(Number(r.amount))}</b>, <span className="tnum sub2" key="r">{r.receipt_no ?? r.reference}</span>])} />
        ) : <PBody><div className="sub2">Nothing confirmed in the last seven days. <Link href="/finance/ledger">The full ledger</Link>.</div></PBody>}
      </Panel>
    </>
  );
}
