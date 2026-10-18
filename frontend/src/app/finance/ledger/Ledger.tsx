"use client";

/** tLedger — proto/part18.html: the day book, filtered by day, exported as the finance system takes it (V037). */
import { useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { when, type DayBookRow } from "@/lib/bursary";
import { csv, download } from "@/lib/results";
import { Btn, LinkBtn, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";

/** V541: the totals are of every confirmation of the days chosen; the table shows the newest the API sends (500), and the
 *  journal's export fetches every one */
export function Ledger({ from, to, rows, count, byChannel: channelTotals, actingOffice }: { from: string; to: string; rows: DayBookRow[]; count: number; byChannel: { channel: string; amount: number }[]; actingOffice?: string | null }) {
  const queryNav = useQueryNav();
  const mayRefund = ["bursar", "super"].includes(actingOffice ?? "");
  const [f, setF] = useState(from);
  const [t, setT] = useState(to);
  const [exporting, setExporting] = useState(false);
  const byChannel = channelTotals.map((c) => [c.channel, Number(c.amount)] as [string, number]);
  const total = byChannel.reduce((n, [, a]) => n + a, 0);
  async function exportJournal() {
    setExporting(true);
    try {
      const r = await fetch(`/api/bff/api/v1/finance/ledger?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}&all=true`, { cache: "no-store" });
      const all = r.ok ? ((await r.json()) as { rows: DayBookRow[] }).rows : rows;
      download(`ledger-${from}-${to}.csv`, csv([["Reference", "Confirmed", "Payer", "Number", "Purpose", "Session", "Amount", "Channel", "Receipt", "Note"], ...all.map((x) => [x.reference, x.confirmed_at, x.payer, x.number, x.purpose, x.session, x.amount, x.channel, x.receipt_no ?? "", x.note ?? ""])]));
    } finally {
      setExporting(false);
    }
  }
  return (
    <>
      <Tiles items={[
        ["Collected", money(total), "var(--green-ink)", `${count.toLocaleString("en-NG")} confirmation${count === 1 ? "" : "s"}, ${from} to ${to}`],
        ["By card", money(byChannel.filter(([c]) => c.startsWith("Card")).reduce((n, [, a]) => n + a, 0)), null, "Paystack and Flutterwave"],
        ["By bank", money(byChannel.filter(([c]) => c.startsWith("Bank")).reduce((n, [, a]) => n + a, 0)), null, "Transfers and branch credits confirmed by hand"],
        ["From the wallet", money(byChannel.filter(([c]) => c.includes("wallet")).reduce((n, [, a]) => n + a, 0)), null, "NELFUND"],
      ]} />
      <Panel title="Filter">
        <PBody>
          <div className="grid grid--3">
            <Field id="lg-from" label="From"><input id="lg-from" className="ctl" type="date" value={f} onChange={(e) => setF(e.target.value)} /></Field>
            <Field id="lg-to" label="To"><input id="lg-to" className="ctl" type="date" value={t} onChange={(e) => setT(e.target.value)} /></Field>
            <div className="row row--end" style={{ paddingBottom: "var(--s-4)" }}>
              <Btn kind="primary" onClick={() => queryNav(`/finance/ledger?from=${f}&to=${t}`)}>Apply</Btn>
              <Btn kind="ghost" disabled={!count} busy={exporting} onClick={() => exportJournal()}>Export the journal</Btn>
            </div>
          </div>
        </PBody>
      </Panel>
      <Panel title="Transactions" right={rows.length < count ? `the newest ${rows.length.toLocaleString("en-NG")} of ${count.toLocaleString("en-NG")}` : `${count.toLocaleString("en-NG")} · newest first`}>
        {rows.length < count ? <PBody><div className="sub2">The newest {rows.length.toLocaleString("en-NG")} confirmations are listed; the totals above are of all {count.toLocaleString("en-NG")}. Narrow the days, or export the journal for every one.</div></PBody> : null}
        {rows.length ? (
          <DTable cols={mayRefund ? ["Reference", "When|mid", "Payer", "Purpose", "Channel", "Amount|num", "Receipt|num", "Action|num"] : ["Reference", "When|mid", "Payer", "Purpose", "Channel", "Amount|num", "Receipt|num"]} rows={rows.map((r) => [
            <span className="tnum sub2" key="r">{r.reference}</span>,
            <span className="sub2 tnum" key="w">{when(r.confirmed_at)}</span>,
            <Two key="p" a={r.payer} b={r.number} />,
            <span className="sub2" key="u">{r.purpose}<div className="sub2">{r.session}</div></span>,
            <span key="c">{r.channel.startsWith("Card") ? <Pil kind="ok">{r.channel}</Pil> : r.channel.includes("wallet") ? <Pil kind="info">{r.channel}</Pil> : <Pil kind="grey">{r.channel}</Pil>}{r.note ? <div className="sub2">{r.note}</div> : null}</span>,
            <b className="tnum" key="a">{money(Number(r.amount))}</b>,
            <span className="tnum sub2" key="n">{r.receipt_no ?? "—"}</span>,
            ...(mayRefund ? [<LinkBtn key="rf" kind="ghost" href={`/finance/refunds?refund=${encodeURIComponent(r.reference)}`}>Refund</LinkBtn>] : []),
          ])} texts={rows.map((r) => `${r.reference} ${r.payer} ${r.number} ${r.purpose} ${r.channel}`)} />
        ) : <PBody><div className="sub2">Nothing confirmed between {from} and {to}.</div></PBody>}
      </Panel>
    </>
  );
}
