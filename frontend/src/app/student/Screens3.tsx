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
import { Gate, Gates, Modal, Passport, Row } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { notify } from "@/components/proto/Toast";
import { reasonWords } from "@/lib/registration-approval";
import { ProblemNotice } from "@/components/ProblemNotice";
import { naira, onDay, useAct } from "./common";
import { CATEGORY_LABEL, addedAsLabel, categoryWords, courseCategory, gstOffice, inUniversityOrder, type Categorised } from "@/lib/course-order";
import { loadKind, loadSummary, minimumBinds, waivedWords, type LoadKind } from "@/lib/registration-load";
import { AddOtherCourse } from "./AddOtherCourse";
import { OverloadRequest } from "./OverloadRequest";

/** the academic type shown on the form: GST, Elective or Core (Core/Required → Core).
 *  Prefer the per-programme offer basis (an elective borrowed from another department that owns
 *  it as Core is still an Elective here); fall back to the course's global kind. */
function courseType(e: { kind?: string; basis?: string; entryType?: string }): string {
  const b = (e.basis ?? "").toLowerCase();
  if (b === "gst") return "GST";
  if (b === "elective") return "Elective";
  if (b === "core" || b === "compulsory" || b === "required") return "Core";
  // V389: a postgraduate programme's research course and deficiency course (the latter earns no credit)
  if (b === "research") return "Research";
  if (b === "deficiency") return "Deficiency";
  const k = (e.kind ?? "").toLowerCase();
  if (k === "gst") return "GST";
  if (k === "elective") return "Elective";
  if (k === "core" || k === "compulsory" || k === "required") return "Core";
  const t = (e.entryType ?? "").toUpperCase();
  if (t === "GST") return "GST";
  if (t === "ELECTIVE") return "Elective";
  return "Core";
}

/** V504: the University's order — carry-over (and deferred), then GST, then core, then elective — as the server sends it
 *  (registration.entry_rank); lib/course-order keeps the server's order within a category */
function byOrder<T extends Categorised>(rows: T[]): T[] {
  return inUniversityOrder(rows);
}

export function Register({ s, v }: { s: Me; v: RegistrationView }) {
  // V602: a graduated record registers nothing — the server sends no menu and says why; the registration of the semester, if any, is history
  if (v.closed) {
    return <RegisterClosed v={v} />;
  }
  return <RegisterForm s={s} v={v} />;
}

function RegisterClosed({ v }: { v: RegistrationView }) {
  const reg = v.registration;
  return (
    <>
      <Note kind="info" title={v.closed!.code === "REG_STUDENT_GRADUATED" ? "You have graduated" : "Course registration is closed"}
        action={<div className="row"><LinkBtn kind="ghost" href="/student/graduation">Graduation & clearance</LinkBtn><LinkBtn kind="ghost" href="/student/registration-history">Registration history</LinkBtn></div>}>
        {v.closed!.words} {v.closed!.remedy}
      </Note>
      {reg ? (
        <Panel title={`Your registration for ${v.session}, ${v.semester === 1 ? "first" : v.semester === 2 ? "second" : "third"} semester`} right={`${reg.status} · ${reg.units} CU`}>
          <DTable cols={["Course code", "Course title", "Units|num", "Type"]} rows={(reg.entries ?? []).filter((e) => e.status !== "DROPPED").map((e) => [
            <b key="c">{e.courseCode}</b>, <span key="t">{e.title}</span>, <span key="u" className="tnum">{e.units}</span>, <span key="k">{e.entryType}</span>,
          ])} />
        </Panel>
      ) : null}
    </>
  );
}

function RegisterForm({ s, v }: { s: Me; v: RegistrationView }) {
  const { act, busy, problem } = useAct();
  const reg = v.registration;
  // V491: where the Head's approval is suspended, a registration that passes the rules is approved on submission
  const auto = v.approval?.mode === "AUTO_APPROVAL";
  const [askReset, setAskReset] = useState(false);
  const [adding, setAdding] = useState(false);
  // V611: the course finder opened on the student's carry-overs (those a published result states, and those declared)
  const [addingCarry, setAddingCarry] = useState(false);
  const locked = !!reg && (reg.status === "SUBMITTED" || reg.status === "APPROVED" || reg.status === "LOCKED");
  // the carry-overs and deferred courses the menu puts on are not the student's choice; a carry-over the student added (V611: one
  // declared, its result not on the portal) is
  const chosenNow = new Set((reg?.entries ?? []).filter((e) => (e.entryType !== "CARRYOVER" && e.entryType !== "DEFERRED") || e.studentAdded).map((e) => e.offeringId));
  const [chosen, setChosen] = useState<Set<string>>(chosenNow);
  const carry = v.menu.filter((m) => m.carryover && !m.deferred);
  const deferredCourses = v.menu.filter((m) => m.deferred);
  // Group by the PER-PROGRAMME offer basis, not the course's global kind: a course can be Core for
  // its own department yet Elective for this programme (course_offer.basis). GST (General Studies) is a University requirement.
  // V504: GST, core and elective in the University's order, each from the programme's own setup (registration.entry_category)
  // V620: a course already on the registration is read as registered — its category (the programme's basis for it at the time)
  // and its units — never as the menu reads its binding today; one not yet chosen as the menu reads it
  const entryOf = new Map((reg?.entries ?? []).filter((e) => e.status !== "DROPPED").map((e) => [e.offeringId, e] as const));
  const menuCategory = (m: RegistrationView["menu"][number]) => { const e = entryOf.get(m.offering_id); return e ? courseCategory(e) : courseCategory({ basis: m.basis, kind: m.kind }); };
  const menuUnits = (m: RegistrationView["menu"][number]) => entryOf.get(m.offering_id)?.units ?? m.units;
  // V389: a postgraduate programme's research and deficiency courses are neither core nor electives
  const special = v.menu.filter((m) => !m.carryover && (m.basis === "Research" || m.basis === "Deficiency"));
  const gstCourses = v.menu.filter((m) => !m.carryover && !special.includes(m) && menuCategory(m) === "GST");
  const core = v.menu.filter((m) => !m.carryover && !special.includes(m) && menuCategory(m) === "CORE");
  const elec = v.menu.filter((m) => !m.carryover && !special.includes(m) && menuCategory(m) === "ELECTIVE");
  // V504: the courses the student added beside the recommended list (the engine judged each; saving judges them again)
  const menuIds = new Set(v.menu.map((m) => m.offering_id));
  // V620: and a course registered under a binding since changed or removed — on no menu now, kept as registered
  const extras = byOrder((reg?.entries ?? []).filter((e) => e.status !== "DROPPED" && !menuIds.has(e.offeringId) && (e.studentAdded || (e.entryType !== "CARRYOVER" && e.entryType !== "DEFERRED"))));
  // V504: the carry-overs the published results state that are not on this semester's list, and why
  const away = (v.outstanding ?? []).filter((o) => !v.menu.some((m) => m.carryover && m.course_code === o.course_code));
  const chosenMenu = v.menu.filter((m) => !m.carryover && chosen.has(m.offering_id));
  const chosenExtras = extras.filter((e) => chosen.has(e.offeringId));
  // V512: a GST/EPS carry-over the GST fee holds is not on the registration until the fee is paid: listed, not counted
  const onReg = new Set((reg?.entries ?? []).filter((e) => e.status !== "DROPPED").map((e) => e.offeringId));
  const heldCarry = (m: RegistrationView["menu"][number]) => !!m.gstLocked && !onReg.has(m.offering_id);
  const chosenTotal = carry.filter((m) => !heldCarry(m)).reduce((n, m) => n + menuUnits(m), 0) + deferredCourses.filter((m) => !heldCarry(m)).reduce((n, m) => n + menuUnits(m), 0)
    + chosenMenu.reduce((n, m) => n + menuUnits(m), 0) + chosenExtras.reduce((n, e) => n + e.units, 0);
  // V504: the selection as it will be registered, in the University's order, numbered on
  const selected = byOrder<{ key: string; code: string; title: string; units: number; category: string; note: string | null }>([
    ...v.menu.filter((m) => (m.carryover && !heldCarry(m)) || chosen.has(m.offering_id)).map((m) => ({ key: m.offering_id, code: m.course_code, title: m.title, units: menuUnits(m),
      category: m.carryover ? courseCategory({ basis: m.deferred ? "Deferred" : "Carryover", kind: m.kind }) : menuCategory(m),
      note: m.deferred ? "Deferred" : m.carryover ? (m.kind === "GST" ? `Carry-over · ${gstOffice(m.course_code)}` : "Carry-over") : null })),
    ...chosenExtras.map((e) => ({ key: e.offeringId, code: e.courseCode, title: e.title, units: e.units, category: courseCategory(e), note: addedAsLabel(e.addedAs) ?? (e.studentAdded ? "Added by you" : "Registered before your programme's structure changed; kept as registered") })),
  ]);
  // a course the student added beside the menu, with its Remove (saving the selection without it): V611 lists a declared carry-over
  // under Carry-over courses, the others under Add other courses
  const extraRow = (e: (typeof extras)[number]) => (
    <div key={e.offeringId} className="row" style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)", alignItems: "center" }}>
      <span className="tnum b600" style={{ minWidth: 92 }}>{e.courseCode}</span>
      <span className="grow">{e.title} <span className="sub2">· {addedAsLabel(e.addedAs) ?? (e.studentAdded ? "added by you" : "registered before your programme's structure changed; kept as registered")}</span></span>
      <Pil kind="grey">{CATEGORY_LABEL[courseCategory(e)]}</Pil>
      <span className="tnum b600" style={{ minWidth: 28, textAlign: "right" }}>{e.units}</span>
      <Btn kind="ghost" size="sm" disabled={busy !== null} busy={busy === `remove-${e.offeringId}`} busyLabel="Removing..." onClick={async () => {
        const n = new Set(chosen); n.delete(e.offeringId);
        const j = await act(`remove-${e.offeringId}`, "PUT", "/me/registration", { session: v.session, semester: v.semester, offerings: [...n] }, `Course ${e.courseCode} removed by the student`, `${e.courseCode} removed`);
        if (j) setChosen(n);
      }}>Remove</Btn>
    </div>
  );
  // a registration submitted or approved is read from itself, not from today's menu: a course whose binding changed after
  // approval, or one added on the student's behalf, is not on the menu, and the page then showed nothing ticked and
  // "0 units · Below minimum" under "Approved · 15 units"
  const registered = byOrder((reg?.entries ?? []).filter((e) => e.status !== "DROPPED"));
  const total = locked ? Number(reg!.units) : chosenTotal;
  const min = v.limit.min_units;
  const max = v.limit.max_units;
  // V495: the minimum is the student's curriculum's (CCMAS, BMAS), as the Directorate of ICT set it for the session and semester
  const curriculum = v.limit.basis === "CURRICULUM" ? v.limit.curriculum ?? null : null;
  const onProbation = !!v.probation && v.probation.standing === "PROBATION";
  // V597: current courses and carry-overs apart — the minimum binds a registration with a current course of the programme; one of
  // carry-overs (and deferred courses) alone, or of GST/EPS courses alone, is submitted at whatever it carries (the server decides
  // the same at submission, registration.load_kind)
  const isCarry = (t: string | null | undefined) => t === "CARRYOVER" || t === "DEFERRED" || t === "REPEAT";
  const carryUnits = locked ? registered.filter((e) => isCarry(e.entryType)).reduce((n, e) => n + e.units, 0)
    : carry.filter((m) => !heldCarry(m)).reduce((n, m) => n + menuUnits(m), 0) + deferredCourses.filter((m) => !heldCarry(m)).reduce((n, m) => n + menuUnits(m), 0)
      + chosenExtras.filter((e) => isCarry(e.entryType)).reduce((n, e) => n + e.units, 0);
  const currentUnits = total - carryUnits;
  const kind: LoadKind = locked && v.loadKind ? v.loadKind
    : loadKind([...chosenMenu.map((m) => ({ category: menuCategory(m) })), ...chosenExtras.map((e) => ({ category: courseCategory(e) }))], carryUnits, v.spilloverState);
  const waived = total < min && !minimumBinds(kind) ? waivedWords(kind) : null;
  const ok = (total >= min || !minimumBinds(kind)) && total <= max;
  const meter: { col: string; bg: string; fg: string; lab: string; hint: string } = total < min && waived ? { col: "var(--green)", bg: "var(--green-bg)", fg: "var(--green-ink)", lab: waived.label, hint: waived.hint }
    : total < min ? { col: "var(--red-ink)", bg: "var(--red-bg)", fg: "var(--red-deep)", lab: "Minimum not met", hint: `${curriculum ? `Your curriculum (${curriculum}) requires` : "You need"} at least ${min} credit units: ${min - total} CU remaining. Add courses to reach it.` }
    : total > max ? { col: "var(--red)", bg: "var(--red-bg)", fg: "var(--red-ink)", lab: "Over limit", hint: onProbation && v.probation?.probation_max_units != null && max === v.probation.probation_max_units ? `On probation the maximum is ${max} units. Remove ${total - max}; the courses you owe stay.` : `Maximum is ${max} units. Remove ${total - max}, or request an overload from your HOD.` }
      : { col: "var(--green)", bg: "var(--green-bg)", fg: "var(--green-ink)", lab: "Minimum met", hint: `Minimum requirement met${curriculum ? ` for ${curriculum}` : ""}; within the permitted range for ${v.level} Level.` };
  // a registration submitted or approved, with add/drop closed, cannot be changed by the student: say what it holds, not what to add
  if (locked && !v.addDropOpen) meter.hint = `${total} units registered; the range for ${v.level} Level is ${min}–${max}.`;

  const fees = v.fees;
  // gate on THIS semester's fees, not only the open one — a full-session payment clears an
  // earlier semester the student never registered, so they can go back and register it now
  const cleared = v.clears ?? (fees.clearsRegistration === true);
  /* V616: a spillover student's choice of courses is what makes the semester's fee due; the submission waits for it */
  const spillPays = fees.spilloverBySemester === true;

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

  // V288 · the late registration period, when the portal window is in it
  const lateReg = v.window?.portal && v.window.portal.state === "OPEN" && v.window.portal.phase === "LATE" ? v.window.portal : null;
  // V287 · the calendar's door on this semester: closed, not yet open, or open early to the session's fresh students
  if (v.window && !v.window.open && !locked) {
    return (
      <>
        {switcher}
        <Note kind="bad" title={v.window.portal && v.window.portal.configured && v.window.portal.state !== "OPEN" ? "COURSE REGISTRATION IS CURRENTLY CLOSED" : v.window.state === "CLOSED" ? "Registration is closed for this semester" : "Registration is not yet open for this semester"}>
          {v.window.gate}{v.window.cce ? " The Centre for Continuing Education sets up its classes and opens the semester on the CCE calendar." : v.window.fresh && v.window.fresh_registration_from ? "" : v.window.fresh_registration_from ? "" : " The Academic Office opens the semester on the University calendar."}
        </Note>
      </>
    );
  }
  const lateNote = lateReg ? <Note kind="info" title="LATE REGISTRATION">The normal registration window closed on {new Date(lateReg.closes_at ?? "").toLocaleString("en-GB", { day: "numeric", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" })}; late registration runs until {new Date(lateReg.late_until ?? "").toLocaleString("en-GB", { day: "numeric", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" })}{lateReg.late_fee_enabled ? ", and the late registration fee the Bursar stated is in your charge on Fees & payments" : ""}.</Note> : null;
  if (!cleared && !locked) {
    return (
      <>
        {switcher}
        <Note kind="bad" title="You cannot register yet">Clear the outstanding requirement below to register.</Note>
        <div className="card"><div className="card__body" style={{ gap: 0, padding: 0 }}>
          <Gates>
            <Gate state={["ADMITTED", "ACTIVE", "PROBATION"].includes(s.status) ? "done" : "todo"} title="Student status" sub={`${s.status.charAt(0) + s.status.slice(1).toLowerCase()} · ${s.level} Level`} />
            <Gate state="done" title="On the register" sub={`${s.matricNo ?? s.admissionNo} · entered ${s.entrySession}`} />
          </Gates>
          <div style={{ padding: "var(--s-4)", borderBottom: "1px solid var(--line-2)", background: "var(--red-wash)", display: "flex", gap: "var(--s-3)" }}>
            <div className="step__mark" style={{ background: "var(--red)" }}><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="3.4" strokeLinecap="round"><path d="M6 6l12 12M18 6 6 18" /></svg></div>
            <div className="grow stack">
              <div><div className="b600 ink-red">Financial clearance</div>
                <div className="t-sm mt-1">{fees.schemeProblem ? fees.schemeProblem : fees.stated === false || (fees.stated === undefined && fees.due === 0) ? (v.window?.cce ? `The Bursary has not yet stated the school fees of the Centre for Continuing Education for ${fees.session}, so nothing can be paid or released; registration opens once it states them and they are paid.` : `No charge is stated for ${fees.session} yet, so nothing can be paid or released; registration opens once the Bursary states it and it is paid.`) : fees.hasArrears ? "Arrears from an earlier session stand against you." : <>Outstanding balance of <strong className="tnum">{naira(fees.balance)}</strong> on the {fees.session} charge.</>}</div></div>
              {fees.due > 0 ? (
                <div className="stack" style={{ background: "var(--surface)", border: "1px solid var(--line)", borderRadius: "var(--r-md)", padding: "var(--s-3)" }}>
                  <Row k={<>School fees, {fees.session}</>} v={naira(fees.due)} />
                  <Row k="Paid" v={<>− {naira(fees.paid)}</>} colour="var(--green-ink)" />
                  <div className="hr" />
                  <div className="row row--between"><strong>Outstanding</strong><strong className="tnum t-md ink-red">{naira(fees.balance)}</strong></div>
                </div>
              ) : null}
              <div><LinkBtn kind="urgent" size="md" href="/student/fees">{fees.due > 0 ? `Pay ${naira(fees.balance)}` : "See fees & payments"}</LinkBtn></div>
              <div className="sub2">Responsible office: <strong style={{ color: "var(--ink)" }}>Bursary Department</strong>.</div>
            </div>
          </div>
          <Gates><Gate state="todo" title="Registration window" sub={`${v.session} · ${semesterText(v.semester)}`} last /></Gates>
        </div></div>
      </>
    );
  }

  const pick = (m: RegistrationView["menu"][number], fixed: boolean, on: boolean, red = false) => (
    <button type="button" key={m.offering_id} className="pick" data-on={on ? 1 : 0} disabled={fixed || locked || !!m.gstLocked || (!!m.prerequisiteLocked && !on)}
      style={red ? { borderColor: "var(--red-line)", background: "var(--red-bg)" } : m.gstLocked || (m.prerequisiteLocked && !on) ? { borderColor: "var(--red-line)", opacity: 0.75 } : undefined}
      title={m.gstLocked ? "Locked until the GST fee is paid" : m.prerequisiteLocked ? `Pass ${m.prerequisitesUnmet} first` : m.prerequisitesUnmet ? `Prerequisite not yet passed: ${m.prerequisitesUnmet}` : undefined}
      onClick={() => { if (fixed || locked || m.gstLocked) return; const n = new Set(chosen); if (n.has(m.offering_id)) n.delete(m.offering_id); else if (m.prerequisiteLocked) return; else n.add(m.offering_id); setChosen(n); }}>
      <div className="pick__box" style={on ? { background: red ? "var(--red)" : "var(--chrome)", borderColor: red ? "var(--red)" : "var(--chrome)" } : undefined}>{on ? <Tick size={12} colour="#fff" /> : null}</div>
      <div className="grow"><div className="pick__t tnum">{m.course_code} — {m.title}</div>
        <div className="pick__s" style={red ? { color: "var(--red-deep)" } : undefined}>{m.deferred ? `Deferred · originally ${m.deferred_from ?? ""} · status DEFERRED` : m.carryover ? `Failed ${m.failed_in} — must be repeated` : m.basis === "Borrowed" ? `Owned by ${m.owner_dept} — open to this programme at ${v.level} level` : m.basis === "GST" ? "University requirement" : m.lecturer ? `${m.lecturer}` : "No lecturer allocated yet"}</div></div>
      {m.basis === "Borrowed" ? <Pil kind="info">{m.owner_dept}</Pil> : null}
      {m.basis === "Research" || m.basis === "Deficiency" ? <Pil kind={m.basis === "Research" ? "ok" : "warn"}>{m.basis}</Pil> : null}
      {m.gstLocked ? <Pil kind="bad">GST fee required</Pil> : null}
      {m.prerequisitesUnmet ? <Pil kind={m.prerequisiteLocked ? "bad" : "warn"}>{`Needs ${m.prerequisitesUnmet}`}</Pil> : null}
      <div className="tnum b700" style={{ color: red ? "var(--red-ink)" : on ? "var(--chrome)" : "var(--muted)" }}>{m.units}</div>
    </button>
  );

  // V512: a carry-over or deferred course: held on the GST fee (a GST/EPS course), to register (not yet on the registration), or on it
  const carryRow = (m: RegistrationView["menu"][number], red: boolean) => heldCarry(m) ? (
    // V512: a GST/EPS carry-over waits for the GST fee — being a carry-over does not pass it
    <div key={m.offering_id} className="pick" data-on={0} style={{ cursor: "default", borderColor: "var(--red-line)", background: "var(--red-bg)" }}>
      <div className="pick__box" />
      <div className="grow"><div className="pick__t tnum">{m.course_code} — {m.title}</div>
        <div className="pick__s" style={{ color: "var(--red-deep)" }}>{m.deferred ? `Deferred from ${m.deferred_from ?? ""}` : `Failed ${m.failed_in}`} — a {gstOffice(m.course_code)} course: GST/EPS PAYMENT REQUIRED before it can be registered</div></div>
      <Pil kind="info">{gstOffice(m.course_code)}</Pil>
      <LinkBtn kind="urgent" size="sm" href={`/student/gst?session=${encodeURIComponent(v.session)}`}>PAY GST/EPS FEE</LinkBtn>
      <div className="tnum b700" style={{ color: "var(--muted)" }}>{m.units}</div>
    </div>
  ) : reg && !onReg.has(m.offering_id) ? (
    <div key={m.offering_id} className="pick" data-on={0} style={{ cursor: "default", borderColor: "var(--red-line)" }}>
      <div className="pick__box" />
      <div className="grow"><div className="pick__t tnum">{m.course_code} — {m.title}</div>
        <div className="pick__s" style={{ color: "var(--red-deep)" }}>{m.deferred ? `Deferred from ${m.deferred_from ?? ""}` : `Failed ${m.failed_in}`} — not yet on this registration{m.kind === "GST" ? "; the GST/EPS fee no longer holds it" : ""}</div></div>
      {m.kind === "GST" ? <Pil kind="info">{gstOffice(m.course_code)}</Pil> : null}
      <Btn kind="primary" size="sm" disabled={busy !== null} busy={busy === `carry-${m.offering_id}`} busyLabel="Registering..."
        onClick={() => void act(`carry-${m.offering_id}`, "POST", "/me/registration/courses", { session: v.session, semester: v.semester, offering: m.offering_id },
          `Carry-over ${m.course_code} registered by the student`, `${m.course_code} registered`)}>REGISTER</Btn>
      <div className="tnum b700" style={{ color: "var(--muted)" }}>{m.units}</div>
    </div>
  ) : pick(m, true, true, red);

  return (
    <>
      {lateNote}
      {switcher}
      {spillPays ? (
        <Note kind="info" title="In spillover, you pay for the semesters you register">
          Choosing a course here makes this semester&rsquo;s school fees due{cleared ? "; they are paid, so the registration can be submitted." : "; the registration is submitted once they are paid."}
        </Note>
      ) : null}
      {v.siwes ? (
        <Note kind="info" title="Industrial training (SIWES) semester">
          Register only the SIWES / industrial training course ({max} units) this semester — no other course and no carryover.
        </Note>
      ) : null}
      {locked ? (
        reg!.status === "SUBMITTED" && auto && v.reviewReason ? (
          <Note kind="bad" title="REGISTRATION REQUIRES REVIEW">
            {reasonWords(v.reviewReason)}. Your registration was submitted ({reg!.units} units) and is held until this is put right; the Academic Office checks it again
            {v.reset?.allowed ? ", or reset it below and register again" : ""}.
          </Note>
        ) : (
        <Note kind={reg!.status === "APPROVED" || reg!.status === "LOCKED" ? "ok" : "info"}
          title={reg!.status === "APPROVED" || reg!.status === "LOCKED" ? (reg!.approval_mode === "AUTO" ? `REGISTRATION SUCCESSFUL — STATUS: APPROVED (${onDay(reg!.approved_at)})` : `Approved on ${onDay(reg!.approved_at)}`)
            : auto ? `Submitted on ${onDay(reg!.submitted_at)}` : `Submitted on ${onDay(reg!.submitted_at)} — with your Head of Department`}
          action={<span className="row row--inline row--tight">
            {reg!.status === "APPROVED" || reg!.status === "LOCKED" ? <LinkBtn kind="primary" href={`/student/form?session=${encodeURIComponent(v.session)}&semester=${v.semester}`}>Course form</LinkBtn> : null}
            {/* V567: the card asks only for the courses registered and school fees paid — no approval */}
            <LinkBtn kind="secondary" href="/student/exams">Examination card</LinkBtn>
          </span>}>
          {reg!.units} units. {reg!.status === "SUBMITTED" ? (auto ? "It is being checked against the registration rules." : "It goes to your Head of Department for approval; a return comes back here with the reason.")
            + " Your examination card is on Examinations once your school fees for the session are paid."
            : reg!.approval_mode === "AUTO" ? "Your registration passed every registration rule and was approved automatically; your examination card is on Examinations once your school fees for the session are paid."
            : "The register carries these courses; the class lists and the score sheets are drawn from them."}
        </Note>
        )
      ) : reg?.status === "RETURNED" ? (
        <Note kind="bad" title="Returned to you">
          {reg.returned_comment ? <><b>Your Head of Department&rsquo;s reason:</b> {reg.returned_comment}<br /></> : null}
          Change your registration and submit it again.
        </Note>
      ) : null}

      {reg && reg.status !== "DRAFT" && v.reset?.allowed ? (
        <Panel title="CURRENT COURSE REGISTRATION" right={`${registered.length} course${registered.length === 1 ? "" : "s"} · ${reg.units} units`}>
          <PBody>
            <div className="row" style={{ alignItems: "center", flexWrap: "wrap", gap: 8 }}>
              <span className="sub2 grow">Courses brought over from the old portal, or chosen in error? Clear this semester&rsquo;s registration and choose your courses again. The carry-overs your published results state stay (those you declared are cleared with your other courses); your results, payments and earlier semesters are not touched.</span>
              <Btn kind="ghost" disabled={busy !== null} onClick={() => setAskReset(true)}>RESET COURSE REGISTRATION</Btn>
            </div>
            {v.reset.history.length ? <div className="sub2 mt-1">Reset {v.reset.history.length} time{v.reset.history.length === 1 ? "" : "s"} this semester; last on {onDay(v.reset.history[0].reset_at)}.</div> : null}
          </PBody>
        </Panel>
      ) : null}
      {askReset && reg ? (
        <Modal title="RESET COURSE REGISTRATION?" sub="This will remove your current editable course registration for this session/semester and allow you to register your courses again."
          onClose={() => { if (busy === null) setAskReset(false); }}
          foot={<>
            <Btn kind="ghost" disabled={busy !== null} onClick={() => setAskReset(false)}>CANCEL</Btn>
            <Btn kind="urgent" busy={busy === "reset"} busyLabel="Resetting registration..." onClick={async () => {
              const j = await act("reset", "POST", "/me/registration/reset", { session: v.session, semester: v.semester, reason: "Reset by the student to register the courses again" }, "Course registration reset by the student", "");
              if (j) { setAskReset(false); notify("Registration cleared. Select your courses and submit again."); }
            }}>RESET AND RE-REGISTER</Btn>
          </>}>
          <div className="grid grid--2">
            <div className="kv"><span className="k">Academic session</span><span className="v tnum">{v.session}</span></div>
            <div className="kv"><span className="k">Semester</span><span className="v">{semesterName(v.semester)}</span></div>
            <div className="kv"><span className="k">Student</span><span className="v">{s.name}</span></div>
            <div className="kv"><span className="k">Programme</span><span className="v">{s.programme}</span></div>
            <div className="kv"><span className="k">Level</span><span className="v tnum">{v.level} Level</span></div>
            <div className="kv"><span className="k">Current courses</span><span className="v tnum">{registered.length} ({reg.units} units)</span></div>
          </div>
          <p className="sub2" style={{ marginBottom: 0 }}>The carry-overs your published results state stay on the registration; a carry-over you declared is cleared with your other courses. Your results, payments, GST/EPS entitlement and earlier semesters are not changed.</p>
        </Modal>
      ) : null}

      {locked && v.addDropOpen ? (() => {
        const activeIds = new Set((reg?.entries ?? []).filter((e) => e.status !== "DROPPED").map((e) => e.offeringId));
        // V611: a carry-over the student declared is dropped as it was added; one the results state is repeated
        const droppable = byOrder((reg?.entries ?? []).filter((e) => e.status !== "DROPPED" && (e.entryType !== "CARRYOVER" || e.addedAs === "CARRY_OVER_DECLARED") && e.entryType !== "DEFERRED"));
        const addable = v.menu.filter((m) => !m.carryover && !activeIds.has(m.offering_id));
        return (
          <Panel title="Add or drop courses" right="the add/drop window is open">
            <PBody>
              {problem ? <ProblemNotice problem={problem} /> : null}
              <div className="sub2">You can still add or drop a course (not a carry-over your results state, or a course with a mark). Total: {min}–{max} units.</div>
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
              {!v.siwes ? (
                <div className="row mt-3" style={{ alignItems: "center", gap: 8 }}>
                  <span className="sub2 grow">A carry-over from an earlier session whose result is not on the portal?</span>
                  <Btn kind="secondary" disabled={busy !== null} onClick={() => setAddingCarry(true)}>+ ADD CARRY-OVER COURSE</Btn>
                </div>
              ) : null}
              {v.flex?.allow_other_courses !== false ? (
                <div className="row mt-3" style={{ alignItems: "center", gap: 8 }}>
                  <span className="sub2 grow">A course not listed here — of your programme at another level, or a University GST/EPS course?</span>
                  <Btn kind="secondary" disabled={busy !== null} onClick={() => setAdding(true)}>+ ADD OTHER COURSE</Btn>
                </div>
              ) : null}
            </PBody>
          </Panel>
        );
      })() : null}

      <div className="card"><div className="card__body">
        <div className="meter">
          <div className="row row--base">
            <span className="tnum b700" style={{ fontSize: "var(--t-3xl)", letterSpacing: "-.6px", color: meter.col }}>{total}</span>
            <span className="ink-muted tnum">/ {min} CU minimum · {max} maximum{curriculum ? <> · <b>{curriculum}</b></> : null}</span>
            <span className="grow" />
            <span className="pill" style={{ background: meter.bg, color: meter.fg }}>{meter.lab}</span>
          </div>
          <div className="meter__bar"><div className="meter__fill" style={{ width: `${Math.min(100, Math.round((total / max) * 100))}%`, background: meter.col }} /></div>
          <div className="sub2">{meter.hint}</div>
          <div className="sub2 tnum">{loadSummary(currentUnits, carryUnits)}</div>
        </div>
      </div></div>
      {/* V508: an overload asked of the Head of Department, and where it stands (not in the SIWES semester) */}
      {v.limit.basis !== "SIWES" && (!locked || v.addDropOpen) ? <OverloadRequest session={v.session} semester={v.semester} total={total} max={max} /> : null}
      {locked ? (
        <Panel title="Your registered courses" right={`${registered.length} course${registered.length === 1 ? "" : "s"} · ${reg!.units} units`}>
          <PBody>
            {registered.length ? registered.map((e, i) => (
              <div key={e.offeringId} className="row" style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)" }}>
                <span className="tnum sub2" style={{ minWidth: 24 }}>{i + 1}</span>
                <span className="tnum b600" style={{ minWidth: 92 }}>{e.courseCode}</span>
                <span className="grow">{e.title}{e.lecturer ? <span className="sub2"> · {e.lecturer}</span> : null}{e.studentAdded ? <span className="sub2"> · {addedAsLabel(e.addedAs) ?? "added by you"}</span> : null}</span>
                <Pil kind={e.entryType === "CARRYOVER" ? "bad" : e.entryType === "DEFERRED" ? "warn" : "grey"}>{e.entryType === "DEFERRED" ? "Deferred" : categoryWords(e)}</Pil>
                <span className="tnum b600" style={{ minWidth: 28, textAlign: "right" }}>{e.units}</span>
              </div>
            )) : <div className="sub2">No course is on this registration.</div>}
          </PBody>
        </Panel>
      ) : null}
      {!locked && (carry.length || deferredCourses.length || away.length) ? (
        <Panel title={<span className="ink-red">CARRY-OVER / OUTSTANDING COURSES</span>} right={carry.length || deferredCourses.length ? "added automatically, cannot be removed" : "not offered this semester"}>
          <PBody>
            {carry.map((m) => carryRow(m, true))}
            {deferredCourses.length ? <div className="sub2 mb-1 mt-1">Courses of your deferred period, now due. They count in your GPA only when taken.</div> : null}
            {deferredCourses.map((m) => carryRow(m, false))}
            {away.map((o) => (
              <div key={o.course_code} className="pick" data-on={0} style={{ cursor: "default", borderColor: "var(--red-line)", opacity: 0.85 }}>
                <div className="pick__box" />
                <div className="grow"><div className="pick__t tnum">{o.course_code} — {o.title}</div>
                  <div className="pick__s" style={{ color: "var(--red-deep)" }}>Failed {o.failed_in} — {o.offering_id ? (v.siwes ? "not registered in the SIWES semester" : "not open to you this semester; ask your department")
                    : o.runs_in ? `not offered this semester; it runs in the ${o.runs_in} semester of ${v.session}` : `not offered in ${v.session} yet`}</div></div>
                <Pil kind="warn">Outstanding</Pil>
                <div className="tnum b700" style={{ color: "var(--muted)" }}>{o.units}</div>
              </div>
            ))}
            <div className="sub2 mt-1">Carry-overs come only from published results: a course with no result, or a result still pending, is never a carry-over.</div>
          </PBody></Panel>
      ) : null}
      {v.window?.pg ? (
        <div className="sub2 mb-2">{v.specialisation ? <>Your specialisation: <b>{v.specialisation}</b>. The courses listed are your programme&rsquo;s for every student and those of your specialisation.</> : "No specialisation is set for you: the courses listed are your programme's for every student. The School of Postgraduate Studies sets a specialisation."}</div>
      ) : null}
      {v.codeFamily ? (
        <div className="sub2 mb-2">Your cohort registers <b>{v.codeFamily}-</b> course codes{v.codeFamily === "BSU" ? " until you graduate; a carry-over keeps the code it was failed under" : ""}. Where a course is listed under one code only, that is the one to take.</div>
      ) : null}
      {v.gst && !locked && v.gst.stated && !v.gst.entitled && Number(v.gst.fee) > 0 && v.menu.some((m) => m.gstLocked) ? (
        <Note kind="bad" title="GST PAYMENT REQUIRED" action={<LinkBtn kind="primary" href={`/student/gst?session=${encodeURIComponent(v.session)}`}>PAY GST FEE</LinkBtn>}>
          Pay the GST fee of <b className="tnum">{naira(Number(v.gst.fee))}</b> for {v.session} to register GST/EPS courses. One payment covers GST and EPS.
          {v.gst.state === "PENDING" ? " A reference is open; the courses unlock when it is confirmed." : ""}
        </Note>
      ) : null}
      {!locked && v.menu.some((m) => m.prerequisiteLocked) ? (
        <Note kind="info" title="Prerequisites not yet passed">
          A course marked &ldquo;Needs&rdquo; is locked until a pass in the course it names is published on your record. If you passed it and the result
          is not yet published, or you were exempted, ask your department; ICT Support can add the course on your ticket.
        </Note>
      ) : null}
      {!locked ? (<>
      {gstCourses.length ? (
        <Panel title="GST COURSES" right="University requirement">
          <PBody>{gstCourses.map((m) => pick(m, false, chosen.has(m.offering_id)))}</PBody></Panel>
      ) : null}
      <Panel title={`${v.level} LEVEL CORE COURSES`}>
        <PBody>{core.length ? core.map((m) => pick(m, false, chosen.has(m.offering_id))) : <div className="sub2">No core course is offered to your programme this semester yet.</div>}</PBody></Panel>
      <Panel title="ELECTIVE COURSES" right={<>choose to reach {min}–{max} units</>}>
        <PBody>{elec.length ? elec.map((m) => pick(m, false, chosen.has(m.offering_id))) : <div className="sub2">No elective is open to your programme this semester.</div>}
          </PBody></Panel>
      </>) : null}
      {!locked && special.length ? (
        <Panel title="Research and deficiency courses">
          <PBody>{special.map((m) => pick(m, false, chosen.has(m.offering_id)))}
            <div className="sub2 mt-2">A deficiency course earns no credit; register it where the School requires it of you.</div></PBody></Panel>
      ) : null}
      {!locked && !v.siwes ? (
        <Panel title="CARRY-OVER COURSES" right={<Btn kind="secondary" disabled={busy !== null} onClick={() => setAddingCarry(true)}>+ ADD CARRY-OVER COURSE</Btn>}>
          <PBody>
            <div className="sub2">
              Failed a course in an earlier session? A carry-over that a published result on the portal shows is listed above and put on your
              registration for you. Your results from the old portal are not on this portal: add such a carry-over yourself from the courses
              you registered before. Add only a course you failed — it is marked as a carry-over you declared, and your department sees it.
            </div>
            {extras.filter((e) => e.addedAs === "CARRY_OVER_DECLARED").map(extraRow)}
          </PBody>
        </Panel>
      ) : null}
      {!locked && !v.siwes ? (
        <Panel title="ADD OTHER COURSES" right={v.flex?.allow_other_courses !== false ? <Btn kind="secondary" disabled={busy !== null} onClick={() => setAdding(true)}>+ ADD OTHER COURSE</Btn> : "closed for now"}>
          <PBody>
            <div className="sub2">{v.flex?.allow_other_courses !== false
              ? <>A course not listed above — of your programme at another level{v.flex?.allow_higher_levels ? "" : " below yours"}, an elective, or a University GST/EPS course{v.flex?.other_scope === "FACULTY" ? ", or one of your faculty" : v.flex?.other_scope === "DEPARTMENT" ? ", or one of your department" : ""}? Search for it; the University&rsquo;s rules decide whether you may add it, and your registration is approved on the same rules.</>
              : "The Academic Office has closed adding courses beside your recommended list for now."}</div>
            {extras.filter((e) => e.addedAs !== "CARRY_OVER_DECLARED").map(extraRow)}
          </PBody>
        </Panel>
      ) : null}
      {!locked ? (
        <Panel title="SELECTED COURSES" right={`${selected.length} course${selected.length === 1 ? "" : "s"} · ${total} units`}>
          {selected.length ? (
            <div className="tablewrap" tabIndex={0}><table className="tbl--data" style={{ minWidth: 520 }}>
              <thead><tr><th className="mid">S/N</th><th>Course code</th><th>Course title</th><th className="mid">Units</th><th>Category</th></tr></thead>
              <tbody>
                {selected.map((x, i) => (
                  <tr key={x.key}>
                    <td className="mid tnum">{i + 1}</td>
                    <td className="tnum b600">{x.code}</td>
                    <td>{x.title}{x.note && x.category !== "CARRY_OVER" ? <div className="sub2">{x.note}</div> : null}</td>
                    <td className="mid tnum">{x.units}</td>
                    <td>{x.note === "Deferred" ? "Deferred" : x.note?.startsWith("Carry-over") ? x.note : CATEGORY_LABEL[courseCategory({ category: x.category })]}</td>
                  </tr>
                ))}
                <tr style={{ background: "var(--bg)" }}><td colSpan={3} className="b700">TOTAL CREDIT UNITS</td><td className="mid tnum b700">{total}</td>
                  <td className="t-xs b600" style={{ color: meter.col }}>{meter.lab} · {min}–{max}</td></tr>
              </tbody>
            </table></div>
          ) : <PBody><div className="sub2">No course is selected yet.</div></PBody>}
        </Panel>
      ) : null}
      {adding ? (
        <AddOtherCourse session={v.session} semester={v.semester} level={v.level} total={total} max={max} addDrop={locked}
          onAdded={(id) => { if (!locked) setChosen((c) => new Set(c).add(id)); }} onClose={() => setAdding(false)} />
      ) : null}
      {addingCarry ? (
        <AddOtherCourse initialCategory="CARRY_OVER" session={v.session} semester={v.semester} level={v.level} total={total} max={max} addDrop={locked}
          onAdded={(id) => { if (!locked) setChosen((c) => new Set(c).add(id)); }} onClose={() => setAddingCarry(false)} />
      ) : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!locked ? (
        <div className="row">
          <Btn kind="ghost" disabled={busy !== null} onClick={() => void act("save", "PUT", "/me/registration", { session: v.session, semester: v.semester, offerings: [...chosen] }, "Course registration saved by the student")}>{busy === "save" ? "Saving…" : "Save the draft"}</Btn>
          <Btn kind="primary" disabled={!ok || busy !== null} onClick={async () => { const saved = await act("save", "PUT", "/me/registration", { session: v.session, semester: v.semester, offerings: [...chosen] }, "Course registration saved by the student"); if (saved) { const j = await act("submit", "POST", "/me/registration/submit", { session: v.session, semester: v.semester }, "Course registration submitted by the student", ""); if (j) notify(j.result === "approved" ? "REGISTRATION SUCCESSFUL — STATUS: APPROVED" : "Course registration submitted"); } }}>{busy === "submit" ? "VALIDATING REGISTRATION..." : busy === "save" ? "Registering…" : auto ? "SUBMIT COURSE REGISTRATION" : "Submit for approval"}</Btn>
          <span className="sub2">{auto ? "Approved at once when it passes the registration rules" : "Goes to your Head of Department for approval"}</span>
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
        {reg ? `Your registration is ${reg.status.toLowerCase()}.` : "You have not registered for this semester yet."} The form prints the approved registration, and nothing else.
      </Note>
    );
  }
  return (
    <>
      <Note kind="ok" title={reg.approval_mode === "HOD" ? `Approved by your Head of Department on ${onDay(reg.approved_at)}`
        : reg.approval_mode === "AUTO" ? `Approved automatically on ${onDay(reg.approved_at)}, on the registration rules` : `Approved on ${onDay(reg.approved_at)}`} />
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
        <div className="tablewrap" tabIndex={0}><table className="tbl--data" style={{ minWidth: 520 }}>
          <thead><tr>
            {["S/N", "Course code", "Course title", "Lecturer"].map((h) => <th key={h} style={{ background: "var(--chrome)", color: "var(--surface)" }}>{h}</th>)}
            <th className="mid" style={{ background: "var(--chrome)", color: "var(--surface)" }}>Unit</th>
            <th className="num" style={{ background: "var(--chrome)", color: "var(--surface)" }}>Type</th>
          </tr></thead>
          <tbody>
            {byOrder(reg.entries.filter((e) => e.status !== "DROPPED" && e.status !== "WITHDRAWN")).map((e, i) => { const co = e.entryType === "CARRYOVER" || e.entryType === "DEFERRED"; return (
              <tr key={e.offeringId}>
                <td className="tnum sub2">{i + 1}</td>
                <td className="tnum b600">{e.courseCode}{co ? <span className="ink-red b700"> · C/O</span> : null}</td>
                <td>{e.title}</td>
                <td className="sub2">{e.lecturer ?? "—"}</td>
                <td className="mid tnum">{e.units}</td>
                <td className="num t-xs b600 ink-muted">{e.basis === "Research" || e.basis === "Deficiency" ? courseType(e) : e.entryType === "DEFERRED" ? "Deferred" : categoryWords(e)}</td>
              </tr>); })}
            <tr style={{ background: "var(--bg)" }}><td className="b700" colSpan={4}>TOTAL CREDIT UNITS</td><td className="mid tnum b700" style={{ fontSize: "var(--t-base)" }}>{reg.units}</td><td /></tr>
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
