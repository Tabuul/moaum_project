"use client";

/**
 * Course registration and the course form — proto/part3.html
 * studentRegister and registrationBlocked, proto/part4.html studentForm, as
 * drawn — against the register: the eligible set for the programme and
 * level, the carryovers added because a published F says so, the units
 * meter under the level's range, the Bursary's gate, and the form once the
 * Head of Department has approved.
 */
import { useState } from "react";
import Link from "next/link";
import type { Me, RegistrationView } from "@/lib/student-portal";
import { Btn, Note, Pil, Tick, WarnIcon } from "@/components/proto/ui";
import { Gate, Gates, Passport } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { naira, onDay, useAct } from "./common";

/** the academic type shown on the form: GST, Elective or Core (Compulsory/Required → Core) */
function courseType(e: { kind?: string; entryType?: string }): string {
  const k = (e.kind ?? "").toLowerCase();
  if (k === "gst") return "GST";
  if (k === "elective") return "Elective";
  if (k === "compulsory" || k === "required") return "Core";
  const t = (e.entryType ?? "").toUpperCase();
  if (t === "GST") return "GST";
  if (t === "ELECTIVE") return "Elective";
  return "Core";
}

export function Register({ s, v }: { s: Me; v: RegistrationView }) {
  const { act, busy, problem } = useAct();
  const reg = v.registration;
  const locked = !!reg && (reg.status === "SUBMITTED" || reg.status === "APPROVED" || reg.status === "LOCKED");
  const chosenNow = new Set((reg?.entries ?? []).filter((e) => e.entryType !== "CARRYOVER").map((e) => e.offeringId));
  const [chosen, setChosen] = useState<Set<string>>(chosenNow);
  const carry = v.menu.filter((m) => m.carryover);
  const core = v.menu.filter((m) => !m.carryover && (m.kind === "Compulsory" || m.kind === "Required" || m.basis === "Core"));
  const elec = v.menu.filter((m) => !m.carryover && !core.includes(m));
  const total = carry.reduce((n, m) => n + m.units, 0) + core.filter((m) => chosen.has(m.offering_id)).reduce((n, m) => n + m.units, 0) + elec.filter((m) => chosen.has(m.offering_id)).reduce((n, m) => n + m.units, 0);
  const min = v.limit.min_units;
  const max = v.limit.max_units;
  const ok = total >= min && total <= max;
  const meter = total < min ? { col: "var(--red-ink)", bg: "var(--red-bg)", fg: "var(--red-deep)", lab: "Below minimum", hint: `You need at least ${min} credit units. Add ${min - total} more.` }
    : total > max ? { col: "var(--red)", bg: "var(--red-bg)", fg: "var(--red-ink)", lab: "Over limit", hint: `Maximum is ${max} units. Remove ${total - max}, or request an overload from your HOD.` }
      : { col: "var(--green)", bg: "var(--green-bg)", fg: "var(--green-ink)", lab: "Valid", hint: `Within the permitted range for ${v.level} Level.` };

  const fees = v.fees;
  const cleared = fees.clearsRegistration === true;

  if (!cleared && !locked) {
    return (
      <>
        <div className="notice notice--bad"><WarnIcon size={19} /><div><div className="notice__t" style={{ color: "var(--red-deep)" }}>You cannot register yet</div>
          <p style={{ color: "var(--red-deep)" }}>One of the requirements below is outstanding. Clear it and registration opens immediately.</p></div></div>
        <div className="card"><div className="card__body" style={{ gap: 0, padding: 0 }}>
          <Gates>
            <Gate state={["ADMITTED", "ACTIVE", "PROBATION"].includes(s.status) ? "done" : "todo"} title="Student status" sub={`${s.status.charAt(0) + s.status.slice(1).toLowerCase()} · ${s.level} Level`} />
            <Gate state="done" title="On the register" sub={`${s.matricNo ?? s.admissionNo} · entered ${s.entrySession}`} />
          </Gates>
          <div style={{ padding: 16, borderBottom: "1px solid var(--line-2)", background: "var(--red-wash)", display: "flex", gap: 12 }}>
            <div className="step__mark" style={{ background: "var(--red)" }}><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="3.4" strokeLinecap="round"><path d="M6 6l12 12M18 6 6 18" /></svg></div>
            <div style={{ flexGrow: 1, display: "flex", flexDirection: "column", gap: 11 }}>
              <div><div style={{ fontWeight: 600, color: "var(--red-ink)" }}>Financial clearance</div>
                <div style={{ fontSize: 13, marginTop: 3 }}>{fees.schemeProblem ? fees.schemeProblem : fees.due === 0 ? `No charge is stated for ${fees.session} yet, so nothing can be paid or released.` : fees.hasArrears ? "Arrears from an earlier session stand against you." : <>Outstanding balance of <strong className="tnum">{naira(fees.balance)}</strong> on the {fees.session} charge.</>}</div></div>
              {fees.due > 0 ? (
                <div style={{ background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 8, padding: 12, display: "flex", flexDirection: "column", gap: 7 }}>
                  <div style={{ display: "flex", justifyContent: "space-between" }}><span className="sub2">School fees, {fees.session}</span><span className="tnum" style={{ fontWeight: 600, fontSize: 12.5 }}>{naira(fees.due)}</span></div>
                  <div style={{ display: "flex", justifyContent: "space-between" }}><span className="sub2">Paid</span><span className="tnum" style={{ fontWeight: 600, fontSize: 12.5, color: "var(--green-ink)" }}>− {naira(fees.paid)}</span></div>
                  <div style={{ height: 1, background: "var(--line-2)" }} />
                  <div style={{ display: "flex", justifyContent: "space-between" }}><strong>Outstanding</strong><strong className="tnum" style={{ fontSize: 15, color: "var(--red-ink)" }}>{naira(fees.balance)}</strong></div>
                </div>
              ) : null}
              <div><Link href="/student/fees" className="btn btn--urgent">{fees.due > 0 ? `Pay towards ${naira(fees.balance)}` : "See fees & payments"}</Link></div>
              <div className="sub2">Responsible office: <strong style={{ color: "var(--ink)" }}>Bursary Department</strong>. Payments are confirmed against the bank&rsquo;s record, not by this page.</div>
            </div>
          </div>
          <Gates><Gate state="todo" title="Registration window" sub={`${v.session} · semester ${v.semester}`} last /></Gates>
        </div></div>
      </>
    );
  }

  const pick = (m: RegistrationView["menu"][number], fixed: boolean, on: boolean, red = false) => (
    <button type="button" key={m.offering_id} className="pick" data-on={on ? 1 : 0} disabled={fixed || locked}
      style={red ? { borderColor: "var(--red-line)", background: "var(--red-bg)" } : undefined}
      onClick={() => { if (fixed || locked) return; const n = new Set(chosen); if (n.has(m.offering_id)) n.delete(m.offering_id); else n.add(m.offering_id); setChosen(n); }}>
      <div className="pick__box" style={on ? { background: red ? "var(--red)" : "var(--chrome)", borderColor: red ? "var(--red)" : "var(--chrome)" } : undefined}>{on ? <Tick size={12} colour="#fff" /> : null}</div>
      <div style={{ flexGrow: 1 }}><div className="pick__t tnum">{m.course_code} — {m.title}</div>
        <div className="pick__s" style={red ? { color: "var(--red-deep)" } : undefined}>{m.carryover ? `Failed ${m.failed_in} — must be repeated` : m.basis === "Borrowed" ? `Owned by ${m.owner_dept} — open to this programme at ${v.level} level` : m.kind === "GST" ? "University requirement" : m.lecturer ? `${m.lecturer}` : "No lecturer allocated yet"}</div></div>
      {m.basis === "Borrowed" ? <Pil kind="info">{m.owner_dept}</Pil> : null}
      <div className="tnum" style={{ fontWeight: 700, color: red ? "var(--red-ink)" : on ? "var(--chrome)" : "var(--muted)" }}>{m.units}</div>
    </button>
  );

  return (
    <>
      {locked ? (
        <Note kind={reg!.status === "APPROVED" || reg!.status === "LOCKED" ? "ok" : "info"} title={reg!.status === "APPROVED" || reg!.status === "LOCKED" ? `Approved on ${onDay(reg!.approved_at)}` : `Submitted on ${onDay(reg!.submitted_at)} — with your Level Adviser`}
          action={reg!.status === "APPROVED" || reg!.status === "LOCKED" ? <Link href="/student/form" className="btn btn--primary btn--sm">Course form</Link> : null}>
          {reg!.units} units. {reg!.status === "SUBMITTED" ? "It goes to your Level Adviser, then your HOD; a return comes back here with the reason." : "The register carries these courses; the class lists and the score sheets are drawn from them."}
        </Note>
      ) : reg?.status === "RETURNED" ? (
        <Note kind="bad" title="Returned to you">Your Level Adviser returned this registration. Change it and submit again.</Note>
      ) : null}
      <div className="card"><div className="card__body">
        <div className="meter">
          <div style={{ display: "flex", alignItems: "baseline", gap: 9, flexWrap: "wrap" }}>
            <span className="tnum" style={{ fontSize: 27, fontWeight: 700, letterSpacing: "-.6px", color: meter.col }}>{total}</span>
            <span style={{ color: "var(--muted)" }}>of {min}–{max} credit units</span>
            <span style={{ flexGrow: 1 }} />
            <span className="pill" style={{ background: meter.bg, color: meter.fg }}>{meter.lab}</span>
          </div>
          <div className="meter__bar"><div className="meter__fill" style={{ width: `${Math.min(100, Math.round((total / max) * 100))}%`, background: meter.col }} /></div>
          <div className="sub2">{meter.hint}</div>
        </div>
      </div></div>
      {carry.length ? (
        <div className="card"><div className="card__head"><span className="card__title" style={{ color: "var(--red-ink)" }}>Outstanding carryovers</span><span className="sub2">added automatically, cannot be removed</span></div>
          <div className="card__body">{carry.map((m) => pick(m, true, true, true))}</div></div>
      ) : null}
      <div className="card"><div className="card__head"><span className="card__title">{v.level} Level compulsory</span></div>
        <div className="card__body">{core.length ? core.map((m) => pick(m, false, chosen.has(m.offering_id))) : <div className="sub2">No compulsory course is offered to your programme this semester yet. Courses appear once the Registry opens registration for the session; a lecturer does not have to be allocated first, and you can register without one.</div>}</div></div>
      <div className="card"><div className="card__head"><span className="card__title">Electives</span><span className="sub2">choose to reach {min}–{max} units</span></div>
        <div className="card__body">{elec.length ? elec.map((m) => pick(m, false, chosen.has(m.offering_id))) : <div className="sub2">No elective is open to your programme this semester.</div>}
          <p className="sub2" style={{ margin: "2px 0 0" }}>A course owned by another department is on your form because your programme and level were made eligible for it when it was created &mdash; you do not request it and nobody grants it to you. Register one and you appear on that lecturer&rsquo;s score sheet like any other candidate.</p></div></div>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!locked ? (
        <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
          <Btn kind="ghost" disabled={busy !== null} onClick={() => void act("save", "PUT", "/me/registration", { session: v.session, semester: v.semester, offerings: [...chosen] }, "Course registration saved by the student")}>{busy === "save" ? "Saving…" : "Save the draft"}</Btn>
          <Btn kind="primary" disabled={!ok || busy !== null} onClick={async () => { const saved = await act("save", "PUT", "/me/registration", { session: v.session, semester: v.semester, offerings: [...chosen] }, "Course registration saved by the student"); if (saved) await act("submit", "POST", "/me/registration/submit", { session: v.session, semester: v.semester }, "Course registration submitted by the student"); }}>{busy === "submit" ? "Submitting…" : "Submit for approval"}</Btn>
          <span className="sub2">Goes to your Level Adviser, then your HOD</span>
        </div>
      ) : null}
    </>
  );
}

export function Form({ s, v }: { s: Me; v: RegistrationView }) {
  const reg = v.registration;
  if (!reg || !(reg.status === "APPROVED" || reg.status === "LOCKED")) {
    return (
      <Note kind="info" title="The course form is issued when your registration is approved" action={<Link href="/student/register" className="btn btn--primary btn--sm">Course registration</Link>}>
        {reg ? `Your registration is ${reg.status.toLowerCase()}.` : "You have not registered for this semester yet."} The form prints what the Head of Department approved, and nothing else.
      </Note>
    );
  }
  return (
    <>
      <div className="notice notice--ok"><Tick size={18} colour="var(--green-ink)" /><div><p style={{ color: "var(--green-ink)", fontWeight: 600 }}>Approved by your Head of Department on {onDay(reg.approved_at)}</p></div></div>
      <div className="doc">
        <div className="doc__head">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 46, height: 48, objectFit: "contain" }} />
          <div className="u">REV. FR. MOSES ORSHIO ADASU<br />UNIVERSITY, MAKURDI</div>
          <div className="eyebrow">Course Registration Form</div>
        </div>
        <div style={{ display: "flex", gap: 18, flexWrap: "wrap", marginBottom: 16, alignItems: "flex-start" }}>
          <Passport w={62} h={77} radius={3} src={s.passportDocumentId ? `/api/bff/api/v1/applicant/me/documents/${s.passportDocumentId}/content` : null} />
          <div className="kv"><span className="k">Name</span><span className="v">{s.name}</span></div>
          <div className="kv"><span className="k">Matriculation number</span><span className="v tnum">{s.matricNo ?? s.admissionNo}</span></div>
          <div className="kv"><span className="k">Level</span><span className="v">{reg.level}</span></div>
          <div className="kv"><span className="k">Session</span><span className="v tnum">{v.session} · semester {v.semester}</span></div>
        </div>
        <div className="tablewrap"><table style={{ minWidth: 520 }}>
          <thead><tr>
            {["Course code", "Course title", "Lecturer"].map((h) => <th key={h} style={{ background: "var(--chrome)", color: "#fff" }}>{h}</th>)}
            <th className="mid" style={{ background: "var(--chrome)", color: "#fff" }}>Unit</th>
            <th className="num" style={{ background: "var(--chrome)", color: "#fff" }}>Type</th>
          </tr></thead>
          <tbody>
            {reg.entries.map((e) => { const co = e.entryType === "CARRYOVER"; return (
              <tr key={e.offeringId}>
                <td className="tnum" style={{ fontWeight: 600 }}>{e.courseCode}{co ? <span style={{ color: "var(--red-ink)", fontWeight: 700 }}> · C/O</span> : null}</td>
                <td>{e.title}</td>
                <td className="sub2">{e.lecturer ?? "—"}</td>
                <td className="mid tnum">{e.units}</td>
                <td className="num" style={{ fontSize: 11, fontWeight: 600, color: "var(--muted)" }}>{courseType(e)}</td>
              </tr>); })}
            <tr style={{ background: "var(--bg)" }}><td style={{ fontWeight: 700 }} colSpan={3}>TOTAL CREDIT UNITS</td><td className="mid tnum" style={{ fontWeight: 700, fontSize: 14 }}>{reg.units}</td><td /></tr>
          </tbody>
        </table></div>
        <div style={{ display: "flex", gap: 16, alignItems: "center", marginTop: 18, flexWrap: "wrap" }}>
          <div className="kv"><span className="k">Verification</span><span className="v tnum" style={{ letterSpacing: ".5px" }}>{reg.id.slice(0, 8).toUpperCase()}</span><span className="sub2">The register is the thing; this form is a view of it</span></div>
        </div>
      </div>
      <div style={{ display: "flex", gap: 9, flexWrap: "wrap" }}>
        <a href={`/student/form/pdf?session=${encodeURIComponent(v.session)}&semester=${v.semester}`} target="_blank" rel="noopener" className="btn btn--primary">Download PDF</a>
        <Btn kind="ghost" onClick={() => window.print()}>Print</Btn>
      </div>
    </>
  );
}
