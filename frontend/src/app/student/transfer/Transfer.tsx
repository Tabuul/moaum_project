"use client";

/** studentTransfer — apply to move to another department, and follow the case through the
 *  committee, Senate, the non-refundable fee, and the change on the register. */
import { useState } from "react";
import Link from "next/link";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { Field, Step } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";
import { naira, PayByCard, useAct } from "../common";

interface App {
  id: string; from_programme: string; from_level: number; to_programme: string; reason: string; state: string;
  recommended_level: number | null; committee_note: string | null; senate_note: string | null; decline_note: string | null;
  fee_reference: string | null; fee_confirmed_at: string | null; applied_at: string;
}
export interface MyTransfer {
  student: { name: string; matric_no: string | null; current_level: number; entry_mode: string; status: string; programme: string; programme_code: string };
  applications: App[];
  programmes: { code: string; name: string; faculty: string }[];
  fee: number | null;
}

const STAGES: [string, string][] = [
  ["Applied", "Your application is submitted"],
  ["Payment", "Pay the non-refundable fee online"],
  ["Current department", "Your current department approves"],
  ["New department", "The department you applied to accepts"],
  ["Registrar", "The Registrar approves"],
  ["Academic office", "The Academic office approves"],
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

export function Transfer({ d }: { d: MyTransfer }) {
  const { act, busy, problem } = useAct();
  const [prog, setProg] = useState("");
  const [reason, setReason] = useState("");
  const [utme, setUtme] = useState("");
  const [feeRef, setFeeRef] = useState<string | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const live = d.applications.find((a) => ["APPLIED", "FROM_OK", "TO_OK", "REG_OK"].includes(a.state)) ?? null;
  const last = d.applications[0] ?? null;
  const fee = d.fee;
  const feeSet = fee != null;
  const canApply = !live && feeSet && d.student.matric_no && ["ACTIVE", "PROBATION"].includes(d.student.status);
  const paidRef = live?.fee_reference ?? feeRef;
  const paid = !!live?.fee_confirmed_at;

  return (
    <>
      <Tiles items={[
        ["Your department", d.student.programme, null, `${d.student.current_level} Level · ${d.student.entry_mode}`],
        ["Processing fee", feeSet ? naira(fee) : "Not set yet", null, feeSet ? "Non-refundable · paid online after you apply" : "The Bursary has not set it yet"],
        ["Applications", String(d.applications.length), null, live ? "One in progress" : "None in progress"],
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}

      {live ? (
        <Panel title="Your application" right={live.to_programme}>
          <div style={{ padding: "4px 0" }}>
            {STAGES.map((s, i) => (
              <div key={s[0]} style={{ padding: "9px 16px", borderTop: i ? "1px solid var(--line-2)" : undefined }}>
                <Step state={stageOf(live.state, paid) > i ? "done" : stageOf(live.state, paid) === i ? "now" : "todo"} title={s[0]} sub={s[1]} />
              </div>
            ))}
          </div>
          <PBody>
            {!live.fee_confirmed_at ? (!feeSet ? (
              <Note kind="bad" title="The transfer fee has not been set yet">
                Your application is submitted, but the Bursary has not set the transfer processing fee. You will be able to pay once it is set — the approvals begin after payment.
              </Note>
            ) : (
              <>
                <Note kind="info" title="Pay the non-refundable processing fee to start your transfer">
                  Your application to move to {live.to_programme} is submitted. Pay the {naira(fee)} fee online now; once it is confirmed, your current department begins the approvals.
                </Note>
                {!paidRef ? (
                  <div className="mt-3"><Btn kind="primary" disabled={busy !== null} onClick={async () => { const r = await act("fee", "POST", `/me/transfer/${live.id}/fee`, {}, "Transfer fee reference"); if (r) { setFeeRef(String(r.reference)); setSaid(`Reference ${r.reference} generated — pay it below.`); } }}>Pay the fee online</Btn></div>
                ) : (
                  <div className="mt-3">
                    <div className="sub2 mb-2">Reference <span className="tnum">{paidRef}</span> for {naira(fee)}. Pay it by card or USSD.</div>
                    <PayByCard reference={paidRef} amount={fee} />
                  </div>
                )}
              </>
            )) : (
              <Note kind="info" title={`In progress — ${STAGES[stageOf(live.state, true)]?.[0] ?? "under review"}`}>
                Your fee is paid. Your request to move to {live.to_programme} is with the {STAGES[stageOf(live.state, true)]?.[0]?.toLowerCase()}. Each office approves in turn; watch it advance above.
              </Note>
            )}
          </PBody>
        </Panel>
      ) : null}

      {last && last.state === "EFFECTED" ? (
        <Note kind="ok" title="Your transfer is complete" action={<Link href={`/student/transfer/letter/${last.id}`} className="btn btn--ghost btn--sm">Approval letter</Link>}>
          You have been moved to {last.to_programme}{last.recommended_level ? ` at ${last.recommended_level} Level` : ""}. Register your courses under your department for the session.
        </Note>
      ) : null}
      {last && last.state === "DECLINED" ? (
        <Note kind="bad" title="Your transfer application was not approved">{last.decline_note ?? "No reason was recorded."} You may apply again if your circumstances change.</Note>
      ) : null}

      {canApply ? (
        <Panel title="Apply to transfer" right="One application at a time">
          <PBody>
            <Field id="ap-prog" label="Course applied for"><SearchSelect id="ap-prog" value={prog} placeholder="Search a programme…" options={d.programmes.map((p) => ({ value: p.code, label: `${p.name} — ${p.faculty}` }))} onChange={(v) => setProg(v)} /></Field>
            <Field id="ap-reason" label="Reason for seeking transfer" hint="Each approving office reads this."><textarea id="ap-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
            <Field id="ap-utme" label="Your UTME score" hint="Optional — helps the offices weigh the case."><input id="ap-utme" className="ctl tnum" inputMode="numeric" value={utme} onChange={(e) => setUtme(e.target.value.replace(/[^0-9]/g, ""))} /></Field>
            <div><Btn kind="primary" disabled={busy !== null || !prog || !reason.trim()} onClick={async () => { const r = await act("apply", "POST", "/me/transfer", { toProgramme: prog, reason: reason.trim(), utme: utme ? Number(utme) : null }, "Apply for departmental transfer"); if (r) { setSaid("Your application is with the office."); setProg(""); setReason(""); setUtme(""); } }}>Submit the application</Btn></div>
            <div className="sub2 mt-2">After you apply, you pay the non-refundable {naira(fee ?? 0)} fee online; your current department and the offices after it then approve in turn. The University sells nothing at the gate.</div>
          </PBody>
        </Panel>
      ) : !live ? (
        !feeSet ? (
          <Note kind="info" title="Transfers are not open yet">The Bursary has not set the transfer processing fee. Once it is set, you can apply to transfer here.</Note>
        ) : (
          <Note kind="info" title="You cannot apply to transfer right now">Only a matriculated student in good standing may apply. If you have just matriculated, check back after your first results are published.</Note>
        )
      ) : null}
    </>
  );
}
