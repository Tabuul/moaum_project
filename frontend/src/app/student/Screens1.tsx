"use client";

/**
 * The student's dashboard and profile — proto/part3.html studentDashboard,
 * proto/part4.html studentProfile, as drawn — from the register: the fees
 * position under the scheme in force, the registration's stage, the
 * results published, and the contact details the student may change.
 */
import { useEffect, useState, type CSSProperties, type ReactNode } from "react";
import Link from "next/link";
import type { Me } from "@/lib/student-portal";
import { semesterName } from "@/lib/student-portal";
import type { StudentRecord } from "@/lib/student";
import { Btn, Ico, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Passport, Step } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { naira, onDay, useAct, when } from "./common";

/** the student's bio-data as a clean, read-only profile card on the dashboard. The full record
 *  (personal, origin, contact, family, next-of-kin) is read from /me/biodata; the JAMB registration
 *  number shows for returning students who carry one. Editing lives on the biodata page. */
function StudentDetails({ s }: { s: Me }) {
  const [rec, setRec] = useState<StudentRecord | null>(null);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    let alive = true;
    fetch("/api/bff/api/v1/me/biodata")
      .then((r) => (r.ok ? r.json() : null))
      .then((j) => { if (alive) { setRec(j); setLoading(false); } })
      .catch(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, []);

  const bio = rec?.biodata ?? [];
  const v = (field: string) => bio.find((b) => b.field === field)?.value?.trim() || null;
  const fmtDate = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : null);
  const sex = rec?.student.sex === "M" ? "Male" : rec?.student.sex === "F" ? "Female" : null;
  const dob = fmtDate(rec?.student.dateOfBirth);
  const jamb = rec?.student.jambRegNo?.trim() || null;

  // one section = a heading and the fields under it that actually have a value (empties are hidden for a clean look)
  const sections: { title: string; pairs: [string, ReactNode][] }[] = [];
  const push = (title: string, pairs: ([string, ReactNode | null | undefined])[]) => {
    const kept = pairs.filter((p) => p[1]) as [string, ReactNode][];
    if (kept.length) sections.push({ title, pairs: kept });
  };
  push("Personal", [
    ["Sex", sex], ["Date of birth", dob], ["Marital status", v("marital_status")],
    ["Religion", v("religion")], ["Blood group", v("blood_group")], ["Genotype", v("genotype")],
  ]);
  push("Origin", [
    ["Nationality", v("nationality")], ["State of origin", v("state_of_origin")],
    ["Local government", v("lga")], ["Place of birth", v("place_of_birth")], ["Ethnic group", v("ethnic_group")],
  ]);
  push("Contact", [
    ["Phone", s.contact.phone ?? s.contact.reach_phone], ["Email", s.contact.email ?? s.contact.reach_email],
    ["Contact address", s.contact.address], ["Permanent address", v("permanent_address") ?? v("home_address")],
  ]);
  push("Family & next of kin", [
    ["Guardian", v("guardian_name")], ["Guardian address", v("guardian_address")],
    ["Sponsor", v("sponsor_name")], ["Sponsor address", v("sponsor_address")],
    ["Next of kin", v("kin_name")], ["Relationship", v("kin_relationship")],
    ["Next-of-kin phone", v("kin_mobile")], ["Next-of-kin address", v("kin_address")],
  ]);

  return (
    <Panel title="Student details" right="Your record on the register">
      <PBody>
        <div className="row row--top" style={{ gap: "var(--s-4)" }}>
          <Passport w={104} h={128} radius={6} src={s.hasPhoto ? `/api/bff/api/v1/me/passport?v=${encodeURIComponent(s.matricNo ?? s.admissionNo ?? s.id)}` : null} />
          <div className="grow" style={{ minWidth: 240 }}>
            <div className="phead__t">{s.name}</div>
            <div className="sub2 tnum mt-1">{s.matricNo ?? s.admissionNo}</div>
            <div className="sub2 mt-1">{s.programme} &middot; {s.department}</div>
            <div className="sub2">{s.faculty}</div>
            <div className="row mt-2">
              <span className={`pill ${s.status === "ACTIVE" ? "pill--ok" : "pill--info"}`}><span className="dot" style={{ background: s.status === "ACTIVE" ? "var(--green)" : "var(--chrome)" }} />{s.status.charAt(0) + s.status.slice(1).toLowerCase()}</span>
              <Pil kind="info">{s.level} Level</Pil>
              <Pil kind="grey">{s.entryMode} · {s.entrySession}</Pil>
            </div>
            <div className="mt-3" style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: "2px var(--s-4)" }}>
              {([["Matriculation number", s.matricNo], ["Admission number", s.admissionNo], jamb ? ["JAMB registration number", jamb] : null, ["CGPA", s.cgpa != null ? String(s.cgpa) : null]].filter(Boolean) as [string, string | null][]).map(([k, val]) => val ? (
                <div key={k} className="kv"><span className="k">{k}</span><span className="v tnum">{val}</span></div>
              ) : null)}
            </div>
          </div>
        </div>

        {loading ? <div className="sub2 mt-4">Loading your details…</div> : null}
        {/* one uniform column track for every section, so the columns line up down the whole card and a
            section with two fields reads as tidily as one with eight (auto-fill packs left, never stretches) */}
        {sections.map((sec, si) => (
          <div key={sec.title} style={{ marginTop: "var(--s-5)", paddingTop: si ? "var(--s-4)" : 0, borderTop: si ? "1px solid var(--line-2)" : undefined }}>
            <div className="eyebrow mb-3">{sec.title}</div>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(240px, 1fr))", columnGap: "var(--s-7)", rowGap: "var(--s-4)", maxWidth: 1160 }}>
              {sec.pairs.map(([k, val], i) => (
                <div key={i} className="kv">
                  <span className="k">{k}</span>
                  <span className="v">{val}</span>
                </div>
              ))}
            </div>
          </div>
        ))}
        <div className="sub2 mt-4">
          Names, programme and JAMB details are held by the Registry and JAMB. You can update your contact and other open
          details on the <Link href="/student/biodata">bio-data page</Link>.
        </div>
      </PBody>
    </Panel>
  );
}

function Quick({ icon, title, sub, href }: { icon: string; title: string; sub: string; href: string | null }) {
  const inner = (
    <>
      <Ico name={icon} size={20} stroke={href ? "var(--chrome)" : "var(--faint)"} w={1.7} />
      <div className="b600 mt-1" style={{ fontSize: "var(--t-base)" }}>{title}</div>
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
  const prob = s.probation && s.probation.standing === "PROBATION" ? s.probation : null;
  const adv = s.probation && s.probation.standing === "ADVISED_TO_WITHDRAW" ? s.probation : null;
  const semWord = (n: number | null) => (n === 2 ? "second" : "first");
  return (
    <>
      {adv ? (
        <Note kind="bad" title="The result sheet advises your withdrawal" action={<LinkBtn kind="ghost" href="/student/results">Your results</LinkBtn>}>
          Your CGPA stood at <strong className="tnum">{adv.cgpa != null ? Number(adv.cgpa).toFixed(2) : "—"}</strong> at the end of the {adv.pronounced_session} second semester at {adv.pronounced_level} level, still under 1.0 after the level&rsquo;s probation list. Senate&rsquo;s rule advises withdrawal from the programme. The decision is Senate&rsquo;s; your Head of Department will tell you of it. Until then your registration is held as on probation{adv.probation_max_units != null ? <>, to <strong>{adv.probation_max_units} units</strong> at most</> : null}.
        </Note>
      ) : null}
      {prob ? (
        <Note kind="bad" title="You are on probation" action={<LinkBtn kind="ghost" href="/student/results">Your results</LinkBtn>}>
          Your CGPA stood at <strong className="tnum">{prob.cgpa != null ? Number(prob.cgpa).toFixed(2) : "—"}</strong> after the {prob.pronounced_session} {semWord(prob.pronounced_semester)} semester at {prob.pronounced_level} level, under the 1.0 the University requires. {prob.probation_max_units != null ? <>Until the next semester&rsquo;s results pronounce again, your course registration is held to <strong>{prob.probation_max_units} units</strong>; the courses you owe stay on the form, so choose fewer new ones.</> : <>The courses you owe stay on your registration form; see your Head of Department about the load you should carry.</>}
        </Note>
      ) : null}
      {noScheme ? (
        <Note kind="info" title="What a payment releases is not yet stated for this session">
          {f.schemeProblem} Your charges and payments are shown on Fees &amp; payments; registration opens the moment the Bursar states the scheme.
        </Note>
      ) : !cleared ? (
        <Note kind="bad" title="Action required" action={<div className="row"><LinkBtn kind="urgent" href="/student/fees">Pay now</LinkBtn><LinkBtn kind="ghost" href="/student/fees">See breakdown</LinkBtn></div>}>
          {f.balance > 0 ? <>Your balance of <strong className="tnum">{naira(f.balance)}</strong> for {f.session} is outstanding. Course registration waits on the Bursary&rsquo;s clearance.</> : f.hasArrears ? <>Arrears from an earlier session stand against you, and the scheme blocks everything while they do.</> : <>The Bursary has not cleared you for registration.</>}
        </Note>
      ) : (
        <Note kind="ok" title="You are cleared to register" action={<LinkBtn kind="go" href="/student/register">Register courses</LinkBtn>}>
          {f.paidInFull ? `School fees settled in full for ${f.session}.` : `Your payment so far releases registration for ${f.session}; ${naira(f.balance)} remains.`}
        </Note>
      )}

      <div className="grid grid--2">
        <div className="card"><div className="card__body">
          <div className="row row--top" style={{ gap: "var(--s-3)" }}>
            <Passport w={52} h={64} radius={6} src={s.hasPhoto ? `/api/bff/api/v1/me/passport?v=${encodeURIComponent(s.matricNo ?? s.admissionNo ?? s.id)}` : null} />
            <div>
              <div className="t-lg b600">{s.name}</div>
              <div className="sub2 tnum">{s.matricNo ?? s.admissionNo}</div>
              <div className="sub2">{s.programme} &middot; {s.level} Level</div>
            </div>
          </div>
          <div className="row">
            <span className={`pill ${s.status === "ACTIVE" ? "pill--ok" : "pill--info"}`}><span className="dot" style={{ background: s.status === "ACTIVE" ? "var(--green)" : "var(--chrome)" }} />{s.status.charAt(0) + s.status.slice(1).toLowerCase()}</span>
            <Pil kind="grey">CGPA {s.cgpa ?? "—"}</Pil>
            {s.curriculumVersion ? <Pil kind="grey">Curriculum {s.curriculumVersion}</Pil> : null}
          </div>
        </div></div>
        <Panel title="This session" right={s.session}>
          <PBody><div className="steps">
            <Step state="done" title="On the register" sub={`${s.matricNo ? "Matriculated" : "Admitted"} · entered ${s.entrySession}`} />
            <Step state={reg?.status === "APPROVED" || reg?.status === "LOCKED" ? "done" : cleared ? "now" : "todo"} title="Course registration"
              sub={reg ? `${reg.status === "APPROVED" || reg.status === "LOCKED" ? "Approved" : reg.status === "SUBMITTED" ? "Submitted, with your Head of Department" : reg.status === "RETURNED" ? "Returned to you" : "Draft"} · ${reg.units} units` : cleared ? "Ready to register" : noScheme ? "Waits on the scheme" : "Blocked — fees outstanding"} />
            <Step state="todo" title="Examination docket" sub="Available after approval" />
          </div></PBody>
        </Panel>
      </div>

      <StudentDetails s={s} />

      <div className="grid grid--4">
        <Quick icon="cap" title="My results" sub={published ? `${published} semester${published === 1 ? "" : "s"} published` : "Nothing published yet"} href="/student/results" />
        <Quick icon="card" title="Fees & payments" sub={f.balance > 0 ? `${naira(f.balance)} outstanding` : f.due > 0 ? "Fully paid" : "No charge stated yet"} href="/student/fees" />
        {s.graduation && (s.graduation.finalist || s.graduation.audited) ? (
          <Quick icon="cap" title="Graduation" sub={s.graduation.senate_state === "APPROVED" ? `${s.graduation.class_of_degree ?? "Approved"} · ${s.graduation.certificate_no ? "certificate printed" : s.graduation.cleared ? "cleared for convocation" : `${s.graduation.units_holding} unit${s.graduation.units_holding === 1 ? "" : "s"} holding`}` : s.graduation.audited ? (s.graduation.unmet ? "A requirement is unmet" : "Awaiting Senate") : "Final year — the audit runs at the end"} href="/student/graduation" />
        ) : (
          <Quick icon="doc" title="Transcript" sub="Request an official copy" href="/student/transcript" />
        )}
        <Quick icon="cal" title="Deferment" sub={s.status === "DEFERRED" ? "Deferment active — see your return" : "Defer a semester or session"} href="/student/deferment" />
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

const pwToggle: CSSProperties = { position: "absolute", right: "var(--s-2)", top: "50%", transform: "translateY(-50%)", background: "none", border: 0, color: "var(--chrome)", fontSize: "var(--t-sm)", fontWeight: 700, cursor: "pointer", padding: "var(--s-1)" };

export function Profile({ s, change }: { s: Me; change: boolean }) {
  const { act, busy, problem } = useAct();
  const [phone, setPhone] = useState(s.contact.phone ?? s.contact.reach_phone ?? "");
  const [email, setEmail] = useState(s.contact.email ?? s.contact.reach_email ?? "");
  const [address, setAddress] = useState(s.contact.address ?? "");
  const [cur, setCur] = useState("");
  const [next, setNext] = useState("");
  const [saidPw, setSaidPw] = useState(false);
  const [showCur, setShowCur] = useState(false);
  const [showNext, setShowNext] = useState(false);
  const [errFor, setErrFor] = useState<string | null>(null);
  return (
    <>
      {change ? <Note kind="bad" title="Choose your own password before you go on">The Registry gave you a first password. Change it below; it is yours alone from then on.</Note> : null}
      <div className="card"><div className="card__body row row--top" style={{ flexDirection: "row", gap: "var(--s-5)" }}>
        <Passport w={112} h={139} radius={5} src={s.hasPhoto ? `/api/bff/api/v1/me/passport?v=${encodeURIComponent(s.matricNo ?? s.admissionNo ?? s.id)}` : null} />
        <div className="stack grow" style={{ minWidth: 230 }}>
          <div><div className="phead__t">{s.name}</div>
            <div className="sub2 tnum">{s.matricNo ?? s.admissionNo} &middot; {s.programme} &middot; {s.level} Level</div></div>
          <div className="row">
            <span className={`pill ${s.status === "ACTIVE" ? "pill--ok" : "pill--info"}`}><span className="dot" style={{ background: "var(--green)" }} />{s.status.charAt(0) + s.status.slice(1).toLowerCase()}</span>
            <Pil kind={s.hasPhoto ? "info" : "grey"}>{s.hasPhoto ? "Photograph on file" : "No photograph on file"}</Pil>
          </div>
          <div className="sub2" style={{ maxWidth: "52ch", lineHeight: 1.55 }}>{s.hasPhoto ? "This is the photograph on your record. It is the one printed on your identity card and shown to the invigilator, so it must remain a true likeness." : "No photograph reached the register with you. The Registry captures one at matriculation."}</div>
          <div className="sub2">A change needs Registry approval &mdash; students cannot replace it themselves after matriculation.</div>
        </div>
      </div></div>
      <div className="grid grid--2">
        <Panel title="You can change these"><PBody>
          <Field id="ph" label="Phone"><input id="ph" value={phone} onChange={(e) => setPhone(e.target.value)} autoComplete="off" /></Field>
          <Field id="em" label="Personal email"><input id="em" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="off" /></Field>
          <Field id="ad" label="Contact address"><input id="ad" value={address} onChange={(e) => setAddress(e.target.value)} autoComplete="off" /></Field>
          <Btn kind="primary" disabled={busy !== null} onClick={async () => { const r = await act("contact", "PUT", "/me/contact", { phone, email, address }, "Contact details changed by the student", "Contact details saved"); setErrFor(r ? null : "contact"); }}>{busy === "contact" ? "Saving…" : "Save changes"}</Btn>
          {problem && errFor === "contact" ? <ProblemNotice problem={problem} /> : null}
          <div className="hr" />
          <div className="b600">Password</div>
          <Field id="pw0" label="Current password">
            <div style={{ position: "relative" }}>
              <input id="pw0" type={showCur ? "text" : "password"} value={cur} onChange={(e) => setCur(e.target.value)} autoComplete="current-password" style={{ paddingRight: 62 }} />
              <button type="button" aria-label={showCur ? "Hide password" : "Show password"} onClick={() => setShowCur((v) => !v)} style={pwToggle}>{showCur ? "Hide" : "Show"}</button>
            </div>
          </Field>
          <Field id="pw1" label="New password" hint="Eight characters at the very least.">
            <div style={{ position: "relative" }}>
              <input id="pw1" type={showNext ? "text" : "password"} value={next} onChange={(e) => setNext(e.target.value)} autoComplete="new-password" style={{ paddingRight: 62 }} />
              <button type="button" aria-label={showNext ? "Hide password" : "Show password"} onClick={() => setShowNext((v) => !v)} style={pwToggle}>{showNext ? "Hide" : "Show"}</button>
            </div>
          </Field>
          <Btn kind="ghost" disabled={busy !== null || !cur || next.length < 8} onClick={async () => { const ok = await act("pw", "POST", "/student-auth/change-password", { current: cur, next }, "Password changed by the student", "Password changed"); if (ok) { setSaidPw(true); setCur(""); setNext(""); setErrFor(null); } else { setErrFor("pw"); } }}>{busy === "pw" ? "Changing…" : "Change the password"}</Btn>
          {saidPw ? <Note kind="ok" title="Password changed">Sign in with the new one from now on.</Note> : null}
          {problem && errFor === "pw" ? <ProblemNotice problem={problem} /> : null}
        </PBody></Panel>
        <Panel title="Only Registry can change these"><PBody>
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
          <div className="sub2 mt-1">Your curriculum version was fixed when you were admitted, so you are always assessed against the rules that applied then. To change a name or programme, apply through Registry with supporting documents.</div>
        </PBody></Panel>
      </div>
    </>
  );
}

export function fmtSemester(g: { session: string; semester: number }): string {
  return `${g.session} · ${semesterName(g.semester)}`;
}
