/** rLecturer — the lecturer's desk: the session and semester in progress, the figures counted from their
 *  own score sheets, every course allocated to them with what each one needs next, the deadlines, the
 *  latest notices and the doors to everything else. Every number is read from the register; nothing is typed
 *  beside it, and a course that is not allocated to this lecturer is not on this page. */
import Link from "next/link";
import type { Me } from "@/components/proto/Shell";
import type { MySheet } from "@/lib/results";
import { KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { semesterName } from "@/lib/student-portal";
import { StandingPil, classListHref, dayOf, dueWords, standingOf, tally, whenAt, type StaffNotice } from "@/lib/lecturer";
import type { AllocationRow } from "./AllocationHistory";

export function LecturerDashboard({ me, sheets, session, semester = null, history = [], notices = [] }: {
  me: Me | null; sheets: MySheet[]; session: string; semester?: number | null; history?: AllocationRow[]; notices?: StaffNotice[];
}) {
  const t = tally(sheets);
  const thisSemester = semester ? sheets.filter((s) => s.semester === semester) : sheets;
  const first = t.notStarted[0] ?? t.inProgress[0] ?? sheets[0] ?? null;
  const overdue = t.open.filter((s) => (s.daysLate ?? 0) > 0);
  const dueSoon = t.open.filter((s) => s.daysToDue != null && s.daysToDue >= 0 && s.daysToDue <= 7);
  const pastSessions = new Set(history.filter((h) => h.session !== session).map((h) => h.session)).size;
  const semesterWord = semester ? `${semesterName(semester)} semester` : "No semester open yet";

  /* what each course needs next, by its standing — the one button a lecturer looks for */
  const nextAct = (s: MySheet): [string, "primary" | "urgent" | "go" | "ghost"] => {
    switch (standingOf(s)) {
      case "NOT_STARTED": return ["Enter Marks", "urgent"];
      case "IN_PROGRESS": return [s.entered < s.candidates ? "Continue Entry" : "Submit Sheet", s.entered < s.candidates ? "primary" : "go"];
      case "SUBMITTED": return ["Track Approval", "ghost"];
      default: return ["View Result", "ghost"];
    }
  };

  return (
    <>
      {/* the session and semester the desk is working in, and who is at it */}
      <div className="card">
        <div className="card__body">
          <KvGrid cls="grid--4" pairs={[
            ["Lecturer", <strong key="n">{me?.name ?? "Lecturer"}</strong>],
            ["Staff number", <span key="s" className="tnum">{me?.staffNumber ?? "—"}</span>],
            ["Current session", <strong key="se" className="tnum">{session}</strong>],
            ["Semester in progress", <span key="sm"><Pil kind={semester ? "ok" : "grey"}>{semesterWord}</Pil></span>],
          ]} />
        </div>
      </div>

      {sheets.length === 0 ? (
        <Note kind="info" title={`No course is allocated to you in ${session}`}>
          A course appears here when your Head of Department allocates it to you and the Academic Office opens the examination session. Until then there is nothing to enter, and nothing is shown as if there were.
          {pastSessions ? <span className="blk">Your courses from earlier sessions are under <Link className="lnk" href="/me/courses">Course History</Link>.</span> : null}
        </Note>
      ) : t.notStarted.length ? (
        <Note kind="bad" title={t.notStarted.length === 1 ? "One score sheet has no marks yet" : `${t.notStarted.length} score sheets have no marks yet`}
          action={<>{first ? <LinkBtn kind="urgent" href={`/results/sheets/${first.id}`}>Enter {first.courseCode} Marks</LinkBtn> : null} <LinkBtn href="/results/sheets">All Score Sheets</LinkBtn></>}>
          {t.notStarted.map((c) => `${c.courseCode} (${c.candidates} registered)`).join(", ")}. A sheet that misses Senate waits for the next sitting, and those students carry an incomplete result into the next semester.
        </Note>
      ) : t.inProgress.length ? (
        <Note kind="info" title={`${t.inProgress.length} sheet${t.inProgress.length === 1 ? " is" : "s are"} still with you`} action={<LinkBtn kind="primary" href="/results/sheets">All Score Sheets</LinkBtn>}>
          Marks are entered but not yet submitted. A sheet leaves your desk when every registered candidate carries a mark or an outcome and you submit and attest it.
        </Note>
      ) : (
        <Note kind="ok" title="Every sheet you owe has been submitted" action={<LinkBtn href="/results/sheets">All Score Sheets</LinkBtn>}>
          All {sheets.length} of your sheets carry a mark or an outcome against every registered candidate. Nothing is waiting on you for this Senate.
        </Note>
      )}

      <Tiles items={[
        ["Assigned courses", String(t.courses), null, `${t.asLecturer} as lecturer · ${t.courses - t.asLecturer} as second examiner or co-lecturer`],
        [semester ? `Courses this semester` : "Courses this session", String(thisSemester.length), null, semester ? `${semesterName(semester)} semester of ${session}` : session],
        ["Registered students", String(t.students), null, "Across every roll, from approved registrations"],
        ["Not started", String(t.notStarted.length), t.notStarted.length ? "var(--red-ink)" : "var(--green-ink)", "Sheets with no mark yet"],
        ["In progress", String(t.inProgress.length), t.inProgress.length ? "var(--amber-ink)" : null, "Marks entered, not yet submitted"],
        ["Awaiting approval", String(t.submitted.length), t.submitted.length ? "var(--chrome)" : null, "Submitted, on the way to Senate"],
        ["Published", String(t.published.length), t.published.length ? "var(--green-ink)" : null, "Approved by Senate this session"],
        ["Result queries", String(t.queries), t.queries ? "var(--amber-ink)" : null, t.queries ? "Raised by students on your courses" : "None open on your courses"],
      ]} />

      <Panel title="My assigned courses" right={`${session} · ${semesterWord.toLowerCase()} · ${sheets.length} course${sheets.length === 1 ? "" : "s"}`}>
        {sheets.length === 0 ? <PBody><div className="sub2">Nothing allocated to you in {session}.</div></PBody> : (
          <DTable pageSize={0} cols={["Course", "Sem|mid", "Units|mid", "Registered|mid", "Entered|mid", "Status", "Due|mid", "|num"]}
            rows={[...sheets].sort((a, b) => a.semester - b.semester || a.courseCode.localeCompare(b.courseCode)).map((s) => {
              const [act, kind] = nextAct(s);
              const late = (s.daysLate ?? 0) > 0;
              return [
                <span key="c"><Link className="lnk b600 tnum" href={`/results/sheets/${s.id}`}>{s.courseCode}</Link><div className="sub2">{s.courseTitle}{s.mine ? "" : " · second examiner"}{s.heldScripts ? ` · ${s.heldScripts} held script${s.heldScripts === 1 ? "" : "s"}` : ""}</div></span>,
                <span key="m" className="tnum">{s.semester}</span>,
                <span key="u" className="tnum">{s.units}</span>,
                <span key="r" className="tnum">{s.candidates}</span>,
                <span key="e" className={`tnum${s.stage === "ENTRY" && s.entered < s.candidates ? " ink-red b700" : ""}`}>{s.entered}<span className="sub2"> / {s.candidates}</span></span>,
                <StandingPil key="st" sheet={s} />,
                <span key="d" className={`tnum sub2${late ? " ink-red b600" : ""}`}>{s.stage === "ENTRY" ? <>{dayOf(s.dueOn)}<div>{dueWords(s)}</div></> : "—"}</span>,
                <span key="a" className="row row--inline row--tight" style={{ justifyContent: "flex-end" }}>
                  <LinkBtn href={classListHref(s.courseCode, s.session, s.semester)} title="The registered students of this course">Students</LinkBtn>
                  <a className="btn btn--ghost btn--sm" href={`/results/sheets/${s.id}/template`} title="The score sheet as an Excel workbook, every registered candidate on it">Score Sheet</a>
                  <LinkBtn kind={kind} href={`/results/sheets/${s.id}`}>{act}</LinkBtn>
                </span>,
              ];
            })}
            texts={sheets.map((s) => `${s.courseCode} ${s.courseTitle} ${standingOf(s)}`)} />
        )}
      </Panel>

      {t.open.length ? (
        <Panel title="Score sheet deadlines" right={overdue.length ? `${overdue.length} overdue` : dueSoon.length ? `${dueSoon.length} due within a week` : "On track"}>
          <DTable pageSize={0} cols={["Course", "Registered|mid", "Entered|mid", "Due|mid", "Deadline|num"]}
            rows={[...t.open].sort((a, b) => (a.daysToDue ?? 9999) - (b.daysToDue ?? 9999)).map((s) => {
              const late = (s.daysLate ?? 0) > 0;
              const soon = !late && dueSoon.includes(s);
              return [
                <span key="c"><Link className="lnk b600 tnum" href={`/results/sheets/${s.id}`}>{s.courseCode}</Link><div className="sub2">{s.courseTitle}</div></span>,
                <span className="tnum" key="r">{s.candidates}</span>,
                <span className={`tnum${s.entered < s.candidates ? " ink-red b700" : ""}`} key="e">{s.entered}</span>,
                <span className="tnum sub2" key="d">{dayOf(s.dueOn)}</span>,
                <Pil key="l" kind={late ? "bad" : soon ? "warn" : "grey"}>{dueWords(s)}</Pil>,
              ];
            })} texts={t.open.map((s) => `${s.courseCode} ${s.courseTitle}`)} />
          <PBody><div className="sub2">A sheet still at entry after its due date is overdue. A sheet that misses Senate waits for the next sitting, and its candidates carry an incomplete result.</div></PBody>
        </Panel>
      ) : null}

      <div className="grid grid--2">
        <Panel title="Quick actions" right="Everything for your courses">
          <PBody>
            <div className="row">
              {first ? <a className="btn btn--primary btn--sm" href={`/results/sheets/${first.id}/template`}>Download Score Sheet · {first.courseCode}</a> : null}
              {first && first.stage === "ENTRY" ? <LinkBtn kind="primary" href={`/results/sheets/${first.id}`}>Upload Completed Sheet</LinkBtn> : null}
              <LinkBtn href="/results/sheets">Score Sheets</LinkBtn>
              <LinkBtn href="/registration/class-list">Registered Students</LinkBtn>
              <LinkBtn href="/me/teaching">My Timetable</LinkBtn>
              <LinkBtn href="/lms">Course Spaces</LinkBtn>
              <LinkBtn href="/results/sheets/history">Score Sheet History</LinkBtn>
              <LinkBtn href="/me/courses">Course History</LinkBtn>
              <LinkBtn href="/me/profile">My Profile</LinkBtn>
            </div>
            <div className="sub2 mt-2">The score sheet is a workbook with every registered candidate already on it, in alphabetical order. Fill CA and Exam, then upload it on the sheet: it is checked before anything is written and accepted whole or not at all.</div>
          </PBody>
        </Panel>
        <Panel title="Notifications" right={notices.length ? <Link className="lnk" href="/me/notices">All notifications</Link> : "Nothing yet"}>
          {notices.length ? (
            <ul className="plain">
              {notices.slice(0, 5).map((n) => (
                <li key={n.id} className="row row--between" style={{ gap: "var(--s-3)", padding: "8px 0", borderBottom: "1px solid var(--line)" }}>
                  <span style={{ minWidth: 0 }}><strong>{n.subject}</strong><div className="sub2">{whenAt(n.created_at)}</div></span>
                  <Pil kind={n.state === "SENT" ? "ok" : n.state === "FAILED" ? "bad" : "grey"}>{n.channel === "SMS" ? "SMS" : "Email"}</Pil>
                </li>
              ))}
            </ul>
          ) : <PBody><div className="sub2">A notice is filed here when a sheet is returned to you, a deadline approaches, a result is published or the desk writes to you. It is the same notice your email carries.</div></PBody>}
        </Panel>
      </div>

      <div className="grid grid--2">
        <Panel title="Course history" right={history.length ? `${new Set(history.map((h) => h.session)).size} session${new Set(history.map((h) => h.session)).size === 1 ? "" : "s"} on record` : "Nothing before this session"}>
          <PBody>
            <div className="sub2">Every course allocated to you, this session and before: the class you taught, the second examiner and where each sheet reached. A past course opens its registered students as they stood that session.</div>
            <div className="mt-2"><LinkBtn kind="ghost" href="/me/courses">Open Course History{pastSessions ? ` · ${history.length} courses` : ""}</LinkBtn></div>
          </PBody>
        </Panel>
        <Panel title="Your staff profile" right="Your record as the University holds it">
          <PBody>
            <div className="sub2">Keep your own record current: a recent photograph, your phone and email, your qualifications, and the lists that grow over a career. Your name, staff number, department and rank are the establishment&rsquo;s to change.</div>
            <div className="mt-2"><LinkBtn kind="ghost" href="/me/profile">View and Update Profile</LinkBtn></div>
          </PBody>
        </Panel>
      </div>

      <Note kind="info" title="You cannot see a student who is not registered for your course">
        The class list, the score sheet and the attendance register are all built from approved registrations, and only for the courses allocated to you. It is why a mark can never be entered for a student who never registered.
      </Note>
    </>
  );
}
