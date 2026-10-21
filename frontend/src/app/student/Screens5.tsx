"use client";

/**
 * The student's services — proto/part29.html sQuery and sCarryover,
 * proto/part8.html sExams, sTimetable and sAttendance, proto/part25.html
 * sIdCard, proto/part4b.html studentTranscript, as drawn — from the record:
 * the query window that opens on publication, the papers the approved
 * registration carries in an open examination session, the slots the
 * department gave, the register the lecturer marked, the card the Library
 * issued, the transcript request staged as the Registry stages it.
 */
import { useState } from "react";
import type { Card, Docket, Me, Queries, RegistrationView, Results, Timetable, Transcripts } from "@/lib/student-portal";
import { STAGE_LABEL, WEEKDAY, semesterName } from "@/lib/student-portal";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Bar, Field, Passport } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PayByCard, naira, onDay, useAct, when } from "./common";
import { CardActions, PermitActions } from "./exams/CardActions";
import { permitStatusLabel, permitSummary, type PermitState } from "@/lib/gst-eps-permit";
import { examCardStatusLabel, examCardSummary, type ExamCardState } from "@/lib/exam-card";

/* ── result query ── */

export function Query({ q }: { q: Queries }) {
  const { act, busy, problem } = useAct();
  const [sheet, setSheet] = useState(q.queryable[0]?.sheet_id ?? "");
  const [part, setPart] = useState("EXAM");
  const [said, setSaid] = useState("");
  const open = q.queryable.length > 0;
  const answered = q.queries.filter((x) => x.state !== "RAISED");
  return (
    <>
      {open ? (
        <Note kind="info" title={`The query window is open until ${onDay(q.queryable.map((x) => x.window_until).sort().slice(-1)[0])}`}>
          A query is against <b>one mark in one course</b>. It goes to the department that owns the course, and the answer appears here.
        </Note>
      ) : (
        <Note kind="bad" title="The query window is not open">It opens when results are released and runs for seven days. {q.queries.length ? "Your earlier queries are below." : "There is nothing to query yet, because nothing has been published in the last seven days."}</Note>
      )}
      <Tiles items={[
        ["Window", open ? "Open" : "Closed", open ? "var(--green-ink)" : "var(--red-ink)", open ? `${q.queryable.length} course${q.queryable.length === 1 ? "" : "s"} may be queried` : "Opens on release"],
        ["Your queries", String(q.queries.length), null, "All sessions"],
        ["Answered", String(answered.length), answered.length ? "var(--green-ink)" : null, `${q.queries.length - answered.length} with the department`],
        ["Marks corrected", String(q.queries.filter((x) => x.state === "CORRECTED").length), "var(--chrome)", "Through the approval chain"],
      ]} />
      {open ? (
        <Panel title="Raise a query" right="One mark, one course">
          <PBody>
            <div className="grid grid--2">
              <Field id="q-course" label="Course"><select id="q-course" className="ctl" value={sheet} onChange={(e) => setSheet(e.target.value)}>{q.queryable.map((x) => <option key={x.sheet_id} value={x.sheet_id}>{x.course_code} — {x.title} · {x.outcome === "GRADED" ? `${x.total} (${x.grade})` : x.outcome}</option>)}</select></Field>
              <Field id="q-part" label="Which mark"><select id="q-part" className="ctl" value={part} onChange={(e) => setPart(e.target.value)}><option value="EXAM">The examination mark</option><option value="CA">The continuous assessment mark</option><option value="ABSENT">I was recorded absent and I sat the paper</option></select></Field>
            </div>
            <Field id="q-say" label="What you say is wrong"><textarea id="q-say" className="ctl" rows={2} value={said} onChange={(e) => setSaid(e.target.value)} placeholder="Say what you expected and why. If you collected your script, say so." /></Field>
            {problem ? <ProblemNotice problem={problem} /> : null}
            <div><Btn kind="primary" disabled={!sheet || !said.trim() || busy !== null} onClick={async () => { const ok = await act("raise", "POST", "/me/queries", { sheetId: sheet, part, said }, "Result query raised by the student"); if (ok) setSaid(""); }}>{busy === "raise" ? "Submitting…" : "Submit the query"}</Btn></div>
          </PBody>
        </Panel>
      ) : null}
      <Panel title="Your queries" right="With the answer each one got">
        <DTable cols={["Reference", "Course", "What you said", "Routed to", "State|mid", "Answer"]} rows={q.queries.map((x) => [
          <span className="tnum sub2" key="r">{x.ref}</span>,
          <Two key="c" a={<span className="tnum">{x.course_code}</span>} b={x.title} />,
          <span className="sub2" key="s">{x.said}</span>,
          <span className="sub2" key="d">{x.dept_name}</span>,
          x.state === "RAISED" ? <Pil kind="info" key="t">With the department</Pil> : x.state === "UPHELD" ? <Pil kind="ok" key="t">Upheld</Pil> : x.state === "CORRECTED" ? <Pil kind="info" key="t">Corrected</Pil> : <Pil kind="grey" key="t">Closed</Pil>,
          <span className="sub2" key="a">{x.answer ?? "—"}</span>,
        ])} />
        {!q.queries.length ? <PBody><div className="sub2">No query yet.</div></PBody> : null}
      </Panel>
      <Note kind="info" title="A corrected mark goes back through approval">
        Your published result changes only after the department, the faculty and Senate approve the amendment.
      </Note>
    </>
  );
}

/* ── carryover ── */

export function Carryover({ r }: { r: Results }) {
  const units = r.carryovers.reduce((n, c) => n + c.units, 0);
  return (
    <>
      {r.carryovers.length ? (
        <Note kind="bad" title={`You are carrying ${r.carryovers.length} course${r.carryovers.length === 1 ? "" : "s"}, ${units} units`}>
          Each is repeated in a semester where it is offered and counts towards that semester&rsquo;s maximum units.
        </Note>
      ) : (
        <Note kind="ok" title="You are carrying nothing">No published sheet has a fail against you that a later pass has not settled.</Note>
      )}
      {/* V611: the old portal's results are not here — a course failed there is declared on Course Registration */}
      <Note kind="info" title="Failed a course whose result is on the old portal?"
        action={<LinkBtn kind="primary" href="/student/register">Course registration</LinkBtn>}>
        This page lists the carry-overs the published results on this portal show. A course you registered in an earlier session whose
        result is not on this portal is not listed: add it yourself on Course Registration with + ADD CARRY-OVER COURSE. It is marked as a
        carry-over you declared, and your department sees it.
      </Note>
      <Tiles items={[
        ["Courses carried", String(r.carryovers.length), r.carryovers.length ? "var(--red-ink)" : null, `${units} units`],
        ["Units they take", String(units), null, "Against the level's maximum"],
        ["Standing", r.standing ?? "—", null, r.cgpa != null ? `CGPA ${r.cgpa}` : "Nothing published yet"],
        ["Registration", "Automatic", "var(--chrome)", "Added to the next form; cannot be removed"],
      ]} />
      <Panel title="What you are carrying" right="Each with the semester it failed in">
        <DTable cols={["Course", "Units|mid", "Failed in", "Note"]} rows={r.carryovers.map((c) => [
          <Two key="c" a={<span className="tnum">{c.course_code}</span>} b={c.title} />, <span className="tnum" key="u">{c.units}</span>,
          <span className="sub2 tnum" key="f">{c.failed_in}</span>, <span className="sub2" key="n">Registered before a new course, not after; every attempt appears on the transcript</span>,
        ])} />
      </Panel>
      <Panel title="How a repeat is scored" right="The rule">
        <PBody><KvGrid cls="grid--2" pairs={[["The attempt is recorded", "Every attempt appears on the transcript, including the failure"], ["The pass mark", "40, the same as any other attempt"], ["Units", "Counted once toward the degree, however many attempts"], ["Registration", "A carryover is registered before a new course, not after"]]} /></PBody>
      </Panel>
    </>
  );
}

/* ── examinations (the examination card) ── */

export function Exams({ d, permits = [], cards = [] }: { d: Docket; s: Me; current?: RegistrationView | null; permits?: PermitState[]; cards?: ExamCardState[] }) {
  const withPapers = d.examSessions.filter((x) => x.papers.length);
  // V501, V567: the examination card — the University's full examination permit — is the server's answer for each semester shown:
  // every student who has registered courses and paid school fees for the session has it, with every registered course; nothing
  // else is asked (no approval, release or clearance scheme). Dates and venues come with the timetable, never invented
  const shownCards = cards.filter((c) => c.registration || c.available);
  const cardOf = (session: string, semester: number) => cards.find((c) => c.session === session && c.semester === semester);
  const unpaid = shownCards.find((c) => c.code === "EXAM_CARD_NOT_PAID");
  return (
    <>
      {/* V567: withheld only while no school-fees payment for the session is on record */}
      {unpaid ? <Note kind="bad" title="Your examination card is issued once your school fees are paid" action={<LinkBtn kind="urgent" href="/student/fees">Fees & payments</LinkBtn>}>Your courses are registered. Once a school-fees payment for {unpaid.session} is on record the card is yours to print. A payment made at a bank or on Quickteller shows here once Interswitch reports it.</Note>
        : <Note kind="info" title="Bring your identity card">Your photograph is checked before the paper opens. Arrive 20 minutes early; late candidates are admitted at the invigilator&rsquo;s discretion and lose the time.</Note>}
      {shownCards.map((card) => (
        <Panel key={`card-${card.session}-${card.semester}`} title={`EXAMINATION CARD · ${card.session} · ${semesterName(card.semester)} semester`} right={examCardStatusLabel(card)}>
          <PBody>
            <div className={`sub2${card.available ? "" : " ink-red"}`}>{card.available
              ? `Courses registered and school fees paid · ${examCardSummary(card)}. The card carries every course you registered. Dates and venues appear when the examination timetable is released.`
              : card.reason}</div>
            {card.available ? <div className="mt-2"><CardActions session={card.session} semester={card.semester} /></div> : null}
          </PBody>
        </Panel>
      ))}
      {/* V492: the GST & EPS examination permit, a document of its own beside the card: only the GST and EPS courses registered */}
      {permits.filter((permit) => permit.courses.length || permit.permit).map((permit) => (
        <Panel key={permit.semester} title={`GST & EPS EXAMINATION PERMIT · ${permit.session} · ${semesterName(permit.semester)} semester`} right={permitStatusLabel(permit)}>
          <PBody>
            <div className="sub2">{permit.available ? `${permitSummary(permit)}. The permit lists only the GST and EPS courses on your course registration.` : permit.reason}</div>
            <div className="row row--inline mt-2" style={{ gap: 8, flexWrap: "wrap" }}>
              {permit.available ? <PermitActions session={permit.session} semester={permit.semester} /> : null}
              <LinkBtn kind="ghost" href={`/student/exams/gst-eps-permit?semester=${permit.semester}`}>VIEW GST & EPS PERMIT</LinkBtn>
            </div>
          </PBody>
        </Panel>
      ))}
      {!withPapers.length ? (
        shownCards.length ? null : <Note kind="info" title={`Examination cards for ${d.session} have not been released yet`}>Your papers and examination card appear here when released.</Note>
      ) : withPapers.map((x) => (
        <Panel key={x.id} title={`${x.session} · ${semesterName(x.semester)} semester · ${x.kind === "MAIN" ? "main" : x.kind.toLowerCase()} examinations`} right={`${onDay(x.exams_from)} – ${onDay(x.exams_to)}${cardOf(x.session, x.semester)?.available ? " · examination card" : ""}`}>
          <DTable cols={["Course", "Date & time", "Venue|mid", "Status|num"]} rows={x.papers.map((p) => [
            <Two key="c" a={p.course_code} b={p.title} />,
            <span className="tnum" key="w">{p.held_on ? `${onDay(p.held_on)} · ${String(p.starts_at).slice(0, 5)}` : "Not yet timetabled"}</span>,
            <span key="v">{p.venue ?? "—"}</span>,
            p.bar ? <Pil kind="bad" key="s" title={p.bar.replace(/^[A-Z_]+: /, "")}>Barred: attendance</Pil> : cardOf(x.session, x.semester)?.available === false ? <Pil kind="bad" key="s">Card withheld</Pil> : p.held_on ? <Pil kind="info" key="s">Card ready</Pil> : <Pil kind="grey" key="s">Awaiting slot</Pil>,
          ])} />
          {x.papers.some((p) => p.bar) ? <div className="card__body"><Note kind="bad" title="Attendance below the minimum">
            {x.papers.filter((p) => p.bar).map((p) => p.bar!.replace(/^[A-Z_]+: /, "").replace(/^your/, "Your")).join(". ")}. The Centre for Continuing Education&rsquo;s policy bars the examination of a class below its minimum attendance; see the Centre if a lecture you missed was excused.
          </Note></div> : null}
          {/* V501, V567: the card's buttons are on its own panel above, by the card's rule; a sitting of a semester whose card was not
              read here has its own, and the server answers when it is pressed */}
          {!cardOf(x.session, x.semester)
            ? <div className="card__body"><CardActions session={x.session} semester={x.semester} /></div> : null}
        </Panel>
      ))}
    </>
  );
}

/* ── timetable ── */

export function TimetableScreen({ t }: { t: Timetable }) {
  const days = [1, 2, 3, 4, 5, 6, 7].map((d) => ({ d, slots: t.slots.filter((x) => x.weekday === d) })).filter((x) => x.slots.length);
  const today = new Date().getDay() === 0 ? 7 : new Date().getDay();
  const mine = t.slots.filter((x) => x.weekday === today);
  return (
    <>
      <Note kind="info" title={`${WEEKDAY[today]} · ${t.session} · ${semesterName(t.semester)} semester`}>
        {mine.length ? `${mine.length} class${mine.length === 1 ? "" : "es"} today.` : "Nothing today."} {t.slots.some((x) => x.carryover) ? "Your carryover is on the timetable." : ""}
      </Note>
      {!t.slots.length ? <Note kind="info" title="No slot has been given to your courses yet" /> : null}
      {days.map((x) => (
        <Panel key={x.d} title={WEEKDAY[x.d]} right={x.d === today ? "today" : ""}>
          <DTable cols={["Time|mid", "Course", "Venue", "Lecturer"]} rows={x.slots.map((s) => [
            <strong className="tnum" key="t">{String(s.starts_at).slice(0, 5)}–{String(s.ends_at).slice(0, 5)}</strong>,
            <Two key="c" a={`${s.course_code}${s.carryover ? " (carryover)" : ""}`} b={`${s.title}${s.kind !== "LECTURE" ? ` · ${s.kind.toLowerCase()}` : ""}`} />,
            <span key="v">{s.venue}</span>, <span className="sub2" key="l">{s.lecturer ?? "—"}</span>,
          ])} />
        </Panel>
      ))}
    </>
  );
}

/* ── attendance ── */

export function AttendanceScreen({ t }: { t: Timetable }) {
  if (t.register) return <RegisterAttendance t={t} />;
  const below = t.attendance.filter((a) => a.rate !== null && a.rate < 75);
  return (
    <>
      {below.length ? (
        <Note kind="bad" title={`${below.map((b) => b.course_code).join(", ")} ${below.length === 1 ? "is" : "are"} below the 75% threshold`}>
          Students below 75% may be barred from the examination.
        </Note>
      ) : t.attendance.some((a) => a.held) ? (
        <Note kind="ok" title="Every course is at or above 75%">Recorded by your lecturers against the class list, lecture by lecture.</Note>
      ) : (
        <Note kind="info" title="No lecture has been recorded yet">Attendance appears here as lecturers mark the register against the class list.</Note>
      )}
      <Panel title={`Attendance · ${t.session} · ${semesterName(t.semester)} semester`} right="Recorded by the lecturer at each lecture">
        <DTable cols={["Course", "Attended|mid", "Held|mid", "Rate", "Status|num"]} rows={t.attendance.map((a) => [
          <Two key="c" a={a.course_code} b={a.title} />, <span className="tnum" key="a">{a.attended}</span>, <span className="tnum" key="h">{a.held}</span>,
          a.rate === null ? <span className="sub2" key="r">—</span> : <div key="r" className="row"><Bar pct={a.rate} colour={a.rate >= 75 ? "var(--green)" : "var(--red)"} /><span className="tnum b600">{a.rate}%</span></div>,
          a.rate === null ? <Pil kind="grey" key="s">Not yet held</Pil> : a.rate >= 75 ? <Pil kind="ok" key="s">Eligible</Pil> : <Pil kind="bad" key="s">At risk</Pil>,
        ])} />
      </Panel>
    </>
  );
}

/** V380: a CCE student's attendance, by the register of the Centre's evening classes — present, late, absent and excused — measured
 *  against the minimum the Centre set (none is invented when it has set none) */
function RegisterAttendance({ t }: { t: Timetable }) {
  if (t.attendanceShown === false) {
    return <Note kind="info" title="Attendance is not shown on the portal">Ask the Centre for Continuing Education for your attendance.</Note>;
  }
  const min = t.attendance.find((a) => a.min_percent != null)?.min_percent ?? null;
  const below = t.attendance.filter((a) => a.verdict === "NOT_ELIGIBLE");
  return (
    <>
      {below.length ? (
        <Note kind="bad" title={`${below.map((b) => b.course_code).join(", ")} ${below.length === 1 ? "is" : "are"} below the Centre's minimum of ${min}%`}>
          Students below the Centre&rsquo;s minimum may be barred from the examination.
        </Note>
      ) : t.attendance.some((a) => a.total) ? (
        <Note kind="ok" title={min != null ? `Every class is at or above the Centre's minimum of ${min}%` : "Your attendance as the lecturers marked it"}>
          Late counts as attended; an excused lecture is not counted.{min == null ? " No minimum attendance is set." : ""}
        </Note>
      ) : (
        <Note kind="info" title="No lecture has been recorded yet">Attendance appears here as your lecturers mark the registers of your evening classes.</Note>
      )}
      <Panel title={`Attendance · CCE ${t.session} · ${semesterName(t.semester)} semester`} right="Marked by the lecturer at each lecture">
        <DTable cols={["Course", "Present|mid", "Late|mid", "Absent|mid", "Excused|mid", "Rate", "Status|num"]} rows={t.attendance.map((a) => [
          <Two key="c" a={a.course_code} b={a.title} />, <span className="tnum" key="p">{a.present ?? 0}</span>, <span className="tnum" key="l">{a.late ?? 0}</span>,
          <span className="tnum" key="a">{a.absent ?? 0}</span>, <span className="tnum" key="e">{a.excused ?? 0}</span>,
          a.rate === null || !a.total ? <span className="sub2" key="r">—</span> : <div key="r" className="row"><Bar pct={a.rate} colour={a.verdict === "NOT_ELIGIBLE" ? "var(--red)" : "var(--green)"} /><span className="tnum b600">{a.rate}%</span></div>,
          !a.total ? <Pil kind="grey" key="s">Not yet held</Pil> : a.verdict === "NOT_ELIGIBLE" ? <Pil kind="bad" key="s">Below the minimum</Pil> : a.verdict === "ELIGIBLE" ? <Pil kind="ok" key="s">Meets the minimum</Pil> : a.verdict === "REQUIRES_REVIEW" ? <Pil kind="warn" key="s">Excused throughout</Pil> : <Pil kind="info" key="s">Recorded</Pil>,
        ])} />
      </Panel>
    </>
  );
}

/* ── identity card ── */

export function IdCard({ c, s }: { c: Card; s: Me }) {
  const { act, busy, problem } = useAct();
  const [now] = useState(() => Date.now());
  const live = c.cards.find((x) => x.state === "ISSUED" || x.state === "PRINTED") ?? null;   // V605: printed and awaiting collection, or in force
  /* the student sees the card's status, never the card: it is printed and issued by the University's card desk and handed over in
     person, so a picture or a printable copy of it is never offered here (portal gap audit: ID cards are the office's to produce) */
  const expired = live ? new Date(live.valid_to).getTime() < now : false;
  return (
    <>
      {live ? (
        live.state === "PRINTED" ? (
        <Note kind="info" title={`Card ${live.card_no} is printed — collect it from the Security Unit`}>Bring a fee receipt and come in person; the card is handed over against the photograph on your record.</Note>
      ) : (
        <Note kind={expired ? "bad" : "ok"} title={`Card ${live.card_no} · issued ${onDay(live.issued_at)} · ${expired ? "expired" : "valid to"} ${onDay(live.valid_to)}`}>{expired ? "Ask the card desk for a renewal." : "Collected in person from the card desk."}</Note>
      )
      ) : !c.matricNo ? (
        <Note kind="info" title="A card is made after matriculation">It is keyed on the matriculation number, which you do not have yet.</Note>
      ) : c.clearsIdCard === false ? (
        <Note kind="bad" title="Your card waits on the school-fee condition" action={<LinkBtn kind="urgent" href="/student/fees">Fees & payments</LinkBtn>}>Under the scheme in force, the identity card is released at the first instalment.</Note>
      ) : (
        <Note kind="info" title="Your card has not been issued yet">The card desk prints it and hands it over in person against the photograph on your record; bring your fee receipt.</Note>
      )}
      <div className="card"><div className="card__body row row--top" style={{ flexDirection: "row", gap: "var(--s-5)" }}>
        <Passport w={112} h={139} radius={5} src={s.hasPhoto ? `/api/bff/api/v1/me/passport?v=${encodeURIComponent(s.matricNo ?? s.admissionNo ?? s.id)}` : null} />
        <div className="grow" style={{ minWidth: 220 }}>
          <div className="phead__t">{s.name}</div>
          <div className="sub2 tnum">{s.matricNo ?? s.admissionNo} &middot; {s.programme} &middot; {s.level} Level</div>
          <KvGrid cls="grid--2" pairs={[["Card number", <span className="tnum" key="n">{live?.card_no ?? "—"}</span>], ["Valid to", live ? onDay(live.valid_to) : "—"], ["Faculty", s.faculty], ["Department", s.department]]} />
        </div>
      </div></div>
      {live ? (
        <div className="row">
          <Btn kind="ghost" disabled={busy !== null} onClick={() => { const reason = window.prompt("What happened to the card? This goes on the record; the card desk issues a replacement."); if (!reason) return; void act("lost", "POST", "/me/id-card/lost", { reason }, `Identity card reported lost: ${reason}`); }}>{busy === "lost" ? "Reporting…" : "Report it lost"}</Btn>
          <LinkBtn kind="ghost" href="/student/support">Request a replacement</LinkBtn>
        </div>
      ) : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title="Cards" right="Every card ever issued to you">
        <DTable cols={["Card", "Issued|mid", "Valid to|mid", "State|num"]} rows={c.cards.map((x) => [
          <span className="tnum" key="n">{x.card_no}</span>, <span className="sub2 tnum" key="i">{onDay(x.issued_at)}</span>, <span className="sub2 tnum" key="v">{onDay(x.valid_to)}</span>,
          x.state === "ISSUED" ? <Pil kind="ok" key="s">Live</Pil> : x.state === "PRINTED" ? <Pil kind="warn" key="s">Printed — collect</Pil> : <Pil kind="grey" key="s">{x.state.charAt(0) + x.state.slice(1).toLowerCase()}{x.ended_reason ? ` · ${x.ended_reason}` : ""}</Pil>,
        ])} />
        {!c.cards.length ? <PBody><div className="sub2">None yet.</div></PBody> : null}
      </Panel>
    </>
  );
}

/* ── transcript ── */

export function Transcript({ t, s }: { t: Transcripts; s: Me }) {
  const { act, busy, problem } = useAct();
  const [dest, setDest] = useState("INSTITUTION");
  const [name, setName] = useState("");
  const [mode, setMode] = useState("DIGITAL");
  const [copies, setCopies] = useState("1");
  const stage = (x: string) => x === "AWAITING_PAYMENT" ? ["Awaiting payment", "info"] : x === "HELD_AT_CLEARANCE" ? ["Held at clearance", "bad"] : x === "READY" ? ["Being produced", "info"] : x === "VERIFIED" ? ["Produced, awaiting release", "info"] : ["Released", "ok"];
  return (
    <>
      <Note kind="info" title="Official transcript">
        Request it here and pay the fee against the reference generated. A transcript is held while any clearance unit holds you.
      </Note>
      {!s.matricNo ? <Note kind="bad" title="A transcript is issued on the matriculation number">You do not have one yet.</Note> : (
        <Panel title="Request a transcript" right={`${naira(t.fee)} per copy`}>
          <PBody>
            <div className="grid grid--2">
              <Field id="td" label="Destination"><select id="td" className="ctl" value={dest} onChange={(e) => setDest(e.target.value)}><option value="SELF">Myself</option><option value="INSTITUTION">An institution</option><option value="EMPLOYER">An employer</option><option value="EMBASSY">An embassy</option></select></Field>
              <Field id="tn" label="Name of the institution, employer or embassy" hint="As it should appear on the sealed copy"><input id="tn" className="ctl" value={name} onChange={(e) => setName(e.target.value)} /></Field>
              <Field id="tm" label="Mode"><select id="tm" className="ctl" value={mode} onChange={(e) => setMode(e.target.value)}><option value="DIGITAL">Digital, verified by code</option><option value="SEALED">Sealed, for collection</option></select></Field>
              <Field id="tc" label="Copies"><input id="tc" className="ctl tnum" value={copies} inputMode="numeric" onChange={(e) => setCopies(e.target.value)} /></Field>
            </div>
            {problem ? <ProblemNotice problem={problem} /> : null}
            <div><Btn kind="primary" disabled={busy !== null} onClick={() => void act("req", "POST", "/me/transcripts", { destination: dest, destinationName: name || undefined, mode, copies: Number(copies) || 1 }, "Transcript requested by the student")}>{busy === "req" ? "Requesting…" : `Request and generate a reference for ${naira(t.fee * (Number(copies) || 1))}`}</Btn></div>
          </PBody>
        </Panel>
      )}
      <Panel title="Your requests" right={t.requests.length ? `${t.requests.length}` : "none yet"}>
        <DTable cols={["Reference", "For", "Requested|mid", "Stage", "|num"]} rows={t.requests.map((x) => { const [label, kind] = stage(x.stage); return [
          <span className="tnum" key="r">{x.ref}</span>,
          <Two key="f" a={x.destination === "SELF" ? "Myself" : x.destination_name ?? x.destination} b={`${x.mode === "SEALED" ? "Sealed" : "Digital"} · ${x.copies} cop${x.copies === 1 ? "y" : "ies"}`} />,
          <span className="sub2 tnum" key="w">{when(x.requested_at)}</span>,
          <Pil kind={kind as "ok" | "info" | "bad"} key="s">{label}</Pil>,
          x.stage === "AWAITING_PAYMENT" && x.open_reference ? <span key="p" className="row row--inline row--tight"><span className="tnum sub2">{x.open_reference}</span><PayByCard reference={x.open_reference} amount={t.fee * x.copies} /></span> : <span key="p" />,
        ]; })} />
        {!t.requests.length ? <PBody><div className="sub2">No request yet.</div></PBody> : null}
      </Panel>
    </>
  );
}

export { STAGE_LABEL };
