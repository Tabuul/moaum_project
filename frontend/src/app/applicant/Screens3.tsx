"use client";

/**
 * Accepting the offer, document clearance, matriculation — proto/part13.html
 * applicantAccept, applicantClearance and applicantMatric, as drawn. The
 * admission number appears when the Academic Office brings the candidate
 * onto the register; the matriculation number when it is issued over the
 * confirmed faculty lists. Neither is shown in the other's box.
 */
import { useState } from "react";
import { at, acceptanceOf, confirmedReference, confirmedReferences, openReference, CLEARANCE_ITEMS, type Application } from "@/lib/applicant";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tick, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PayByCard, Rail, StepList, useAct, when } from "./common";

/* ── 7. accept the offer ── */

/** V724: the acceptance fee revised after part of it was paid — the figures from the record (admissions.acceptance_entitlement), the
 *  balance owed once, never the full fee again; the one button draws the reference for the balance (the same POST: the server answers
 *  what is owed now) and the card checkout pays it */
function AcceptanceBalanceDue({ a, open, busy, onPay }: { a: Application; open: { reference: string; amount: number; expiresAt: string | null } | null; busy: boolean; onPay: () => void }) {
  const acc = acceptanceOf(a);
  return (
    <>
      <Note kind="bad" title={`Acceptance fee balance of ${money(acc.balance)} to pay`} action={open ? null : <Btn kind="urgent" disabled={busy} onClick={onPay}>{busy ? "Generating…" : "Pay outstanding balance"}</Btn>}>
        The acceptance fee for {a.session} was revised to {money(acc.feeDue)} after you paid {money(acc.paidTotal)}. Your place is held; only the balance of {money(acc.balance)} is owed — you are never charged the full fee again. The acceptance letter is issued once the balance is paid.
      </Note>
      <Panel title="Acceptance fee" right="Revised after your payment">
        <PBody>
          <KvGrid cls="grid--4" pairs={[
            ["Required acceptance fee", <b key="f" className="tnum">{money(acc.feeDue)}</b>],
            ["Amount previously paid", <b key="p" className="tnum">{money(acc.paidTotal)}</b>],
            ["Outstanding balance", <b key="b" className="tnum ink-red">{money(acc.balance)}</b>],
            ["Payment status", <Pil key="s" kind="warn">PARTIALLY PAID</Pil>],
          ]} />
          {open ? (
            <div className="mt-2">
              <div className="eyebrow">Reference for the balance</div>
              <div className="tnum b700" style={{ fontSize: "var(--t-2xl)", letterSpacing: ".5px" }}>{open.reference}</div>
              <div className="sub2">{money(open.amount)}{open.expiresAt ? ` · expires ${when(open.expiresAt)}` : ""}. Quote this reference only; at a bank, by transfer, or by card below.</div>
              <div className="row mt-2"><PayByCard reference={open.reference} amount={open.amount} /></div>
            </div>
          ) : (
            <div className="row row--between mt-2">
              <span className="sub2">The reference is drawn for the balance alone and is valid for 24 hours; pay by card, USSD or at the bank.</span>
              <Btn kind="urgent" disabled={busy} onClick={onPay}>{busy ? "Generating…" : "Pay outstanding balance"}</Btn>
            </div>
          )}
        </PBody>
      </Panel>
    </>
  );
}

/** every acceptance payment confirmed, oldest first: one, or two once the revised fee's balance is paid (V724) */
function AcceptanceReceipts({ a }: { a: Application }) {
  const rows = confirmedReferences(a, "ACCEPTANCE");
  return (
    <Panel title={rows.length > 1 ? "Receipts" : "Receipt"} right={rows.map((r) => r.reference).join(" · ")}>
      <DTable cols={["Field", "Value"]} rows={rows.flatMap((paid, i) => [
        ["Reference", <span className="tnum" key={`r${i}`}>{paid.reference}</span>],
        ["Confirmed", <span className="tnum" key={`p${i}`}>{when(paid.confirmedAt)}</span>],
        ["Channel", paid.channel ?? "—"],
        ["Amount", <strong className="tnum" key={`a${i}`}>{money(Number(paid.amount))}</strong>],
        ["Non-refundable", "Yes — the acceptance fee is not refunded if you later withdraw"],
        ["Status", <Pil kind="ok" key={`s${i}`}>Paid</Pil>],
      ])} />
    </Panel>
  );
}

export function Accept({ a }: { a: Application }) {
  const { act, busy, problem } = useAct();
  const [agreed, setAgreed] = useState(!!a.undertakingAt);
  const paid = confirmedReference(a, "ACCEPTANCE");
  const open = openReference(a, "ACCEPTANCE");
  /* V724: the fee as stated now, what is confirmed and the balance — the reference is always drawn for the balance (the whole fee
     before anything is confirmed), and the figures on this page are the record's, never typed */
  const acc = acceptanceOf(a);
  const owed = acc.balance > 0;
  const fee = acc.feeDue;
  const openRef = open ? { reference: open.reference, amount: Number(open.amount), expiresAt: open.expiresAt } : acc.openReference ? { reference: acc.openReference, amount: Number(acc.openAmount ?? acc.balance), expiresAt: acc.openExpiresAt } : null;
  const drawBalance = () => void act("ref", "POST", "/me/fee-references", { kind: "ACCEPTANCE" }, "Acceptance fee balance reference generated for the applicant");

  /* V295: an offer is accepted once the applicant has checked the admission status and read it, through Admission Status
     Checking; until then this page says nothing of whether there is one */
  if (a.checking && !a.checking.past && !(a.decision && a.decision !== "OFFERED")) {
    return (
      <>
        <Note kind="info" title="Check your admission status first" action={<LinkBtn kind="primary" href="/applicant/status">Admission status</LinkBtn>}>
          Read your offer through Admission Status Checking, then accept it here.
        </Note>
        <Rail a={a} />
      </>
    );
  }
  if (!at(a, 5) || a.decision !== "OFFERED") {
    return (
      <>
        <Note kind="info" title="There is nothing to accept yet">This page opens when the Admissions Board publishes an offer.</Note>
        <Rail a={a} />
      </>
    );
  }
  if (a.declinedAt) {
    return <Note kind="bad" title={`You declined this offer on ${when(a.declinedAt)}`}>If you declined by mistake, write to the Academic Office quoting your application number: a decline is reversed only while your place has not been given to someone else.</Note>;
  }
  if (at(a, 6) && acc.partPaid) {
    /* V724: accepted on the fee as it stood, then the fee revised: the balance is paid here, once; the letter waits for it */
    return (
      <>
        {problem ? <ProblemNotice problem={problem} /> : null}
        <AcceptanceBalanceDue a={a} open={openRef} busy={busy !== null} onPay={drawBalance} />
        <AcceptanceReceipts a={a} />
      </>
    );
  }
  if (at(a, 6) && paid) {
    return (
      <>
        <Note kind="ok" title={`Offer accepted — ${money(acc.paidTotal)} received`} action={<LinkBtn kind="primary" href="/applicant/clearance">Clearance checklist</LinkBtn>}>
          Your place is held and the acceptance fee is settled. <a className="lnk" href="/applicant/status/letter" target="_blank" rel="noopener">View and print your admission letter</a>; bring your original documents to the Registry for clearance.
        </Note>
        <AcceptanceReceipts a={a} />
      </>
    );
  }
  return (
    <>
      <Panel title="To accept, you must do both">
        <DTable cols={["What", "Detail", "Amount|num"]} rows={[
          [<Two key="w" a="Pay the acceptance fee" b="Non-refundable. It is credited against your first session charges." />, <span className="sub2" key="d">{acc.settled ? "Confirmed" : acc.partPaid ? `${money(acc.paidTotal)} confirmed · balance of ${money(acc.balance)} outstanding after the fee was revised` : openRef ? `Reference ${openRef.reference}, expires ${when(openRef.expiresAt)}` : "Generate a reference below"}</span>, <strong className="tnum" key="a">{money(fee)}</strong>],
          [<Two key="w" a="Sign the undertaking" b="The University’s conditions of studentship" />, <span className="sub2" key="d">{a.undertakingAt ? `Signed ${when(a.undertakingAt)}` : "Signed electronically below"}</span>, <span className="sub2" key="a">&mdash;</span>],
        ]} />
      </Panel>
      {acc.partPaid ? (
        <Panel title="Acceptance fee" right="Revised after your payment">
          <PBody>
            <KvGrid cls="grid--4" pairs={[
              ["Required acceptance fee", <b key="f" className="tnum">{money(acc.feeDue)}</b>],
              ["Amount previously paid", <b key="p" className="tnum">{money(acc.paidTotal)}</b>],
              ["Outstanding balance", <b key="b" className="tnum ink-red">{money(acc.balance)}</b>],
              ["Payment status", <Pil key="s" kind="warn">PARTIALLY PAID</Pil>],
            ]} />
            <div className="sub2 mt-2">Only the balance is owed; you are never charged the full fee again. The acceptance letter is issued once it is paid.</div>
          </PBody>
        </Panel>
      ) : null}
      <Panel title="Undertaking" right="Read it before you sign">
        <PBody>
          <div className="sub2" style={{ lineHeight: 1.65 }}>I accept the offer of provisional admission on the terms stated. I declare that the particulars and results I submitted are true and complete, and I understand that the University verifies them with the examination bodies. I undertake to abide by the statutes, regulations and disciplinary code of the University, and I accept that admission obtained on a false declaration is void at any time, including after the award of a degree.</div>
          <label className="ink-muted mt-2" style={{ display: "flex", gap: 9, alignItems: "flex-start" }}>
            <input type="checkbox" className="chk" checked={agreed} disabled={!!a.undertakingAt} onChange={(e) => setAgreed(e.target.checked)} />
            <span>I have read the undertaking and I accept it.</span>
          </label>
        </PBody>
      </Panel>
      <Note kind="info" title="Accepting does not complete your admission">
        It holds your place. Admission completes after clearance and Senate approval.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <div className="row">
        {!a.undertakingAt ? (
          <Btn kind="urgent" disabled={!agreed || busy !== null} onClick={() => void act("sign", "POST", "/me/accept", { undertaking: true }, "Undertaking signed by the applicant")}>{busy === "sign" ? "Signing…" : "Sign the undertaking"}</Btn>
        ) : null}
        {owed ? (
          /* V724: the reference is for the balance — the whole fee before anything is confirmed; the server answers the open one again rather than a second */
          <Btn kind={openRef ? "ghost" : (a.undertakingAt || acc.partPaid ? "urgent" : "primary")} disabled={busy !== null} onClick={() => void act("ref", "POST", "/me/fee-references", { kind: "ACCEPTANCE" }, acc.partPaid ? "Acceptance fee balance reference generated for the applicant" : "Acceptance fee reference generated for the applicant")}>{busy === "ref" ? "Generating…" : openRef ? "Generate a new reference" : acc.partPaid ? "Pay outstanding balance" : `Generate a reference for ${money(acc.balance)}`}</Btn>
        ) : null}
        <Btn kind="ghost" disabled={busy !== null} onClick={() => { if (window.confirm("Decline this offer? Your place may then be given to someone else, and a decline is reversed only while it has not been.")) void act("decline", "POST", "/me/decline", {}, "Offer declined by the applicant"); }}>Decline this offer</Btn>
      </div>
      {openRef && owed ? (
        <Panel title="Your payment reference" right="Generated for you alone">
          <PBody>
            <div className="eyebrow">Reference</div>
            <div className="tnum b700" style={{ fontSize: "var(--t-2xl)", letterSpacing: ".5px" }}>{openRef.reference}</div>
            <div className="sub2 mt-2">{money(openRef.amount)}{acc.partPaid ? " — the balance of the acceptance fee" : ""}{openRef.expiresAt ? ` · expires ${when(openRef.expiresAt)}` : ""}. Quote this reference only.</div>
            <div className="row mt-2"><PayByCard reference={openRef.reference} amount={openRef.amount} /></div>
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
        action={done ? <LinkBtn kind="primary" href="/applicant/matric">What happens next</LinkBtn> : null}>
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
        Clearance is a document check. Report any request for money to the Registrar.
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
        <Note kind="info" title="Courses first, then matriculation">
          Pay your fees and register your courses under your <b>admission number</b>; your matriculation number is issued afterwards.
        </Note>
        <Rail a={a} />
        <div className="grid grid--2">
          <Panel title="What you carry now" right="Your admission number">
            <PBody>
              {a.admissionNo ? (
                <div className="tnum b700" style={{ fontFamily: "var(--serif)", fontSize: "clamp(19px,4vw,26px)", letterSpacing: ".6px" }}>{a.admissionNo}</div>
              ) : (
                <div className="sub2"><b>Not issued yet.</b></div>
              )}
              <p className="sub2 m-0">It identifies you for fees and course registration until you are matriculated.</p>
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
              <p className="sub2 m-0">It never changes.</p>
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

      </>
    );
  }
  return (
    <>
      <div className="card" style={{ borderTop: "4px solid var(--green)" }}>
        <PBody>
          <div className="row">
            <div style={{ width: 26, height: 26, borderRadius: "var(--r-pill)", background: "var(--green)", display: "flex", alignItems: "center", justifyContent: "center" }}><Tick size={14} colour="var(--surface)" /></div>
            <span className="eyebrow ink-green">Matriculation number issued</span>
          </div>
          <div className="tnum b700" style={{ fontFamily: "var(--serif)", fontSize: "clamp(24px,5vw,34px)", letterSpacing: "1px" }}>{a.matricNo}</div>
          <div className="sub2">{a.name} &middot; {a.programme} &middot; {a.entryLevel} Level</div>
          <div className="hr" />
          <div className="sub2">Quote it in all correspondence. It never changes.</div>
        </PBody>
      </div>
      <Note kind="ok" title="Your application account is now your student account">
        Your application number {a.applicationNo} and admission number {a.admissionNo} stay on your record.
      </Note>
      <Note kind="info" title="You are admitted provisionally until your results are verified">
        Verification with WAEC, NECO and JAMB is completed in your first session; admission on a result that does not verify is void at any point.
      </Note>
    </>
  );
}
