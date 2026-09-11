"use client";

/** studentWallet — proto/part37.html: the balance, its sources, the statement, applying it to the
 *  invoice, and — once the fees are cleared — withdrawing the balance to a bank account (V033, V079). */
import { useState } from "react";
import Link from "next/link";
import { type StudentWallet } from "@/lib/wallet";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { naira, onDay, PayByCard, useAct } from "../common";

const KIND: Record<string, [string, "ok" | "info" | "bad" | "grey"]> = { CREDIT: ["Credit", "ok"], TOPUP: ["Top-up", "ok"], APPLIED: ["Applied to fees", "info"], REVERSED: ["Reversed to source", "bad"], REFUND: ["Withdrawn to bank", "grey"] };
const NATURE: Record<string, [string, "ok" | "info" | "grey"]> = { LOAN: ["Loan", "info"], GRANT: ["Grant", "ok"], SELF: ["Own money", "grey"] };

export function Wallet({ w }: { w: StudentWallet }) {
  const { act, busy, problem } = useAct();
  const [topup, setTopup] = useState("");
  const [topupRef, setTopupRef] = useState<{ reference: string; amount: number } | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [wd, setWd] = useState({ amount: "", bank: "", accountNo: "", accountName: "" });
  const owed = Number(w.position.balance);
  const bal = Number(w.balance);
  const credited = w.statement.filter((e) => e.kind === "CREDIT").reduce((n, e) => n + Number(e.amount), 0);
  const applied = w.statement.filter((e) => e.kind === "APPLIED").reduce((n, e) => n + Number(e.amount), 0);

  /* every credit and top-up carries the source it came from — group them so NELFUND and each
     other source stand on their own, while the balance above is the sum of them all (V079). */
  const bySource = (() => {
    const m = new Map<string, { name: string; nature: string | null; received: number }>();
    for (const e of w.statement) {
      if (!e.source_code) continue;
      const cur = m.get(e.source_code) ?? { name: e.source_name ?? e.source_code, nature: e.nature, received: 0 };
      if (e.kind === "CREDIT" || e.kind === "TOPUP") cur.received += Number(e.amount);
      else if (e.kind === "REVERSED") cur.received -= Number(e.amount);
      m.set(e.source_code, cur);
    }
    /* NELFUND and the other loans first, then grants, then the student's own money */
    const rank: Record<string, number> = { LOAN: 0, GRANT: 1, SELF: 2 };
    return [...m.entries()]
      .map(([code, v]) => ({ code, ...v }))
      .filter((x) => x.received > 0)
      .sort((a, b) => (rank[a.nature ?? ""] ?? 3) - (rank[b.nature ?? ""] ?? 3) || (a.code === "NELFUND" ? -1 : b.code === "NELFUND" ? 1 : 0) || b.received - a.received);
  })();
  const funded = bySource.reduce((n, x) => n + x.received, 0);
  const srcCls = bySource.length >= 4 ? "grid--4" : bySource.length === 3 ? "grid--3" : "grid--2";
  const canClear = bal > 0 && owed > 0;
  const st = w.status;
  const elig = w.eligibility;
  const wdl = w.withdrawal;

  return (
    <>
      <Tiles items={[
        ["Wallet balance", naira(bal), null, bal ? "Held by the University on your behalf" : "Fully applied"],
        ["Funded", naira(funded || credited), null, "Every source, added together"],
        ["Applied to your invoices", naira(applied), null, w.position.paid_in_full ? "The session charge is settled" : `${w.position.instalments_paid} instalment${w.position.instalments_paid === 1 ? "" : "s"} counted`],
        ["Outstanding on your account", naira(owed), owed ? "var(--red-ink)" : null, owed ? `For ${w.session}` : "Nothing owing"],
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record; the receipt is on your Fees page.</Note> : null}
      {bySource.length ? (
        <>
          <div className="eyebrow" style={{ margin: "6px 2px -2px", color: "var(--chrome-dim)" }}>Funding by source — the wallet balance above is all of them together</div>
          <Tiles cls={srcCls} items={bySource.map((x) => [
            x.name,
            naira(x.received),
            null,
            <span key="c">{NATURE[x.nature ?? ""]?.[0] ?? x.nature ?? "Source"} · <span className="tnum">{x.code}</span></span>,
          ])} />
        </>
      ) : (
        <Note kind="info" title="No funding on your wallet yet">NELFUND, a scholarship or your own top-up will each show as its own card here, and the wallet balance is their total.</Note>
      )}
      {st ? (
        <Note kind={st.state === "APPROVED" ? "ok" : st.state === "NOT_APPROVED" ? "bad" : "info"} title={st.state === "APPROVED" ? "The Fund approved your NELFUND loan" : st.state === "NOT_APPROVED" ? "The Fund did not approve your NELFUND loan" : "Your NELFUND application is still with the Fund"}>
          {st.state === "NOT_APPROVED" ? `${st.reason ?? "No reason was given."} ${st.correctable ? "This is a correction, not a judgement: fix the field named and the Fund reissues." : ""}` : st.state === "PENDING" ? "No decision yet — and that is a real answer, shown as one. You apply to NELFUND on the Fund's own portal; the University records what it decides and credits your wallet when the money arrives." : `Recorded from the Fund's list of ${onDay(st.loaded_at)}. Money arrives as a remittance and is credited here when it does.`}
        </Note>
      ) : null}
      {owed ? (canClear ? (
        <Note kind="ok" title="Your wallet covers what you owe" action={<Btn kind="primary" disabled={busy !== null} onClick={async () => { const r = await act("apply", "POST", "/me/wallet/apply", { session: w.session }, "Wallet applied to the session charge"); if (r) setSaid(`${naira(Math.min(bal, owed))} applied against ${r.reference}`); }}>Apply {naira(Math.min(bal, owed))} to {w.session}</Btn>}>
          There is {naira(bal)} in the wallet and {naira(owed)} outstanding for {w.session}. Applying it settles the invoice and clears you in the same moment — there is no bank transfer to wait for, because the money is already with the University.
        </Note>
      ) : bal > 0 ? (
        <Note kind="bad" title="Your wallet does not cover the balance">There is {naira(bal)} in the wallet against {naira(owed)} outstanding. Apply what is there and pay the difference, or top the wallet up below.</Note>
      ) : (
        <Note kind="info" title="Nothing in the wallet yet">{naira(owed)} is outstanding for {w.session}. Funding is credited here when the Bursary receives it; a top-up is a payment reference like any other.</Note>
      )) : (
        <Note kind="ok" title="Nothing outstanding">Your session charges are settled. The receipts on your Fees page show which source paid, which is what a sponsor or an employer will ask to see.</Note>
      )}
      <Panel title="Wallet statement" right="Every movement, oldest first">
        {w.statement.length ? (
          <DTable cols={["Date|mid", "Entry", "Source", "Reference|mid", "In|num", "Out|num", "Balance|num"]} rows={w.statement.map((e) => [
            <span className="sub2 tnum" key="d">{onDay(e.at)}</span>,
            <Two key="e" a={<Pil kind={KIND[e.kind]?.[1] ?? "grey"}>{KIND[e.kind]?.[0] ?? e.kind}</Pil>} b={e.note ?? ""} />,
            e.source_name ? <Two key="s" a={<span>{e.source_name}</span>} b={e.nature ? <Pil kind={NATURE[e.nature]?.[1] ?? "grey"}>{NATURE[e.nature]?.[0] ?? e.nature}</Pil> : ""} /> : <span className="sub2" key="s">—</span>,
            <span className="tnum sub2" key="r">{e.reference ?? "—"}</span>,
            e.kind === "CREDIT" || e.kind === "TOPUP" ? <span className="tnum" key="i" style={{ color: "var(--green-ink)", fontWeight: 600 }}>{naira(e.amount)}</span> : <span className="sub2" key="i">—</span>,
            e.kind === "CREDIT" || e.kind === "TOPUP" ? <span className="sub2" key="o">—</span> : <span className="tnum" key="o">{naira(e.amount)}</span>,
            <b className="tnum" key="b">{naira(e.balance)}</b>,
          ])} />
        ) : <PBody><div className="sub2">No movement on the wallet yet.</div></PBody>}
      </Panel>
      <div className="grid grid--2">
        <Panel title="Top up the wallet" right="When funding does not cover the whole fee">
          <PBody>
            <Field id="wt-amt" label="Amount" hint="A payment reference like any other; confirmed, it credits the wallet."><input id="wt-amt" className="ctl tnum" value={topup} onChange={(e) => setTopup(e.target.value.replace(/[^0-9.]/g, ""))} /></Field>
            <div><Btn kind="ghost" disabled={busy !== null || !Number(topup)} onClick={async () => { const amt = Number(topup); const r = await act("topup", "POST", "/me/wallet/topup-reference", { session: w.session, amount: amt }, "Wallet top-up reference"); if (r) { setTopupRef({ reference: String(r.reference), amount: amt }); setSaid(`Reference ${r.reference} generated — pay it by card below, or on the Fees page.`); } }}>Generate the reference</Btn> <Link href="/student/fees" className="btn btn--ghost btn--sm">Fees &amp; payments</Link></div>
            {topupRef ? (
              <div style={{ marginTop: 10, paddingTop: 10, borderTop: "1px solid var(--line-2)" }}>
                <div className="sub2" style={{ marginBottom: 6 }}>Reference <span className="tnum">{topupRef.reference}</span> for {naira(topupRef.amount)}. Pay it by card or USSD; the moment the gateway confirms, your wallet is credited.</div>
                <PayByCard reference={topupRef.reference} amount={topupRef.amount} />
              </div>
            ) : null}
          </PBody>
        </Panel>
        <Panel title="Withdraw to your bank account" right="Once your fees are cleared">
          <PBody>
            {wdl ? (
              <Note kind={wdl.state === "PAID" ? "ok" : wdl.state === "REJECTED" ? "bad" : "info"} title={wdl.state === "REQUESTED" ? "A withdrawal is with the Bursary" : wdl.state === "APPROVED" ? "Approved — awaiting payout" : wdl.state === "PAID" ? "Paid to your account" : "The Bursary declined the withdrawal"}>
                {naira(wdl.amount)} to {wdl.bank_name} {wdl.account_no}. {wdl.state === "PAID" ? `Paid ${wdl.paid_at ? onDay(wdl.paid_at) : ""}${wdl.paid_ref ? ` · ${wdl.paid_ref}` : ""}.` : wdl.state === "REJECTED" ? (wdl.reason ?? "") : "Requested " + onDay(wdl.requested_at) + "."}
              </Note>
            ) : null}
            {elig.eligible ? (
              <>
                <div className="sub2" style={{ marginBottom: 8 }}>Your {w.session} fees are cleared and {naira(elig.balance)} is left in the wallet. Enter <b>your own</b> bank account to withdraw it.</div>
                <Field id="wd-amt" label="Amount" hint={`Up to ${naira(elig.balance)}`}><input id="wd-amt" className="ctl tnum" value={wd.amount} placeholder={String(elig.balance)} onChange={(e) => setWd({ ...wd, amount: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
                <Field id="wd-bank" label="Bank"><input id="wd-bank" className="ctl" value={wd.bank} onChange={(e) => setWd({ ...wd, bank: e.target.value })} autoComplete="off" /></Field>
                <div className="grid grid--2">
                  <Field id="wd-no" label="Account number"><input id="wd-no" className="ctl tnum" value={wd.accountNo} onChange={(e) => setWd({ ...wd, accountNo: e.target.value.replace(/[^0-9]/g, "") })} autoComplete="off" /></Field>
                  <Field id="wd-name" label="Account name"><input id="wd-name" className="ctl" value={wd.accountName} onChange={(e) => setWd({ ...wd, accountName: e.target.value })} autoComplete="off" /></Field>
                </div>
                <Btn kind="primary" disabled={busy !== null || !wd.bank || !wd.accountNo || !wd.accountName} onClick={async () => {
                  const amt = Number(wd.amount) || elig.balance;
                  const r = await act("withdraw", "POST", "/me/wallet/withdrawal", { session: w.session, amount: amt, bank: wd.bank, accountNo: wd.accountNo, accountName: wd.accountName }, `Withdrawal of ${amt} requested`);
                  if (r) { setSaid(`Withdrawal of ${naira(amt)} requested — the Bursary will review it.`); setWd({ amount: "", bank: "", accountNo: "", accountName: "" }); }
                }}>Request the withdrawal</Btn>
              </>
            ) : (
              <Note kind="info" title="Not available yet">{elig.reason}</Note>
            )}
          </PBody>
        </Panel>
      </div>
      <Note kind="info" title="What is a loan, and what is a gift">A wallet credit is only repayable if its <b>source is a loan</b> — the statement says which each credit is. A NELFUND credit is a loan you repay the Fund after graduation on the terms in your agreement; a scholarship or bursary is a grant that is never repaid. Once your fees are cleared and nothing is owed, any balance left over is yours to withdraw to your bank.</Note>
    </>
  );
}
