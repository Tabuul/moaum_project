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
import type { Me, RegistrationView } from "@/lib/student-portal";
import { semesterName, semesterText } from "@/lib/student-portal";
import { Btn, Ico, LinkBtn, Note, Panel, PBody, Pil, Tick } from "@/components/proto/ui";
import { Gate, Gates, Passport, Row } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { naira, onDay, useAct } from "./common";

/** the academic type shown on the form: GST, Elective or Core (Core/Required → Core).
 *  Prefer the per-programme offer basis (an elective borrowed from another department that owns
 *  it as Core is still an Elective here); fall back to the course's global kind. */
function courseType(e: { kind?: string; basis?: string; entryType?: string }): string {
  const b = (e.basis ?? "").toLowerCase();
  if (b === "gst") return "GST";
  if (b === "elective") return "Elective";
  if (b === "core" || b === "compulsory" || b === "required") return "Core";
  const k = (e.kind ?? "").toLowerCase();
  if (k === "gst") return "GST";
  if (k === "elective") return "Elective";
  if (k === "core" || k === "compulsory" || k === "required") return "Core";
  const t = (e.entryType ?? "").toUpperCase();
  if (t === "GST") return "GST";
  if (t === "ELECTIVE") return "Elective";
  return "Core";
}

/** display order: carryover first, then GST, then Core, then Elective */
function orderRank(e: { kind?: string; basis?: string; entryType?: string }): number {
  if ((e.entryType ?? "").toUpperCase() === "CARRYOVER") return 0;
  const t = courseType(e);
  return t === "GST" ? 1 : t === "Core" ? 2 : 3;
}
function byOrder<T extends { kind?: string; entryType?: string; courseCode?: string }>(rows: T[]): T[] {
  return [...rows].sort((a, b) => orderRank(a) - orderRank(b) || (a.courseCode ?? "").localeCompare(b.courseCode ?? ""));
}

export function Register({ s, v }: { s: Me; v: RegistrationView }) {
  const { act, busy, problem } = useAct();
  const reg = v.registration;
  const locked = !!reg && (reg.status === "SUBMITTED" || reg.status === "APPROVED" || reg.status === "LOCKED");
  const chosenNow = new Set((reg?.entries ?? []).filter((e) => e.entryType !== "CARRYOVER").map((e) => e.offeringId));
  const [chosen, setChosen] = useState<Set<string>>(chosenNow);
  const carry = v.menu.filter((m) => m.carryover);
  // Group by the PER-PROGRAMME offer basis, not the course's global kind: a course can be Core for
  // its own department yet Elective for this programme (course_offer.basis). Core/GST are required here;
  // everything else is an elective. GST (General Studies) is a University requirement.
  const core = v.menu.filter((m) => !m.carryover && (m.basis === "Core" || m.basis === "GST"));
  const elec = v.menu.filter((m) => !m.carryover && !core.includes(m));
  const total = carry.reduce((n, m) => n + m.units, 0) + core.filter((m) => chosen.has(m.offering_id)).reduce((n, m) => n + m.units, 0) + elec.filter((m) => chosen.has(m.offering_id)).reduce((n, m) => n + m.units, 0);
  const min = v.limit.min_units;
  const max = v.limit.max_units;
  const onProbation = !!v.probation && v.probation.standing === "PROBATION";
  const ok = total >= min && total <= max;
  const meter = total < min ? { col: "var(--red-ink)", bg: "var(--red-bg)", fg: "var(--red-deep)", lab: "Below minimum", hint: `You need at least ${min} credit units. Add ${min - total} more.` }
    : total > max ? { col: "var(--red)", bg: "var(--red-bg)", fg: "var(--red-ink)", lab: "Over limit", hint: onProbation && v.probation?.probation_max_units != null && max === v.probation.probation_max_units ? `On probation the maximum is ${max} units. Remove ${total - max}; the courses you owe stay.` : `Maximum is ${max} units. Remove ${total - max}, or request an overload from your HOD.` }
      : { col: "var(--green)", bg: "var(--green-bg)", fg: "var(--green-ink)", lab: "Valid", hint: `Within the permitted range for ${v.level} Level.` };

  const fees = v.fees;
  // gate on THIS semester's fees, not only the open one — a full-session payment clears an
  // earlier semester the student never registered, so they can go back and register it now
  const cleared = v.clears ?? (fees.clearsRegistration === true);

  // the student may register any semester up to the open one; an earlier semester never
  // registered can still be registered (its fees are covered by a full-session payment)
  const openSem = v.openSemester ?? v.semester;
  const done = new Set(v.registeredSemesters ?? []);
  const semName = (n: number) => (n === 1 ? "First" : n === 2 ? "Second" : "Third") + " semester";
  const missingEarlier = Array.from({ length: openSem }, (_, i) => i + 1).filter((n) => n < openSem && !done.has(n));
  const switcher = openSem > 1 ? (
    <div className="card"><div className="card__body row">
      <span className="eyebrow">Register semester</span>
      {Array.from({ length: openSem }, (_, i) => i + 1).map((n) => (
        <LinkBtn key={n} href={`/student/register?session=${encodeURIComponent(v.session)}&semester=${n}`}
          kind={n === v.semester ? "primary" : "ghost"}>
          {semName(n)}{done.has(n) ? <Ico name="check" size={14} /> : null}
        </LinkBtn>
      ))}
      {missingEarlier.length && !done.has(v.semester) && v.semester >= openSem ? (
        <span className="sub2 ink-red" style={{ flexBasis: "100%" }}>
          You have not registered {missingEarlier.map(semName).join(" or ")} yet — register {missingEarlier.length > 1 ? "them" : "it"} first, then this semester. Both semesters&rsquo; fees are cleared.
        </span>
      ) : null}
    </div></div>
  ) : null;

  if (!cleared && !locked) {
    return (
      <>
        {switcher}
        <Note kind="bad" title="You cannot register yet">One of the requirements below is outstanding. Clear it and registration opens immediately.</Note>
        <div className="card"><div className="card__body" style={{ gap: 0, padding: 0 }}>
          <Gates>
            <Gate state={["ADMITTED", "ACTIVE", "PROBATION"].includes(s.status) ? "done" : "todo"} title="Student status" sub={`${s.status.charAt(0) + s.status.slice(1).toLowerCase()} · ${s.level} Level`} />
            <Gate state="done" title="On the register" sub={`${s.matricNo ?? s.admissionNo} · entered ${s.entrySession}`} />
          </Gates>
          <div style={{ padding: "var(--s-4)", borderBottom: "1px solid var(--line-2)", background: "var(--red-wash)", display: "flex", gap: "var(--s-3)" }}>
            <div className="step__mark" style={{ background: "var(--red)" }}><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="3.4" strokeLinecap="round"><path d="M6 6l12 12M18 6 6 18" /></svg></div>
            <div className="grow stack">
              <div><div className="b600 ink-red">Financial clearance</div>
                <div className="t-sm mt-1">{fees.schemeProblem ? fees.schemeProblem : fees.due === 0 ? `No charge is stated for ${fees.session} yet, so nothing can be paid or released.` : fees.hasArrears ? "Arrears from an earlier session stand against you." : <>Outstanding balance of <strong className="tnum">{naira(fees.balance)}</strong> on the {fees.session} charge.</>}</div></div>
              {fees.due > 0 ? (
                <div className="stack" style={{ background: "var(--surface)", border: "1px solid var(--line)", borderRadius: "var(--r-md)", padding: "var(--s-3)" }}>
                  <Row k={<>School fees, {fees.session}</>} v={naira(fees.due)} />
                  <Row k="Paid" v={<>− {naira(fees.paid)}</>} colour="var(--green-ink)" />
                  <div className="hr" />
                  <div className="row row--between"><strong>Outstanding</strong><strong className="tnum t-md ink-red">{naira(fees.balance)}</strong></div>
                </div>
              ) : null}
              <div><LinkBtn kind="urgent" size="md" href="/student/fees">{fees.due > 0 ? `Pay ${naira(fees.balance)}` : "See fees & payments"}</LinkBtn></div>
              <div className="sub2">Responsible office: <strong style={{ color: "var(--ink)" }}>Bursary Department</strong>. Payments are confirmed against the bank&rsquo;s record, not by this page.</div>
            </div>
          </div>
          <Gates><Gate state="todo" title="Registration window" sub={`${v.session} · ${semesterText(v.semester)}`} last /></Gates>
        </div></div>
      </>
    );
  }

  const pick = (m: RegistrationView["menu"][number], fixed: boolean, on: boolean, red = false) => (
    <button type="button" key={m.offering_id} className="pick" data-on={on ? 1 : 0} disabled={fixed || locked}
      style={red ? { borderColor: "var(--red-line)", background: "var(--red-bg)" } : undefined}
      onClick={() => { if (fixed || locked) return; const n = new Set(chosen); if (n.has(m.offering_id)) n.delete(m.offering_id); else n.add(m.offering_id); setChosen(n); }}>
      <div className="pick__box" style={on ? { background: red ? "var(--red)" : "var(--chrome)", borderColor: red ? "var(--red)" : "var(--chrome)" } : undefined}>{on ? <Tick size={12} colour="#fff" /> : null}</div>
      <div className="grow"><div className="pick__t tnum">{m.course_code} — {m.title}</div>
        <div className="pick__s" style={red ? { color: "var(--red-deep)" } : undefined}>{m.carryover ? `Failed ${m.failed_in} — must be repeated` : m.basis === "Borrowed" ? `Owned by ${m.owner_dept} — open to this programme at ${v.level} level` : m.basis === "GST" ? "University requirement" : m.lecturer ? `${m.lecturer}` : "No lecturer allocated yet"}</div></div>
      {m.basis === "Borrowed" ? <Pil kind="info">{m.owner_dept}</Pil> : null}
      <div className="tnum b700" style={{ color: red ? "var(--red-ink)" : on ? "var(--chrome)" : "var(--muted)" }}>{m.units}</div>
    </button>
  );

  return (
    <>
      {switcher}
      {v.siwes ? (
        <Note kind="info" title="Industrial training (SIWES) semester">
          The whole of this semester is your industrial training. Register only the SIWES / industrial training course ({max} units) — nothing else, and no carryover. A carryover is registered when the course is next offered.
        </Note>
      ) : null}
      {locked ? (
        <Note kind={reg!.status === "APPROVED" || reg!.status === "LOCKED" ? "ok" : "info"} title={reg!.status === "APPROVED" || reg!.status === "LOCKED" ? `Approved on ${onDay(reg!.approved_at)}` : `Submitted on ${onDay(reg!.submitted_at)} — with your Head of Department`}
          action={reg!.status === "APPROVED" || reg!.status === "LOCKED" ? <LinkBtn kind="primary" href={`/student/form?session=${encodeURIComponent(v.session)}&semester=${v.semester}`}>Course form</LinkBtn> : null}>
          {reg!.units} units. {reg!.status === "SUBMITTED" ? "It goes to your Head of Department for approval; a return comes back here with the reason." : "The register carries these courses; the class lists and the score sheets are drawn from them."}
        </Note>
      ) : reg?.status === "RETURNED" ? (
        <Note kind="bad" title="Returned to you">
          {reg.returned_comment ? <><b>Your Head of Department&rsquo;s reason:</b> {reg.returned_comment}<br /></> : null}
          Change your registration and submit it again.
        </Note>
      ) : null}

      {locked && v.addDropOpen ? (() => {
        const activeIds = new Set((reg?.entries ?? []).filter((e) => e.status !== "DROPPED").map((e) => e.offeringId));
        const droppable = byOrder((reg?.entries ?? []).filter((e) => e.status !== "DROPPED" && e.entryType !== "CARRYOVER"));
        const addable = v.menu.filter((m) => !m.carryover && !activeIds.has(m.offering_id));
        return (
          <Panel title="Add or drop courses" right="the add/drop window is open">
            <PBody>
              {problem ? <ProblemNotice problem={problem} /> : null}
              <div className="sub2">You can still add a course or drop one (not a carryover, and not one you already have a mark in). The change is on the record at once; your total stays within {min}–{max} units.</div>
              {droppable.length ? (<>
                <div className="eyebrow mt-2">Registered — drop</div>
                {droppable.map((e) => (
                  <div key={e.offeringId} className="row" style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)" }}>
                    <span className="tnum b600" style={{ minWidth: 92 }}>{e.courseCode}</span>
                    <span className="grow">{e.title} <span className="sub2">· {e.units}u · {courseType(e)}</span></span>
                    <Btn kind="ghost" disabled={busy !== null} onClick={() => void act(`drop-${e.offeringId}`, "POST", "/me/registration/drop", { session: v.session, semester: v.semester, offering: e.offeringId }, `Dropped ${e.courseCode}`)}>{busy === `drop-${e.offeringId}` ? "Dropping…" : "Drop"}</Btn>
                  </div>
                ))}
              </>) : null}
              {addable.length ? (<>
                <div className="eyebrow mt-3">Offered — add</div>
                {addable.map((m) => (
                  <div key={m.offering_id} className="row" style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)" }}>
                    <span className="tnum b600" style={{ minWidth: 92 }}>{m.course_code}</span>
                    <span className="grow">{m.title} <span className="sub2">· {m.units}u · {m.lecturer ?? "no lecturer yet"}</span></span>
                    <Btn kind="primary" disabled={busy !== null} onClick={() => void act(`add-${m.offering_id}`, "POST", "/me/registration/add", { session: v.session, semester: v.semester, offering: m.offering_id }, `Added ${m.course_code}`)}>{busy === `add-${m.offering_id}` ? "Adding…" : "Add"}</Btn>
                  </div>
                ))}
              </>) : null}
              {!droppable.length && !addable.length ? <div className="sub2">Nothing to add or drop.</div> : null}
            </PBody>
          </Panel>
        );
      })() : null}

      <div className="card"><div className="card__body">
        <div className="meter">
          <div className="row row--base">
            <span className="tnum b700" style={{ fontSize: "var(--t-3xl)", letterSpacing: "-.6px", color: meter.col }}>{total}</span>
            <span className="ink-muted">of {min}–{max} credit units</span>
            <span className="grow" />
            <span className="pill" style={{ background: meter.bg, color: meter.fg }}>{meter.lab}</span>
          </div>
          <div className="meter__bar"><div className="meter__fill" style={{ width: `${Math.min(100, Math.round((total / max) * 100))}%`, background: meter.col }} /></div>
          <div className="sub2">{meter.hint}</div>
        </div>
      </div></div>
      {carry.length ? (
        <Panel title={<span className="ink-red">Outstanding carryovers</span>} right="added automatically, cannot be removed">
          <PBody>{carry.map((m) => pick(m, true, true, true))}</PBody></Panel>
      ) : null}
      <Panel title={`${v.level} Level Core Courses`}>
        <PBody>{core.length ? core.map((m) => pick(m, false, chosen.has(m.offering_id))) : <div className="sub2">No core course is offered to your programme this semester yet. Courses appear once the Registry opens registration for the session; a lecturer does not have to be allocated first, and you can register without one.</div>}</PBody></Panel>
      <Panel title="Electives" right={<>choose to reach {min}–{max} units</>}>
        <PBody>{elec.length ? elec.map((m) => pick(m, false, chosen.has(m.offering_id))) : <div className="sub2">No elective is open to your programme this semester.</div>}
          <p className="sub2" style={{ margin: "2px 0 0" }}>A course owned by another department is on your form because your programme and level were made eligible for it when it was created &mdash; you do not request it and nobody grants it to you. Register one and you appear on that lecturer&rsquo;s score sheet like any other candidate.</p></PBody></Panel>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!locked ? (
        <div className="row">
          <Btn kind="ghost" disabled={busy !== null} onClick={() => void act("save", "PUT", "/me/registration", { session: v.session, semester: v.semester, offerings: [...chosen] }, "Course registration saved by the student")}>{busy === "save" ? "Saving…" : "Save the draft"}</Btn>
          <Btn kind="primary" disabled={!ok || busy !== null} onClick={async () => { const saved = await act("save", "PUT", "/me/registration", { session: v.session, semester: v.semester, offerings: [...chosen] }, "Course registration saved by the student"); if (saved) await act("submit", "POST", "/me/registration/submit", { session: v.session, semester: v.semester }, "Course registration submitted by the student"); }}>{busy === "submit" ? "Submitting…" : "Submit for approval"}</Btn>
          <span className="sub2">Goes to your Head of Department for approval</span>
        </div>
      ) : null}
    </>
  );
}

/** print the branded course-form PDF (a proper print sheet) rather than window.print() of the web page,
 *  which the print stylesheet blanks. Loads the PDF in a hidden iframe and prints it; opens it if blocked. */
function printPdf(url: string) {
  const f = document.createElement("iframe");
  f.style.position = "fixed"; f.style.right = "0"; f.style.bottom = "0"; f.style.width = "0"; f.style.height = "0"; f.style.border = "0";
  f.src = url;
  f.onload = () => {
    try { f.contentWindow?.focus(); f.contentWindow?.print(); }
    catch { window.open(url, "_blank", "noopener"); }
    window.setTimeout(() => { try { document.body.removeChild(f); } catch { /* already gone */ } }, 60000);
  };
  document.body.appendChild(f);
}

export function Form({ s, v }: { s: Me; v: RegistrationView }) {
  const reg = v.registration;
  const pdfUrl = `/student/form/pdf?session=${encodeURIComponent(v.session)}&semester=${v.semester}`;
  if (!reg || !(reg.status === "APPROVED" || reg.status === "LOCKED")) {
    return (
      <Note kind="info" title="The course form is issued when your registration is approved" action={<LinkBtn kind="primary" href="/student/register">Course registration</LinkBtn>}>
        {reg ? `Your registration is ${reg.status.toLowerCase()}.` : "You have not registered for this semester yet."} The form prints what the Head of Department approved, and nothing else.
      </Note>
    );
  }
  return (
    <>
      <Note kind="ok" title={`Approved by your Head of Department on ${onDay(reg.approved_at)}`} />
      <div className="doc">
        <div className="doc__head">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 46, height: 48, objectFit: "contain" }} />
          <div className="u">REV. FR. MOSES ORSHIO ADASU<br />UNIVERSITY, MAKURDI</div>
          <div className="eyebrow">Course Registration Form</div>
        </div>
        <div className="row row--top" style={{ gap: "var(--s-5)", marginBottom: "var(--s-4)" }}>
          <Passport w={62} h={77} radius={3} src={s.hasPhoto ? `/api/bff/api/v1/me/passport?v=${encodeURIComponent(s.matricNo ?? s.admissionNo ?? s.id)}` : null} />
          <div className="kv"><span className="k">Name</span><span className="v">{s.name}</span></div>
          <div className="kv"><span className="k">Matriculation number</span><span className="v tnum">{s.matricNo ?? s.admissionNo}</span></div>
          <div className="kv"><span className="k">Level</span><span className="v">{reg.level}</span></div>
          <div className="kv"><span className="k">Session</span><span className="v tnum">{v.session}</span></div>
          <div className="kv"><span className="k">Semester</span><span className="v">{semesterName(v.semester)}</span></div>
        </div>
        <div className="tablewrap"><table className="tbl--data" style={{ minWidth: 520 }}>
          <thead><tr>
            {["Course code", "Course title", "Lecturer"].map((h) => <th key={h} style={{ background: "var(--chrome)", color: "var(--surface)" }}>{h}</th>)}
            <th className="mid" style={{ background: "var(--chrome)", color: "var(--surface)" }}>Unit</th>
            <th className="num" style={{ background: "var(--chrome)", color: "var(--surface)" }}>Type</th>
          </tr></thead>
          <tbody>
            {byOrder(reg.entries).map((e) => { const co = e.entryType === "CARRYOVER"; return (
              <tr key={e.offeringId}>
                <td className="tnum b600">{e.courseCode}{co ? <span className="ink-red b700"> · C/O</span> : null}</td>
                <td>{e.title}</td>
                <td className="sub2">{e.lecturer ?? "—"}</td>
                <td className="mid tnum">{e.units}</td>
                <td className="num t-xs b600 ink-muted">{courseType(e)}</td>
              </tr>); })}
            <tr style={{ background: "var(--bg)" }}><td className="b700" colSpan={3}>TOTAL CREDIT UNITS</td><td className="mid tnum b700" style={{ fontSize: "var(--t-base)" }}>{reg.units}</td><td /></tr>
          </tbody>
        </table></div>
        <div className="row mt-4">
          <div className="kv"><span className="k">Verification</span><span className="v tnum" style={{ letterSpacing: ".5px" }}>{reg.id.slice(0, 8).toUpperCase()}</span></div>
        </div>
      </div>
      <div className="row">
        <a href={pdfUrl} target="_blank" rel="noopener" className="btn btn--primary">Download PDF</a>
        <Btn kind="ghost" onClick={() => printPdf(pdfUrl)}>Print</Btn>
      </div>
    </>
  );
}
