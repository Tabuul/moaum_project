"use client";

/** studentWallet — proto/part37.html: every naira to its source (V033, V079, V327). The balance by source — NELFUND available, used,
 *  reserved and refundable; a scholarship or sponsor; the student's own money — the session's fees and what is outstanding, a top-up
 *  only for the shortfall the server itself works out, the statement, applying the wallet to the invoice, and — once the fees are
 *  settled — a refund of the Fund's money that arrived after they were paid, or of the student's own leftover; never a grant. */
import { useState } from "react";
import { topupWord, type SourceBalance, type StudentWallet } from "@/lib/wallet";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint } from "@/lib/exportbrand";
import { naira, onDay, PayByCard, useAct } from "../common";

const KIND: Record<string, [string, "ok" | "info" | "bad" | "grey"]> = { CREDIT: ["Credit", "ok"], TOPUP: ["Top-up", "ok"], APPLIED: ["Applied to fees", "info"], REVERSED: ["Reversed to source", "bad"], REFUND: ["Refunded to you", "grey"] };
const NATURE: Record<string, [string, "ok" | "info" | "grey"]> = { LOAN: ["Loan", "info"], GRANT: ["Grant", "ok"], SELF: ["Own money", "grey"], UNKNOWN: ["Unattributed", "grey"] };
const ORIGIN: Record<string, string> = { OLD_PORTAL: "Old portal", REMITTANCE: "The Fund's remittance", GATEWAY: "Paid by you", BURSARY: "Credited by the Bursary", WALLET: "" };

export function Wallet({ w }: { w: StudentWallet }) {
  const { act, busy, problem } = useAct();
  const [topupRef, setTopupRef] = useState<{ reference: string; amount: number } | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [wd, setWd] = useState({ amount: "", bank: "", accountNo: "", accountName: "", source: "" });
  const owed = Number(w.position.balance);
  const bal = Number(w.balance);
  const t = w.topup;
  const elig = w.eligibility;
  const wdl = w.withdrawal;
  const st = w.status;
  const by = (code: string): SourceBalance | undefined => w.balances.find((b) => b.source_code === code);
  const nelfund = by("NELFUND");
  const grants = w.balances.filter((b) => b.nature === "GRANT");
  const own = by("SELF");
  const nelRefundable = Number(elig.nelfund_refundable ?? 0);
  const selfRefundable = Number(elig.self_refundable ?? 0);
  const refundSource = wd.source || (nelRefundable > 0 ? "NELFUND" : selfRefundable > 0 ? "SELF" : "");
  const refundCap = refundSource === "NELFUND" ? nelRefundable : refundSource === "SELF" ? selfRefundable : 0;
  const canApply = bal > 0 && owed > 0;

  function printStatement() {
    const head = ["S/N", "Date", "Session", "Entry", "Source", "Reference", "In", "Out", "Balance"];
    const body = w.statement.map((e, i) => [i + 1, onDay(e.at), e.session, `${KIND[e.kind]?.[0] ?? e.kind}${e.note ? ` — ${e.note}` : ""}`, e.source_name ?? "", e.reference ?? "",
      e.kind === "CREDIT" || e.kind === "TOPUP" ? Number(e.amount) : "", e.kind === "CREDIT" || e.kind === "TOPUP" ? "" : Number(e.amount), Number(e.balance)]);
    brandedPrint("Funding statement", `${w.session} · NELFUND ${naira(nelfund?.credited ?? 0)} credited, ${naira(nelfund?.applied ?? 0)} applied, ${naira(nelfund?.refunded ?? 0)} refunded · fees ${naira(w.position.due)} due, ${naira(w.position.paid)} paid, ${naira(owed)} outstanding`, head, body);
  }

  return (
    <>
      <Tiles items={[
        ["NELFUND available", naira(nelfund?.available ?? 0), null, nelfund ? `${naira(nelfund.credited)} received` : "Nothing from the Fund yet"],
        ["NELFUND used", naira(nelfund?.applied ?? 0), null, "Applied to your fees"],
        ["NELFUND reserved", naira(nelfund?.held ?? 0), null, "Held for a refund you requested"],
        ["Refundable NELFUND", naira(nelRefundable), nelRefundable ? "var(--green-ink)" : null, elig.nelfund_after_settlement ? "Arrived after your fees were paid" : "Only after the session's fees are settled"],
      ]} />
      {grants.length || own ? (
        <Tiles cls={grants.length + (own ? 1 : 0) >= 3 ? "grid--3" : "grid--2"} items={[
          ...grants.map((g): [string, string, null, string] => [g.source_name, naira(g.available), null, `Grant · ${naira(g.applied)} used · not refundable to you`]),
          ...(own ? [[`Your own money`, naira(own.available), null, `${naira(own.credited)} topped up · ${naira(own.applied)} used`] as [string, string, null, string]] : []),
        ]} />
      ) : null}
      <Tiles items={[
        ["School fees", naira(w.position.due), null, w.session],
        ["Amount already paid", naira(w.position.paid), null, w.position.paid_in_full ? "Settled in full" : `${w.position.instalments_paid} instalment${w.position.instalments_paid === 1 ? "" : "s"} counted`],
        ["Outstanding school fees", naira(owed), owed ? "var(--red-ink)" : null, owed ? "Still owed for the session" : "Nothing owing"],
        ["NELFUND shortfall", naira(t.shortfall), Number(t.shortfall) ? "var(--red-ink)" : null, Number(t.shortfall) ? "What your funding does not cover" : "Your funding covers what is outstanding"],
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record; the receipt is on your Fees page.</Note> : null}
      {st ? (
        <Note kind={st.state === "APPROVED" ? "ok" : st.state === "NOT_APPROVED" ? "bad" : "info"} title={st.state === "APPROVED" ? "The Fund approved your NELFUND loan" : st.state === "NOT_APPROVED" ? "The Fund did not approve your NELFUND loan" : "Your NELFUND application is with the Fund"}>
          {st.state === "NOT_APPROVED" ? `${st.reason ?? "No reason was given."} ${st.correctable ? "This is a correction, not a judgement: fix the field named and the Fund reissues." : ""}` : st.state === "PENDING" ? "Nothing to do here; the University records the Fund's decision when it arrives." : `For ${st.session}. The money is credited here when the Fund remits it.`}
        </Note>
      ) : null}

      {owed ? (canApply ? (
        <Note kind="ok" title="Your funding covers part or all of what you owe" action={<Btn kind="primary" disabled={busy !== null} onClick={async () => { const r = await act("apply", "POST", "/me/wallet/apply", { session: w.session }, `Wallet applied to the ${w.session} charge`, ""); if (r) setSaid(`${naira(Math.min(bal, owed))} applied to your ${w.session} fees.`); }}>Apply {naira(Math.min(bal, owed))} to my fees</Btn>}>
          There is {naira(bal)} in the wallet and {naira(owed)} outstanding for {w.session}. Applying it settles the invoice in the same moment — the money is already with the University. The loan is used first, then a grant, then your own money.
        </Note>
      ) : null) : (
        <Note kind="ok" title="Nothing outstanding">Your {w.session} charges are settled. The receipts on your Fees page show which source paid.</Note>
      )}

      <Panel title={t.allowed ? "Additional payment required" : "Top-up"} right={<Pil kind={t.allowed ? "warn" : "grey"}>{t.allowed ? `Top up ${naira(t.max_topup)}` : "Not required"}</Pil>}>
        <PBody>
          <div className={t.allowed ? "mb-2" : "sub2"}>{topupWord(t, w.session)}</div>
          <KvGrid cls="grid--3" pairs={[
            ["School fees", naira(t.due)], ["NELFUND funding", naira(t.nelfund_available)], ["Other eligible funding", naira(Number(t.other_available) + Number(t.self_available))],
            ["Already paid", naira(t.paid)], ["Outstanding", naira(t.outstanding)], ["NELFUND shortfall", <b key="s" className={Number(t.shortfall) ? "ink-red" : ""}>{naira(t.shortfall)}</b>],
          ]} />
          {t.allowed ? (
            <div className="mt-2">
              <div className="sub2 mb-2">A top-up is for exactly the shortfall{t.over_shortfall_allowed ? ", or more if you choose" : ""}; it is your own money, never the Fund&rsquo;s, and it is credited to your wallet the moment the gateway confirms. The shortfall is worked out again when you ask.</div>
              <Btn kind="primary" disabled={busy !== null} onClick={async () => { const r = await act("topup", "POST", "/me/wallet/topup-reference", { session: w.session, amount: t.max_topup }, `Top-up reference for the ${w.session} shortfall`, ""); if (r) setTopupRef({ reference: String(r.reference), amount: Number(r.amount) }); }}>TOP UP {naira(t.max_topup)}</Btn>
              {topupRef ? (
                <div className="mt-2" style={{ paddingTop: "var(--s-2)", borderTop: "1px solid var(--line-2)" }}>
                  <div className="sub2 mb-2">Reference <span className="tnum">{topupRef.reference}</span> for {naira(topupRef.amount)}. Pay it by card or USSD; the moment the gateway confirms, your wallet is credited and you can apply it.</div>
                  <PayByCard reference={topupRef.reference} amount={topupRef.amount} />
                </div>
              ) : t.open_reference ? <div className="sub2 mt-2">A top-up reference <span className="tnum">{t.open_reference}</span> is open; asking again retires it and issues a fresh one for today&rsquo;s shortfall.</div> : null}
            </div>
          ) : null}
        </PBody>
      </Panel>

      <div className="grid grid--2">
        <Panel title="NELFUND refund" right={nelRefundable || selfRefundable ? <Pil kind="ok">Eligible</Pil> : <Pil kind="grey">Not available</Pil>}>
          <PBody>
            {wdl ? (
              <Note kind={wdl.state === "PAID" ? "ok" : wdl.state === "REJECTED" ? "bad" : "info"} title={wdl.state === "REQUESTED" ? "Your refund request is with the Bursary" : wdl.state === "APPROVED" ? "Approved — awaiting payment" : wdl.state === "PAID" ? "Refund paid" : "Refund request not approved"}>
                {naira(wdl.amount)} of {wdl.source_code ?? "funding"} for {wdl.session} to {wdl.bank_name} {wdl.account_no}. {wdl.state === "PAID" ? `Paid ${wdl.paid_at ? onDay(wdl.paid_at) : ""}${wdl.paid_ref ? ` · ${wdl.paid_ref}` : ""}.` : wdl.state === "REJECTED" ? (wdl.reason ?? "") : "You will be told the decision."}
              </Note>
            ) : null}
            {elig.nelfund_after_settlement ? <Note kind="info" title="NELFUND funds received after your school fees were already paid">The Fund&rsquo;s {naira(nelRefundable)} for {w.session} arrived after your fees were settled by other means, so it may be refunded to you. The University approves each refund before any money leaves it.</Note> : null}
            {elig.eligible && refundCap > 0 ? (
              <>
                <div className="sub2 mb-2">Your {w.session} fees are cleared and {naira(refundCap)} of {refundSource === "NELFUND" ? "the Fund's money" : "your own money"} may be refunded. Enter <b>your own</b> bank account.</div>
                {nelRefundable > 0 && selfRefundable > 0 ? <Field id="wd-src" label="Refund"><select id="wd-src" className="ctl" value={refundSource} onChange={(e) => setWd({ ...wd, source: e.target.value, amount: "" })}><option value="NELFUND">NELFUND · up to {naira(nelRefundable)}</option><option value="SELF">My own money · up to {naira(selfRefundable)}</option></select></Field> : null}
                <Field id="wd-amt" label="Amount" hint={`Up to ${naira(refundCap)}`}><input id="wd-amt" className="ctl tnum" value={wd.amount} placeholder={String(refundCap)} onChange={(e) => setWd({ ...wd, amount: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
                <Field id="wd-bank" label="Bank"><input id="wd-bank" className="ctl" value={wd.bank} onChange={(e) => setWd({ ...wd, bank: e.target.value })} autoComplete="off" /></Field>
                <div className="grid grid--2">
                  <Field id="wd-no" label="Account number"><input id="wd-no" className="ctl tnum" value={wd.accountNo} onChange={(e) => setWd({ ...wd, accountNo: e.target.value.replace(/[^0-9]/g, "") })} autoComplete="off" /></Field>
                  <Field id="wd-name" label="Account name"><input id="wd-name" className="ctl" value={wd.accountName} onChange={(e) => setWd({ ...wd, accountName: e.target.value })} autoComplete="off" /></Field>
                </div>
                <Btn kind="primary" disabled={busy !== null || !wd.bank || !wd.accountNo || !wd.accountName} onClick={async () => {
                  const amt = Number(wd.amount) || refundCap;
                  const r = await act("withdraw", "POST", "/me/wallet/withdrawal", { session: w.session, amount: amt, bank: wd.bank, accountNo: wd.accountNo, accountName: wd.accountName, source: refundSource }, `Refund of ${amt} of ${refundSource} requested`, "");
                  if (r) { setSaid(`Refund of ${naira(amt)} requested — the Bursary will review it.`); setWd({ amount: "", bank: "", accountNo: "", accountName: "", source: "" }); }
                }}>APPLY FOR REFUND</Btn>
              </>
            ) : (
              <Note kind="info" title={Number(elig.grant_held) && !nelRefundable && !selfRefundable ? "A grant is not refunded to you" : "Not available yet"}>{elig.reason}</Note>
            )}
          </PBody>
        </Panel>
        <Panel title="Where your funding stands" right={<Btn kind="ghost" size="sm" onClick={printStatement}>Download statement</Btn>}>
          <PBody>
            {w.balances.length ? <DTable cols={["Source", "Credited|num", "Used|num", "Refunded|num", "Available|num"]} rows={w.balances.map((b) => [
              <Two key="s" a={<span>{b.source_name}</span>} b={<Pil kind={NATURE[b.nature]?.[1] ?? "grey"}>{NATURE[b.nature]?.[0] ?? b.nature}</Pil>} />,
              <span key="c" className="tnum">{naira(b.credited)}</span>, <span key="a" className="tnum">{naira(b.applied)}</span>, <span key="r" className="tnum">{naira(b.refunded)}</span>, <b key="v" className="tnum">{naira(b.available)}</b>,
            ])} /> : <div className="sub2">No funding on your wallet yet. NELFUND, a scholarship or your own top-up each show as their own line here.</div>}
            <div className="sub2 mt-2">The Fund&rsquo;s money and your own are refundable once the session&rsquo;s fees are settled; a scholarship or a sponsor&rsquo;s grant is not. <LinkBtn kind="ghost" size="sm" href="/student/fees">Fees page</LinkBtn></div>
          </PBody>
        </Panel>
      </div>

      <Panel title="Wallet statement" right="Every movement, oldest first">
        {w.statement.length ? (
          <DTable cols={["Date|mid", "Entry", "Source", "Reference|mid", "In|num", "Out|num", "Balance|num"]} rows={w.statement.map((e) => [
            <span className="sub2 tnum" key="d">{onDay(e.at)}</span>,
            <Two key="e" a={<Pil kind={KIND[e.kind]?.[1] ?? "grey"}>{KIND[e.kind]?.[0] ?? e.kind}</Pil>} b={<span>{e.note ?? ""}{e.origin && ORIGIN[e.origin] ? <span className="sub2"> · {ORIGIN[e.origin]}{e.legacy_reference ? ` · ${e.legacy_reference}` : ""}{e.legacy_paid_at ? ` · paid ${onDay(e.legacy_paid_at)}` : ""}</span> : null}</span>} />,
            e.source_name ? <Two key="s" a={<span>{e.source_name}</span>} b={e.nature ? <Pil kind={NATURE[e.nature]?.[1] ?? "grey"}>{NATURE[e.nature]?.[0] ?? e.nature}</Pil> : ""} /> : <span className="sub2" key="s">—</span>,
            <span className="tnum sub2" key="r">{e.reference ?? "—"}</span>,
            e.kind === "CREDIT" || e.kind === "TOPUP" ? <span className="tnum ink-green b600" key="i">{naira(e.amount)}</span> : <span className="sub2" key="i">—</span>,
            e.kind === "CREDIT" || e.kind === "TOPUP" ? <span className="sub2" key="o">—</span> : <span className="tnum" key="o">{naira(e.amount)}</span>,
            <b className="tnum" key="b">{naira(e.balance)}</b>,
          ])} />
        ) : <PBody><div className="sub2">No movement on the wallet yet.</div></PBody>}
      </Panel>
    </>
  );
}
