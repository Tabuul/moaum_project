"use client";

/** The student's hostel conduct and room swaps (V291): an incident reported against them, which they may answer in their own
 *  words before the Dean decides; each sanction, its effect, the fine's payment reference, and one appeal within 14 days; a
 *  swap proposed to another occupant by their number, or one proposed to them to agree or decline. The witnesses and who
 *  reported are not shown here. */
import { useState } from "react";
import { Btn, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { APPEAL_STATE, INCIDENT_STATE, SANCTION_LABEL, SWAP_STATE, dayOf, naira, whenAt, type ConductData, type SanctionRow } from "@/lib/hostel";
import { useAct } from "../common";

export function Conduct({ data, canSwap }: { data: ConductData; canSwap: boolean }) {
  const { act, busy } = useAct();
  const [answer, setAnswer] = useState<null | { id: string; reference: string; text: string }>(null);
  const [appeal, setAppeal] = useState<null | { id: string; reference: string; text: string }>(null);
  const [swap, setSwap] = useState<null | { partnerNumber: string; reason: string }>(null);
  const [paid, setPaid] = useState<null | { reference: string; amount: number }>(null);
  const open = data.swaps.filter((w) => w.state === "PROPOSED" || w.state === "AGREED");

  async function sendAnswer() {
    if (!answer) return;
    const r = await act("answer", "POST", `/me/hostel/incidents/${answer.id}/answer`, { statement: answer.text.trim() }, `Account of hostel incident ${answer.reference}`, "Your account is with the Dean of Student Affairs.");
    if (r) setAnswer(null);
  }
  async function sendAppeal() {
    if (!appeal) return;
    const r = await act("appeal", "POST", `/me/hostel/sanctions/${appeal.id}/appeal`, { ground: appeal.text.trim() }, `Appeal against hostel sanction ${appeal.reference}`, "Appeal lodged. The sanction stands until it is decided.");
    if (r) setAppeal(null);
  }
  async function pay(x: SanctionRow) {
    const r = await act(`pay-${x.id}`, "POST", `/me/hostel/sanctions/${x.id}/pay`, {}, `Payment reference for hostel fine ${x.reference}`, "");
    if (r) setPaid({ reference: String(r.reference), amount: Number(r.amount) });
  }
  async function propose() {
    if (!swap) return;
    const r = await act("swap", "POST", "/me/hostel/swaps", { session: data.session, partnerNumber: swap.partnerNumber.trim(), reason: swap.reason.trim() }, "Room swap proposed", "Swap proposed. Nothing moves until the other student agrees and the Dean approves.");
    if (r) setSwap(null);
  }
  async function reply(id: string, agree: boolean) {
    await act(`reply-${id}`, "POST", `/me/hostel/swaps/${id}/answer`, { agree }, agree ? "Room swap agreed" : "Room swap declined", agree ? "Agreed. The swap is with the Dean for approval." : "Declined. Your bed is unchanged.");
  }
  async function withdraw(id: string) {
    await act(`cancel-${id}`, "POST", `/me/hostel/swaps/${id}/cancel`, {}, "Room swap withdrawn", "Swap withdrawn.");
  }

  const nothing = !data.incidents.length && !data.sanctions.length && !data.swaps.length;
  if (nothing && !canSwap && !data.bar) return null;

  return (
    <>
      {data.bar ? <Note kind="bad" title="You may not be given a hostel bed at present">{data.bar}. {data.bar.startsWith("An unpaid") ? "Pay the fine below; the bar lifts when the Bursary confirms it." : "A sanction may be appealed once, within 14 days of the decision."}</Note> : null}
      {paid ? (
        <Note kind="info" title={`Pay ${naira(paid.amount)} against ${paid.reference}`} action={<LinkBtn kind="primary" href="/student/fees">Fees &amp; payments</LinkBtn>}>
          The reference is on your Fees page with the card option and the bank details. The fine is settled when the Bursary confirms the payment.
        </Note>
      ) : null}

      {data.incidents.length || data.sanctions.length ? (
        <Panel title="Hostel conduct" right={`${data.incidents.length} incident${data.incidents.length === 1 ? "" : "s"}`}>
          {data.incidents.map((i) => {
            const mine = data.sanctions.filter((x) => x.incident_ref === i.reference);
            return (
              <PBody key={i.id}>
                <div className="row row--tight" style={{ justifyContent: "space-between" }}>
                  <strong>{i.reference} · {i.kind_label}</strong>
                  <Pil kind={INCIDENT_STATE[i.state]?.[1] ?? "grey"}>{INCIDENT_STATE[i.state]?.[0] ?? i.state}</Pil>
                </div>
                <div className="sub2">{whenAt(i.occurred_at)}{i.place ? ` · ${i.place}` : ""}{i.hall_name ? ` · ${i.hall_name}${i.room_no ? ` ${i.block}-${i.room_no}` : ""}` : ""} · {i.session}</div>
                <p>{i.description}</p>
                {i.statement ? <div className="sub2">Your account ({whenAt(i.statement_at)}): {i.statement}</div>
                  : i.state === "REPORTED" ? <Btn kind="secondary" onClick={() => setAnswer({ id: i.id, reference: i.reference, text: "" })}>Give your account</Btn> : null}
                {i.state === "DISMISSED" && i.decision_note ? <div className="sub2">Dismissed: {i.decision_note}</div> : null}
                {mine.map((x) => (
                  <Note key={x.id} kind={x.state === "QUASHED" ? "ok" : x.kind === "WARNING" ? "info" : "bad"} title={`${x.reference} · ${SANCTION_LABEL[x.kind] ?? x.kind}${x.kind === "FINE" ? ` ${naira(x.amount)}` : ""}${x.state === "QUASHED" ? " · quashed" : ""}`}
                    action={<span className="row row--inline row--tight">
                      {x.payable ? <Btn kind="primary" disabled={busy !== null} onClick={() => void pay(x)}>Pay the fine</Btn> : null}
                      {x.may_appeal ? <Btn kind="ghost" onClick={() => setAppeal({ id: x.id, reference: x.reference, text: "" })}>Appeal</Btn> : null}
                    </span>}>
                    {x.reason}. {x.effect ?? ""}.
                    {x.kind === "FINE" ? (x.settled_at ? " Paid." : x.waived_at ? " Waived." : "") : ""}
                    {x.appeal_state ? ` ${APPEAL_STATE[x.appeal_state]?.[0] ?? x.appeal_state}${x.appeal_note ? `: ${x.appeal_note}` : ""}.` : x.may_appeal ? ` You may appeal until ${dayOf(x.appeal_by)}.` : ""}
                  </Note>
                ))}
              </PBody>
            );
          })}
        </Panel>
      ) : null}

      {canSwap || data.swaps.length ? (
        <Panel title="Room swaps" right={canSwap && !open.length ? <Btn kind="secondary" onClick={() => setSwap({ partnerNumber: "", reason: "" })}>Propose a swap</Btn> : "Both students agree; the Dean approves"}>
          {data.swaps.length ? <DTable cols={["Reference|mid", "With", "Your bed · theirs", "Reason", "Status|mid", "|num"]} rows={data.swaps.map((w) => {
            const proposer = w.role === "PROPOSER";
            return [
              <span key="r" className="tnum">{w.reference}<div className="sub2">{dayOf(w.proposed_at)}</div></span>,
              <span key="w">{proposer ? w.partner_name : w.student_name}<div className="sub2 tnum">{proposer ? w.partner_number : w.student_number}</div></span>,
              <span key="b" className="sub2">{proposer ? `${w.student_room} · ${w.student_bed ?? ""}` : `${w.partner_room} · ${w.partner_bed ?? ""}`} ⇄ {proposer ? `${w.partner_room} · ${w.partner_bed ?? ""}` : `${w.student_room} · ${w.student_bed ?? ""}`}</span>,
              <span key="why" className="sub2">{w.reason}{w.decision_note ? ` · ${w.decision_note}` : ""}</span>,
              <Pil key="st" kind={SWAP_STATE[w.state]?.[1] ?? "grey"}>{SWAP_STATE[w.state]?.[0] ?? w.state}</Pil>,
              <span key="act" className="row row--inline row--tight">
                {!proposer && w.state === "PROPOSED" ? <><Btn kind="primary" disabled={busy !== null} onClick={() => void reply(w.id, true)}>Agree</Btn><Btn kind="ghost" disabled={busy !== null} onClick={() => void reply(w.id, false)}>Decline</Btn></> : null}
                {(w.state === "PROPOSED" && proposer) || w.state === "AGREED" ? <Btn kind="ghost" disabled={busy !== null} onClick={() => void withdraw(w.id)}>Withdraw</Btn> : null}
              </span>,
            ];
          })} /> : <PBody><div className="sub2">To exchange beds with another student of this session, propose a swap naming them by their number. The two beds must carry the same hostel fee; nothing moves until they agree and the Dean of Student Affairs approves.</div></PBody>}
        </Panel>
      ) : null}

      {answer ? (
        <Modal title={`Your account of ${answer.reference}`} sub="Read by the Dean of Student Affairs before a decision is made" onClose={() => setAnswer(null)}
          foot={<><Btn kind="ghost" onClick={() => setAnswer(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy !== null || !answer.text.trim()} onClick={() => void sendAnswer()}>Send</Btn></>}>
          <Field id="cd-ans" label="What happened, in your own words" full><textarea id="cd-ans" className="ctl" rows={5} value={answer.text} onChange={(e) => setAnswer({ ...answer, text: e.target.value })} /></Field>
        </Modal>
      ) : null}
      {appeal ? (
        <Modal title={`Appeal against ${appeal.reference}`} sub="A sanction is appealed once; the sanction stands until the appeal is decided" onClose={() => setAppeal(null)}
          foot={<><Btn kind="ghost" onClick={() => setAppeal(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy !== null || !appeal.text.trim()} onClick={() => void sendAppeal()}>Lodge the appeal</Btn></>}>
          <Field id="cd-app" label="The ground of your appeal" full><textarea id="cd-app" className="ctl" rows={5} value={appeal.text} onChange={(e) => setAppeal({ ...appeal, text: e.target.value })} /></Field>
        </Modal>
      ) : null}
      {swap ? (
        <Modal title="Propose a room swap" sub={`${data.session} · the other student agrees, then the Dean approves`} onClose={() => setSwap(null)}
          foot={<><Btn kind="ghost" onClick={() => setSwap(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy !== null || !swap.partnerNumber.trim() || !swap.reason.trim()} onClick={() => void propose()}>Propose</Btn></>}>
          <div className="grid grid--2 rfgrid">
            <Field id="cd-no" label="The other student's number"><input id="cd-no" className="ctl tnum" value={swap.partnerNumber} onChange={(e) => setSwap({ ...swap, partnerNumber: e.target.value })} placeholder="Matriculation or admission number" /></Field>
            <Field id="cd-why" label="Why you wish to swap" full><input id="cd-why" className="ctl" value={swap.reason} onChange={(e) => setSwap({ ...swap, reason: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
