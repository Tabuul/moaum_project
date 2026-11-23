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
import { useRouter, useSearchParams } from "next/navigation";
import type { MeCore, RegistrationView } from "@/lib/student-portal";
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
import { CarryOverPicker } from "./CarryOverPicker";
import { carrySummary } from "@/lib/carry-over";
import { SEMESTER_STATUS_WORDS, registeringWords, semesterWord as spilloverSemesterWord } from "@/lib/spillover";
import { unpaidGstRegistered } from "@/lib/gst-payable";
import { OverloadRequest } from "./OverloadRequest";
import { codeVariant, courseLabel, shownCode } from "@/lib/course-code";
import { codeTaken, onRecord, takenOff } from "@/lib/registration-corrections";
import {
  dropOthersWords, isSiwesRegistration, otherCoursesOf, schoolFeesOwed, siwesApplies, siwesClearing, siwesCourseOf, siwesFormRows, siwesInTheWay, siwesLockKind, siwesLockNotes,
  siwesPayShutWords, siwesSemesterWords, siwesUnpaidRegisteredWords, waitsWords, FEES_PAGE, SIWES_LOCK_PILL, SIWES_LOCK_TITLE, SIWES_RESET_WORDS, type MySiwes,
} from "@/lib/siwes";

/** a course the Directorate of ICT took off the registration (withdrawn), as the student reads it */
const REMOVED_WORDS = "Taken off your registration by the Directorate of ICT";

/** V655: a course under a shared code named by its curriculum, as courseLabel names it ("ITN 201" + " (BMAS)") */
const curriculumMark = (code: string) => { const v = codeVariant(code)?.replace(/\d$/, ""); return v && v !== "V" ? ` (${v})` : ""; };

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

export function Register({ s, v, siwes = null }: { s: MeCore; v: RegistrationView;
  /** V752: the student's SIWES (GET /me/siwes), read for a Second Semester */
  siwes?: MySiwes | null }) {
  // V602: a graduated record registers nothing — the server sends no menu and says why; the registration of the semester, if any, is history
  if (v.closed) {
    return <RegisterClosed v={v} />;
  }
  // V752: the Second Semester of a student the SIWES rule binds is registered on the SIWES page — the SIWES course alone, after its fee;
  // the ordinary page stays beneath (the server's gate says it is closed to them; an ordinary course already on it is shown, to be removed)
  if (v.semester === 2 && siwes && siwes.session === v.session && siwesApplies(siwes)) {
    return <><SiwesSemesterNote s={s} v={v} siwes={siwes} /><RegisterForm s={s} v={v} siwesSemester={{ course: siwesCourseOf(siwes)?.code ?? null }} /></>;
  }
  // V777: every SIWES course carries the SIWES fee: a SIWES course among the ordinary courses is locked on the form (SIWES fee required)
  // until the fee is paid; the amount, when the student's SIWES is read here and the Bursary has published it. A student SIWES binds,
  // whose First or Third Semester holds a SIWES course while the SIWES window is not open, cannot pay now: the form says when, and
  // offers no payment link that would lead to a page that takes none
  const siwesShut = siwes && siwes.session === v.session ? siwesPayShutWords(siwes) : null;
  return <RegisterForm s={s} v={v} siwesFee={siwes?.fee?.state === "PUBLISHED" ? siwes.fee.amount : null} siwesShut={siwesShut} />;
}

/** V752: the note that sends a 300 Level student of a programme taking SIWES this session to the SIWES page: no ordinary course, no
 *  carry-over in the Second Semester — the SIWES course, registered there once its fee (and the semester's school fees, K10) is paid.
 *  Its words follow where the student stands (not paid, paid, registered). A course already on the Second Semester registration leaves
 *  it here (K11): by the student's own drop door (Remove), which takes any course but the SIWES course, only while add and drop is open;
 *  by the reset when the reset door allows it, which clears the courses, carry-overs and deferred courses alike; otherwise the Academic
 *  Office or ICT Support removes them. Carry-overs and deferred courses are listed apart: they wait for a later semester. The SIWES
 *  course is the one registered once registered, whatever the programme is mapped to since. */
function SiwesSemesterNote({ s, v, siwes }: { s: MeCore; v: RegistrationView; siwes: MySiwes }) {
  const { act, busy, problem } = useAct();
  const [askReset, setAskReset] = useState(false);
  const others = otherCoursesOf(siwes);
  const note = siwesSemesterWords(siwes, v.session);
  // the courses the server counts as in the way (otherCourses), as they stand on the registration: never the SIWES course
  const { ordinary, waiting } = siwesInTheWay(v.registration?.entries, siwes);
  const shown = ordinary.length + waiting.length;
  const clearing = siwesClearing({ addDropOpen: v.addDropOpen, resetAllowed: v.reset?.allowed, count: shown });
  const feesFirst = !!siwes.paid && !siwes.registration && schoolFeesOwed(siwes);
  const row = (e: (typeof ordinary)[number], waits: boolean) => (
    <div key={e.offeringId} className="row" style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)", alignItems: "center" }}>
      <span className="tnum b600" style={{ minWidth: 92 }}>{shownCode(e.courseCode)}</span>
      <span className="grow">{e.title} <span className="sub2">· {e.units} unit{e.units === 1 ? "" : "s"}</span>
        {waits ? <span className="blk sub2">{waitsWords(e.courseCode)}</span> : null}</span>
      {waits ? <Pil kind={e.entryType === "DEFERRED" ? "warn" : "bad"}>{e.entryType === "DEFERRED" ? "Deferred" : "Carry-over"}</Pil> : null}
      {/* the student's drop door takes a course only while add and drop is open (registration.student_drop) */}
      {clearing.remove ? (
        <Btn kind="ghost" size="sm" disabled={busy !== null} busy={busy === `siwes-drop-${e.offeringId}`} busyLabel="Removing…"
          onClick={() => void act(`siwes-drop-${e.offeringId}`, "POST", "/me/registration/drop", { session: v.session, semester: v.semester, offering: e.offeringId },
            waits ? `${e.courseCode} removed by the student: it waits for a later semester, the Second Semester being SIWES`
              : `${e.courseCode} removed by the student: the Second Semester is SIWES`,
            waits ? `${e.courseCode} removed: it waits for a later semester` : `${e.courseCode} removed`)}>Remove</Btn>
      ) : null}
    </div>
  );
  return (
    <>
      <Note kind={note.tone} title={note.title} action={<span className="row row--inline row--tight">
        {feesFirst ? <LinkBtn kind="urgent" href={FEES_PAGE.href}>{FEES_PAGE.label}</LinkBtn> : null}
        <LinkBtn kind="primary" href="/student/siwes">{siwes.registration ? "SIWES page" : "Go to SIWES"}</LinkBtn>
      </span>}>
        {note.words}
        {!others.length ? "" : shown
          ? ` ${others.join(", ")} ${others.length === 1 ? "is" : "are"} on your Second Semester registration; the SIWES course is registered alone. ${clearing.words}`
          : ` ${others.join(", ")} ${others.length === 1 ? "is" : "are"} on your Second Semester registration. ${dropOthersWords(others)}.`}
      </Note>
      {shown ? (
        <Panel title={clearing.remove ? "Remove before you register SIWES" : "In the way of your SIWES course"} right={`${shown} course${shown === 1 ? "" : "s"}`}>
          <PBody>
            {ordinary.map((e) => row(e, false))}
            {waiting.length ? <div className={`eyebrow${ordinary.length ? " mt-2" : ""}`}>Carry-overs and deferred courses</div> : null}
            {waiting.map((e) => row(e, true))}
            {/* K11: the reset door judges the SIWES Second Semester by reset_refusal alone; it clears carry-overs and deferred courses too */}
            {clearing.reset ? (
              <div className="row mt-2" style={{ alignItems: "center", flexWrap: "wrap", gap: 8 }}>
                <span className="sub2 grow">{SIWES_RESET_WORDS}</span>
                <Btn kind="ghost" disabled={busy !== null} onClick={() => setAskReset(true)}>RESET COURSE REGISTRATION</Btn>
              </div>
            ) : null}
            {problem ? <ProblemNotice problem={problem} /> : null}
          </PBody>
        </Panel>
      ) : null}
      {askReset && v.registration ? (
        <ResetModal s={s} v={v} kind="siwes" count={(v.registration.entries ?? []).filter(onRecord).length} units={v.registration.units}
          onClose={() => setAskReset(false)} />
      ) : null}
    </>
  );
}

/** V491: the student's reset of the semester's registration, through the reset door (POST /me/registration/reset); the words by whose
 *  registration it is — every course a spillover student added (V682); in a SIWES Second Semester (K11) the courses, carry-overs and
 *  deferred courses, which wait for a later semester; otherwise the student's courses, the carry-overs the published results state
 *  staying. A refusal shows in the modal with its remedy. */
function ResetModal({ s, v, kind, count, units, onClose }: { s: MeCore; v: RegistrationView; kind: "siwes" | "carryOnly" | "ordinary"; count: number; units: number; onClose: () => void }) {
  const { act, busy, problem } = useAct();
  const siwes = kind === "siwes";
  return (
    <Modal title="RESET COURSE REGISTRATION?"
      sub={siwes ? "This clears your Second Semester registration, so that your SIWES course can be registered alone on the SIWES page."
        : "This will remove your current editable course registration for this session/semester and allow you to register your courses again."}
      onClose={() => { if (busy === null) onClose(); }}
      foot={<>
        <Btn kind="ghost" disabled={busy !== null} onClick={onClose}>CANCEL</Btn>
        <Btn kind="urgent" busy={busy === "reset"} busyLabel="Resetting registration..." onClick={async () => {
          const j = await act("reset", "POST", "/me/registration/reset",
            { session: v.session, semester: v.semester, reason: siwes ? "Reset by the student: the Second Semester is SIWES" : "Reset by the student to register the courses again" },
            siwes ? "Course registration reset by the student: the Second Semester is SIWES" : "Course registration reset by the student", "");
          if (j) { onClose(); notify(siwes ? "Registration cleared. Register your SIWES course on the SIWES page." : "Registration cleared. Select your courses and submit again."); }
        }}>{siwes ? "RESET THE REGISTRATION" : "RESET AND RE-REGISTER"}</Btn>
      </>}>
      <div className="grid grid--2">
        <div className="kv"><span className="k">Academic session</span><span className="v tnum">{v.session}</span></div>
        <div className="kv"><span className="k">Semester</span><span className="v">{semesterName(v.semester)}</span></div>
        <div className="kv"><span className="k">Student</span><span className="v">{s.name}</span></div>
        <div className="kv"><span className="k">Programme</span><span className="v">{s.programme}</span></div>
        <div className="kv"><span className="k">Level</span><span className="v tnum">{v.level} Level</span></div>
        <div className="kv"><span className="k">Current courses</span><span className="v tnum">{count} ({units} units)</span></div>
      </div>
      <p className="sub2" style={{ marginBottom: 0 }}>{siwes
        ? "The courses, carry-overs and deferred courses are cleared; carry-overs and deferred courses wait for a later semester. Then register your SIWES course on the SIWES page."
        : kind === "carryOnly" ? "Every course on the registration is cleared, and you pick your carry-overs again."
        : "The carry-overs your published results state stay on the registration; a carry-over you declared is cleared with your other courses."} Your results, payments, GST/EPS entitlement and earlier semesters are not changed.</p>
      {problem ? <ProblemNotice problem={problem} /> : null}
    </Modal>
  );
}

function RegisterClosed({ v }: { v: RegistrationView }) {
  const reg = v.registration;
  return (
    <>
      <Note kind="info" title={v.closed!.code === "REG_STUDENT_GRADUATED" ? "You have graduated" : v.closed!.code === "REG_STUDENT_AWARD_APPROVED" ? "Your award is approved" : "Course registration is closed"}
        action={<div className="row"><LinkBtn kind="ghost" href="/student/graduation">Graduation & clearance</LinkBtn><LinkBtn kind="ghost" href="/student/registration-history">Registration history</LinkBtn></div>}>
        {v.closed!.words} {v.closed!.remedy}
      </Note>
      {reg ? (
        <Panel title={`Your registration for ${v.session}, ${v.semester === 1 ? "first" : v.semester === 2 ? "second" : "third"} semester`} right={`${reg.status} · ${reg.units} CU`}>
          <DTable cols={["Course code", "Course title", "Units|num", "Type"]} rows={(reg.entries ?? []).filter(onRecord).map((e) => [
            <b key="c">{codeTaken(e.courseCode, e.codeAsTaken)}</b>, <span key="t">{e.title}</span>, <span key="u" className="tnum">{e.units}</span>, <span key="k">{e.entryType}</span>,
          ])} />
        </Panel>
      ) : null}
    </>
  );
}

function RegisterForm({ s, v, siwesSemester = null, siwesFee = null, siwesShut = null }: { s: MeCore; v: RegistrationView;
  /** V752: the Second Semester the SIWES rule binds, and the student's SIWES course (the one registered, once registered) */
  siwesSemester?: { course: string | null } | null;
  /** V777: the SIWES fee the Bursary has published, where the student's SIWES is read here (named in the note over a locked course) */
  siwesFee?: number | string | null;
  /** V777: why the SIWES fee cannot be paid now (the SIWES window is not open), in words: no PAY SIWES FEE link is drawn while it is said */
  siwesShut?: string | null }) {
  const { act, busy, problem } = useAct();
  const reg = v.registration;
  // V752: a Second Semester the SIWES rule binds (the note above it, or the server's window): nothing is added to it here — the SIWES
  // course is registered on the SIWES page — and the SIWES course is never dropped here; V503's attachment semester adds nothing either
  const siwesSem = !!siwesSemester || (v.semester === 2 && v.window?.siwes === true);
  const siwesCourse = siwesSemester?.course ?? null;
  const isSiwesCourse = (code: string) => siwesSem && siwesCourse !== null && code === siwesCourse;
  const noAdds = !!v.siwes || siwesSem;
  // V674: a spillover student registers carry-overs only: the level's courses are not offered as fresh courses — every course is added
  // through ADD CARRY-OVER, and the server enters any course of theirs as a carry-over
  // V682: and no course is listed for them to register, the carry-overs the results state included (the picker lists those first):
  // the registration holds only the courses they add, each removable before submission
  const carryOnly = v.carryOnly === true;
  // V711: except the programme's electives, which a spillover student may add as electives (fresh courses of their choice, never
  // carry-overs); an elective already on the registration as a carry-over (as V674 entered it) stays with the carry-overs
  const menu = carryOnly
    ? v.menu.filter((m) => !m.carryover && !m.deferred && courseCategory({ basis: m.basis, kind: m.kind }) === "ELECTIVE"
        && !(reg?.entries ?? []).some((e) => e.offeringId === m.offering_id && e.status !== "DROPPED" && courseCategory(e) !== "ELECTIVE"))
    : v.menu;
  // V491: where the Head's approval is suspended, a registration that passes the rules is approved on submission
  const auto = v.approval?.mode === "AUTO_APPROVAL";
  const [askReset, setAskReset] = useState(false);
  const [adding, setAdding] = useState(false);
  // V611, V663: the carry-over picker — every earlier course, ticked and added at once; opened from the dashboard by ?carry=1
  // and the side menu's Add Carry-Over: opened each time the link is followed (the page may already be showing), the link taken off
  // the address when the picker closes so that the next click opens it again
  const params = useSearchParams();
  const router = useRouter();
  const carryAsked = params.get("carry") === "1" && !noAdds;
  const [addingCarry, setAddingCarry] = useState(carryAsked);
  const [carrySeen, setCarrySeen] = useState(carryAsked);
  if (carryAsked !== carrySeen) { setCarrySeen(carryAsked); if (carryAsked) setAddingCarry(true); }
  const closeCarry = () => {
    setAddingCarry(false);
    if (!params.has("carry")) return;
    const rest = new URLSearchParams(params.toString()); rest.delete("carry");
    router.replace(`/student/register${rest.toString() ? `?${rest}` : ""}`, { scroll: false });
  };
  const locked = !!reg && (reg.status === "SUBMITTED" || reg.status === "APPROVED" || reg.status === "LOCKED");
  // the carry-overs and deferred courses the menu puts on are not the student's choice; a carry-over the student added (V611: one
  // declared, its result not on the portal) is
  // a course dropped, or taken off the registration by the Directorate of ICT (withdrawn), starts unticked — in spillover or not — so
  // that a save never puts it back
  const chosenNow = new Set((reg?.entries ?? []).filter((e) => onRecord(e) && (carryOnly
    || (e.entryType !== "CARRYOVER" && e.entryType !== "DEFERRED") || e.studentAdded || e.addedAs === "CARRY_OVER_DECLARED")).map((e) => e.offeringId));
  const [chosen, setChosen] = useState<Set<string>>(chosenNow);
  // a menu course whose entry was taken off the registration is shown removed: never ticked, never counted
  const removedIds = new Set((reg?.entries ?? []).filter(takenOff).map((e) => e.offeringId));
  const removed = (m: RegistrationView["menu"][number]) => removedIds.has(m.offering_id);
  const carry = menu.filter((m) => m.carryover && !m.deferred);
  const deferredCourses = menu.filter((m) => m.deferred);
  // Group by the PER-PROGRAMME offer basis, not the course's global kind: a course can be Core for
  // its own department yet Elective for this programme (course_offer.basis). GST (General Studies) is a University requirement.
  // V504: GST, core and elective in the University's order, each from the programme's own setup (registration.entry_category)
  // V620: a course already on the registration is read as registered — its category (the programme's basis for it at the time)
  // and its units — never as the menu reads its binding today; one not yet chosen as the menu reads it
  const entryOf = new Map((reg?.entries ?? []).filter(onRecord).map((e) => [e.offeringId, e] as const));
  const menuCategory = (m: RegistrationView["menu"][number]) => { const e = entryOf.get(m.offering_id); return e ? courseCategory(e) : courseCategory({ basis: m.basis, kind: m.kind }); };
  const menuUnits = (m: RegistrationView["menu"][number]) => entryOf.get(m.offering_id)?.units ?? m.units;
  // V389: a postgraduate programme's research and deficiency courses are neither core nor electives
  const special = menu.filter((m) => !m.carryover && (m.basis === "Research" || m.basis === "Deficiency"));
  const gstCourses = menu.filter((m) => !m.carryover && !special.includes(m) && menuCategory(m) === "GST");
  const core = menu.filter((m) => !m.carryover && !special.includes(m) && menuCategory(m) === "CORE");
  const elec = menu.filter((m) => !m.carryover && !special.includes(m) && menuCategory(m) === "ELECTIVE");
  // V504: the courses the student added beside the recommended list (the engine judged each; saving judges them again)
  const menuIds = new Set(menu.map((m) => m.offering_id));
  // V620: and a course registered under a binding since changed or removed — on no menu now, kept as registered
  // V682: a spillover student's every course is one they added
  const extras = byOrder((reg?.entries ?? []).filter((e) => onRecord(e) && !menuIds.has(e.offeringId)
    && (carryOnly || e.studentAdded || e.addedAs === "CARRY_OVER_DECLARED" || (e.entryType !== "CARRYOVER" && e.entryType !== "DEFERRED"))));
  // a course on the registration, in words: how it came on (V504, V611), or — a spillover student's (V682) — the carry-over the results state
  const addedWords = (e: (typeof extras)[number]) => addedAsLabel(e.addedAs)
    ?? (carryOnly ? "Carry-over · your results show it failed" : e.studentAdded ? "Added by you" : "Registered before your programme's structure changed; kept as registered");
  // V504: the carry-overs the published results state that are not on this semester's list, and why (V682: a spillover student finds them
  // in the picker)
  const away = carryOnly ? [] : (v.outstanding ?? []).filter((o) => !menu.some((m) => m.carryover && m.course_code === o.course_code));
  const chosenMenu = menu.filter((m) => !m.carryover && chosen.has(m.offering_id) && !removed(m));
  const chosenExtras = extras.filter((e) => chosen.has(e.offeringId));
  // V512: a GST/EPS carry-over the GST fee holds is not on the registration until the fee is paid: listed, not counted
  const onReg = new Set((reg?.entries ?? []).filter(onRecord).map((e) => e.offeringId));
  // V777: and a SIWES carry-over the unpaid SIWES fee holds (every SIWES course carries it): the draft leaves it off until the fee is paid
  const heldCarry = (m: RegistrationView["menu"][number]) => (!!m.gstLocked || !!m.siwesLocked) && !onReg.has(m.offering_id);
  // V777: a SIWES course (a carry-over or not) the unpaid fee locks, held off the form like a GST/EPS course; one already on the
  // registration (registered before every SIWES course carried the fee) is not locked — it stands, and the note below asks the fee;
  // one the Directorate of ICT took off the registration is shown removed, and no note asks the fee for a course only ICT can put back
  const siwesHold = (m: RegistrationView["menu"][number]) => !!m.siwesLocked && !onReg.has(m.offering_id) && !removed(m);
  const siwesOnRegistration = menu.filter((m) => !!m.siwesLocked && onReg.has(m.offering_id) && !removed(m) && siwesLockKind(m.siwesGate) === "UNPAID").map((m) => shownCode(m.course_code));
  const siwesPage = `/student/siwes?session=${encodeURIComponent(v.session)}`;
  // a carry-over or deferred course the menu puts on counts unless the GST fee holds it or it was taken off the registration
  const carryCounts = (m: RegistrationView["menu"][number]) => !heldCarry(m) && !removed(m);
  const chosenTotal = carry.filter(carryCounts).reduce((n, m) => n + menuUnits(m), 0) + deferredCourses.filter(carryCounts).reduce((n, m) => n + menuUnits(m), 0)
    + chosenMenu.reduce((n, m) => n + menuUnits(m), 0) + chosenExtras.reduce((n, e) => n + e.units, 0);
  // V504: the selection as it will be registered, in the University's order, numbered on
  const selected = byOrder<{ key: string; code: string; title: string; units: number; category: string; note: string | null }>([
    ...menu.filter((m) => !removed(m) && ((m.carryover && !heldCarry(m)) || chosen.has(m.offering_id))).map((m) => ({ key: m.offering_id, code: m.course_code, title: m.title, units: menuUnits(m),
      category: m.carryover ? courseCategory({ basis: m.deferred ? "Deferred" : "Carryover", kind: m.kind }) : menuCategory(m),
      note: m.deferred ? "Deferred" : m.carryover ? (m.kind === "GST" ? `Carry-over · ${gstOffice(m.course_code)}` : "Carry-over") : null })),
    ...chosenExtras.map((e) => ({ key: e.offeringId, code: e.courseCode, title: e.title, units: e.units, category: courseCategory(e), note: addedWords(e) })),
  ]);
  // a course the student added beside the menu, with its Remove (saving the selection without it): V611 lists a declared carry-over
  // under Carry-over courses, the others under Add other courses
  const extraRow = (e: (typeof extras)[number]) => (
    <div key={e.offeringId} className="row" style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)", alignItems: "center" }}>
      <span className="tnum b600" style={{ minWidth: 92 }}>{shownCode(e.courseCode)}</span>
      <span className="grow">{e.title} <span className="sub2">· {addedWords(e).charAt(0).toLowerCase() + addedWords(e).slice(1)}</span></span>
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
  const registered = byOrder((reg?.entries ?? []).filter(onRecord));
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
    : carry.filter(carryCounts).reduce((n, m) => n + menuUnits(m), 0) + deferredCourses.filter(carryCounts).reduce((n, m) => n + menuUnits(m), 0)
      + chosenExtras.filter((e) => isCarry(e.entryType)).reduce((n, e) => n + e.units, 0);
  const currentUnits = total - carryUnits;
  // V663: the carry-overs on the selection, for the carry-over summary — those the results place and those the student added
  const levelOf = (code: string) => { const m = /(\d)\d\d/.exec(code); return m ? Number(m[1]) * 100 : null; };
  const carryOn = carrySummary([
    ...carry.filter(carryCounts).map((m) => ({ units: menuUnits(m), level: levelOf(m.course_code) })),
    ...chosenExtras.filter((e) => isCarry(e.entryType)).map((e) => ({ units: e.units, level: levelOf(e.courseCode) })),
  ]);
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
  // V690: a GST/EPS course on the registration while the GST fee is unpaid
  const gstUnpaid = unpaidGstRegistered(reg?.entries, v.gst);
  // gate on THIS semester's fees, not only the open one — a full-session payment clears an
  // earlier semester the student never registered, so they can go back and register it now
  const cleared = v.clears ?? (fees.clearsRegistration === true);
  /* V616: a spillover student's choice of courses is what makes the semester's fee due; the submission waits for it */
  const spillPays = fees.spilloverBySemester === true;
  // V664: the semester being registered, as the server reads it — its own spillover fee, paid, outstanding, and where it stands
  const spillSem = spillPays ? fees.spillover?.semesters.find((x) => x.semester === v.semester) ?? null : null;
  const spillWords = spillSem?.status ? registeringWords(spillSem) : null;

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
    // V752: a SIWES Second Semester is not closed — the gate sends it to the SIWES page. The note above says so (and how the courses in
    // the way leave it); without that note, the gate's own words, never "the Academic Office opens the semester"
    if (siwesSem) {
      if (siwesSemester) return switcher;
      return (
        <>
          {switcher}
          <Note kind="info" title="Your Second Semester is SIWES (industrial training)" action={<LinkBtn kind="primary" href="/student/siwes">Go to SIWES</LinkBtn>}>{v.window.gate}</Note>
        </>
      );
    }
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
  if (!cleared && !locked && !(spillWords && fees.stated !== false)) {
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

  // a course taken off the registration by the Directorate of ICT is shown removed: disabled, never ticked, never counted
  const pick = (m: RegistrationView["menu"][number], fixed: boolean, on: boolean, red = false) => removed(m) ? (
    <div key={m.offering_id} className="pick" data-on={0} aria-disabled="true" title={REMOVED_WORDS} style={{ cursor: "default", opacity: 0.7 }}>
      <div className="pick__box" />
      <div className="grow"><div className="pick__t tnum">{courseLabel(m.course_code, m.title)}</div>
        <div className="pick__s">{REMOVED_WORDS}</div></div>
      <Pil kind="grey">Removed</Pil>
      <div className="tnum b700" style={{ color: "var(--muted)", textDecoration: "line-through" }}>{m.units}</div>
    </div>
  ) : (
    <button type="button" key={m.offering_id} className="pick" data-on={on ? 1 : 0} disabled={fixed || locked || !!m.gstLocked || siwesHold(m) || (!!m.prerequisiteLocked && !on)}
      style={red ? { borderColor: "var(--red-line)", background: "var(--red-bg)" } : m.gstLocked || siwesHold(m) || (m.prerequisiteLocked && !on) ? { borderColor: "var(--red-line)", opacity: 0.75 } : undefined}
      title={m.gstLocked ? "Locked until the GST fee is paid" : siwesHold(m) ? SIWES_LOCK_TITLE[siwesLockKind(m.siwesGate)] : m.prerequisiteLocked ? `Pass ${m.prerequisitesUnmet} first` : m.prerequisitesUnmet ? `Prerequisite not yet passed: ${m.prerequisitesUnmet}` : undefined}
      onClick={() => { if (fixed || locked || m.gstLocked || siwesHold(m)) return; const n = new Set(chosen); if (n.has(m.offering_id)) n.delete(m.offering_id); else if (m.prerequisiteLocked) return; else n.add(m.offering_id); setChosen(n); }}>
      <div className="pick__box" style={on ? { background: red ? "var(--red)" : "var(--chrome)", borderColor: red ? "var(--red)" : "var(--chrome)" } : undefined}>{on ? <Tick size={12} colour="#fff" /> : null}</div>
      <div className="grow"><div className="pick__t tnum">{courseLabel(m.course_code, m.title)}</div>
        <div className="pick__s" style={red ? { color: "var(--red-deep)" } : undefined}>{m.deferred ? `Deferred · originally ${m.deferred_from ?? ""} · status DEFERRED` : m.carryover ? `Failed ${m.failed_in} — must be repeated` : m.basis === "Borrowed" ? `Owned by ${m.owner_dept} — open to this programme at ${v.level} level` : m.basis === "GST" ? "University requirement" : m.lecturer ? `${m.lecturer}` : "No lecturer allocated yet"}</div></div>
      {m.basis === "Borrowed" ? <Pil kind="info">{m.owner_dept}</Pil> : null}
      {m.basis === "Research" || m.basis === "Deficiency" ? <Pil kind={m.basis === "Research" ? "ok" : "warn"}>{m.basis}</Pil> : null}
      {m.gstLocked ? <Pil kind="bad">GST fee required</Pil> : null}
      {m.siwesLocked ? <Pil kind="bad">{SIWES_LOCK_PILL[siwesLockKind(m.siwesGate)]}</Pil> : null}
      {m.prerequisitesUnmet ? <Pil kind={m.prerequisiteLocked ? "bad" : "warn"}>{`Needs ${m.prerequisitesUnmet}`}</Pil> : null}
      <div className="tnum b700" style={{ color: red ? "var(--red-ink)" : on ? "var(--chrome)" : "var(--muted)" }}>{m.units}</div>
    </button>
  );

  // V512: a carry-over or deferred course: held on the GST fee (a GST/EPS course), to register (not yet on the registration), or on it;
  // one taken off the registration by the Directorate of ICT shown removed, with nothing to register
  const carryRow = (m: RegistrationView["menu"][number], red: boolean) => removed(m) ? pick(m, true, false) : heldCarry(m) && m.siwesLocked ? (
    // V777: a SIWES carry-over waits for the SIWES fee — every SIWES course carries it, a carry-over included; the draft left it off
    <div key={m.offering_id} className="pick" data-on={0} style={{ cursor: "default", borderColor: "var(--red-line)", background: "var(--red-bg)" }}>
      <div className="pick__box" />
      <div className="grow"><div className="pick__t tnum">{courseLabel(m.course_code, m.title)}</div>
        <div className="pick__s" style={{ color: "var(--red-deep)" }}>{m.deferred ? `Deferred from ${m.deferred_from ?? ""}` : `Failed ${m.failed_in}`} — a SIWES course: {{
          UNPAID: "the SIWES fee is required before it can be registered",
          FEE_NOT_SET: "the Bursary has not published the SIWES fee yet; it is registered once the fee is published and paid",
          NOT_IN_REACH: "not open to you: your programme carries no SIWES course at your level",
        }[siwesLockKind(m.siwesGate)]}</div></div>
      <Pil kind="info">SIWES</Pil>
      {siwesLockKind(m.siwesGate) === "UNPAID" && !siwesShut ? <LinkBtn kind="urgent" size="sm" href={siwesPage}>PAY SIWES FEE</LinkBtn> : null}
      <div className="tnum b700" style={{ color: "var(--muted)" }}>{m.units}</div>
    </div>
  ) : heldCarry(m) ? (
    // V512: a GST/EPS carry-over waits for the GST fee — being a carry-over does not pass it
    <div key={m.offering_id} className="pick" data-on={0} style={{ cursor: "default", borderColor: "var(--red-line)", background: "var(--red-bg)" }}>
      <div className="pick__box" />
      <div className="grow"><div className="pick__t tnum">{courseLabel(m.course_code, m.title)}</div>
        <div className="pick__s" style={{ color: "var(--red-deep)" }}>{m.deferred ? `Deferred from ${m.deferred_from ?? ""}` : `Failed ${m.failed_in}`} — a {gstOffice(m.course_code)} course: GST/EPS PAYMENT REQUIRED before it can be registered</div></div>
      <Pil kind="info">{gstOffice(m.course_code)}</Pil>
      <LinkBtn kind="urgent" size="sm" href={`/student/gst?session=${encodeURIComponent(v.session)}`}>PAY GST/EPS FEE</LinkBtn>
      <div className="tnum b700" style={{ color: "var(--muted)" }}>{m.units}</div>
    </div>
  ) : reg && !onReg.has(m.offering_id) ? (
    <div key={m.offering_id} className="pick" data-on={0} style={{ cursor: "default", borderColor: "var(--red-line)" }}>
      <div className="pick__box" />
      <div className="grow"><div className="pick__t tnum">{courseLabel(m.course_code, m.title)}</div>
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
      {spillWords && spillSem ? (
        // V664: this semester's spillover fee on its own — a payment for another semester never opens it
        <Note kind={spillWords.pay ? "bad" : spillSem.status === "PAID" ? "ok" : "info"} title={spillWords.title}
          action={spillWords.pay ? <LinkBtn kind="urgent" href="/student/fees">PAY NOW {naira(spillWords.amount)}</LinkBtn> : <Pil kind={SEMESTER_STATUS_WORDS[spillSem.status!][1]}>{SEMESTER_STATUS_WORDS[spillSem.status!][0]}</Pil>}>
          {spillWords.body}
          {spillSem.registered ? (
            <div className="row mt-2" style={{ flexWrap: "wrap", gap: "var(--s-3)" }}>
              <span className="tnum"><span className="sub2">{spilloverSemesterWord(v.semester)} spillover fee</span> <b>{naira(spillSem.owed ?? spillSem.fee)}</b></span>
              <span className="tnum"><span className="sub2">Paid</span> <b className="ink-green">{naira(spillSem.paid ?? 0)}</b></span>
              <span className="tnum"><span className="sub2">Outstanding</span> <b className={Number(spillSem.outstanding ?? 0) >= 1 ? "ink-red" : ""}>{naira(spillSem.outstanding ?? 0)}</b></span>
            </div>
          ) : null}
        </Note>
      ) : spillPays ? (
        <Note kind="info" title="In spillover, you pay for the semesters you register">
          Choosing a course here makes this semester&rsquo;s school fees due{cleared ? "; they are paid, so the registration can be submitted." : "; the registration is submitted once they are paid."}
        </Note>
      ) : null}
      {/* V690: a GST/EPS course on the registration with the GST fee unpaid (added before the gate held it): the fee is paid for it */}
      {gstUnpaid.length ? (
        <Note kind="bad" title="GST PAYMENT REQUIRED" action={<LinkBtn kind="urgent" href={`/student/gst?session=${encodeURIComponent(v.session)}`}>PAY GST FEE</LinkBtn>}>
          {gstUnpaid.join(", ")} {gstUnpaid.length === 1 ? "is" : "are"} on your registration, but the GST fee of <b className="tnum">{naira(Number(v.gst!.fee))}</b> for {v.session} is
          not paid. Pay it on GST &amp; EPS: one payment covers GST and EPS. Your examination card and the GST &amp; EPS permit wait for it.
        </Note>
      ) : null}
      {/* V777: a SIWES course on the registration with the SIWES fee unpaid (registered before every SIWES course carried it): the fee is paid for it */}
      {siwesOnRegistration.length ? (
        <Note kind="bad" title="SIWES fee required" action={siwesShut ? undefined : <LinkBtn kind="urgent" href={siwesPage}>PAY SIWES FEE</LinkBtn>}>
          {siwesUnpaidRegisteredWords(siwesOnRegistration, v.session, siwesFee, siwesShut)}
        </Note>
      ) : null}
      {carryOnly ? (
        <Note kind="info" title="IN SPILLOVER, THE COURSES YOU STILL OWE ARE CARRY-OVERS"
          action={!noAdds && (!locked || v.addDropOpen) ? <Btn kind="urgent" disabled={busy !== null} onClick={() => setAddingCarry(true)}>ADD CARRY-OVER</Btn> : undefined}>
          You have completed your programme&rsquo;s years, so you register only the courses you still owe. Pick them with ADD CARRY-OVER &mdash; of your
          level and the levels before it, those your results show failed listed first. Each is registered as a carry-over, never as a fresh course; as you
          pick, the window shows this semester&rsquo;s spillover fee, owed once a course is on your registration. You may also add an elective of your
          programme below; it is registered as an elective.
        </Note>
      ) : null}
      {/* V503's attachment semester; a SIWES Second Semester has its own note above the form */}
      {v.siwes && !siwesSemester ? (
        <Note kind="info" title="Industrial training (SIWES) semester">
          Register only the SIWES / industrial training course ({max} units) this semester — no other course and no carryover.
        </Note>
      ) : null}
      {locked ? (
        reg!.status === "SUBMITTED" && auto && v.reviewReason ? (
          <Note kind="bad" title="REGISTRATION REQUIRES REVIEW">
            {reasonWords(v.reviewReason)}. Your registration was submitted ({reg!.units} units) and is held until this is put right; the Academic Office checks it again
            {v.reset?.allowed ? `, or reset it ${siwesSemester ? "above" : "below"} and register again` : ""}.
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
      {/* V663: ADD CARRY-OVER from the dashboard on a registration that can take no more courses now */}
      {addingCarry && locked && !v.addDropOpen && !noAdds ? (
        <Note kind="info" title="Carry-overs are added in add and drop">
          Your registration for this semester is {reg!.status === "SUBMITTED" ? "submitted" : "approved"}, so no course can be added to it now.
          A carry-over can be added when the add and drop window opens{v.reset?.allowed ? ", or reset your registration below and register again" : ""}.
        </Note>
      ) : null}

      {/* K11: in a SIWES Second Semester the reset is offered in the SIWES note above, in its words, a draft included (the reset door
          judges it by reset_refusal alone); here only where that note is not shown */}
      {reg && v.reset?.allowed && !siwesSemester && (siwesSem || reg.status !== "DRAFT") ? (
        <Panel title="CURRENT COURSE REGISTRATION" right={`${registered.length} course${registered.length === 1 ? "" : "s"} · ${reg.units} units`}>
          <PBody>
            <div className="row" style={{ alignItems: "center", flexWrap: "wrap", gap: 8 }}>
              <span className="sub2 grow">{siwesSem ? SIWES_RESET_WORDS : carryOnly
                ? "Courses brought over from the old portal, or added in error? Clear this semester's registration and pick your carry-overs again. Every course you added is cleared; your results, payments and earlier semesters are not touched."
                : <>Courses brought over from the old portal, or chosen in error? Clear this semester&rsquo;s registration and choose your courses again. The carry-overs your published results state stay (those you declared are cleared with your other courses); your results, payments and earlier semesters are not touched.</>}</span>
              <Btn kind="ghost" disabled={busy !== null} onClick={() => setAskReset(true)}>RESET COURSE REGISTRATION</Btn>
            </div>
            {v.reset.history.length ? <div className="sub2 mt-1">Reset {v.reset.history.length} time{v.reset.history.length === 1 ? "" : "s"} this semester; last on {onDay(v.reset.history[0].reset_at)}.</div> : null}
          </PBody>
        </Panel>
      ) : null}
      {askReset && reg ? (
        <ResetModal s={s} v={v} kind={siwesSem ? "siwes" : carryOnly ? "carryOnly" : "ordinary"} count={registered.length} units={reg.units} onClose={() => setAskReset(false)} />
      ) : null}

      {locked && v.addDropOpen ? (() => {
        // a course taken off the registration (withdrawn) is not offered again here: only its undo by the Directorate of ICT puts it back
        const activeIds = new Set((reg?.entries ?? []).filter((e) => e.status !== "DROPPED").map((e) => e.offeringId));
        // V611: a carry-over the student declared is dropped as it was added; one the results state is repeated
        // V752: in a SIWES Second Semester the SIWES course is never dropped here (a carry-over there is removed in the note above)
        const droppable = byOrder((reg?.entries ?? []).filter((e) => onRecord(e) && (e.entryType !== "CARRYOVER" || e.addedAs === "CARRY_OVER_DECLARED") && e.entryType !== "DEFERRED"
          && !isSiwesCourse(e.courseCode)));
        // V752: and nothing is added to it: the SIWES course is registered on the SIWES page
        const addable = siwesSem ? [] : menu.filter((m) => !m.carryover && !activeIds.has(m.offering_id));
        if (siwesSem && !droppable.length) return null;
        return (
          <Panel title={siwesSem ? "Drop courses" : "Add or drop courses"} right="the add/drop window is open">
            <PBody>
              {problem ? <ProblemNotice problem={problem} /> : null}
              <div className="sub2">{siwesSem
                ? "Your Second Semester is SIWES: drop a course registered before SIWES bound it. Nothing is added here; your SIWES course is registered on the SIWES page."
                : <>You can still add or drop a course (not a carry-over your results state, or a course with a mark). Total: {min}–{max} units.</>}</div>
              {droppable.length ? (<>
                <div className="eyebrow mt-2">Registered — drop</div>
                {droppable.map((e) => (
                  <div key={e.offeringId} className="row" style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)" }}>
                    <span className="tnum b600" style={{ minWidth: 92 }}>{shownCode(e.courseCode)}</span>
                    <span className="grow">{e.title} <span className="sub2">· {e.units}u · {courseType(e)}</span></span>
                    <Btn kind="ghost" disabled={busy !== null} onClick={() => void act(`drop-${e.offeringId}`, "POST", "/me/registration/drop", { session: v.session, semester: v.semester, offering: e.offeringId }, `Dropped ${e.courseCode}`)}>{busy === `drop-${e.offeringId}` ? "Dropping…" : "Drop"}</Btn>
                  </div>
                ))}
              </>) : null}
              {addable.length ? (<>
                <div className="eyebrow mt-3">Offered — add</div>
                {addable.map((m) => (
                  <div key={m.offering_id} className="row" style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)" }}
                    title={m.siwesLocked ? SIWES_LOCK_TITLE[siwesLockKind(m.siwesGate)] : undefined}>
                    <span className="tnum b600" style={{ minWidth: 92 }}>{shownCode(m.course_code)}</span>
                    <span className="grow">{m.title} <span className="sub2">· {m.units}u · {m.lecturer ?? "no lecturer yet"}</span></span>
                    {m.siwesLocked ? (
                      // V777: a SIWES course the fee holds is listed with its pill and the SIWES page that takes the fee, as on the form — never an Add
                      // the database would refuse
                      <>
                        <Pil kind="bad">{SIWES_LOCK_PILL[siwesLockKind(m.siwesGate)]}</Pil>
                        {siwesLockKind(m.siwesGate) === "UNPAID" && !siwesShut ? <LinkBtn kind="urgent" size="sm" href={siwesPage}>PAY SIWES FEE</LinkBtn> : null}
                      </>
                    ) : (
                      <Btn kind="primary" disabled={busy !== null} onClick={() => void act(`add-${m.offering_id}`, "POST", "/me/registration/add", { session: v.session, semester: v.semester, offering: m.offering_id }, `Added ${m.course_code}`)}>{busy === `add-${m.offering_id}` ? "Adding…" : "Add"}</Btn>
                    )}
                  </div>
                ))}
              </>) : null}
              {!droppable.length && !addable.length ? <div className="sub2">Nothing to add or drop.</div> : null}
              {!noAdds ? (
                <div className="row mt-3" style={{ alignItems: "center", gap: 8 }}>
                  <span className="sub2 grow">{carryOnly ? "Select the courses you still owe, of your level and the levels before it." : "Select courses from previous levels that you have not cleared."}</span>
                  <Btn kind="urgent" disabled={busy !== null} onClick={() => setAddingCarry(true)}>ADD CARRY-OVER</Btn>
                </div>
              ) : null}
              {v.flex?.allow_other_courses !== false && !carryOnly && !siwesSem ? (
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
      {v.limit.basis !== "SIWES" && !siwesSem && (!locked || v.addDropOpen) ? <OverloadRequest session={v.session} semester={v.semester} total={total} max={max} /> : null}
      {locked ? (
        <div id="registered-courses">
        <Panel title="Your registered courses" right={`${registered.length} course${registered.length === 1 ? "" : "s"} · ${reg!.units} units`}>
          <PBody>
            {registered.length ? registered.map((e, i) => (
              <div key={e.offeringId} className="row" style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)" }}>
                <span className="tnum sub2" style={{ minWidth: 24 }}>{i + 1}</span>
                <span className="tnum b600" style={{ minWidth: 92 }}>{shownCode(e.courseCode)}</span>
                <span className="grow">{e.title}{e.lecturer ? <span className="sub2"> · {e.lecturer}</span> : null}{e.studentAdded ? <span className="sub2"> · {addedAsLabel(e.addedAs) ?? "added by you"}</span> : null}</span>
                <Pil kind={e.entryType === "CARRYOVER" ? "bad" : e.entryType === "DEFERRED" ? "warn" : isSiwesCourse(e.courseCode) ? "info" : "grey"}>{e.entryType === "DEFERRED" ? "Deferred" : isSiwesCourse(e.courseCode) ? "SIWES" : categoryWords(e)}</Pil>
                <span className="tnum b600" style={{ minWidth: 28, textAlign: "right" }}>{e.units}</span>
              </div>
            )) : <div className="sub2">No course is on this registration.</div>}
          </PBody>
        </Panel>
        </div>
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
                <div className="grow"><div className="pick__t tnum">{courseLabel(o.course_code, o.title)}</div>
                  <div className="pick__s" style={{ color: "var(--red-deep)" }}>Failed {o.failed_in} — {o.offering_id ? (v.siwes ? "not registered in the SIWES semester" : "not open to you this semester; ask your department")
                    : o.runs_in ? `not offered this semester; it runs in the ${o.runs_in} semester of ${v.session}` : `no class opened in ${v.session} yet — add it with ADD CARRY-OVER, which opens its class`}</div></div>
                <Pil kind="warn">Outstanding</Pil>
                <div className="tnum b700" style={{ color: "var(--muted)" }}>{o.units}</div>
              </div>
            ))}
            <div className="sub2 mt-1">These a published result places on your registration. A course of an earlier level you did not clear whose result is not on the portal: ADD CARRY-OVER below.</div>
          </PBody></Panel>
      ) : null}
      {v.window?.pg ? (
        <div className="sub2 mb-2">{v.specialisation ? <>Your specialisation: <b>{v.specialisation}</b>. The courses listed are your programme&rsquo;s for every student and those of your specialisation.</> : "No specialisation is set for you: the courses listed are your programme's for every student. The School of Postgraduate Studies sets a specialisation."}</div>
      ) : null}
      {v.codeFamily ? (
        <div className="sub2 mb-2">Your cohort registers <b>{v.codeFamily}-</b> course codes{v.codeFamily === "BSU" ? " until you graduate; a carry-over keeps the code it was failed under" : ""}. Where a course is listed under one code only, that is the one to take.</div>
      ) : null}
      {v.gst && !locked && v.gst.stated && !v.gst.entitled && Number(v.gst.fee) > 0 && menu.some((m) => m.gstLocked) ? (
        <Note kind="bad" title="GST PAYMENT REQUIRED" action={<LinkBtn kind="primary" href={`/student/gst?session=${encodeURIComponent(v.session)}`}>PAY GST FEE</LinkBtn>}>
          Pay the GST fee of <b className="tnum">{naira(Number(v.gst.fee))}</b> for {v.session} to register GST/EPS courses. One payment covers GST and EPS.
          {v.gst.state === "PENDING" ? " A reference is open; the courses unlock when it is confirmed." : ""}
        </Note>
      ) : null}
      {/* V777: a SIWES course locked on the form — the SIWES fee unpaid, or not yet published: what is done, and the SIWES page that takes the fee */}
      {!locked ? siwesLockNotes(menu.filter(siwesHold).map((m) => ({ code: shownCode(m.course_code), gate: m.siwesGate })), v.session, siwesFee, siwesShut).map((x) => (
        <Note key={x.title} kind={x.kind} title={x.title} action={x.pay ? <LinkBtn kind="primary" href={siwesPage}>PAY SIWES FEE</LinkBtn> : undefined}>{x.words}</Note>
      )) : null}
      {!locked && menu.some((m) => m.prerequisiteLocked) ? (
        <Note kind="info" title="Prerequisites not yet passed">
          A course marked &ldquo;Needs&rdquo; is locked until a pass in the course it names is published on your record. If you passed it and the result
          is not yet published, or you were exempted, ask your department; ICT Support can add the course on your ticket.
        </Note>
      ) : null}
      {!locked && !carryOnly ? (<>
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
      {!locked && carryOnly && elec.length ? (
        <Panel title="ELECTIVE COURSES" right="optional">
          <PBody>{elec.map((m) => pick(m, false, chosen.has(m.offering_id)))}
            <div className="sub2 mt-2">An elective you tick is registered as an elective, not a carry-over. Untick it before you submit if you do not want it.</div></PBody></Panel>
      ) : null}
      {!locked && special.length ? (
        <Panel title="Research and deficiency courses">
          <PBody>{special.map((m) => pick(m, false, chosen.has(m.offering_id)))}
            <div className="sub2 mt-2">A deficiency course earns no credit; register it where the School requires it of you.</div></PBody></Panel>
      ) : null}
      {!locked && !noAdds ? (
        <Panel title={<span className="ink-red">CARRY-OVER COURSES</span>} right={<Btn kind="urgent" disabled={busy !== null} onClick={() => setAddingCarry(true)}>ADD CARRY-OVER</Btn>}>
          <PBody>
            <div className="sub2">{carryOnly ? "The courses you still owe are registered as carry-overs: pick them with ADD CARRY-OVER, of your level and the levels before it. Each one you add is listed here; remove one before you submit if you added it in error." : "Select courses from previous levels that you have not cleared."}</div>
            {carryOn.count ? (
              <div className="row mt-2" style={{ flexWrap: "wrap", gap: "var(--s-3)" }}>
                <span><b className="tnum">{carryOn.count}</b> carry-over course{carryOn.count === 1 ? "" : "s"}</span>
                <span><b className="tnum">{carryOn.units}</b> credit units</span>
                {carryOn.byLevel.map(([l, n]) => <span key={l} className="sub2">{l} Level: <b className="tnum">{n}</b></span>)}
                <span className="sub2">Payment: <b>{cleared ? "VERIFIED" : "OUTSTANDING"}</b></span>
                <span className="sub2">Registration: <b>{reg ? reg.status === "DRAFT" ? "NOT YET SUBMITTED" : reg.status : "NOT YET SAVED"}</b></span>
              </div>
            ) : null}
            {(carryOnly ? extras : extras.filter((e) => e.addedAs === "CARRY_OVER_DECLARED")).map(extraRow)}
            {carryOnly && !extras.length ? <div className="sub2 mt-2">No course added yet.</div> : null}
          </PBody>
        </Panel>
      ) : null}
      {!locked && !noAdds && !carryOnly ? (
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
        <div id="registered-courses">
        <Panel title="SELECTED COURSES" right={`${selected.length} course${selected.length === 1 ? "" : "s"} · ${total} units`}>
          {selected.length ? (
            <div className="tablewrap" tabIndex={0}><table className="tbl--data" style={{ minWidth: 520 }}>
              <thead><tr><th className="mid">S/N</th><th>Course code</th><th>Course title</th><th className="mid">Units</th><th>Type</th><th>Category</th></tr></thead>
              <tbody>
                {selected.map((x, i) => (
                  <tr key={x.key}>
                    <td className="mid tnum">{i + 1}</td>
                    <td className="tnum b600">{shownCode(x.code)}</td>
                    <td>{x.title}{curriculumMark(x.code)}{x.note && x.category !== "CARRY_OVER" ? <div className="sub2">{x.note}</div> : null}</td>
                    <td className="mid tnum">{x.units}</td>
                    <td>{x.note === "Deferred" ? <Pil kind="warn">DEFERRED</Pil> : x.category === "CARRY_OVER" || x.note?.startsWith("Carry-over") ? <Pil kind="bad">CARRY-OVER</Pil> : <Pil kind="grey">CURRENT</Pil>}</td>
                    <td>{x.note === "Deferred" ? "Deferred" : x.note?.startsWith("Carry-over") ? x.note : CATEGORY_LABEL[courseCategory({ category: x.category })]}</td>
                  </tr>
                ))}
                <tr style={{ background: "var(--bg)" }}><td colSpan={3} className="b700">TOTAL CREDIT UNITS</td><td className="mid tnum b700">{total}</td>
                  <td colSpan={2} className="t-xs b600" style={{ color: meter.col }}>{meter.lab} · {min}–{max}</td></tr>
              </tbody>
            </table></div>
          ) : <PBody><div className="sub2">No course is selected yet.</div></PBody>}
        </Panel>
        </div>
      ) : null}
      {adding ? (
        <AddOtherCourse session={v.session} semester={v.semester} level={v.level} total={total} max={max} addDrop={locked}
          onAdded={(id) => { if (!locked) setChosen((c) => new Set(c).add(id)); }} onClose={() => setAdding(false)} />
      ) : null}
      {/* only where a course can still be added: before submission, or in add and drop (the dashboard's ?carry=1 included) */}
      {addingCarry && !noAdds && (!locked || v.addDropOpen) ? (
        <CarryOverPicker session={v.session} semester={v.semester} spillover={carryOnly} addDrop={locked}
          onAdded={(ids) => { if (!locked) setChosen((c) => { const n = new Set(c); ids.forEach((id) => n.add(id)); return n; }); }}
          onClose={closeCarry}
          onViewRegistered={() => document.getElementById("registered-courses")?.scrollIntoView({ behavior: "smooth", block: "start" })} />
      ) : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!locked ? (
        <div className="row">
          <Btn kind="ghost" disabled={busy !== null} onClick={() => void act("save", "PUT", "/me/registration", { session: v.session, semester: v.semester, offerings: [...chosen] }, "Course registration saved by the student")}>{busy === "save" ? "Saving…" : "Save the draft"}</Btn>
          <Btn kind="primary" disabled={!ok || busy !== null || (carryOnly && !selected.length)} onClick={async () => { const saved = await act("save", "PUT", "/me/registration", { session: v.session, semester: v.semester, offerings: [...chosen] }, "Course registration saved by the student"); if (saved) { const j = await act("submit", "POST", "/me/registration/submit", { session: v.session, semester: v.semester }, "Course registration submitted by the student", ""); if (j) notify(j.result === "approved" ? "REGISTRATION SUCCESSFUL — STATUS: APPROVED" : "Course registration submitted"); } }}>{busy === "submit" ? "VALIDATING REGISTRATION..." : busy === "save" ? "Registering…" : auto ? "SUBMIT COURSE REGISTRATION" : "Submit for approval"}</Btn>
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

export function Form({ s, v, siwes = null }: { s: MeCore; v: RegistrationView;
  /** V752: the student's SIWES for the session: a Second Semester registration that is the SIWES one prints as the SIWES course form */
  siwes?: MySiwes | null }) {
  const reg = v.registration;
  const siwesForm = isSiwesRegistration(siwes, v.session, v.semester);
  // the course the SIWES registration was made on, even when the programme has been mapped to another course since
  const siwesCode = siwesForm ? siwesCourseOf(siwes)?.code ?? null : null;
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
          <div className="eyebrow">{siwesForm ? "SIWES Course Registration Form" : "Course Registration Form"}</div>
        </div>
        <div className="row row--top" style={{ gap: "var(--s-5)", marginBottom: "var(--s-4)" }}>
          <Passport w={62} h={77} radius={3} src={s.hasPhoto ? `/api/bff/api/v1/me/passport?v=${encodeURIComponent(s.matricNo ?? s.admissionNo ?? s.id)}` : null} />
          <div className="kv"><span className="k">Name</span><span className="v">{s.name}</span></div>
          <div className="kv"><span className="k">Matriculation number</span><span className="v tnum">{s.matricNo ?? s.admissionNo}</span></div>
          <div className="kv"><span className="k">Level</span><span className="v">{reg.level}</span></div>
          <div className="kv"><span className="k">Session</span><span className="v tnum">{v.session}</span></div>
          <div className="kv"><span className="k">Semester</span><span className="v">{semesterName(v.semester)}</span></div>
        </div>
        {siwesForm ? (
          <div className="row" style={{ gap: "var(--s-5)", marginBottom: "var(--s-4)", flexWrap: "wrap" }}>
            {[["Programme", s.programme] as [string, string], ...siwesFormRows(siwes)].map(([k, val]) => (
              <div key={k} className="kv"><span className="k">{k}</span><span className="v tnum">{val}</span></div>
            ))}
          </div>
        ) : null}
        <div className="tablewrap" tabIndex={0}><table className="tbl--data" style={{ minWidth: 520 }}>
          <thead><tr>
            {["S/N", "Course code", "Course title", "Lecturer"].map((h) => <th key={h} style={{ background: "var(--chrome)", color: "var(--surface)" }}>{h}</th>)}
            <th className="mid" style={{ background: "var(--chrome)", color: "var(--surface)" }}>Unit</th>
            <th className="num" style={{ background: "var(--chrome)", color: "var(--surface)" }}>Type</th>
          </tr></thead>
          <tbody>
            {byOrder(reg.entries.filter(onRecord)).map((e, i) => { const co = e.entryType === "CARRYOVER" || e.entryType === "DEFERRED"; return (
              <tr key={e.offeringId}>
                <td className="tnum sub2">{i + 1}</td>
                <td className="tnum b600">{codeTaken(e.courseCode, e.codeAsTaken)}{co ? <span className="ink-red b700"> · C/O</span> : null}</td>
                <td>{e.title}</td>
                <td className="sub2">{e.lecturer ?? "—"}</td>
                <td className="mid tnum">{e.units}</td>
                <td className="num t-xs b600 ink-muted">{siwesCode && e.courseCode === siwesCode ? "SIWES" : e.basis === "Research" || e.basis === "Deficiency" ? courseType(e) : e.entryType === "DEFERRED" ? "Deferred" : categoryWords(e)}</td>
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
