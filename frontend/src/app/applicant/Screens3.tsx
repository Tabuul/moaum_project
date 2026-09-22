"use client";

/**
 * Accepting the offer, document clearance, matriculation — proto/part13.html
 * applicantAccept, applicantClearance and applicantMatric, as drawn. The
 * admission number appears when the Academic Office brings the candidate
 * onto the register; the matriculation number when it is issued over the
 * confirmed faculty lists. Neither is shown in the other's box.
 */
import { useState } from "react";
import Link from "next/link";
import { at, confirmedReference, openReference, CLEARANCE_ITEMS, type Application } from "@/lib/applicant";
import { Btn, Note, Panel, PBody, Pil, Tick, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PayByCard, Rail, StepList, useAct, when } from "./common";

/* ── 7. accept the offer ── */

export function Accept({ a }: { a: Application }) {
  const { act, busy, problem } = useAct();
  const [agreed, setAgreed] = useState(!!a.undertakingAt);
  const paid = confirmedReference(a, "ACCEPTANCE");
  const open = openReference(a, "ACCEPTANCE");
  const fee = Number(a.fees.acceptanceFee);

  if (!at(a, 5) || a.decision !== "OFFERED") {
    return (
      <>
        <Note kind="info" title="There is nothing to accept yet">This page opens when the Admissions Board publishes an offer.</Note>
        <Rail a={a} />
      </>
    );
  }
  if (a.declinedAt) {
    return <Note kind="bad" title={`You declined this offer on ${when(a.declinedAt)}`}>A declined offer is not reinstated.</Note>;
  }
  if (at(a, 6) && paid) {
    return (
      <>
        <Note kind="ok" title={`Offer accepted — ${money(Number(paid.amount))} received`} action={<Link href="/applicant/clearance" className="btn btn--primary btn--sm">Clearance checklist</Link>}>
          Your place is held. Bring your original documents to the Registry for clearance.
        </Note>
        <Panel title="Receipt" right={paid.reference}>
          <DTable cols={["Field", "Value"]} rows={[
            ["Reference", <span className="tnum" key="r">{paid.reference}</span>],
            ["Confirmed", <span className="tnum" key="p">{when(paid.confirmedAt)}</span>],
            ["Channel", paid.channel ?? "—"],
            ["Amount", <strong className="tnum" key="a">{money(Number(paid.amount))}</strong>],
            ["Non-refundable", "Yes — the acceptance fee is not refunded if you later withdraw"],
            ["Status", <Pil kind="ok" key="s">Paid</Pil>],
          ]} />
        </Panel>
      </>
    );
  }
  return (
    <>
      <Panel title="To accept, you must do both">
        <DTable cols={["What", "Detail", "Amount|num"]} rows={[
          [<Two key="w" a="Pay the acceptance fee" b="Non-refundable. It is credited against your first session charges." />, <span className="sub2" key="d">{paid ? "Confirmed" : open ? `Reference ${open.reference}, expires ${when(open.expiresAt)}` : "Generate a reference below"}</span>, <strong className="tnum" key="a">{money(fee)}</strong>],
          [<Two key="w" a="Sign the undertaking" b="The University’s conditions of studentship" />, <span className="sub2" key="d">{a.undertakingAt ? `Signed ${when(a.undertakingAt)}` : "Signed electronically below"}</span>, <span className="sub2" key="a">&mdash;</span>],
        ]} />
      </Panel>
      <Panel title="Undertaking" right="Read it before you sign">
        <PBody>
          <div className="sub2" style={{ lineHeight: 1.65 }}>I accept the offer of provisional admission on the terms stated. I declare that the particulars and results I submitted are true and complete, and I understand that the University verifies them with the examination bodies. I undertake to abide by the statutes, regulations and disciplinary code of the University, and I accept that admission obtained on a false declaration is void at any time, including after the award of a degree.</div>
          <label style={{ display: "flex", gap: 9, alignItems: "flex-start", fontSize: 13.5, color: "var(--muted)", marginTop: 6 }}>
            <input type="checkbox" className="chk" checked={agreed} disabled={!!a.undertakingAt} onChange={(e) => setAgreed(e.target.checked)} />
            <span>I have read the undertaking and I accept it.</span>
          </label>
        </PBody>
      </Panel>
      <Note kind="info" title="Accepting does not complete your admission">
        It holds your place. Admission is complete only after the Registry has seen your original documents at clearance and Senate has approved the list.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <div style={{ display: "flex", gap: 9, flexWrap: "wrap" }}>
        {!a.undertakingAt ? (
          <Btn kind="urgent" disabled={!agreed || busy !== null} onClick={() => void act("sign", "POST", "/me/accept", { undertaking: true }, "Undertaking signed by the applicant")}>{busy === "sign" ? "Signing…" : "Sign the undertaking"}</Btn>
        ) : null}
        {!paid ? (
          <Btn kind={open ? "ghost" : (a.undertakingAt ? "urgent" : "primary")} disabled={busy !== null} onClick={() => void act("ref", "POST", "/me/fee-references", { kind: "ACCEPTANCE" }, "Acceptance fee reference generated for the applicant")}>{busy === "ref" ? "Generating…" : open ? "Generate a new reference" : `Generate a reference for ${money(fee)}`}</Btn>
        ) : null}
        <Btn kind="ghost" disabled={busy !== null} onClick={() => { if (window.confirm("Decline this offer? A declined offer is not reinstated.")) void act("decline", "POST", "/me/decline", {}, "Offer declined by the applicant"); }}>Decline this offer</Btn>
      </div>
      {open && !paid ? (
        <Panel title="Your payment reference" right="Generated for you alone">
          <PBody>
            <div className="eyebrow">Reference</div>
            <div className="tnum" style={{ fontSize: 22, fontWeight: 700, letterSpacing: ".5px" }}>{open.reference}</div>
            <div className="sub2" style={{ marginTop: 6 }}>Quote this reference and nothing else. You do not need a new one &mdash; pay this one now: on the gateway it confirms at once and your place is held (the undertaking signed), or pay it at a bank and the Bursary confirms it against the reference.</div>
            <div style={{ display: "flex", gap: 9, flexWrap: "wrap", marginTop: 8 }}><PayByCard reference={open.reference} amount={fee} /></div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}

/* ── 8. document clearance ── */

export function Clearance({ a }: { a: Application }) {
  const done = at(a, 7);
  if (!at(a, 6)) {
    return (
      <>
        <Note kind="info" title="Clearance opens when you have accepted your offer">The Registry clears only candidates who have accepted and paid the acceptance fee.</Note>
        <Rail a={a} />
      </>
    );
  }
  const state = (item: string) => a.clearance.find((c) => c.item === item);
  const verified = a.clearance.filter((c) => c.state === "VERIFIED").length;
  return (
    <>
      <Note kind={done ? "ok" : "info"} title={done ? "You are cleared" : "Clearance is in person, at the Registry"}
        action={done ? <Link href="/applicant/matric" className="btn btn--primary btn--sm">What happens next</Link> : null}>
        {done ? "Every document has been seen and verified. You may now pay your fees and register your courses — under your admission number. Your matriculation number is issued afterwards, over the list of students who actually registered." : "Bring the originals, not photocopies. Nothing is paid at clearance."}
      </Note>
      <Panel title="Documents" right={`${verified} of 6 verified`}>
        <DTable cols={["Document", "What is required", "Status|num"]} rows={CLEARANCE_ITEMS.map(([k, label, req]) => {
          const c = state(k);
          return [
            <Two key="d" a={label} b={c?.state === "VERIFIED" ? `Verified ${when(c.decidedAt)}` : c?.state === "QUERY" ? c.note ?? "Query" : "Not yet presented"} />,
            <span className="sub2" key="r">{req}</span>,
            c?.state === "VERIFIED" ? <Pil kind="ok" key="s">Verified</Pil> : c?.state === "QUERY" ? <Pil kind="bad" key="s">Query</Pil> : <Pil kind="info" key="s">Not presented</Pil>,
          ];
        })} />
      </Panel>
      <Note kind="info" title="Nothing is paid at clearance, to anyone">
        Clearance is a check of documents. Any request for money at the counter, in the corridor or afterwards should be reported to the Registrar with the name and the date.
      </Note>
    </>
  );
}

/* ── 9 and 10. registration, then matriculation ── */

export function Matric({ a }: { a: Application }) {
  if (!at(a, 9) || !a.matricNo) {
    const dept = a.studentProgramme ?? a.programmeCode ?? "—";
    return (
      <>
        <Note kind="info" title="You register your courses first, and are matriculated afterwards">
          This is the order the Academic Office works in, and it is deliberate. You pay your fees and register your courses under your <b>admission number</b>. Your Faculty Officer then generates the list of students who actually registered, the Academic Office confirms it, and matriculation numbers are issued over that confirmed list in one run. A number is not issued to somebody who accepted an offer and did not come.
        </Note>
        <Rail a={a} />
        <div className="grid grid--2">
          <Panel title="What you carry now" right="Your admission number">
            <PBody>
              {a.admissionNo ? (
                <div className="tnum" style={{ fontFamily: "var(--serif)", fontSize: "clamp(19px,4vw,26px)", fontWeight: 700, letterSpacing: ".6px" }}>{a.admissionNo}</div>
              ) : (
                <div className="sub2"><b>Not issued yet.</b> The Academic Office issues it when it brings the accepted candidates onto the register.</div>
              )}
              <p className="sub2" style={{ margin: 0 }}>Issued when the Academic Office brings you onto the register after you accept. It identifies you for your fees and for your course registration. Quote it at any counter until you are matriculated. It is kept on your record afterwards &mdash; it is retired, not deleted.</p>
            </PBody>
          </Panel>
          <Panel title="What you will be issued" right="Your matriculation number">
            <PBody>
              <DTable cols={["Part", "Meaning"]} rows={[
                [<span className="tnum" key="p">MOAUM</span>, "The University"],
                [<span className="tnum" key="p">{dept}</span>, "Your department"],
                [<span className="tnum" key="p">{a.session.slice(2, 4)}</span>, `The session you were admitted in — ${a.session}`],
                [<span className="tnum" key="p">NNNN</span>, "Your serial within that department and session"],
              ]} />
              <p className="sub2" style={{ margin: 0 }}>It never changes, and it is never given to anybody else.</p>
            </PBody>
          </Panel>
        </div>
        <Panel title="Between the two numbers" right="What each office sees while you have no matriculation number">
          <StepList list={[
            [a.admissionNo ? "done" : "todo", "The Academic Office", "Brings you onto the register under your admission number."],
            [a.admissionNo ? "now" : "todo", "The Bursary and your department", "Bill you, receipt you and register your courses under your admission number."],
            ["todo", "Your Faculty Officer", "Puts you on the list of students who registered. This is the step that makes you a candidate for matriculation."],
            ["todo", "The Academic Office", "Confirms the faculty list and runs matriculation. Your number is issued here."],
            ["todo", "The Library", "Cannot make your identity card yet — the card is keyed on the matriculation number."],
          ]} />
        </Panel>
        <Note kind="info" title="Where a matriculation number does not exist yet, the portal says so">
          It does not quietly show your admission number in a field labelled matriculation number. Two identifiers that look alike in the same box is how a record ends up attached to the wrong person.
        </Note>
      </>
    );
  }
  return (
    <>
      <div className="card" style={{ borderTop: "4px solid var(--green)" }}>
        <PBody>
          <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
            <div style={{ width: 26, height: 26, borderRadius: 13, background: "var(--green)", display: "flex", alignItems: "center", justifyContent: "center" }}><Tick size={14} colour="#fff" /></div>
            <span className="eyebrow" style={{ color: "var(--green-ink)" }}>Matriculation number issued</span>
          </div>
          <div className="tnum" style={{ fontFamily: "var(--serif)", fontSize: "clamp(24px,5vw,34px)", fontWeight: 700, letterSpacing: "1px" }}>{a.matricNo}</div>
          <div className="sub2">{a.name} &middot; {a.programme} &middot; {a.entryLevel} Level</div>
          <div style={{ height: 1, background: "var(--line-2)" }} />
          <div className="sub2">This number identifies you for the rest of your studies and beyond &mdash; on every course registration, every score sheet, every result slip, your certificate and your transcript. Quote it in all correspondence. It never changes.</div>
        </PBody>
      </div>
      <Note kind="ok" title="Your application account is now your student account">
        Your application number {a.applicationNo} and your admission number {a.admissionNo} are both retired and both kept on your record &mdash; a document issued to you under either of them is still yours. Student sign-in arrives with the student module.
      </Note>
      <Note kind="info" title="You are admitted provisionally until your results are verified">
        The Registry completes verification with WAEC, NECO and JAMB during your first session. Admission obtained on a result that does not verify is void at any point afterwards, including after graduation.
      </Note>
    </>
  );
}
