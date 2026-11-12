"use client";

/** studentTransfer — apply to move to another department, pay the transfer fee, and follow the application through the current HOD,
 *  the new HOD, the Registry and the Academic Office to the change on the register. V727: the fee is the one the Bursary states now,
 *  less every verified payment, here and on the old portal; any payment lets the desks begin, and the final approval waits for the
 *  whole fee. */
import { useState } from "react";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Step } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PayByCard, onDay, useAct, when } from "../common";
import {
  bandWords, creditWords, isLive, madeWords, naira, nextActionWords, num, openForBalance, overpaidWords, owedNow, payLabel, sourceWord,
  type Money, type TransferCredit, type TransferLegacy, type TransferPayment, type TransferPaymentMade,
} from "@/lib/transfer-fee";

interface App {
  id: string; from_programme: string; from_level: number; to_programme: string; reason: string; state: string;
  recommended_level: number | null; committee_note: string | null; senate_note: string | null; decline_note: string | null;
  fee_reference: string | null; fee_confirmed_at: string | null; applied_at: string; session?: string | null;
  // V727: people.transfer_list's columns, as the server reads them
  fee_due?: Money | null; paid_total?: Money | null; old_portal_paid?: Money | null; balance?: Money | null; band?: string | null; legacy_ref?: string | null;
  /** V734: the desk holding it now, in words — at a department of a College, its faculty's Dean */
  desk_label?: string | null;
}
export interface MyTransfer {
  student: { name: string; matric_no: string | null; current_level: number; entry_mode: string; status: string; programme: string; programme_code: string };
  applications: App[];
  programmes: { code: string; name: string; faculty: string }[];
  fee: number | null;
  /** V727: the live application's fee, what is paid here and on the old portal, the balance, what to do next */
  payment?: TransferPayment | null;
  paymentsMade?: TransferPaymentMade[] | null;
  /** V727: old-portal transfer payments awaiting an application */
  credit?: TransferCredit | null;
  /** V727: the old portal's record of the live application */
  legacy?: TransferLegacy | null;
}

const STAGES: [string, string][] = [
  ["Applied", "Your application is submitted"],
  ["Payment", "Pay the transfer fee; your current department acts once a payment is confirmed"],
  ["Current department", "The Head of your department approves (in a College, the Dean of its faculty)"],
  ["New department", "The Head of the department you applied to accepts (in a College, the Dean of its faculty)"],
  ["Registry", "The Registry approves"],
  ["Academic office", "The final approval, once the whole fee is paid"],
  ["Completed", "Moved on the register"],
];
// the index of the stage currently in progress (earlier stages are done). Payment comes right after applying.
function stageOf(state: string, paid: boolean): number {
  switch (state) {
    case "APPLIED": return paid ? 2 : 1;
    case "FROM_OK": return 3;
    case "TO_OK": return 4;
    case "REG_OK": return 5;
    case "EFFECTED": return 7;
    default: return 1;
  }
}

/** the payment step's line: what is paid and what remains */
function paymentSub(p: TransferPayment | null): string {
  if (!p || p.feeDue == null) return STAGES[1][1];
  const owed = owedNow(p);
  if (num(p.paidTotal) <= 0) return STAGES[1][1];
  return owed > 0 ? `${naira(p.paidTotal)} paid · ${naira(owed)} outstanding before the final approval` : `${naira(p.paidTotal)} paid · the fee is paid in full`;
}

/** V727: the fee panel — the fee, what is paid on the old portal and here, the balance, the status, the next action; the button draws the
 *  reference for the balance and that reference's own amount is paid */
function FeePanel({ p }: { p: TransferPayment }) {
  const { act, busy, problem } = useAct();
  const [drawn, setDrawn] = useState<{ reference: string; amount: number } | null>(null);
  // the server's read is the truth: once the page is read again, the open reference comes from it (state adjusted as the prop changes)
  const [seen, setSeen] = useState(p);
  if (p !== seen) {
    setSeen(p);
    setDrawn(null);
  }
  const [word, tone] = bandWords(p.band);
  const label = payLabel(p);
  const open = drawn ?? openForBalance(p);
  const over = overpaidWords(p);
  const stated = p.feeDue != null;
  const owed = owedNow(p);
  async function draw() {
    const r = await act("fee", "POST", `/me/transfer/${p.applicationId}/fee`, {}, "Transfer fee reference", "Reference ready — pay it below");
    if (r && typeof r.reference === "string" && r.amount != null) setDrawn({ reference: r.reference, amount: num(r.amount as Money) });
  }
  return (
    <Panel title="Transfer fee" right={<Pil kind={tone}>{word.toUpperCase()}</Pil>}>
      <PBody>
        <KvGrid cls="grid--4" pairs={[
          ["Total fee", stated ? <b key="f" className="tnum">{naira(p.feeDue)}</b> : "Not yet stated"],
          ["Paid on the old portal", <span key="o" className="tnum">{naira(p.oldPortalPaid)}</span>],
          ["Paid here", <span key="h" className="tnum">{naira(p.portalPaid)}</span>],
          ["Outstanding", stated ? <b key="b" className="tnum" style={{ color: owed > 0 ? "var(--red-ink)" : "var(--green-ink)" }}>{naira(owed)}</b> : "—"],
        ]} />
        <div className="mt-2"><KvGrid cls="grid--3" pairs={[
          ["Payment status", word],
          ["Application status", p.stageLabel ?? "—"],
          ["Next action", nextActionWords(p)],
        ]} /></div>
        {over ? <Note kind="info" title="Paid over the fee">{over}</Note> : null}
        {label ? (
          open ? (
            <div className="mt-2">
              <div className="sub2 mb-2">
                Reference <b className="tnum">{open.reference}</b> for {naira(open.amount)}
                {open.reference === p.openReference && p.openExpiresAt ? `, payable until ${when(p.openExpiresAt)}` : ""}. Pay it by card or USSD, or at a bank against the reference.
              </div>
              <div className="row" style={{ flexWrap: "wrap" }}><PayByCard reference={open.reference} amount={open.amount} /></div>
            </div>
          ) : (
            <div className="mt-2">
              <Btn kind="primary" size="md" busy={busy === "fee"} busyLabel="Preparing the reference…" disabled={busy !== null} onClick={() => void draw()}>{label}</Btn>
              <div className="sub2 mt-1">The reference is for {naira(owed)}, what is owed now; then pay it by card or USSD.</div>
            </div>
          )
        ) : null}
        {problem ? <ProblemNotice problem={problem} /> : null}
      </PBody>
    </Panel>
  );
}

/** V727: every payment counted toward the application, here and on the old portal */
function PaymentsMade({ made }: { made: TransferPaymentMade[] }) {
  return (
    <Panel title="Payments made" right={`${made.length}`}>
      <DTable cols={["Paid on|mid", "Where", "Item", "Reference", "Amount|num", "Status"]} rows={made.map((m, i) => {
        const [w, t] = madeWords(m.status);
        return [
          <span key={`d${i}`} className="tnum sub2">{onDay(m.paidOn)}</span>,
          <span key={`s${i}`}>{sourceWord(m.source)}</span>,
          <span key={`i${i}`}>{m.item ?? "Inter-departmental transfer fee"}</span>,
          <span key={`r${i}`} className="tnum t-xs">{m.source === "OLD_PORTAL" ? (m.payref ?? m.reference ?? "—") : (m.reference ?? "—")}</span>,
          <span key={`a${i}`} className="tnum">{naira(m.amount)}</span>,
          <Pil key={`p${i}`} kind={t}>{w}</Pil>,
        ];
      })} />
    </Panel>
  );
}

export function Transfer({ d, paid = null }: { d: MyTransfer; paid?: string | null }) {
  const { act, busy, problem } = useAct();
  const [prog, setProg] = useState("");
  const [reason, setReason] = useState("");
  const [utme, setUtme] = useState("");
  const [said, setSaid] = useState<string | null>(null);

  const live = d.applications.find((a) => isLive(a.state)) ?? null;
  const last = d.applications[0] ?? null;
  const fee = d.fee;
  const feeSet = fee != null;
  const canApply = !live && feeSet && d.student.matric_no && ["ACTIVE", "PROBATION"].includes(d.student.status);
  const p = d.payment ?? null;
  // the live application's own fee: any verified payment, here or on the old portal, lets the desks begin
  const pLive = p && live && p.applicationId === live.id ? p : null;
  const paidAny = pLive ? num(pLive.paidTotal) > 0 : !!live?.fee_confirmed_at;
  const owed = pLive ? owedNow(pLive) : 0;
  const made = d.paymentsMade ?? [];
  const credit = !live && d.credit && num(d.credit.total) > 0 ? d.credit : null;
  const legacy = live ? d.legacy ?? null : null;
  // back from the gateway: the reference verified on arrival (page.tsx), confirmed or still with the bank
  const back = paid ? made.find((m) => m.reference === paid) ?? null : null;
  const confirmed = !!back && back.status === "CONFIRMED";
  const confirming = !!paid && !confirmed && (!!back || p?.openReference === paid);
  const senate = live && (live.state === "RECOMMENDED" || live.state === "APPROVED");
  // the fee panel for a live application, or for the transfer completed; a declined one's payments stay on Fees & payments
  const showFee = !!p && (isLive(p.state) || p.state === "EFFECTED");

  return (
    <>
      {confirming ? (
        <div className="card"><div className="card__body" style={{ alignItems: "center", textAlign: "center", gap: "var(--s-4)", padding: "var(--s-6) var(--s-5)" }}>
          <div><div className="t-lg b700" style={{ letterSpacing: "-.3px" }}>Confirming your payment</div>
            <p className="sub2" style={{ margin: "6px auto 0", maxWidth: "44ch", lineHeight: 1.55 }}>Reference {paid}. This page updates when the payment is confirmed.</p></div>
          <Btn kind="ghost" onClick={() => window.location.reload()}>Check again</Btn>
        </div></div>
      ) : null}
      {confirmed && back ? (
        <Note kind="ok" title="Transfer fee payment confirmed">
          Reference {back.reference} · {naira(back.amount)} counted toward your transfer fee. {pLive && owed > 0 ? `${naira(owed)} remains before the final approval.` : pLive && pLive.feeDue != null ? "The fee is paid in full." : ""}
        </Note>
      ) : null}
      <Tiles items={[
        ["Your department", d.student.programme, null, `${d.student.current_level} Level · ${d.student.entry_mode}`],
        ["Processing fee", feeSet ? naira(fee) : "Not set yet", null, feeSet ? "Non-refundable · payments here and on the old portal count" : "The Bursary has not set it yet"],
        ["Applications", String(d.applications.length), null, live ? "One in progress" : "None in progress"],
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}

      {showFee && p ? <FeePanel p={p} /> : null}
      {showFee && made.length ? <PaymentsMade made={made} /> : null}

      {live ? (
        <Panel title="Your application" right={live.to_programme}>
          {!senate ? (
            <div style={{ padding: "var(--s-1) 0" }}>
              {STAGES.map((s, i) => (
                <div key={s[0]} style={{ padding: "var(--s-2) var(--s-4)", borderTop: i ? "1px solid var(--line-2)" : undefined }}>
                  <Step state={i === 1 && !paidAny ? "now" : stageOf(live.state, paidAny) > i ? "done" : stageOf(live.state, paidAny) === i ? "now" : "todo"}
                        title={s[0]} sub={i === 1 ? paymentSub(pLive) : s[1]} />
                </div>
              ))}
            </div>
          ) : null}
          <PBody>
            {/* V734: who holds it now, named */}
            {live.desk_label ? <div className="sub2">Now with {live.desk_label}.</div> : null}
            {legacy ? (
              <div className="sub2">
                Begun on the old portal as <b className="tnum">{legacy.legacyRef}</b>{legacy.appliedOn ? ` on ${onDay(legacy.appliedOn)}` : ""}{legacy.stage ? `; it reached “${legacy.stage}” there` : ""}. It continues here, and your payments there count toward the fee.
                {/* V727: the old portal's approvals and documents, as its export gave them */}
                {legacy.approvals?.trim() ? <div className="mt-1"><b>Approvals on the old portal</b><div style={{ whiteSpace: "pre-wrap", overflowWrap: "anywhere" }}>{legacy.approvals}</div></div> : null}
                {legacy.documents?.trim() ? <div className="mt-1"><b>Documents on the old portal</b><div style={{ whiteSpace: "pre-wrap", overflowWrap: "anywhere" }}>{legacy.documents}</div></div> : null}
              </div>
            ) : null}
            {senate ? (
              <Note kind="info" title={live.state === "RECOMMENDED" ? "Recommended to Senate" : "Approved by Senate"}
                action={live.state === "APPROVED" ? <LinkBtn kind="ghost" href={`/student/transfer/letter/${live.id}`}>Approval letter</LinkBtn> : undefined}>
                {live.state === "RECOMMENDED"
                  ? `The committee recommends your transfer to ${live.to_programme}${live.recommended_level ? ` at ${live.recommended_level} Level` : ""}. Senate decides next; you will be told.`
                  : `Senate approved your transfer to ${live.to_programme}. The Registry gives it effect on the register once the transfer fee is paid in full.`}
              </Note>
            ) : !feeSet && !paidAny ? (
              <Note kind="bad" title="The transfer fee has not been set yet">
                Your application is submitted. You can pay once the Bursary sets the fee; approvals begin after payment.
              </Note>
            ) : !paidAny && live.state === "APPLIED" ? (
              <Note kind="info" title="Pay the transfer fee to start your transfer">
                Your application to move to {live.to_programme} is submitted. Pay the fee above; your current department acts once a payment is confirmed.
              </Note>
            ) : (
              <Note kind="info" title={`In progress — ${pLive?.stageLabel ?? STAGES[stageOf(live.state, true)]?.[0] ?? "under review"}`}>
                Your request to move to {live.to_programme} is with the {STAGES[stageOf(live.state, true)]?.[0]?.toLowerCase()}.
                {owed > 0 ? ` Pay the ${naira(owed)} balance before the Academic Office's final approval.` : ""}
              </Note>
            )}
          </PBody>
        </Panel>
      ) : null}

      {last && last.state === "EFFECTED" ? (
        <Note kind="ok" title="Your transfer is complete" action={<LinkBtn kind="ghost" href={`/student/transfer/letter/${last.id}`}>Approval letter</LinkBtn>}>
          You have been moved to {last.to_programme}{last.recommended_level ? ` at ${last.recommended_level} Level` : ""}. Register your courses under your department for the session.
        </Note>
      ) : null}
      {last && last.state === "DECLINED" ? (
        <Note kind="bad" title="Your transfer application was not approved">{last.decline_note ?? "No reason was recorded."} You may apply again if your circumstances change.</Note>
      ) : null}

      {/* V727: old-portal transfer payments with no application here yet: nothing is owed until one is made, and then they count */}
      {credit ? (
        <Note kind="info" title="Paid on the old portal">
          {creditWords(credit, canApply ? "below" : "later")}
          {credit.payments.length ? (
            <span className="blk sub2 mt-1">
              {credit.payments.map((c, i) => <span key={i} className="blk tnum">{[c.payref, c.item, naira(c.amount), c.paidOn ? onDay(c.paidOn) : null].filter(Boolean).join(" · ")}</span>)}
            </span>
          ) : null}
        </Note>
      ) : null}

      {canApply ? (
        <Panel title="Apply to transfer" right="One application at a time">
          <PBody>
            <Field id="ap-prog" label="Course applied for"><SearchSelect id="ap-prog" value={prog} placeholder="Search a programme…" options={d.programmes.map((x) => ({ value: x.code, label: `${x.name} — ${x.faculty}` }))} onChange={(v) => setProg(v)} /></Field>
            <Field id="ap-reason" label="Reason for seeking transfer" hint="Each approving office reads this."><textarea id="ap-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
            <Field id="ap-utme" label="Your UTME score" hint="Optional — helps the offices weigh the case."><input id="ap-utme" className="ctl tnum" inputMode="numeric" value={utme} onChange={(e) => setUtme(e.target.value.replace(/[^0-9]/g, ""))} /></Field>
            <div><Btn kind="primary" disabled={busy !== null || !prog || !reason.trim()} onClick={async () => { const r = await act("apply", "POST", "/me/transfer", { toProgramme: prog, reason: reason.trim(), utme: utme ? Number(utme) : null }, "Apply for departmental transfer"); if (r) { setSaid("Your application is with the office."); setProg(""); setReason(""); setUtme(""); } }}>Submit the application</Btn></div>
            <div className="sub2 mt-2">
              After you apply, you pay the non-refundable {naira(fee)} fee online{credit ? ", less what you paid on the old portal" : ""}. Your current department acts once a payment is confirmed; the
              offices after it approve in turn, and the Academic Office gives its final approval once the whole fee is paid.
            </div>
          </PBody>
        </Panel>
      ) : !live ? (
        !feeSet ? (
          <Note kind="info" title="Transfers are not open yet">The Bursary has not set the transfer processing fee. Once it is set, you can apply to transfer here.</Note>
        ) : (
          <Note kind="info" title="You cannot apply to transfer right now">Only a matriculated student in good standing may apply.</Note>
        )
      ) : null}
    </>
  );
}
