"use client";

/** The applicant's admission, in one place (V269, V295). Until an offer is read, Admission Status Checking: every applicant whose
 *  Post-UTME application is paid for and submitted pays the admission checking fee once, while the Director of ICT has checking
 *  open, and checks — admitted, not admitted or not yet decided alike; each check is kept with what it returned. Once an offer is
 *  read: the congratulations and the official details, where they stand, what comes next, the acceptance fee paid once for the
 *  admission, and the tracker of the steps that concern them. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { money } from "@/lib/format";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tick } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { CHECKING_GATE, STATUS_KIND, dayOf, parseTracker, stepHref, whenAt, type Admission, type StatusChecking, type TrackerStep } from "@/lib/screening";
import { AdmissionDocumentsCentre, useAdmissionDocuments } from "@/components/AdmissionDocumentsCentre";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { PayByCard } from "./common";

const ADMISSION = "/api/bff/api/v1/applicant/me/admission";
type Read = { ok: true; d: Admission } | { ok: false; problem: Problem };

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
  useEffect(() => {
    let live = true;
    void (async () => {
      try {
        const first = await readAdmission();
        if (!live) return;
        if (!first.ok) { setProblem(first.problem); return; }
        const c = first.d.checking;
        if (check && c?.mayCheck && !c.past) {
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
  }, [check]);
  /** check again — pending today, decided later — without paying again */
  async function again() {
    setBusy(true);
    try {
      const done = await checkStatus();
      if (done.ok) { setD(done.d); notify("Admission status checked"); } else notifyProblem(done.problem);
    } finally { setBusy(false); }
  }
  return { d, problem, again, busy };
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
  return !!d.screeningRequired && ![...CHECKING_GATE, "PENDING", "NOT_ADMITTED", "DECLINED", "ADMITTED", "ACCEPTANCE_PENDING", "SCREENING_PENDING", "SCREENING_IN_REVIEW", "SCREENING_CORRECTION", "SCREENING_IN_PROGRESS", "SCREENING_SUBMITTED", "SCREENING_RETURNED", "CHANGE_OF_PROGRAMME_REQUIRED", "CHANGE_OF_PROGRAMME_PENDING"].includes(d.status);
}

/** an offer the applicant has read, or may read now: the admission under way rather than Admission Status Checking (V295) */
function offerRead(d: Admission): boolean {
  const o = d.offer;
  return !!o && o.decision === "OFFERED" && !!o.decision_released_at && (!d.checking || d.checking.decisionVisible);
}

const feeWord = (c: StatusChecking) => (c.feeRequired ? money(Number(c.fee)) : "Not charged this session");

/** the dashboard's Admission Status section: always there — checking closed, open and not paid for, paid for and ready to check —
 *  and, once an offer is read, the admission under way: status, next step, tracker */
export function AdmissionProgress() {
  const { d } = useAdmission();
  if (!d) return null;
  if (d.checking && !d.checking.past) return <CheckingSection d={d} c={d.checking} />;
  if (!d.offer || d.offer.decision !== "OFFERED") return null;
  return (
    <Panel title="Your admission" right={<Pil kind={STATUS_KIND(d.status) === "ok" ? "ok" : STATUS_KIND(d.status) === "bad" ? "bad" : "info"}>{d.label}</Pil>}>
      <PBody>
        <div className="row row--between">
          <span><b>{d.offer.changed_to ?? d.offer.programme}</b><div className="sub2">{d.offer.faculty ? `Faculty of ${d.offer.faculty}` : ""}{d.offer.department ? ` · ${d.offer.department}` : ""} · {d.offer.session}</div></span>
          {d.next_action ? <LinkBtn kind="primary" href={stepHref(d.next_href)}>{d.next_action}</LinkBtn> : null}
        </div>
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
              {c.windowState === "SCHEDULED" && c.opensAt ? `It opens ${whenAt(c.opensAt)}.` : "Please check back later: you are told by email and SMS the moment the University opens it."}
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
  const { d, problem, again, busy } = useAdmission(true);
  const docs = useAdmissionDocuments("/api/bff/api/v1/applicant/me/documents-centre");
  // the handover to the student portal sends the applicant back here when it is refused, naming the rule (V278, V282)
  const [refused] = useState<{ code: string; why: string } | null>(() => {
    if (typeof window === "undefined") return null;
    const q = new URLSearchParams(window.location.search);
    const code = q.get("portal");
    return code ? { code, why: q.get("why") ?? "" } : null;
  });
  if (problem) return <Note kind="bad" title="Your admission">{problem.title}</Note>;
  if (!d) return <Panel title="Your admission"><PBody><div className="sub2">Reading…</div></PBody></Panel>;
  const o = d.offer;
  const steps = parseTracker(d.tracker);
  if (!offerRead(d)) return <CheckingView d={d} again={() => void again()} busy={busy} />;
  const kind = STATUS_KIND(d.status);
  return (
    <>
      {refused ? (
        <Note kind="bad" title="The student portal could not be opened">
          {refused.code === "AUTH_NOT_ON_REGISTER" ? "You are not yet on the student register; the portal opens the moment your screening is successful (or on acceptance where your session needs no screening). Everything until then is here." : refused.why || `The crossing was refused (${refused.code}). Try again; if it persists, write to the Directorate of ICT quoting this code.`}
        </Note>
      ) : null}
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

      <Note kind={kind} title={d.next_action ? `Next step: ${d.next_action}` : d.label} action={d.next_action && d.next_href ? <LinkBtn kind={kind === "bad" ? "urgent" : "primary"} href={stepHref(d.next_href)}>{d.next_action}</LinkBtn> : null}>
        {d.detail ?? ""}
        {d.status === "SCHOOL_FEES_PENDING" || d.status === "COURSE_REGISTRATION_PENDING" ? <span className="blk">Your admission number{o.admission_no ? ` ${o.admission_no}` : ""} is your sign-in on the student portal, with the password you chose as an applicant. From here, <a className="lnk" href={stepHref(d.next_href ?? "/student/fees")}>continue to the student portal</a> without signing in again.</span> : null}
      </Note>

      <div className="grid grid--2">
        <Panel title="Progress tracker" right={`${steps.filter((s) => s.state === "done").length} of ${steps.length} done`}>
          <PBody><Tracker steps={steps} /></PBody>
        </Panel>
        <Panel title="Acceptance and screening" right="Acceptance fee is paid once, for the admission">
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["Acceptance fee", d.entitlement.paid ? <span key="e"><Pil kind="ok">PAID</Pil> <span className="sub2 tnum">{d.entitlement.reference ?? ""} · {dayOf(d.entitlement.confirmed_at)}</span></span> : <Pil key="e" kind="warn">NOT YET PAID</Pil>],
              ["University screening", !d.screeningRequired ? <span key="s" className="sub2">Not required for your session</span> : o.cleared_at ? <Pil key="s" kind="ok">SUCCESSFUL</Pil> : <LinkBtn key="s" kind="secondary" size="sm" href="/applicant/clearance">Screening status</LinkBtn>],
              ["Change of programme", o.changed_to ? <span key="c">{o.changed_from} → <b>{o.changed_to}</b><div className="sub2">Your acceptance payment remained valid; it was not charged again.</div></span> : <span key="c" className="sub2">None</span>],
              ["School fees", d.status === "SCHOOL_FEES_PENDING" ? <LinkBtn key="f" kind="primary" size="sm" href={stepHref("/student/fees")}>Pay school fees</LinkBtn> : ["COURSE_REGISTRATION_PENDING", "MATRICULATION_PENDING", "MATRICULATED"].includes(d.status) ? <Pil key="f" kind="ok">PAID</Pil> : <span key="f" className="sub2">After successful screening</span>],
            ]} />
            {d.entitlement.paid ? <div className="sub2 mt-2">Whatever programme your admission ends on, the acceptance fee is never asked for a second time.</div> : null}
          </PBody>
        </Panel>
      </div>

      {["SCHOOL_FEES_PENDING", "COURSE_REGISTRATION_PENDING", "MATRICULATION_PENDING", "MATRICULATED"].includes(d.status) && o.student_id ? (
        <Panel title="Student status" right={o.matric_no ? "Matriculated" : d.status === "SCHOOL_FEES_PENDING" ? "Admitted · school fees pending" : "Student · matriculation pending"}>
          <PBody>
            <KvGrid cls="grid--3" pairs={[
              ["Status", <Pil key="s" kind={o.matric_no ? "ok" : d.status === "SCHOOL_FEES_PENDING" ? "info" : "ok"}>{o.matric_no ? "MATRICULATED · ACTIVE STUDENT" : d.status === "SCHOOL_FEES_PENDING" ? "ADMITTED · SCHOOL FEES PENDING" : "STUDENT · MATRICULATION PENDING"}</Pil>],
              ["School fees", d.status === "SCHOOL_FEES_PENDING" ? <Pil key="f" kind="warn">PENDING</Pil> : <Pil key="f" kind="ok">PAID</Pil>],
              ["Student portal", d.status === "SCHOOL_FEES_PENDING" ? <span key="p" className="sub2">Opens fully once your school fees are paid</span> : <Pil key="p" kind="ok">ACTIVE</Pil>],
              ["Matriculation number", <span key="m" className="tnum">{o.matric_no ?? "Pending · issued by the Academic Office"}</span>],
              ["Login username", <span key="u" className="tnum">{o.matric_no ?? o.jamb_reg_no}</span>],
              ["Password", <span key="w" className="sub2">The one you chose as an applicant; it does not change when your matriculation number becomes your username</span>],
            ]} />
            <div className="sub2 mt-2">{o.matric_no ? `Your matriculation number ${o.matric_no} is now your username on the student portal.` : d.status === "SCHOOL_FEES_PENDING" ? "Pay your school fees to activate your student portal; your official matriculation number is issued by the Academic Office afterwards." : "Your student account is active. Your official matriculation number is being processed by the Academic Office; you will be notified when it is issued, and it becomes your username."}</div>
            <div className="mt-2 row row--inline row--tight"><LinkBtn kind={d.status === "SCHOOL_FEES_PENDING" ? "secondary" : "primary"} href={stepHref(d.status === "SCHOOL_FEES_PENDING" ? "/student/fees" : "/student")}>{d.status === "SCHOOL_FEES_PENDING" ? "Pay school fees" : "Open the student portal"}</LinkBtn></div>
          </PBody>
        </Panel>
      ) : null}

      <div id="documents">
        {docs ? <AdmissionDocumentsCentre rows={docs} side="applicant" /> : <Panel title="Admission & screening documents"><PBody><div className="sub2">Reading your documents…</div></PBody></Panel>}
      </div>
    </>
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
          {d.detail ?? "Please check back later."} You cannot pay the admission checking fee or check your status while it is closed; you are told by email and SMS when it opens.
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
        <Note kind="info" title="Keep watching the University's official admission updates">
          Supplementary lists and changes are published through this portal first. A later decision on your application appears here when you check again.
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
  async function getReference() {
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/applicant/me/fee-references", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Admission checking fee reference") }, body: JSON.stringify({ kind: "CHECKING" }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      setReference(String((j as { reference: string }).reference));
    } finally { setBusy(false); }
  }
  return (
    <>
      <Note kind="info" title="Admission Status Checking is open">
        Pay the admission checking fee of <b className="tnum">{money(fee)}</b> to check your admission status. It is paid once: you can then check as often as you need while checking is open, and a status that is still pending is checked again later for nothing. The acceptance fee, if you are offered admission, is separate.
      </Note>
      <Panel title="Admission checking fee" right={reference ? <span className="tnum">{reference}</span> : "Get a payment reference"}>
        <PBody>
          {reference ? (
            <>
              <KvGrid cls="grid--3" pairs={[["Reference", <b key="r" className="tnum">{reference}</b>], ["Amount", <b key="a" className="tnum">{money(fee)}</b>], ["Purpose", "Admission checking fee"]]} />
              <div className="mt-2"><PayByCard reference={reference} amount={fee} /></div>
              <div className="sub2 mt-2">Paying at a bank: quote the reference exactly; the Bursary confirms it against the bank&rsquo;s record, you are told by email and SMS, and you then check your status here. A payment that fails or is not confirmed does not count, and you are never charged twice.</div>
            </>
          ) : (
            <div className="row row--between"><span className="sub2">A reference of the University&rsquo;s own is generated for you; it is good for 24 hours and is paid by card, USSD or at the bank.</span><Btn kind="primary" disabled={busy} onClick={() => void getReference()}>{busy ? "Generating…" : "Pay now"}</Btn></div>
          )}
        </PBody>
      </Panel>
    </>
  );
}
