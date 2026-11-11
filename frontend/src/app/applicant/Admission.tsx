"use client";

/** The applicant's admission, in one place (V269, V295). Until an offer is read, Admission Status Checking: every applicant whose
 *  Post-UTME application is paid for and submitted pays the admission checking fee once, while the Director of ICT has checking
 *  open, and checks — admitted, not admitted or not yet decided alike; each check is kept with what it returned. Once an offer is
 *  read: the congratulations and the official details, where they stand, what comes next, the acceptance fee paid once for the
 *  admission, and the tracker of the steps that concern them. Since V724: an acceptance fee revised after part of it was paid is
 *  owed as its balance, never the full fee again, and the letter waits for it; the admitted applicant's school fees are read and
 *  paid here, on their own dashboard, and the student portal opens once the fee gate is cleared — never merely on admission. */
import { useEffect, useRef, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { money } from "@/lib/format";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tick } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ACCEPTANCE_BALANCE_PENDING, CHECKING_GATE, SCHOOL_FEE_STATUSES, STATUS_KIND, acceptanceFigures, dayOf, gateClearsWord, parseTracker, schoolFeeChoices, stepHref, whenAt, type Admission, type SchoolFees, type StatusChecking, type TrackerStep } from "@/lib/screening";
import { AdmissionDocumentsCentre, useAdmissionDocuments } from "@/components/AdmissionDocumentsCentre";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { PayByCard, when } from "./common";

const ADMISSION = "/api/bff/api/v1/applicant/me/admission";
const SCHOOL_FEES = "/api/bff/api/v1/applicant/me/school-fees";
type Read = { ok: true; d: Admission } | { ok: false; problem: Problem };
const problemOf = (j: unknown, r: Response): Problem => (j && typeof j === "object" && "status" in (j as object) ? (j as Problem) : { status: r.status, title: r.statusText || "Not now" });

async function readAdmission(): Promise<Read> {
  const r = await fetch(ADMISSION, { cache: "no-store" });
  const j = await r.json().catch(() => null);
  return r.ok ? { ok: true, d: j as Admission } : { ok: false, problem: (j as Problem) ?? { status: r.status, title: r.statusText } };
}

/** the check itself (V271, V295): the server refuses it unless Admission Status Checking allows it — a valid application, checking
 *  open, the checking fee confirmed — and keeps it, each time, with the status it returned */
async function checkStatus(): Promise<Read> {
  const r = await fetch(`${ADMISSION}/checked`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Admission status checked") }, body: "{}" });
  const j = await r.json().catch(() => null);
  return r.ok ? { ok: true, d: j as Admission } : { ok: false, problem: (j as Problem) ?? { status: r.status, title: r.statusText } };
}

/** the admission as the applicant reads it. Opening a full page (`check`) is a check of the status wherever Admission Status
 *  Checking allows one, and only then; the dashboard and the other pages only read */
export function useAdmission(check = false) {
  const [d, setD] = useState<Admission | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  // V724: read again after a payment made on this page (the acceptance fee's balance, the school fees), without a check
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let live = true;
    void (async () => {
      try {
        const first = await readAdmission();
        if (!live) return;
        if (!first.ok) { setProblem(first.problem); return; }
        const c = first.d.checking;
        if (check && tick === 0 && c?.mayCheck && !c.past) {
          const done = await checkStatus();
          if (!live) return;
          if (done.ok) { setD(done.d); return; }
          notifyProblem(done.problem);
        }
        setD(first.d);
      } catch {
        if (live) setProblem({ status: 0, title: "Could not read your admission." });
      }
    })();
    return () => { live = false; };
  }, [check, tick]);
  /** check again — pending today, decided later — without paying again */
  async function again() {
    setBusy(true);
    try {
      const done = await checkStatus();
      if (done.ok) { setD(done.d); notify("Admission status checked"); } else notifyProblem(done.problem);
    } finally { setBusy(false); }
  }
  const reload = () => setTick((t) => t + 1);
  return { d, problem, again, busy, reload };
}

/** V724: the admitted applicant's school fees as GET /applicant/me/school-fees reads them for the application's session — read when the
 *  acceptance is behind them, and again after a reference is drawn or a payment verified */
function useSchoolFees(wanted: boolean, tick: number) {
  const [f, setF] = useState<SchoolFees | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [n, setN] = useState(0);
  useEffect(() => {
    if (!wanted) return;
    let live = true;
    void (async () => {
      try {
        const r = await fetch(SCHOOL_FEES, { cache: "no-store" });
        const j = await r.json().catch(() => null);
        if (!live) return;
        if (!r.ok) { setProblem(problemOf(j, r)); return; }
        setProblem(null);
        setF(j as SchoolFees);
      } catch {
        if (live) setProblem({ status: 0, title: "Could not read your school fees." });
      }
    })();
    return () => { live = false; };
  }, [wanted, tick, n]);
  return { f, problem, reload: () => setN((x) => x + 1) };
}

/** V724: on return from the gateway (…/applicant/admission?paid=<reference>) the reference is verified with the gateway and confirmed
 *  at once, as the accept and fees pages do on the server — no wait for a webhook; then the admission and the fees are read again */
function usePaidReturn(onVerified: () => void) {
  const [reference] = useState<string | null>(() => (typeof window === "undefined" ? null : new URLSearchParams(window.location.search).get("paid")));
  const [verifying, setVerifying] = useState(!!reference);
  // the latest callback, read when the verification settles: the verifying effect runs once for the reference, not for every render
  const after = useRef(onVerified);
  useEffect(() => { after.current = onVerified; });
  useEffect(() => {
    if (!reference) return;
    let live = true;
    void (async () => {
      try {
        await fetch("/api/bff/api/v1/payments/verify", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Verify payment ${reference}`) }, body: JSON.stringify({ reference }) });
      } catch { /* the webhook or the next read confirms it */ }
      if (!live) return;
      setVerifying(false);
      after.current();
      try { window.history.replaceState(null, "", window.location.pathname + window.location.hash); } catch { /* the address stays */ }
    })();
    return () => { live = false; };
  }, [reference]);
  return { reference, verifying };
}

export function Tracker({ steps, compact }: { steps: TrackerStep[]; compact?: boolean }) {
  if (!steps.length) return null;
  return (
    <ol className={`plain ${compact ? "row row--tight" : "stack"}`} style={compact ? { flexWrap: "wrap", gap: 10 } : undefined}>
      {steps.map((s) => (
        <li key={s.key} className="row row--tight" style={{ gap: 8, alignItems: "center" }}>
          <span className="tnum b700" style={{ color: s.state === "done" ? "var(--green-ink)" : s.state === "failed" ? "var(--red-ink)" : s.state === "now" ? "var(--chrome)" : "var(--faint)" }}>
            {s.state === "done" ? "✓" : s.state === "failed" ? "✕" : s.state === "now" ? "→" : "○"}
          </span>
          <span className={s.state === "todo" ? "sub2" : s.state === "now" ? "b600" : ""}>{s.label}</span>
        </li>
      ))}
    </ol>
  );
}

export { stepHref } from "@/lib/screening";

/** the five screening forms print once the applicant has filled and submitted them (V273): not before the form is submitted */
function formsPrintable(d: Admission): boolean {
  return !!d.screeningRequired && ![...CHECKING_GATE, "PENDING", "NOT_ADMITTED", "DECLINED", "LAPSED", "ADMITTED", "ACCEPTANCE_PENDING", "SCREENING_PENDING", "SCREENING_IN_REVIEW", "SCREENING_CORRECTION", "SCREENING_IN_PROGRESS", "SCREENING_SUBMITTED", "SCREENING_RETURNED", "CHANGE_OF_PROGRAMME_REQUIRED", "CHANGE_OF_PROGRAMME_PENDING"].includes(d.status);
}

/** an offer the applicant has read, or may read now: the admission under way rather than Admission Status Checking (V295) */
function offerRead(d: Admission): boolean {
  const o = d.offer;
  return !!o && o.decision === "OFFERED" && !!o.decision_released_at && (!d.checking || d.checking.decisionVisible);
}

const feeWord = (c: StatusChecking) => (c.fee == null ? "Not stated yet" : c.feeRequired ? money(Number(c.fee)) : "Not charged this session");

/** the dashboard's Admission Status section: always there — checking closed, open and not paid for, paid for and ready to check —
 *  and, once an offer is read, the admission under way: status, next step, tracker */
export function AdmissionProgress() {
  const { d } = useAdmission();
  if (!d) return null;
  if (d.checking && !d.checking.past) return <CheckingSection d={d} c={d.checking} />;
  if (!d.offer || d.offer.decision !== "OFFERED") return null;
  const acc = acceptanceFigures(d.entitlement);
  const fees = d.status.startsWith("SCHOOL_FEES");
  // V724: the acceptance fee's balance before everything that follows — its note below carries the one button (the Accept page)
  const balanceFirst = d.status === ACCEPTANCE_BALANCE_PENDING;
  return (
    <Panel title="Your admission" right={<Pil kind={STATUS_KIND(d.status) === "ok" ? "ok" : STATUS_KIND(d.status) === "bad" ? "bad" : balanceFirst || (fees && d.status !== "SCHOOL_FEES_PART_PAID") ? "warn" : "info"}>{d.label}</Pil>}>
      <PBody>
        <div className="row row--between">
          <span><b>{d.offer.changed_to ?? d.offer.programme}</b><div className="sub2">{d.offer.faculty ? `Faculty of ${d.offer.faculty}` : ""}{d.offer.department ? ` · ${d.offer.department}` : ""} · {d.offer.session}</div></span>
          {d.next_action && !(balanceFirst && acc.partPaid) ? <LinkBtn kind="primary" href={stepHref(d.next_href)}>{d.next_action}</LinkBtn> : null}
        </div>
        {/* V724: the acceptance fee revised after part of it was paid — the balance, owed once, is paid on the Accept page */}
        {acc.partPaid ? (
          <div className="mt-2">
            <Note kind="bad" title={`Acceptance fee balance of ${money(acc.balance)} to pay`} action={<LinkBtn kind="urgent" href="/applicant/accept">Pay outstanding balance</LinkBtn>}>
              Required acceptance fee <b className="tnum">{money(acc.feeDue)}</b> · amount previously paid <b className="tnum">{money(acc.paidTotal)}</b> · outstanding balance <b className="tnum">{money(acc.balance)}</b> · <Pil kind="warn">PARTIALLY PAID</Pil>. Only the balance is owed, never the full fee again; the acceptance letter is issued once it is paid.
            </Note>
          </div>
        ) : null}
        {/* V724: the school fees are read, and paid, here on the applicant dashboard; the student portal opens once the fee gate is cleared */}
        {fees && d.detail ? <div className="sub2 mt-2">{d.detail}</div> : null}
        <div className="mt-2"><Tracker steps={parseTracker(d.tracker)} compact /></div>
        <div className="mt-1 row row--inline row--tight"><LinkBtn kind="ghost" size="sm" href="/applicant/admission">Admission progress</LinkBtn><LinkBtn kind="ghost" size="sm" href="/applicant/admission#documents">My documents</LinkBtn>{formsPrintable(d) ? <a className="btn btn--secondary btn--sm" href="/applicant/clearance/print" target="_blank" rel="noopener">Print your screening forms</a> : null}</div>
      </PBody>
    </Panel>
  );
}

/** Admission Status Checking on the dashboard (V295): what the applicant may do now, never what the decision is — the result is
 *  read on the Admission Status page, where reading it is a check kept on the record */
function CheckingSection({ d, c }: { d: Admission; c: StatusChecking }) {
  const last = d.checks?.[0];
  const [word, kind]: [string, "grey" | "warn" | "ok"] = !c.applicationValid ? ["NOT AVAILABLE YET", "grey"] : !c.windowOpen ? ["CLOSED", "grey"] : c.mayPay ? ["OPEN · FEE NOT PAID", "warn"] : ["OPEN · READY TO CHECK", "ok"];
  return (
    <Panel title="Admission status" right={<Pil kind={kind}>{word}</Pil>}>
      <PBody>
        {!c.applicationValid ? (
          <div className="row row--between">
            <span><span className="b600">Admission Status Checking opens to you once your Post-UTME application is complete.</span><div className="sub2">{d.detail ?? "The application fee confirmed and the application submitted."}</div></span>
            {d.next_action && d.next_href ? <LinkBtn kind="primary" href={d.next_href}>{d.next_action}</LinkBtn> : null}
          </div>
        ) : !c.windowOpen ? (
          <>
            <div className="b600">Admission Status Checking is currently closed.</div>
            <div className="sub2">
              {c.windowState === "SCHEDULED" && c.opensAt ? `It opens ${whenAt(c.opensAt)}.`
                : d.offer?.entry_mode === "CCE" ? "It opens when the Centre for Continuing Education publishes the outcome of your application; you are told by email and SMS."
                : "Please check back later: you are told by email and SMS the moment the University opens it."}
              {c.paid ? " Your admission checking fee is paid; you will not pay it again." : ""}
              {last ? ` Your last check, ${whenAt(last.checked_at)}: ${last.label}.` : ""}
            </div>
          </>
        ) : c.mayPay ? (
          <div className="row row--between">
            <KvGrid cls="grid--2" pairs={[["Admission checking fee", <b key="f" className="tnum">{feeWord(c)}</b>], ["Payment status", <Pil key="p" kind="warn">NOT PAID</Pil>]]} />
            <LinkBtn kind="primary" href="/applicant/status">Pay now</LinkBtn>
          </div>
        ) : (
          <div className="row row--between">
            <KvGrid cls="grid--3" pairs={[
              ["Admission checking fee", <b key="f" className="tnum">{feeWord(c)}</b>],
              ["Payment status", c.feeRequired ? <Pil key="p" kind="ok">PAID ✓</Pil> : <span key="p" className="sub2">Nothing to pay</span>],
              ["Last checked", last ? <span key="l">{last.label}<div className="sub2 tnum">{whenAt(last.checked_at)}</div></span> : <span key="l" className="sub2">Not yet</span>],
            ]} />
            <LinkBtn kind="primary" href="/applicant/status">{last ? "Check again" : "Check status"}</LinkBtn>
          </div>
        )}
      </PBody>
    </Panel>
  );
}

/** the Admission Status page's own view until an offer is read (V295): the check is made on opening, where it may be; when it
 *  reveals an offer the server page is read again, so the offer and the acceptance show in full */
export function AdmissionStatusCheck() {
  const router = useRouter();
  const { d, problem, again, busy } = useAdmission(true);
  const read = !!d && offerRead(d);
  useEffect(() => { if (read) router.refresh(); }, [read, router]);
  if (problem) return <Note kind="bad" title="Your admission status">{problem.title}</Note>;
  if (!d) return <Panel title="Admission status"><PBody><div className="sub2">Reading…</div></PBody></Panel>;
  if (read) {
    return (
      <Note kind="ok" title="Congratulations! You have been offered admission" action={<LinkBtn kind="primary" href="/applicant/admission">Continue to acceptance</LinkBtn>}>
        Opening your offer — programme, faculty, department — and the acceptance that follows…
      </Note>
    );
  }
  return <CheckingView d={d} again={() => void again()} busy={busy} />;
}

/** the full page */
export function AdmissionPage() {
  const { d, problem, again, busy, reload } = useAdmission(true);
  const docs = useAdmissionDocuments("/api/bff/api/v1/applicant/me/documents-centre");
  // the handover to the student portal sends the applicant back here when it is refused, naming the rule (V278, V282)
  const [refused] = useState<{ code: string; why: string } | null>(() => {
    if (typeof window === "undefined") return null;
    const q = new URLSearchParams(window.location.search);
    const code = q.get("portal");
    return code ? { code, why: q.get("why") ?? "" } : null;
  });
  // V724: the school fees paid here come back from the gateway to this page: verified on arrival, then everything read again
  const [feesTick, setFeesTick] = useState(0);
  const paidReturn = usePaidReturn(() => { reload(); setFeesTick((t) => t + 1); });
  const wantFees = !!d && offerRead(d) && SCHOOL_FEE_STATUSES.includes(d.status);
  const fees = useSchoolFees(wantFees, feesTick);
  if (problem) return <Note kind="bad" title="Your admission">{problem.title}</Note>;
  if (!d) return <Panel title="Your admission"><PBody><div className="sub2">Reading…</div></PBody></Panel>;
  const o = d.offer;
  const steps = parseTracker(d.tracker);
  if (!offerRead(d)) return <CheckingView d={d} again={() => void again()} busy={busy} />;
  const kind = STATUS_KIND(d.status);
  const acc = acceptanceFigures(d.entitlement);
  // V724: the hand-off to the student portal is offered only where the status sends the applicant there (the fee gate off, or cleared);
  // ACCEPTANCE_BALANCE_PENDING sends them to the Accept page (/applicant/accept), a plain link
  const handoff = /^\/student(\/|$)/.test(d.next_href ?? "");
  const schoolFeeStatus = d.status.startsWith("SCHOOL_FEES");
  const balanceFirst = d.status === ACCEPTANCE_BALANCE_PENDING;
  // V724: headings once — the school fees panel says a school-fee status in full (the figures, the window, where the portal stands, the
  // Bursary's exception in its words), and the balance block says the acceptance balance: the Next step note is not said over them
  const feesPanel = wantFees && schoolFeeStatus && !fees.problem;
  const nextStepSaid = feesPanel || (balanceFirst && acc.partPaid);
  // V724: the school fees row's word — the first semester paid only when the school fees say so; otherwise the server's label
  const clearedWord = fees.f?.firstSemesterCleared ? "FIRST SEMESTER PAID" : d.label;
  const scheduled = fees.f ? fees.f.windowState === "SCHEDULED" : !/closed/i.test(d.label);
  return (
    <>
      {refused ? (
        refused.code === "STUDENT_PORTAL_HELD_FEES" ? (
          /* V724: the student portal's fee gate — the school fees are paid here, and the portal opens when the payment is verified */
          <Note kind="info" title="The student portal opens once your school fees are paid and verified" action={<LinkBtn kind="primary" href="#fees">Pay school fees</LinkBtn>}>
            {refused.why || `Pay your ${o.session} school fees here, on your applicant dashboard; the student portal opens when the payment is verified.`}
          </Note>
        ) : refused.code === "STUDENT_PORTAL_ACCEPTANCE_BALANCE" ? (
          /* V724: the acceptance fee revised after part of it was paid — the balance comes before the school fees and the portal */
          <Note kind="bad" title="The student portal opens once the acceptance fee balance is paid" action={<LinkBtn kind="urgent" href={acc.partPaid ? "#acceptance-balance" : "/applicant/accept"}>Pay outstanding balance</LinkBtn>}>
            {refused.why || `The acceptance fee for ${o.session} was revised after your payment. Pay the outstanding balance${acc.partPaid ? ` of ${money(acc.balance)}` : ""} here; your school fees, and then the student portal, follow it.`}
          </Note>
        ) : refused.code === "STUDENT_PORTAL_FEES_NOT_AVAILABLE" ? (
          <Note kind="info" title={`${o.session} school fees not yet available`}>
            {refused.why || `The University has not yet published the school fees for your session; the student portal opens once they are stated and paid. Check here for updates.`}
          </Note>
        ) : (
          <Note kind="bad" title="The student portal could not be opened">
            {refused.code === "AUTH_NOT_ON_REGISTER" ? "You are not yet on the student register; the portal opens the moment your screening is successful (or on acceptance where your session needs no screening). Everything until then is here." : refused.why || `The crossing was refused (${refused.code}). Try again; if it persists, write to the Directorate of ICT quoting this code.`}
          </Note>
        )
      ) : null}
      {paidReturn.reference && paidReturn.verifying ? <Note kind="info" title="Confirming your payment">Reference <span className="tnum">{paidReturn.reference}</span> is being verified with the gateway…</Note> : null}
      <div className="card" style={{ borderTop: "4px solid var(--green)" }}>
        <PBody>
          <div className="row" style={{ gap: 10 }}>
            <div style={{ width: 26, height: 26, borderRadius: "var(--r-pill)", background: "var(--green)", display: "flex", alignItems: "center", justifyContent: "center" }}><Tick size={14} colour="var(--surface)" /></div>
            <span className="eyebrow ink-green">Congratulations</span>
          </div>
          <div className="phead__t" style={{ fontFamily: "var(--serif)", fontSize: "var(--t-2xl)" }}>You have been offered admission to Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
          <div className="sub2">Offer of provisional admission released {whenAt(o.decision_released_at)}{o.changed_to ? ` · programme changed to ${o.changed_to} on approval` : ""}</div>
          <div className="hr" />
          <KvGrid cls="grid--3" pairs={[
            ["Name", `${o.surname}, ${o.other_names}`], ["JAMB registration number", <span key="j" className="tnum">{o.jamb_reg_no}</span>], ["Application number", <span key="a" className="tnum">{o.application_no}</span>],
            ["Admission session", o.session], ["Faculty", o.faculty ?? "—"], ["Department", o.department ?? "—"],
            ["Programme", <b key="p">{o.changed_to ?? o.programme}</b>], ["Degree / programme type", o.degree_type ?? "—"], ["Admission type", `${o.entry_mode.replace("_", " ")} · ${o.entry_level} Level${o.decision_basis ? ` · ${o.decision_basis}` : ""}`],
            ["Admission status", <Pil key="s" kind={kind === "ok" ? "ok" : kind === "bad" ? "bad" : "info"}>{d.label}</Pil>], ["Admission number", <span key="n" className="tnum">{o.admission_no ?? "Issued when you are brought onto the register"}</span>],
            ["Matriculation number", <span key="m" className="tnum">{o.matric_no ?? "Issued after registration"}</span>],
          ]} />
        </PBody>
      </div>

      {nextStepSaid ? null : (
        <Note kind={kind} title={d.next_action ? `Next step: ${d.next_action}` : d.label} action={d.next_action && d.next_href ? <LinkBtn kind={kind === "bad" ? "urgent" : "primary"} href={stepHref(d.next_href)}>{d.next_action}</LinkBtn> : null}>
          {d.detail ?? ""}
          {/* V724: the hand-off line only where the status sends the applicant to the student portal — the fee gate off, or the fees paid */}
          {(schoolFeeStatus && handoff) || d.status === "COURSE_REGISTRATION_PENDING" ? <span className="blk">Your admission number{o.admission_no ? ` ${o.admission_no}` : ""} is your sign-in on the student portal, with the password you chose as an applicant. From here, <a className="lnk" href={stepHref(d.next_href ?? "/student/fees")}>continue to the student portal</a> without signing in again.</span> : null}
        </Note>
      )}

      {/* V724: the acceptance fee revised after part of it was paid — the balance, owed once, drawn and paid here as on the Accept page */}
      {acc.partPaid ? <AcceptanceBalance d={d} onDrawn={reload} /> : null}

      <div className="grid grid--2">
        <Panel title="Progress tracker" right={`${steps.filter((s) => s.state === "done").length} of ${steps.length} done`}>
          <PBody><Tracker steps={steps} /></PBody>
        </Panel>
        <Panel title="Acceptance and screening" right="Acceptance fee is paid once, for the admission">
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              /* V724: the amount only where something was paid through a reference — an acceptance confirmed by hand reads PAID, never "PAID · ₦0" */
              ["Acceptance fee", acc.settled ? <span key="e"><Pil kind="ok">PAID</Pil> <span className="sub2 tnum">{[d.entitlement.reference, d.entitlement.confirmed_at ? dayOf(d.entitlement.confirmed_at) : null, acc.paidTotal > 0 ? money(acc.paidTotal) : null].filter(Boolean).join(" · ")}</span></span>
                : acc.partPaid ? <span key="e"><Pil kind="warn">PARTIALLY PAID</Pil> <span className="sub2 tnum">{money(acc.paidTotal)} of {money(acc.feeDue)} paid · balance {money(acc.balance)}</span><div className="mt-1"><LinkBtn kind="urgent" size="sm" href="#acceptance-balance">Pay outstanding balance</LinkBtn></div></span>
                : <Pil key="e" kind="warn">NOT YET PAID</Pil>],
              /* V724: the letter is issued once the acceptance fee is settled — paid in full after any revision of the fee */
              /* V724: the letter waits for a balance owed after a revision of the fee alone (the part-paid truth), as the server's letter does */
              ["Acceptance letter", o.accepted_at && !acc.partPaid ? <a key="l" className="lnk" href="/applicant/status/letter" target="_blank" rel="noopener">Available · view and print</a>
                : acc.partPaid ? <span key="l" className="sub2">After the acceptance fee balance of {money(acc.balance)} · <a className="lnk" href="/applicant/accept">pay it</a></span>
                : <span key="l" className="sub2">After acceptance</span>],
              ["University screening", !d.screeningRequired ? <span key="s" className="sub2">Not required for your session</span> : o.cleared_at ? <Pil key="s" kind="ok">SUCCESSFUL</Pil> : <LinkBtn key="s" kind="secondary" size="sm" href="/applicant/clearance">Screening status</LinkBtn>],
              ["Change of programme", o.changed_to ? <span key="c">{o.changed_from} → <b>{o.changed_to}</b><div className="sub2">Your acceptance payment remained valid; it was not charged again.</div></span> : <span key="c" className="sub2">None</span>],
              ["School fees", balanceFirst ? <span key="f" className="sub2">After the acceptance fee balance</span>
                : d.status === "SCHOOL_FEES_NOT_AVAILABLE" ? <span key="f"><Pil kind="warn">NOT YET AVAILABLE</Pil> <a className="lnk sub2" href="#fees">details</a></span>
                : d.status === "SCHOOL_FEES_NOT_OPEN" ? <span key="f"><Pil kind="info">{scheduled ? "PAYMENT NOT YET OPEN" : "PAYMENT CLOSED FOR NOW"}</Pil> <a className="lnk sub2" href="#fees">details</a></span>
                : d.status === "SCHOOL_FEES_PART_PAID" ? <span key="f"><Pil kind="warn">{clearedWord}</Pil> <LinkBtn kind="primary" size="sm" href={stepHref(d.next_href ?? "#fees")}>Pay the balance</LinkBtn></span>
                : d.status === "SCHOOL_FEES_PENDING" && fees.f?.portalState === "EXCEPTION" ? <span key="f"><Pil kind="info">{clearedWord}</Pil> <LinkBtn kind="primary" size="sm" href={stepHref(d.next_href ?? "#fees")}>Pay school fees</LinkBtn></span>
                : d.status === "SCHOOL_FEES_PENDING" ? <LinkBtn key="f" kind="primary" size="sm" href={stepHref(d.next_href ?? "#fees")}>Pay school fees</LinkBtn>
                : ["COURSE_REGISTRATION_PENDING", "MATRICULATION_PENDING", "MATRICULATED"].includes(d.status) ? <Pil key="f" kind="ok">PAID</Pil> : <span key="f" className="sub2">After successful screening</span>],
            ]} />
            {acc.partPaid ? <div className="sub2 mt-2">The acceptance fee was revised after your payment; only the balance is owed, never the full fee again. The acceptance letter is issued once the balance is paid.</div>
              : d.entitlement.paid ? <div className="sub2 mt-2">The acceptance fee is never charged twice.</div> : null}
          </PBody>
        </Panel>
      </div>

      {/* V724: the school fees panel — the register, the fees as stated (or not yet), the payment made here, and the student portal's gate */}
      {wantFees ? <SchoolFeesPanel d={d} f={fees.f} problem={fees.problem} reload={() => { fees.reload(); reload(); }} /> : null}

      <div id="documents">
        {docs ? <AdmissionDocumentsCentre rows={docs} side="applicant" /> : <Panel title="Admission & screening documents"><PBody><div className="sub2">Reading your documents…</div></PBody></Panel>}
      </div>
    </>
  );
}

/** V724: the acceptance fee revised after part of it was paid, on the Admission page: the figures from the entitlement alone (the fee
 *  stated now, what is confirmed, the balance), the one button that draws the reference for the balance — the same POST as the Accept
 *  page, kind ACCEPTANCE: the server answers what is owed now, and the open one again rather than a second — and the card checkout
 *  for that amount; the gateway returns the payer to the Accept page, which verifies the reference on arrival */
function AcceptanceBalance({ d, onDrawn }: { d: Admission; onDrawn: () => void }) {
  const acc = acceptanceFigures(d.entitlement);
  const e = d.entitlement;
  const [made, setMade] = useState<{ reference: string; amount: number; expiresAt: string | null } | null>(null);
  const [busy, setBusy] = useState(false);
  const open = e.open_reference ? { reference: e.open_reference, amount: Number(e.open_amount ?? acc.balance), expiresAt: e.open_expires_at ?? null } : made;
  async function draw() {
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/applicant/me/fee-references", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Acceptance fee balance reference generated for the applicant") }, body: JSON.stringify({ kind: "ACCEPTANCE" }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(problemOf(j, r)); return; }
      const v = j as { reference: string; feeReferences?: { reference: string; amount: number | string; expiresAt: string }[] };
      const row = v.feeReferences?.find((x) => x.reference === v.reference);
      setMade({ reference: String(v.reference), amount: row ? Number(row.amount) : acc.balance, expiresAt: row?.expiresAt ?? null });
      notify("Reference generated for the acceptance fee balance");
      onDrawn();
    } finally { setBusy(false); }
  }
  return (
    <div id="acceptance-balance">
      <Note kind="bad" title={`Acceptance fee balance of ${money(acc.balance)} to pay`} action={open ? null : <Btn kind="urgent" disabled={busy} onClick={() => void draw()}>{busy ? "Generating…" : "Pay outstanding balance"}</Btn>}>
        The acceptance fee for {d.offer.session} was revised to {money(acc.feeDue)} after you paid {money(acc.paidTotal)}. Your place is held; only the balance of {money(acc.balance)} is owed — you are never charged the full fee again. The acceptance letter is issued once the balance is paid.
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
              <Btn kind="urgent" disabled={busy} onClick={() => void draw()}>{busy ? "Generating…" : "Pay outstanding balance"}</Btn>
            </div>
          )}
        </PBody>
      </Panel>
    </div>
  );
}

const num = (v: number | string | null | undefined) => (v == null ? 0 : Number(v));

/** V724: the admitted applicant's school fees, on their own dashboard (id="fees": the status's next_href lands here). Off the register:
 *  what opens them. On it: not yet stated (the University's words, no pay button — nothing is charged at a guess), the payment window
 *  not yet open, payable (the first semester or the whole balance, as the student fees page offers them; the reference is the
 *  student's, drawn through POST …/school-fees/references and paid by card as the acceptance fee is), a reference awaiting the bank,
 *  or paid — and where the student portal's fee gate leaves them: the hand-off once cleared, the words while held. An acceptance fee
 *  balance still owed (HELD_ACCEPTANCE_BALANCE) comes first: it is said, with the way to the Accept page, and nothing of the school
 *  fees is offered for payment until it is paid. */
function SchoolFeesPanel({ d, f, problem, reload }: { d: Admission; f: SchoolFees | null; problem: Problem | null; reload: () => void }) {
  const o = d.offer;
  const acc = acceptanceFigures(d.entitlement);
  const [sel, setSel] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [made, setMade] = useState<{ reference: string; amount: number; expiresAt: string | null } | null>(null);
  const session = f?.session ?? o.session;
  const register = (
    <KvGrid cls="grid--3" pairs={[
      ["Admission number", <span key="n" className="tnum">{f?.admissionNo ?? o.admission_no ?? "Issued when you are brought onto the register"}</span>],
      ["Login username", <span key="u" className="tnum">{o.matric_no ?? f?.admissionNo ?? o.admission_no ?? o.jamb_reg_no}</span>],
      ["Password", <span key="w" className="sub2">The one you chose as an applicant; it does not change when your matriculation number becomes your username</span>],
    ]} />
  );
  if (problem) {
    return (
      <div id="fees"><Panel title="School fees" right={session}><PBody><Note kind="bad" title={problem.title ?? "Could not read your school fees"}>{problem.detail ?? ""}{problem.remedy ? <span className="sub2"> {problem.remedy.message}</span> : null}</Note></PBody></Panel></div>
    );
  }
  if (!f) return <div id="fees"><Panel title="School fees" right={session}><PBody><div className="sub2">Reading your school fees…</div></PBody></Panel></div>;
  if (!f.onRegister || f.state === "REGISTER_PENDING") {
    return (
      <div id="fees">
        <Panel title="School fees" right={session}>
          <PBody>
            <Note kind="info" title="School fees open once you are on the register under your admission number">The Registry brings you onto the register; your admission number is issued then, and your {session} school fees are read and paid here.</Note>
          </PBody>
        </Panel>
      </div>
    );
  }
  async function draw(amount: number) {
    setBusy(true);
    try {
      const r = await fetch(`${SCHOOL_FEES}/references`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`School fees reference generated by the applicant for ${session}`) }, body: JSON.stringify({ amount }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(problemOf(j, r)); return; }
      const v = j as { reference: string; amount?: number | string; expiresAt?: string | null };
      setMade({ reference: String(v.reference), amount: v.amount != null ? Number(v.amount) : amount, expiresAt: v.expiresAt ?? null });
      notify(`Reference generated for ${money(amount)}`);
      reload();
    } finally { setBusy(false); }
  }
  const gateWord = gateClearsWord(f.gate?.clearsOn);
  const portalOpen = f.portalState === "CLEARED" || f.portalState === "EXCEPTION" || f.portalState === "OPEN";
  // V724: the acceptance fee's balance before the school fees — where the gate reads it (HELD_ACCEPTANCE_BALANCE) or the GET says it is owed
  const balanceFirst = f.portalState === "HELD_ACCEPTANCE_BALANCE" || f.acceptanceBalanceDue === true;
  const acceptanceBalance = num(f.acceptanceBalance) > 0 ? num(f.acceptanceBalance) : acc.balance;
  const portal: [string, ReactNode] = ["Student portal",
    portalOpen && !balanceFirst
      ? <span key="p"><Pil kind="ok">OPEN TO YOU</Pil> <LinkBtn kind="primary" size="sm" href={stepHref("/student")}>Continue to the student portal</LinkBtn></span>
      : balanceFirst
        ? <span key="p" className="sub2">Opens once the acceptance fee balance is paid, and then {gateWord} paid and verified</span>
      : f.portalState === "HELD_FEES_NOT_AVAILABLE"
        ? <span key="p" className="sub2">Opens once the {session} school fees are stated by the University and paid; check here for updates</span>
        : <span key="p" className="sub2">The Student Portal opens once {gateWord} paid and verified</span>];
  // where the portal stands, in a sentence: open to the student already (the gate cleared, the Bursary's exception, or no gate), or after the payment
  const portalWord = portalOpen ? "The Student Portal is open to you; the fees may be paid here or there." : `The Student Portal opens once ${gateWord} paid and verified.`;
  const open = f.openReference ? { reference: f.openReference, amount: num(f.openAmount), expiresAt: f.openExpiresAt ?? null } : made;
  const figures: [string, ReactNode][] = [
    ["Total due", <b key="d" className="tnum">{money(num(f.due))}</b>],
    ["First semester", <b key="1" className="tnum">{money(num(f.dueFirstSemester))}</b>],
    ["Paid", <b key="p" className="tnum">{money(num(f.paid))}</b>],
    ["Balance", <b key="b" className={`tnum${num(f.balance) > 0 ? " ink-red" : ""}`}>{money(num(f.balance))}</b>],
  ];
  // V724: the Bursary let the student into the portal before the fees are paid — said in the server's words (the Next step note is not
  // repeated over this panel)
  const exception = f.portalState === "EXCEPTION" && d.status.startsWith("SCHOOL_FEES")
    ? <div className="mt-2"><Note kind="info" title={d.label}>{d.detail ?? ""}</Note></div> : null;
  if (balanceFirst) {
    return (
      <div id="fees">
        <Panel title="School fees" right={session}>
          <PBody>
            <Note kind="bad" title={`Pay the acceptance fee balance of ${money(acceptanceBalance)} first`} action={<LinkBtn kind="urgent" href="/applicant/accept">Pay outstanding balance</LinkBtn>}>
              The acceptance fee was revised after your payment; its balance comes before your {session} school fees and the Student Portal. Your school fees are paid here once the balance is paid.
            </Note>
            {f.state !== "NOT_CONFIGURED" ? <div className="mt-2"><KvGrid cls="grid--4" pairs={figures} /></div> : null}
            <div className="mt-2">{register}</div>
            <div className="mt-2"><KvGrid cls="grid--2" pairs={[["School fees", <Pil key="f" kind="grey">AFTER THE ACCEPTANCE BALANCE</Pil>], portal]} /></div>
          </PBody>
        </Panel>
      </div>
    );
  }
  if (f.state === "NOT_CONFIGURED") {
    return (
      <div id="fees">
        <Panel title={`${session} school fees not yet available`} right={<Pil kind="warn">NOT YET AVAILABLE</Pil>}>
          <PBody>
            {/* V724: "completed successfully" only of an acceptance fee settled; a balance owed is said as such */}
            {acc.partPaid ? (
              <Note kind="bad" title={`Acceptance fee balance of ${money(acc.balance)} to pay`} action={<LinkBtn kind="urgent" href="/applicant/accept">Pay outstanding balance</LinkBtn>}>
                The acceptance fee was revised after your payment; pay its balance. The University has not yet published the approved school fees for the {session} academic session; check your Applicant Dashboard for updates.
              </Note>
            ) : (
              <div>{acc.settled ? "Your acceptance fee payment has been completed successfully. However, the" : "The"} University has not yet published the approved school fees for the {session} academic session. Please check your Applicant Dashboard for updates.{portalOpen ? "" : " You will be able to complete your school fee payment here before gaining access to the Student Portal."}</div>
            )}
            {exception}
            <div className="mt-2">{register}</div>
            <div className="mt-2"><KvGrid cls="grid--2" pairs={[["School fees", <Pil key="f" kind="warn">NOT YET AVAILABLE</Pil>], portal]} /></div>
          </PBody>
        </Panel>
      </div>
    );
  }
  if (f.state === "PAID") {
    return (
      <div id="fees">
        <Panel title="School fees" right={<Pil kind="ok">PAID</Pil>}>
          <PBody>
            <Note kind="ok" title={`${session} school fees paid`}>{money(num(f.paid))} paid in full. {portalOpen ? "The student portal is open to you: register your courses there." : "The student portal opens when the payment is verified."}</Note>
            <div className="mt-2"><KvGrid cls="grid--4" pairs={figures} /></div>
            <div className="mt-2">{register}</div>
            <div className="mt-2"><KvGrid cls="grid--2" pairs={[["School fees", <Pil key="f" kind="ok">PAID</Pil>], portal]} /></div>
          </PBody>
        </Panel>
      </div>
    );
  }
  if (f.state === "NOT_OPEN") {
    // V724: the payment window as it stands — scheduled (not yet open, or opening on a date) or closed for now (CLOSED, EXPIRED)
    const scheduled = f.windowState === "SCHEDULED";
    return (
      <div id="fees">
        <Panel title={scheduled ? "School fees payment not yet open" : "School fees payment closed"} right={session}>
          <PBody>
            <Note kind="info" title={scheduled ? (f.opensAt ? `Payment for ${session} opens on ${whenAt(f.opensAt)}` : `Payment for ${session} is not yet open`) : `Payment for ${session} is closed for now`}>
              The school fees for {session} are stated; you will pay here, on your Applicant Dashboard, when the University {scheduled ? "opens" : "reopens"} payment. {portalWord}
            </Note>
            {exception}
            <div className="mt-2"><KvGrid cls="grid--4" pairs={figures} /></div>
            <div className="mt-2">{register}</div>
            <div className="mt-2"><KvGrid cls="grid--2" pairs={[["School fees", <Pil key="f" kind="info">{scheduled ? "PAYMENT NOT YET OPEN" : "PAYMENT CLOSED FOR NOW"}</Pil>], portal]} /></div>
          </PBody>
        </Panel>
      </div>
    );
  }
  // PAYMENT_PENDING, PART_PAID, AVAILABLE: payable now, against a reference this portal draws for the student the applicant has become
  const choices = schoolFeeChoices(f);
  const chosen = choices.find((c) => c.amount === sel) ?? choices[0];
  const pending = f.state === "PAYMENT_PENDING" || !!open;
  return (
    <div id="fees">
      <Panel title="School fees" right={<Pil kind={pending ? "info" : "warn"}>{pending ? "PAYMENT PENDING" : f.state === "PART_PAID" ? "PART PAID" : "NOT PAID"}</Pil>}>
        <PBody>
          <div className="sub2">Your {session} school fees are paid here, on your Applicant Dashboard, by card or USSD against a reference this portal generates (or at a bank, quoting it). {portalWord}</div>
          {exception}
          <div className="mt-2"><KvGrid cls="grid--4" pairs={figures} /></div>
          {open ? (
            <div className="mt-2">
              <div className="eyebrow">Reference</div>
              <div className="tnum b700" style={{ fontSize: "var(--t-2xl)", letterSpacing: ".5px" }}>{open.reference}</div>
              <div className="sub2">{money(open.amount)}{open.expiresAt ? ` · expires ${when(open.expiresAt)}` : ""}. Pay with this reference only: at a bank branch, by transfer, or by card below. A payment made is confirmed here once the bank reports it.</div>
              <div className="row mt-2"><PayByCard reference={open.reference} amount={open.amount} /></div>
            </div>
          ) : choices.length ? (
            <div className="mt-2">
              <div className="sub2">{choices.length > 1 ? "Pay the first semester, or the whole session at once. Pick one, then generate the reference." : "Pay the outstanding school fees. Generate the reference, then pay against it."}</div>
              <div className="row mt-1">
                {choices.map((c) => <Btn key={c.key} kind={chosen?.key === c.key ? "primary" : "ghost"} disabled={busy} onClick={() => setSel(c.amount)}>{c.label} · {money(c.amount)}</Btn>)}
              </div>
              <div className="row mt-1">
                <Btn kind="primary" disabled={busy || !chosen} onClick={() => { if (chosen) void draw(chosen.amount); }}>{busy ? "Generating…" : chosen ? `Generate a reference for ${money(chosen.amount)}` : "Nothing to pay"}</Btn>
              </div>
            </div>
          ) : null}
          <div className="mt-2">{register}</div>
          <div className="mt-2"><KvGrid cls="grid--2" pairs={[["School fees", <Pil key="f" kind={pending ? "info" : "warn"}>{pending ? "PAYMENT PENDING" : f.state === "PART_PAID" ? "PART PAID" : "NOT PAID"}</Pil>], portal]} /></div>
        </PBody>
      </Panel>
    </div>
  );
}

/** Admission Status Checking (V295), the same four states for everyone whatever the decision: the application not complete,
 *  checking closed, the fee to pay, the status checked — with the status the check returned and every check made */
function CheckingView({ d, again, busy }: { d: Admission; again: () => void; busy: boolean }) {
  const c = d.checking;
  const steps = parseTracker(d.tracker);
  const checks = d.checks ?? [];
  const tracker = steps.length ? <Panel title="Progress tracker"><PBody><Tracker steps={steps} /></PBody></Panel> : null;
  if (!c) return <><Note kind="info" title={d.label}>{d.detail ?? "Your admission status is published here."}</Note>{tracker}</>;
  if (!c.applicationValid) {
    return (
      <>
        <Note kind="bad" title="Admission Status Checking is for completed Post-UTME applications" action={d.next_action && d.next_href ? <LinkBtn kind="primary" href={d.next_href}>{d.next_action}</LinkBtn> : null}>
          {d.detail ?? "Your application fee is confirmed and your application submitted before you can pay the admission checking fee and check your status."}
        </Note>
        {tracker}
      </>
    );
  }
  if (!c.windowOpen) {
    return (
      <>
        <Note kind="info" title="Admission Status Checking is currently closed">
          {d.detail ?? "Please check back later."} You are told by email and SMS when it opens.
        </Note>
        <CheckingFacts d={d} c={c} />
        {checks.length ? <ChecksPanel d={d} /> : null}
        {tracker}
      </>
    );
  }
  if (c.mayPay) return <><CheckingFee d={d} c={c} />{tracker}</>;
  return <><CheckResult d={d} c={c} again={again} busy={busy} />{checks.length ? <ChecksPanel d={d} /> : null}{tracker}</>;
}

/** where the applicant stands with the service: the window, the fee, the payment */
function CheckingFacts({ d, c }: { d: Admission; c: StatusChecking }) {
  return (
    <Panel title="Admission Status Checking" right={d.offer?.session ?? ""}>
      <PBody>
        <KvGrid cls="grid--3" pairs={[
          ["Checking", <Pil key="w" kind={c.windowOpen ? "ok" : "grey"}>{c.windowOpen ? "OPEN" : c.windowState === "SCHEDULED" ? "SCHEDULED" : "CLOSED"}</Pil>],
          [c.windowOpen ? "Closes" : "Opens", <span key="t" className="tnum">{c.windowOpen ? (c.closesAt ? whenAt(c.closesAt) : "No closing date announced") : c.windowState === "SCHEDULED" && c.opensAt ? whenAt(c.opensAt) : "When the University opens it"}</span>],
          ["Admission checking fee", <span key="f"><b className="tnum">{feeWord(c)}</b>{c.feeRequired ? <span className="sub2"> · paid once</span> : null}</span>],
          ["Payment status", !c.feeRequired ? <span key="p" className="sub2">Nothing to pay</span> : c.paid ? <span key="p"><Pil kind="ok">PAID ✓</Pil>{c.paidAt ? <span className="sub2 tnum"> {dayOf(c.paidAt)}</span> : null}</span> : <Pil key="p" kind="warn">NOT PAID</Pil>],
          ["Receipt", c.paidReference ? <a key="r" className="lnk tnum" href={`/applicant/fee/receipt?reference=${encodeURIComponent(c.paidReference)}`} target="_blank" rel="noopener">{c.paidReference}</a> : <span key="r" className="sub2">—</span>],
          ["Checks made", <span key="k" className="tnum">{c.checks}</span>],
        ]} />
      </PBody>
    </Panel>
  );
}

/** the status a check returned when it is not an offer: pending, the waiting list, not admitted — checked again for nothing */
function CheckResult({ d, c, again, busy }: { d: Admission; c: StatusChecking; again: () => void; busy: boolean }) {
  const o = d.offer;
  const last = d.checks?.[0];
  const pending = d.status === "PENDING";
  const waiting = d.label === "Waiting list";
  const colour = pending || waiting ? "var(--chrome)" : "var(--red)";
  return (
    <>
      <div className="card" style={{ borderTop: `4px solid ${colour}` }}>
        <PBody>
          <span className="eyebrow">Admission status · {o?.session ?? ""}</span>
          <div className="phead__t" style={{ fontFamily: "var(--serif)", fontSize: "var(--t-2xl)" }}>{pending ? "Admission pending" : waiting ? "Waiting list" : "Not admitted"}</div>
          <div className="sub2">{d.detail ?? ""}</div>
          <div className="hr" />
          <KvGrid cls="grid--3" pairs={[
            ["Name", o ? `${o.surname}, ${o.other_names}` : "—"], ["JAMB registration number", <span key="j" className="tnum">{o?.jamb_reg_no ?? "—"}</span>], ["Application number", <span key="a" className="tnum">{o?.application_no ?? "—"}</span>],
            ["Admission status", <Pil key="s" kind={pending || waiting ? "info" : "bad"}>{pending ? "PENDING" : waiting ? "WAITING LIST" : "NOT ADMITTED"}</Pil>],
            ["Checked", <span key="c" className="tnum">{last ? whenAt(last.checked_at) : "—"}</span>],
            ["Admission checking fee", c.feeRequired ? <span key="f"><Pil kind="ok">PAID ✓</Pil> <span className="sub2">not charged again</span></span> : <span key="f" className="sub2">Not charged this session</span>],
          ]} />
          <div className="row row--inline row--tight mt-2">
            <Btn kind="primary" disabled={busy} onClick={again}>{busy ? "Checking…" : "Check again"}</Btn>
            <span className="sub2">{pending ? "Check again when further admission processing has been completed; you do not pay again." : "You may check again while checking is open; you do not pay again."}</span>
          </div>
        </PBody>
      </div>
      {!pending ? (
        <Note kind="info" title="Supplementary lists">
          Later lists and changes are published here first.
        </Note>
      ) : null}
    </>
  );
}

/** every check the applicant made, with what it returned (admissions.status_check) */
function ChecksPanel({ d }: { d: Admission }) {
  const checks = d.checks ?? [];
  return (
    <Panel title="Your checks" right={`${checks.length} · each kept on the record`}>
      <DTable pageSize={10} cols={["Checked|mid", "Status returned"]} rows={checks.map((k, i) => [<span key={`t${i}`} className="tnum sub2">{whenAt(k.checked_at)}</span>, k.label])} />
    </Panel>
  );
}

/** the admission checking fee (V271, V295): paid once for the admission exercise, on its own, by every applicant who checks; a
 *  reference of the portal's own, paid by card, USSD or bank — one still open is the one to pay */
function CheckingFee({ d, c }: { d: Admission; c: StatusChecking }) {
  const [reference, setReference] = useState<string | null>(c.openReference ?? d.checkingReference ?? null);
  const [busy, setBusy] = useState(false);
  const fee = Number(c.fee ?? d.checkingFee ?? 0);
  /* V404: a CCE applicant whose checking fee the Bursary has not stated yet: owed, and not payable until it is */
  const unstated = c.fee == null;
  async function getReference() {
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/applicant/me/fee-references", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Admission checking fee reference") }, body: JSON.stringify({ kind: "CHECKING" }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      setReference(String((j as { reference: string }).reference));
    } finally { setBusy(false); }
  }
  if (unstated) {
    return (
      <Note kind="info" title="The admission checking fee is not stated yet">
        {d.detail ?? "The Bursary has not yet stated the admission checking fee for your session; you can pay it, and read your outcome, once it does."}
      </Note>
    );
  }
  return (
    <>
      <Note kind="info" title="Admission Status Checking is open">
        Pay the admission checking fee of <b className="tnum">{money(fee)}</b> once, then check your status as often as you need while checking is open. The acceptance fee is separate.
      </Note>
      <Panel title="Admission checking fee" right={reference ? <span className="tnum">{reference}</span> : "Get a payment reference"}>
        <PBody>
          {reference ? (
            <>
              <KvGrid cls="grid--3" pairs={[["Reference", <b key="r" className="tnum">{reference}</b>], ["Amount", <b key="a" className="tnum">{money(fee)}</b>], ["Purpose", "Admission checking fee"]]} />
              <div className="mt-2"><PayByCard reference={reference} amount={fee} /></div>
              <div className="sub2 mt-2">At a bank, quote the reference exactly. You are never charged twice.</div>
            </>
          ) : (
            <div className="row row--between"><span className="sub2">The reference is valid for 24 hours; pay by card, USSD or at the bank.</span><Btn kind="primary" disabled={busy} onClick={() => void getReference()}>{busy ? "Generating…" : "Pay now"}</Btn></div>
          )}
        </PBody>
      </Panel>
    </>
  );
}
