"use client";

/**
 * The student's dashboard and profile — proto/part3.html studentDashboard,
 * proto/part4.html studentProfile, as drawn — from the register: the fees
 * position under the scheme in force, the registration's stage, the
 * results published, and the contact details the student may change.
 */
import { useState } from "react";
import Link from "next/link";
import type { Me } from "@/lib/student-portal";
import { semesterName } from "@/lib/student-portal";
import { Btn, Ico, KvGrid, Note, Panel, PBody, Pil, Tick, Two, WarnIcon } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Passport, Step } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { naira, onDay, useAct, when } from "./common";

function Quick({ icon, title, sub, href }: { icon: string; title: string; sub: string; href: string | null }) {
  const inner = (
    <>
      <Ico name={icon} size={20} stroke={href ? "var(--chrome)" : "var(--faint)"} w={1.7} />
      <div style={{ fontSize: 13.5, fontWeight: 600, marginTop: 4 }}>{title}</div>
      <div className="c">{sub}</div>
    </>
  );
  return href ? <Link href={href} className="tile" style={{ textAlign: "left", alignItems: "flex-start", textDecoration: "none" }}>{inner}</Link>
    : <button type="button" className="tile" style={{ textAlign: "left", alignItems: "flex-start" }} disabled>{inner}</button>;
}

export function Dashboard({ s }: { s: Me }) {
  const f = s.fees;
  const cleared = f.clearsRegistration === true;
  const noScheme = f.clearsRegistration === null;
  const reg = s.registration;
  const published = s.gpa.filter((g) => g.published_count > 0).length;
  return (
    <>
      {noScheme ? (
        <Note kind="info" title="What a payment releases is not yet stated for this session">
          {f.schemeProblem} Your charges and payments are shown on Fees &amp; payments; registration opens the moment the Bursar states the scheme.
        </Note>
      ) : !cleared ? (
        <div className="notice notice--bad">
          <WarnIcon size={19} />
          <div>
            <div className="notice__t" style={{ color: "var(--red-deep)" }}>Action required</div>
            <p style={{ color: "var(--red-deep)" }}>{f.balance > 0 ? <>Your balance of <strong className="tnum">{naira(f.balance)}</strong> for {f.session} is outstanding. Course registration waits on the Bursary&rsquo;s clearance.</> : f.hasArrears ? <>Arrears from an earlier session stand against you, and the scheme blocks everything while they do.</> : <>The Bursary has not cleared you for registration.</>}</p>
            <div style={{ display: "flex", gap: 8, marginTop: 11, flexWrap: "wrap" }}>
              <Link href="/student/fees" className="btn btn--urgent btn--sm">Pay now</Link>
              <Link href="/student/fees" className="btn btn--ghost btn--sm">See breakdown</Link>
            </div>
          </div>
        </div>
      ) : (
        <div className="notice notice--ok">
          <Tick size={19} colour="var(--green-ink)" />
          <div>
            <div className="notice__t" style={{ color: "var(--green-ink)" }}>You are cleared to register</div>
            <p style={{ color: "var(--green-ink)" }}>{f.paidInFull ? `School fees settled in full for ${f.session}.` : `Your payment so far releases registration for ${f.session}; ${naira(f.balance)} remains.`}</p>
            <div style={{ marginTop: 11 }}><Link href="/student/register" className="btn btn--go btn--sm">Register courses</Link></div>
          </div>
        </div>
      )}

      <div className="grid grid--2">
        <div className="card"><div className="card__body">
          <div style={{ display: "flex", gap: 13, alignItems: "flex-start" }}>
            <Passport w={52} h={64} radius={6} src={s.passportDocumentId ? `/api/bff/api/v1/applicant/me/documents/${s.passportDocumentId}/content` : null} />
            <div>
              <div style={{ fontSize: 16, fontWeight: 600 }}>{s.name}</div>
              <div className="sub2 tnum">{s.matricNo ?? s.admissionNo}</div>
              <div className="sub2">{s.programme} &middot; {s.level} Level</div>
            </div>
          </div>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <span className={`pill ${s.status === "ACTIVE" ? "pill--ok" : "pill--info"}`}><span className="dot" style={{ background: s.status === "ACTIVE" ? "var(--green)" : "var(--chrome)" }} />{s.status.charAt(0) + s.status.slice(1).toLowerCase()}</span>
            <span className="pill" style={{ background: "var(--bg)", border: "1px solid var(--line)", color: "var(--muted)" }}>CGPA {s.cgpa ?? "—"}</span>
            {s.curriculumVersion ? <span className="pill" style={{ background: "var(--bg)", border: "1px solid var(--line)", color: "var(--muted)" }}>Curriculum {s.curriculumVersion}</span> : null}
          </div>
        </div></div>
        <div className="card">
          <div className="card__head"><span className="card__title">This session</span><span className="sub2">{s.session}</span></div>
          <div className="card__body"><div className="steps">
            <Step state="done" title="On the register" sub={`${s.matricNo ? "Matriculated" : "Admitted"} · entered ${s.entrySession}`} />
            <Step state={reg?.status === "APPROVED" || reg?.status === "LOCKED" ? "done" : cleared ? "now" : "todo"} title="Course registration"
              sub={reg ? `${reg.status === "APPROVED" || reg.status === "LOCKED" ? "Approved" : reg.status === "SUBMITTED" ? "Submitted, with your Head of Department" : reg.status === "RETURNED" ? "Returned to you" : "Draft"} · ${reg.units} units` : cleared ? "Ready to register" : noScheme ? "Waits on the scheme" : "Blocked — fees outstanding"} />
            <Step state="todo" title="Examination docket" sub="Available after approval" />
          </div></div>
        </div>
      </div>

      <div className="grid grid--4">
        <Quick icon="cap" title="My results" sub={published ? `${published} semester${published === 1 ? "" : "s"} published` : "Nothing published yet"} href="/student/results" />
        <Quick icon="card" title="Fees & payments" sub={f.balance > 0 ? `${naira(f.balance)} outstanding` : f.due > 0 ? "Fully paid" : "No charge stated yet"} href="/student/fees" />
        {s.graduation && (s.graduation.finalist || s.graduation.audited) ? (
          <Quick icon="cap" title="Graduation" sub={s.graduation.senate_state === "APPROVED" ? `${s.graduation.class_of_degree ?? "Approved"} · ${s.graduation.certificate_no ? "certificate printed" : s.graduation.cleared ? "cleared for convocation" : `${s.graduation.units_holding} unit${s.graduation.units_holding === 1 ? "" : "s"} holding`}` : s.graduation.audited ? (s.graduation.unmet ? "A requirement is unmet" : "Awaiting Senate") : "Final year — the audit runs at the end"} href="/student/graduation" />
        ) : (
          <Quick icon="doc" title="Transcript" sub="Request an official copy" href="/student/transcript" />
        )}
        <Quick icon="book" title="Course form" sub={reg && (reg.status === "APPROVED" || reg.status === "LOCKED") ? "Ready to print" : "After approval"} href={reg && (reg.status === "APPROVED" || reg.status === "LOCKED") ? "/student/form" : null} />
      </div>

      {s.carryovers.length ? (
        <Note kind="bad" title={`${s.carryovers.length} carryover${s.carryovers.length === 1 ? "" : "s"}`}>
          {s.carryovers.map((c) => `${c.course_code} (${c.failed_in})`).join(", ")} will be added to your next registration automatically. You do not need to request them.
        </Note>
      ) : null}

      <Panel title="Notices sent to you" right={s.notices.length ? `${s.notices.length} · email and SMS` : "none yet"}>
        {s.notices.length ? (
          <DTable cols={["When|mid", "Notice", "Channel|mid", "Status|num"]} rows={s.notices.map((n) => [
            <span className="tnum sub2" key="w">{when(n.created_at)}</span>,
            <Two key="n" a={n.subject} b={n.body} />,
            <span className="sub2" key="c">{n.channel === "SMS" ? `SMS · ${n.recipient}` : `Email · ${n.recipient}`}</span>,
            n.state === "SENT" ? <Pil kind="ok" key="s">Sent</Pil> : n.state === "FAILED" ? <Pil kind="bad" key="s">Not delivered</Pil> : <Pil kind="info" key="s">Waiting to be sent</Pil>,
          ])} />
        ) : <PBody><div className="sub2">Every notice the portal sends you is listed here as well, so nothing depends on a message reaching your phone.</div></PBody>}
      </Panel>
    </>
  );
}

export function Profile({ s, change }: { s: Me; change: boolean }) {
  const { act, busy, problem } = useAct();
  const [phone, setPhone] = useState(s.contact.phone ?? s.contact.reach_phone ?? "");
  const [email, setEmail] = useState(s.contact.email ?? s.contact.reach_email ?? "");
  const [address, setAddress] = useState(s.contact.address ?? "");
  const [cur, setCur] = useState("");
  const [next, setNext] = useState("");
  const [saidPw, setSaidPw] = useState(false);
  return (
    <>
      {change ? <Note kind="bad" title="Choose your own password before you go on">The Registry gave you a first password. Change it below; it is yours alone from then on.</Note> : null}
      <div className="card"><div className="card__body" style={{ flexDirection: "row", gap: 20, alignItems: "flex-start", flexWrap: "wrap" }}>
        <Passport w={112} h={139} radius={5} src={s.passportDocumentId ? `/api/bff/api/v1/applicant/me/documents/${s.passportDocumentId}/content` : null} />
        <div style={{ display: "flex", flexDirection: "column", gap: 9, flexGrow: 1, minWidth: 230 }}>
          <div><div style={{ fontSize: 19, fontWeight: 700, letterSpacing: "-.3px" }}>{s.name}</div>
            <div className="sub2 tnum">{s.matricNo ?? s.admissionNo} &middot; {s.programme} &middot; {s.level} Level</div></div>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <span className={`pill ${s.status === "ACTIVE" ? "pill--ok" : "pill--info"}`}><span className="dot" style={{ background: "var(--green)" }} />{s.status.charAt(0) + s.status.slice(1).toLowerCase()}</span>
            <Pil kind={s.passportDocumentId ? "info" : "grey"}>{s.passportDocumentId ? "Photograph on file" : "No photograph on file"}</Pil>
          </div>
          <div className="sub2" style={{ maxWidth: "52ch", lineHeight: 1.55 }}>{s.passportDocumentId ? "This is the photograph you uploaded at application. It is the one printed on your identity card and shown to the invigilator, so it must remain a true likeness." : "No photograph reached the register with you. The Registry captures one at matriculation."}</div>
          <div className="sub2">A change needs Registry approval &mdash; students cannot replace it themselves after matriculation.</div>
        </div>
      </div></div>
      <div className="grid grid--2">
        <div className="card"><div className="card__head"><span className="card__title">You can change these</span></div><div className="card__body">
          <div className="field"><label htmlFor="ph">Phone</label><input id="ph" value={phone} onChange={(e) => setPhone(e.target.value)} autoComplete="off" /></div>
          <div className="field"><label htmlFor="em">Personal email</label><input id="em" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="off" /></div>
          <div className="field"><label htmlFor="ad">Contact address</label><input id="ad" value={address} onChange={(e) => setAddress(e.target.value)} autoComplete="off" /></div>
          {problem && busy !== "pw" ? <ProblemNotice problem={problem} /> : null}
          <Btn kind="primary" disabled={busy !== null} onClick={() => void act("contact", "PUT", "/me/contact", { phone, email, address }, "Contact details changed by the student")}>{busy === "contact" ? "Saving…" : "Save changes"}</Btn>
          <div style={{ height: 1, background: "var(--line-2)" }} />
          <div style={{ fontWeight: 600 }}>Password</div>
          <div className="field"><label htmlFor="pw0">Current password</label><input id="pw0" type="password" value={cur} onChange={(e) => setCur(e.target.value)} autoComplete="current-password" /></div>
          <div className="field"><label htmlFor="pw1">New password</label><input id="pw1" type="password" value={next} onChange={(e) => setNext(e.target.value)} autoComplete="new-password" /><div className="hint">Eight characters at the very least.</div></div>
          {saidPw ? <Note kind="ok" title="Password changed">Sign in with the new one from now on.</Note> : null}
          <Btn kind="ghost" disabled={busy !== null || !cur || next.length < 8} onClick={async () => { const ok = await act("pw", "POST", "/student-auth/change-password", { current: cur, next }, "Password changed by the student"); if (ok) { setSaidPw(true); setCur(""); setNext(""); } }}>{busy === "pw" ? "Changing…" : "Change the password"}</Btn>
        </div></div>
        <div className="card"><div className="card__head"><span className="card__title">Only Registry can change these</span></div><div className="card__body">
          <KvGrid cls="grid--2" pairs={[
            ["Full name", s.name],
            ["Matriculation number", <span className="tnum" key="m">{s.matricNo ?? "Not yet issued"}</span>],
            ["Admission number", <span className="tnum" key="a">{s.admissionNo ?? "—"}</span>],
            ["Programme", s.programme],
            ["Department", s.department],
            ["Entry session & mode", <span className="tnum" key="e">{s.entrySession} · {s.entryMode}</span>],
            ["Curriculum version", <span className="tnum" key="c">{s.curriculumVersion ?? "—"}</span>],
            ["On the register since", onDay(s.entrySession ? undefined : null)],
          ]} />
          <div className="sub2" style={{ marginTop: 4 }}>Your curriculum version was fixed when you were admitted, so you are always assessed against the rules that applied then. To change a name or programme, apply through Registry with supporting documents.</div>
        </div></div>
      </div>
    </>
  );
}

export function fmtSemester(g: { session: string; semester: number }): string {
  return `${g.session} · ${semesterName(g.semester)}`;
}
