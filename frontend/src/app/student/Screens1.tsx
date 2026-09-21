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
import { Btn, Ico, KvGrid, Note, Panel, PBody, Pil, Tick, Two, WarnIcon } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Passport, Step } from "@/components/proto/blocks";
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
        <div style={{ display: "flex", gap: 18, alignItems: "flex-start", flexWrap: "wrap" }}>
          <Passport w={104} h={128} radius={6} src={s.hasPhoto ? `/api/bff/api/v1/me/passport?v=${encodeURIComponent(s.matricNo ?? s.admissionNo ?? s.id)}` : null} />
          <div style={{ flexGrow: 1, minWidth: 240 }}>
            <div style={{ fontSize: 20, fontWeight: 700, letterSpacing: "-.3px" }}>{s.name}</div>
            <div className="sub2 tnum" style={{ marginTop: 2 }}>{s.matricNo ?? s.admissionNo}</div>
            <div className="sub2" style={{ marginTop: 2 }}>{s.programme} &middot; {s.department}</div>
            <div className="sub2">{s.faculty}</div>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 10 }}>
              <span className={`pill ${s.status === "ACTIVE" ? "pill--ok" : "pill--info"}`}><span className="dot" style={{ background: s.status === "ACTIVE" ? "var(--green)" : "var(--chrome)" }} />{s.status.charAt(0) + s.status.slice(1).toLowerCase()}</span>
              <Pil kind="info">{s.level} Level</Pil>
              <Pil kind="grey">{s.entryMode} · {s.entrySession}</Pil>
            </div>
            <div style={{ marginTop: 12, display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: "2px 18px" }}>
              {([["Matriculation number", s.matricNo], ["Admission number", s.admissionNo], jamb ? ["JAMB registration number", jamb] : null, ["CGPA", s.cgpa != null ? String(s.cgpa) : null]].filter(Boolean) as [string, string | null][]).map(([k, val]) => val ? (
                <div key={k} className="kv"><span className="k">{k}</span><span className="v tnum">{val}</span></div>
              ) : null)}
            </div>
          </div>
        </div>

        {loading ? <div className="sub2" style={{ marginTop: 14 }}>Loading your details…</div> : null}
        {/* one uniform column track for every section, so the columns line up down the whole card and a
            section with two fields reads as tidily as one with eight (auto-fill packs left, never stretches) */}
        {sections.map((sec, si) => (
          <div key={sec.title} style={{ marginTop: si ? 18 : 20, paddingTop: si ? 16 : 0, borderTop: si ? "1px solid var(--line-2)" : undefined }}>
            <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: ".08em", textTransform: "uppercase", color: "var(--muted)", marginBottom: 12 }}>{sec.title}</div>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(240px, 1fr))", columnGap: 32, rowGap: 16, maxWidth: 1160 }}>
              {sec.pairs.map(([k, val], i) => (
                <div key={i} style={{ display: "flex", flexDirection: "column", gap: 4, minWidth: 0 }}>
                  <span style={{ fontSize: 10, fontWeight: 600, letterSpacing: ".07em", textTransform: "uppercase", color: "var(--faint)" }}>{k}</span>
                  <span style={{ fontSize: 13.5, fontWeight: 600, lineHeight: 1.4, overflowWrap: "anywhere" }}>{val}</span>
                </div>
              ))}
            </div>
          </div>
        ))}
        <div className="sub2" style={{ marginTop: 14 }}>
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
            <Passport w={52} h={64} radius={6} src={s.hasPhoto ? `/api/bff/api/v1/me/passport?v=${encodeURIComponent(s.matricNo ?? s.admissionNo ?? s.id)}` : null} />
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

      <StudentDetails s={s} />

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

const pwToggle: CSSProperties = { position: "absolute", right: 8, top: "50%", transform: "translateY(-50%)", background: "none", border: 0, color: "var(--chrome, #0e3f55)", fontSize: 12, fontWeight: 700, cursor: "pointer", padding: 4 };

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
      <div className="card"><div className="card__body" style={{ flexDirection: "row", gap: 20, alignItems: "flex-start", flexWrap: "wrap" }}>
        <Passport w={112} h={139} radius={5} src={s.hasPhoto ? `/api/bff/api/v1/me/passport?v=${encodeURIComponent(s.matricNo ?? s.admissionNo ?? s.id)}` : null} />
        <div style={{ display: "flex", flexDirection: "column", gap: 9, flexGrow: 1, minWidth: 230 }}>
          <div><div style={{ fontSize: 19, fontWeight: 700, letterSpacing: "-.3px" }}>{s.name}</div>
            <div className="sub2 tnum">{s.matricNo ?? s.admissionNo} &middot; {s.programme} &middot; {s.level} Level</div></div>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <span className={`pill ${s.status === "ACTIVE" ? "pill--ok" : "pill--info"}`}><span className="dot" style={{ background: "var(--green)" }} />{s.status.charAt(0) + s.status.slice(1).toLowerCase()}</span>
            <Pil kind={s.hasPhoto ? "info" : "grey"}>{s.hasPhoto ? "Photograph on file" : "No photograph on file"}</Pil>
          </div>
          <div className="sub2" style={{ maxWidth: "52ch", lineHeight: 1.55 }}>{s.hasPhoto ? "This is the photograph on your record. It is the one printed on your identity card and shown to the invigilator, so it must remain a true likeness." : "No photograph reached the register with you. The Registry captures one at matriculation."}</div>
          <div className="sub2">A change needs Registry approval &mdash; students cannot replace it themselves after matriculation.</div>
        </div>
      </div></div>
      <div className="grid grid--2">
        <div className="card"><div className="card__head"><span className="card__title">You can change these</span></div><div className="card__body">
          <div className="field"><label htmlFor="ph">Phone</label><input id="ph" value={phone} onChange={(e) => setPhone(e.target.value)} autoComplete="off" /></div>
          <div className="field"><label htmlFor="em">Personal email</label><input id="em" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="off" /></div>
          <div className="field"><label htmlFor="ad">Contact address</label><input id="ad" value={address} onChange={(e) => setAddress(e.target.value)} autoComplete="off" /></div>
          <Btn kind="primary" disabled={busy !== null} onClick={async () => { const r = await act("contact", "PUT", "/me/contact", { phone, email, address }, "Contact details changed by the student", "Contact details saved"); setErrFor(r ? null : "contact"); }}>{busy === "contact" ? "Saving…" : "Save changes"}</Btn>
          {problem && errFor === "contact" ? <ProblemNotice problem={problem} /> : null}
          <div style={{ height: 1, background: "var(--line-2)" }} />
          <div style={{ fontWeight: 600 }}>Password</div>
          <div className="field"><label htmlFor="pw0">Current password</label>
            <div style={{ position: "relative" }}>
              <input id="pw0" type={showCur ? "text" : "password"} value={cur} onChange={(e) => setCur(e.target.value)} autoComplete="current-password" style={{ paddingRight: 62 }} />
              <button type="button" aria-label={showCur ? "Hide password" : "Show password"} onClick={() => setShowCur((v) => !v)} style={pwToggle}>{showCur ? "Hide" : "Show"}</button>
            </div>
          </div>
          <div className="field"><label htmlFor="pw1">New password</label>
            <div style={{ position: "relative" }}>
              <input id="pw1" type={showNext ? "text" : "password"} value={next} onChange={(e) => setNext(e.target.value)} autoComplete="new-password" style={{ paddingRight: 62 }} />
              <button type="button" aria-label={showNext ? "Hide password" : "Show password"} onClick={() => setShowNext((v) => !v)} style={pwToggle}>{showNext ? "Hide" : "Show"}</button>
            </div>
            <div className="hint">Eight characters at the very least.</div>
          </div>
          <Btn kind="ghost" disabled={busy !== null || !cur || next.length < 8} onClick={async () => { const ok = await act("pw", "POST", "/student-auth/change-password", { current: cur, next }, "Password changed by the student", "Password changed"); if (ok) { setSaidPw(true); setCur(""); setNext(""); setErrFor(null); } else { setErrFor("pw"); } }}>{busy === "pw" ? "Changing…" : "Change the password"}</Btn>
          {saidPw ? <Note kind="ok" title="Password changed">Sign in with the new one from now on.</Note> : null}
          {problem && errFor === "pw" ? <ProblemNotice problem={problem} /> : null}
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
