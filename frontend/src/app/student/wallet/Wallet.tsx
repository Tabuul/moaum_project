"use client";

/** studentWallet — proto/part37.html: the balance, what it covers, the statement, the Fund's decision, and applying it to the invoice (V033). */
import { useState } from "react";
import Link from "next/link";
import { COVERS, type StudentWallet } from "@/lib/wallet";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { naira, onDay, PayByCard, useAct } from "../common";

const KIND: Record<string, [string, "ok" | "info" | "bad" | "grey"]> = { CREDIT: ["NELFUND credit", "ok"], TOPUP: ["Top-up", "ok"], APPLIED: ["Applied to fees", "info"], REVERSED: ["Reversed to the Fund", "bad"], REFUND: ["Refund", "grey"] };

export function Wallet({ w }: { w: StudentWallet }) {
  const { act, busy, problem } = useAct();
  const [topup, setTopup] = useState("");
  const [topupRef, setTopupRef] = useState<{ reference: string; amount: number } | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const owed = Number(w.position.balance);
  const bal = Number(w.balance);
  const credited = w.statement.filter((e) => e.kind === "CREDIT").reduce((n, e) => n + Number(e.amount), 0);
  const applied = w.statement.filter((e) => e.kind === "APPLIED").reduce((n, e) => n + Number(e.amount), 0);
  const canClear = bal > 0 && owed > 0;
  const st = w.status;

  return (
    <>
      <Tiles items={[
        ["Wallet balance", naira(bal), null, bal ? "Held by the University for your charges" : "Fully applied"],
        ["Credited by the Fund", naira(credited), null, "NELFUND institutional charges"],
        ["Applied to your invoices", naira(applied), null, w.position.paid_in_full ? "The session charge is settled" : `${w.position.instalments_paid} instalment${w.position.instalments_paid === 1 ? "" : "s"} counted`],
        ["Outstanding on your account", naira(owed), owed ? "var(--red-ink)" : null, owed ? `For ${w.session}` : "Nothing owing"],
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record; the receipt is on your Fees page.</Note> : null}
      {st ? (
        <Note kind={st.state === "APPROVED" ? "ok" : st.state === "NOT_APPROVED" ? "bad" : "info"} title={st.state === "APPROVED" ? "The Fund approved your loan" : st.state === "NOT_APPROVED" ? "The Fund did not approve your loan" : "Your application is still with the Fund"}>
          {st.state === "NOT_APPROVED" ? `${st.reason ?? "No reason was given."} ${st.correctable ? "This is a correction, not a judgement: fix the field named and the Fund reissues." : ""}` : st.state === "PENDING" ? "No decision yet — and that is a real answer, shown as one. The University records what the Fund decides; it does not decide." : `Recorded from the Fund's list of ${onDay(st.loaded_at)}. Money arrives as a remittance and is credited here when it does.`}
        </Note>
      ) : null}
      {owed ? (canClear ? (
        <Note kind="ok" title="Your wallet covers what you owe" action={<Btn kind="primary" disabled={busy !== null} onClick={async () => { const r = await act("apply", "POST", "/me/wallet/apply", { session: w.session }, "Wallet applied to the session charge"); if (r) setSaid(`${naira(Math.min(bal, owed))} applied against ${r.reference}`); }}>Apply {naira(Math.min(bal, owed))} to {w.session}</Btn>}>
          There is {naira(bal)} in the wallet and {naira(owed)} outstanding for {w.session}. Applying it settles the invoice and clears you in the same moment — there is no bank transfer to wait for, because the money is already with the University.
        </Note>
      ) : bal > 0 ? (
        <Note kind="bad" title="Your wallet does not cover the balance">There is {naira(bal)} in the wallet against {naira(owed)} outstanding. Apply what is there and pay the difference, or top the wallet up below.</Note>
      ) : (
        <Note kind="info" title="Nothing in the wallet yet">{naira(owed)} is outstanding for {w.session}. A remittance from the Fund is credited here when the Bursary receives and matches it; a top-up is a payment reference like any other.</Note>
      )) : (
        <Note kind="ok" title="Nothing outstanding">Your session charges are settled. The receipts on your Fees page show the wallet as the channel where it paid, which is what a sponsor or an employer will ask to see.</Note>
      )}
      <Panel title="Wallet statement" right="Every movement, oldest first">
        {w.statement.length ? (
          <DTable cols={["Date|mid", "Entry", "Reference|mid", "In|num", "Out|num", "Balance|num"]} rows={w.statement.map((e) => [
            <span className="sub2 tnum" key="d">{onDay(e.at)}</span>,
            <Two key="e" a={<Pil kind={KIND[e.kind]?.[1] ?? "grey"}>{KIND[e.kind]?.[0] ?? e.kind}</Pil>} b={e.note ?? ""} />,
            <span className="tnum sub2" key="r">{e.reference ?? "—"}</span>,
            e.kind === "CREDIT" || e.kind === "TOPUP" ? <span className="tnum" key="i" style={{ color: "var(--green-ink)", fontWeight: 600 }}>{naira(e.amount)}</span> : <span className="sub2" key="i">—</span>,
            e.kind === "CREDIT" || e.kind === "TOPUP" ? <span className="sub2" key="o">—</span> : <span className="tnum" key="o">{naira(e.amount)}</span>,
            <b className="tnum" key="b">{naira(e.balance)}</b>,
          ])} />
        ) : <PBody><div className="sub2">No movement on the wallet yet.</div></PBody>}
      </Panel>
      <div className="grid grid--2">
        <Panel title="What the wallet may pay" right="Set by what the Fund covers">
          <DTable cols={["Charge", "Covered|mid", "Why"]} rows={COVERS.map((c) => [<span key="c">{c[0]}</span>, c[1] ? <Pil kind="ok" key="y">Yes</Pil> : <Pil kind="bad" key="y">No</Pil>, <span className="sub2" key="w">{c[2]}</span>])} />
          <PBody><div className="sub2">The wallet cannot be withdrawn as cash and cannot be moved to another student. It pays charges, and only the charges the Fund carries.</div></PBody>
        </Panel>
        <Panel title="Top up the wallet" right="When the loan does not cover the whole fee">
          <PBody>
            <Field id="wt-amt" label="Amount" hint="A payment reference like any other; confirmed, it credits the wallet."><input id="wt-amt" className="ctl tnum" value={topup} onChange={(e) => setTopup(e.target.value.replace(/[^0-9.]/g, ""))} /></Field>
            <div><Btn kind="ghost" disabled={busy !== null || !Number(topup)} onClick={async () => { const amt = Number(topup); const r = await act("topup", "POST", "/me/wallet/topup-reference", { session: w.session, amount: amt }, "Wallet top-up reference"); if (r) { setTopupRef({ reference: String(r.reference), amount: amt }); setSaid(`Reference ${r.reference} generated — pay it by card below, or on the Fees page.`); } }}>Generate the reference</Btn> <Link href="/student/fees" className="btn btn--ghost btn--sm">Fees &amp; payments</Link></div>
            {topupRef ? (
              <div style={{ marginTop: 10, paddingTop: 10, borderTop: "1px solid var(--line-2)" }}>
                <div className="sub2" style={{ marginBottom: 6 }}>Reference <span className="tnum">{topupRef.reference}</span> for {naira(topupRef.amount)}. Pay it by card or USSD; the moment the gateway confirms, your wallet is credited.</div>
                <PayByCard reference={topupRef.reference} amount={topupRef.amount} />
              </div>
            ) : null}
            <div className="sub2" style={{ marginTop: 8 }}>Your upkeep is not here, and that is not an error: NELFUND pays it straight into the account you gave the Fund. It does not pass through the University.</div>
          </PBody>
        </Panel>
      </div>
      <Note kind="info" title="A loan is a debt, and this page is the record of it">Everything credited here is repayable to the Fund after you graduate, on the terms in your loan agreement. The statement above is the University&rsquo;s record of what was received on your behalf and what it was applied to.</Note>
    </>
  );
}
