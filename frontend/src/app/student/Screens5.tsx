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
import type { Card, Docket, Me, Queries, Results, Timetable, Transcripts } from "@/lib/student-portal";
import { STAGE_LABEL, WEEKDAY, semesterName } from "@/lib/student-portal";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Bar, Field, Passport } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { IdCardPair, type IdCardData } from "@/components/proto/idcard";
import { PayByCard, naira, onDay, useAct, when } from "./common";
import { printNode } from "@/lib/print";

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
          Seven days from release &mdash; five working days and a weekend. A query is against <b>one mark in one course</b>, is routed automatically to the department that owns that course, and is answered on the record &mdash; you will see the answer here, not be told to come back next week.
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
      <Note kind="info" title="A corrected mark does not quietly change your result">
        A correction sends the whole set back through the department, the faculty and Senate for an amendment minute. Your published result changes when that finishes and not before. The old figure is not deleted &mdash; the transcript will show one grade, and the record behind it will show both versions and why it changed.
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
          A failed course does not go away and it is not replaced by a later course. It is repeated, in a semester where it is offered, and it counts against the maximum units you may register in that semester &mdash; which is why carryovers are on the registration form from the start, not discovered during one.
        </Note>
      ) : (
        <Note kind="ok" title="You are carrying nothing">No published sheet has a fail against you that a later pass has not settled.</Note>
      )}
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

/* ── examinations (the docket) ── */

export function Exams({ d }: { d: Docket; s: Me }) {
  const cleared = d.clearsExamination === true;
  const withPapers = d.examSessions.filter((x) => x.papers.length);
  return (
    <>
      {d.schemeProblem ? <Note kind="info" title="What a payment releases is not yet stated">{d.schemeProblem}</Note>
        : !cleared ? <Note kind="bad" title="Your docket is withheld until your fees are settled" action={<LinkBtn kind="urgent" href="/student/fees">Fees & payments</LinkBtn>}>Under the scheme in force, sitting an examination is released on payment in full. The papers below are what your approved registration carries; the docket prints the moment the Bursary&rsquo;s position releases it.</Note>
          : <Note kind="info" title="Bring your identity card">Your photograph is checked against the record on file before the paper opens. Arrive 20 minutes early &mdash; late candidates are admitted at the invigilator&rsquo;s discretion and lose the time.</Note>}
      {!withPapers.length ? (
        <Note kind="info" title={`No examination session is open for ${d.session} yet`}>Papers appear here when the Examinations Office opens the session over your approved registration and timetables them.</Note>
      ) : withPapers.map((x) => (
        <Panel key={x.id} title={`${x.session} · ${semesterName(x.semester)} semester · ${x.kind === "MAIN" ? "main" : x.kind.toLowerCase()} examinations`} right={`${onDay(x.exams_from)} – ${onDay(x.exams_to)}${cleared ? " · docket" : ""}`}>
          <DTable cols={["Course", "Date & time", "Venue|mid", "Status|num"]} rows={x.papers.map((p) => [
            <Two key="c" a={p.course_code} b={p.title} />,
            <span className="tnum" key="w">{p.held_on ? `${onDay(p.held_on)} · ${String(p.starts_at).slice(0, 5)}` : "Not yet timetabled"}</span>,
            <span key="v">{p.venue ?? "—"}</span>,
            !cleared ? <Pil kind="bad" key="s">Withheld</Pil> : p.held_on ? <Pil kind="info" key="s">Docket ready</Pil> : <Pil kind="grey" key="s">Awaiting slot</Pil>,
          ])} />
          {cleared ? <div className="card__body row">
            <a href={`/student/exams/card/pdf?session=${encodeURIComponent(x.session)}&semester=${x.semester}`} target="_blank" rel="noopener" className="btn btn--primary btn--sm">Download exam card</a>
            <Btn kind="ghost" onClick={(e) => { const card = (e.currentTarget as HTMLElement).closest(".card") as HTMLElement | null; printNode(card, card?.querySelector(".card__title")?.textContent ?? "Examination docket"); }}>Print the docket</Btn>
            <span className="sub2">The card carries your photograph and a QR the invigilator scans to verify it — it cannot be cloned.</span>
          </div> : null}
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
        {mine.length ? `${mine.length} class${mine.length === 1 ? "" : "es"} today.` : "Nothing today."} {t.slots.some((x) => x.carryover) ? "Your carryover is on the timetable beside the rest." : ""} The slots are the department&rsquo;s, given to each offering; a clash is theirs to resolve.
      </Note>
      {!t.slots.length ? <Note kind="info" title="No slot has been given to your courses yet">The department gives each offering its day, time and venue; the timetable fills the moment it does.</Note> : null}
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
  const below = t.attendance.filter((a) => a.rate !== null && a.rate < 75);
  return (
    <>
      {below.length ? (
        <Note kind="bad" title={`${below.map((b) => b.course_code).join(", ")} ${below.length === 1 ? "is" : "are"} below the 75% threshold`}>
          Departments may bar a student below 75% from sitting the examination &mdash; check with the department before the semester ends.
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

/* ── identity card ── */

export function IdCard({ c, s }: { c: Card; s: Me }) {
  const { act, busy, problem } = useAct();
  const [now] = useState(() => Date.now());
  const live = c.cards.find((x) => x.state === "ISSUED") ?? null;
  /* the card is drawn for every matriculated student — it is a picture of the card, keyed on the
     matriculation number; the serial and validity fill in once the Library has issued the card itself */
  const card: IdCardData | null = s.matricNo ? {
    name: s.name,
    matric: s.matricNo,
    barcode: s.matricNo.replace(/[^A-Za-z0-9]/g, ""),
    serial: live ? live.card_no : "Not yet issued",
    faculty: s.faculty,
    prog: s.programme,
    level: String(s.level),
    session: s.session,
    admitted: (s.entrySession ?? "").slice(0, 4) || "—",
    graduates: "—",
    blood: "—",
    expiresShort: live ? onDay(live.valid_to) : "—",
    kinPhone: "—",
    photoSrc: s.hasPhoto ? `/api/bff/api/v1/me/passport?v=${encodeURIComponent(s.matricNo ?? s.admissionNo ?? s.id)}` : null,
    state: live ? (new Date(live.valid_to).getTime() < now ? "expired" : "issued") : undefined,
  } : null;
  return (
    <>
      {live ? (
        <Note kind="ok" title={`Card ${live.card_no} · issued ${onDay(live.issued_at)} · valid to ${onDay(live.valid_to)}`}>Collected at the Library. The card is keyed on your matriculation number and carries the photograph on file.</Note>
      ) : !c.matricNo ? (
        <Note kind="info" title="A card is made after matriculation">It is keyed on the matriculation number, which you do not have yet.</Note>
      ) : c.clearsIdCard === false ? (
        <Note kind="bad" title="Your card waits on the Bursary's clearance" action={<LinkBtn kind="urgent" href="/student/fees">Fees & payments</LinkBtn>}>Under the scheme in force, the identity card is released at the first instalment.</Note>
      ) : (
        <Note kind="info" title="Your card has not been issued yet">This is what your card will carry. The Library prints it and Security hands it over — bring your fee receipt to the Library; your photograph and signature are checked at the counter. The printable copy opens once the card is issued.</Note>
      )}
      {card ? (
        <Panel title="Your identity card" right={live ? "This is a picture of the card, not the card" : "Preview — not yet issued"}>
          <PBody>
            <IdCardPair c={card} big />
            <div className="sub2 mt-1">The barcode on the back is your borrower number at the Library and the number the gate reads; it does not change when a card is replaced &mdash; the serial does. A field shown as &ldquo;&mdash;&rdquo; is one the University has not recorded against you.</div>
          </PBody>
        </Panel>
      ) : null}
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
          <a href="/student/idcard/pdf" target="_blank" rel="noopener" className="btn btn--primary btn--sm">Open the printable copy</a>
          <Btn kind="ghost" disabled={busy !== null} onClick={() => { const reason = window.prompt("What happened to the card? This goes on the record; the Library issues a replacement."); if (!reason) return; void act("lost", "POST", "/me/id-card/lost", { reason }, `Identity card reported lost: ${reason}`); }}>{busy === "lost" ? "Reporting…" : "Report it lost"}</Btn>
          <LinkBtn kind="ghost" href="/student/support">Request a replacement</LinkBtn>
        </div>
      ) : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title="Cards" right="Every card ever issued to you">
        <DTable cols={["Card", "Issued|mid", "Valid to|mid", "State|num"]} rows={c.cards.map((x) => [
          <span className="tnum" key="n">{x.card_no}</span>, <span className="sub2 tnum" key="i">{onDay(x.issued_at)}</span>, <span className="sub2 tnum" key="v">{onDay(x.valid_to)}</span>,
          x.state === "ISSUED" ? <Pil kind="ok" key="s">Live</Pil> : <Pil kind="grey" key="s">{x.state.charAt(0) + x.state.slice(1).toLowerCase()}{x.ended_reason ? ` · ${x.ended_reason}` : ""}</Pil>,
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
      <Note kind="info" title="An official transcript is produced by the Registry from the published record">
        Request it here, pay the fee against the reference the portal generates, and follow it to release. A transcript is held at clearance while any unit holds you; the Registry produces it and a different officer releases it.
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
