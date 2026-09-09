"use client";

/** tLedger — proto/part18.html: the day book, filtered by day, exported as the finance system takes it (V037). */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { when, type DayBookRow } from "@/lib/bursary";
import { csv, download } from "@/lib/results";
import { Btn, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";

export function Ledger({ from, to, rows }: { from: string; to: string; rows: DayBookRow[] }) {
  const router = useRouter();
  const [f, setF] = useState(from);
  const [t, setT] = useState(to);
  const total = rows.reduce((n, r) => n + Number(r.amount), 0);
  const channels = Array.from(new Set(rows.map((r) => r.channel)));
  const byChannel = channels.map((c) => [c, rows.filter((r) => r.channel === c).reduce((n, r) => n + Number(r.amount), 0)] as [string, number]);
  return (
    <>
      <Tiles items={[
        ["Collected", money(total), "var(--green-ink)", `${rows.length} confirmation${rows.length === 1 ? "" : "s"}, ${from} to ${to}`],
        ["By card", money(byChannel.filter(([c]) => c.startsWith("Card")).reduce((n, [, a]) => n + a, 0)), null, "Paystack and Flutterwave"],
        ["By bank", money(byChannel.filter(([c]) => c.startsWith("Bank")).reduce((n, [, a]) => n + a, 0)), null, "Transfers and branch credits confirmed by hand"],
        ["From the wallet", money(byChannel.filter(([c]) => c.includes("wallet")).reduce((n, [, a]) => n + a, 0)), null, "NELFUND"],
      ]} />
      <Panel title="Filter">
        <PBody>
          <div className="grid grid--3">
            <Field id="lg-from" label="From"><input id="lg-from" className="ctl" type="date" value={f} onChange={(e) => setF(e.target.value)} /></Field>
            <Field id="lg-to" label="To"><input id="lg-to" className="ctl" type="date" value={t} onChange={(e) => setT(e.target.value)} /></Field>
            <div style={{ display: "flex", gap: 8, alignItems: "flex-end", paddingBottom: 14 }}>
              <Btn kind="primary" onClick={() => router.push(`/finance/ledger?from=${f}&to=${t}`)}>Apply</Btn>
              <Btn kind="ghost" disabled={!rows.length} onClick={() => download(`ledger-${from}-${to}.csv`, csv([["Reference", "Confirmed", "Payer", "Number", "Purpose", "Session", "Amount", "Channel", "Receipt", "Note"], ...rows.map((r) => [r.reference, r.confirmed_at, r.payer, r.number, r.purpose, r.session, r.amount, r.channel, r.receipt_no ?? "", r.note ?? ""])]))}>Export the journal</Btn>
            </div>
          </div>
        </PBody>
      </Panel>
      <Panel title="Transactions" right={`${rows.length} · newest first`}>
        {rows.length ? (
          <DTable cols={["Reference", "When|mid", "Payer", "Purpose", "Channel", "Amount|num", "Receipt|num"]} rows={rows.map((r) => [
            <span className="tnum sub2" key="r">{r.reference}</span>,
            <span className="sub2 tnum" key="w">{when(r.confirmed_at)}</span>,
            <Two key="p" a={r.payer} b={r.number} />,
            <span className="sub2" key="u">{r.purpose}<div className="sub2">{r.session}</div></span>,
            <span key="c">{r.channel.startsWith("Card") ? <Pil kind="ok">{r.channel}</Pil> : r.channel.includes("wallet") ? <Pil kind="info">{r.channel}</Pil> : <Pil kind="grey">{r.channel}</Pil>}{r.note ? <div className="sub2">{r.note}</div> : null}</span>,
            <b className="tnum" key="a">{money(Number(r.amount))}</b>,
            <span className="tnum sub2" key="n">{r.receipt_no ?? "—"}</span>,
          ])} texts={rows.map((r) => `${r.reference} ${r.payer} ${r.number} ${r.purpose} ${r.channel}`)} />
        ) : <PBody><div className="sub2">Nothing confirmed between {from} and {to}.</div></PBody>}
      </Panel>
    </>
  );
}
