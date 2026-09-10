"use client";

/** studentTransfer — apply to move to another department, and follow the case through the
 *  committee, Senate, the non-refundable fee, and the change on the register. */
import { useState } from "react";
import Link from "next/link";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { Field, Step } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { naira, PayByCard, useAct } from "../common";

interface App {
  id: string; from_programme: string; from_level: number; to_programme: string; reason: string; state: string;
  recommended_level: number | null; committee_note: string | null; senate_note: string | null;
  fee_reference: string | null; fee_confirmed_at: string | null; applied_at: string;
}
export interface MyTransfer {
  student: { name: string; matric_no: string | null; current_level: number; entry_mode: string; status: string; programme: string; programme_code: string };
  applications: App[];
  programmes: { code: string; name: string; faculty: string }[];
  fee: number;
}

const STAGES: [string, string][] = [
  ["Applied", "Your application is with the office"],
  ["Committee", "The committee considers the case"],
  ["Senate", "The recommended case goes to Senate"],
  ["Approved", "Pay the non-refundable fee"],
  ["Effected", "Moved on the register"],
];
// map a state to how many stages are complete
function stageOf(state: string): number {
  switch (state) {
    case "APPLIED": return 1;
    case "RECOMMENDED": return 2;
    case "APPROVED": return 3;
    case "EFFECTED": return 5;
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

  const live = d.applications.find((a) => ["APPLIED", "RECOMMENDED", "APPROVED"].includes(a.state)) ?? null;
  const last = d.applications[0] ?? null;
  const canApply = !live && d.student.matric_no && ["ACTIVE", "PROBATION"].includes(d.student.status);
  const paidRef = live?.fee_reference ?? feeRef;

  return (
    <>
      <Tiles items={[
        ["Your department", d.student.programme, null, `${d.student.current_level} Level · ${d.student.entry_mode}`],
        ["Processing fee", naira(d.fee), null, "Non-refundable, paid only if approved"],
        ["Applications", String(d.applications.length), null, live ? "One in progress" : "None in progress"],
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}

      {live ? (
        <Panel title="Your application" right={live.to_programme}>
          <div style={{ padding: "4px 0" }}>
            {STAGES.map((s, i) => (
              <div key={s[0]} style={{ padding: "9px 16px", borderTop: i ? "1px solid var(--line-2)" : undefined }}>
                <Step state={stageOf(live.state) > i ? "done" : stageOf(live.state) === i ? "now" : "todo"} title={s[0]} sub={s[1]} />
              </div>
            ))}
          </div>
          <PBody>
            {live.state === "NOT_RECOMMENDED" || live.state === "DECLINED" ? (
              <Note kind="bad" title={live.state === "NOT_RECOMMENDED" ? "The committee did not recommend your case" : "Senate did not approve your case"}>{live.committee_note ?? live.senate_note ?? "No reason was recorded."}</Note>
            ) : null}
            {live.state === "RECOMMENDED" ? <Note kind="info" title="Recommended — awaiting Senate">The committee recommended your transfer to {live.to_programme}{live.recommended_level ? ` at ${live.recommended_level} Level` : ""}. It now goes to Senate for approval.</Note> : null}
            {live.state === "APPROVED" ? (
              <>
                <Note kind="ok" title="Approved — pay the processing fee to complete your transfer">
                  Senate approved your transfer to {live.to_programme}{live.recommended_level ? ` at ${live.recommended_level} Level` : ""}. Pay the non-refundable {naira(d.fee)} fee to process it, then the registry moves you on the register.
                </Note>
                {!paidRef ? (
                  <div style={{ marginTop: 10 }}><Btn kind="primary" disabled={busy !== null} onClick={async () => { const r = await act("fee", "POST", `/me/transfer/${live.id}/fee`, {}, "Transfer fee reference"); if (r) { setFeeRef(String(r.reference)); setSaid(`Reference ${r.reference} generated — pay it by card below.`); } }}>Generate the payment reference</Btn></div>
                ) : (
                  <div style={{ marginTop: 10 }}>
                    {live.fee_confirmed_at ? <Note kind="ok" title="Fee received">Your payment is confirmed. The registry will effect your transfer.</Note> : (
                      <>
                        <div className="sub2" style={{ marginBottom: 6 }}>Reference <span className="tnum">{paidRef}</span> for {naira(d.fee)}. Pay it by card or USSD.</div>
                        <PayByCard reference={paidRef} amount={d.fee} />
                      </>
                    )}
                    <div style={{ marginTop: 8 }}><Link href={`/student/transfer/letter/${live.id}`} className="btn btn--ghost btn--sm">Print approval letter</Link></div>
                  </div>
                )}
              </>
            ) : null}
          </PBody>
        </Panel>
      ) : null}

      {last && last.state === "EFFECTED" ? (
        <Note kind="ok" title="Your transfer is complete" action={<Link href={`/student/transfer/letter/${last.id}`} className="btn btn--ghost btn--sm">Approval letter</Link>}>
          You have been moved to {last.to_programme}{last.recommended_level ? ` at ${last.recommended_level} Level` : ""}. Register your courses under your department for the session.
        </Note>
      ) : null}

      {canApply ? (
        <Panel title="Apply to transfer" right="One application at a time">
          <PBody>
            <Field id="ap-prog" label="Course applied for"><select id="ap-prog" className="ctl" value={prog} onChange={(e) => setProg(e.target.value)}><option value="">Select a department…</option>{d.programmes.map((p) => <option key={p.code} value={p.code}>{p.name} — {p.faculty}</option>)}</select></Field>
            <Field id="ap-reason" label="Reason for seeking transfer" hint="The committee reads this."><textarea id="ap-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
            <Field id="ap-utme" label="Your UTME score" hint="Optional — helps the committee weigh the case."><input id="ap-utme" className="ctl tnum" inputMode="numeric" value={utme} onChange={(e) => setUtme(e.target.value.replace(/[^0-9]/g, ""))} /></Field>
            <div><Btn kind="primary" disabled={busy !== null || !prog || !reason.trim()} onClick={async () => { const r = await act("apply", "POST", "/me/transfer", { toProgramme: prog, reason: reason.trim(), utme: utme ? Number(utme) : null }, "Apply for departmental transfer"); if (r) { setSaid("Your application is with the office."); setProg(""); setReason(""); setUtme(""); } }}>Submit the application</Btn></div>
            <div className="sub2" style={{ marginTop: 6 }}>The {naira(d.fee)} fee is paid only if your case is approved, and it is non-refundable. The University sells nothing at the gate.</div>
          </PBody>
        </Panel>
      ) : !live ? (
        <Note kind="info" title="You cannot apply to transfer right now">Only a matriculated student in good standing may apply. If you have just matriculated, check back after your first results are published.</Note>
      ) : null}
    </>
  );
}
