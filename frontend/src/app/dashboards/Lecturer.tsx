/** rLecturer — proto/part17.html: what the lecturer owes, two ways in, the courses this semester. */
import Link from "next/link";
import type { Me } from "@/components/proto/Shell";
import { stageOf, type MySheet } from "@/lib/results";
import { Ico, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { AllocationHistory, type AllocationRow } from "./AllocationHistory";

export function LecturerDashboard({ me, sheets, session, history = [] }: { me: Me | null; sheets: MySheet[]; session: string; history?: AllocationRow[] }) {
  const owed = sheets.filter((s) => s.stage === "ENTRY" && s.entered === 0);
  const open = sheets.filter((s) => s.stage === "ENTRY");
  const first = owed[0] ?? open[0] ?? sheets[0] ?? null;
  const candidates = sheets.reduce((n, s) => n + s.candidates, 0);
  const queries = sheets.reduce((n, s) => n + (s.openQueries ?? 0), 0);
  const overdue = open.filter((s) => (s.daysLate ?? 0) > 0);
  const dueSoon = open.filter((s) => s.daysToDue != null && s.daysToDue >= 0 && s.daysToDue <= 7);
  const noBank = open.filter((s) => (s.bankQuestions ?? 0) === 0);
  const dueLabel = (s: MySheet) => { const d = s.daysToDue; if (d == null) return "No date set"; if (d < 0) return `${-d} day${d === -1 ? "" : "s"} overdue`; return d === 0 ? "Due today" : `${d} day${d === 1 ? "" : "s"} to go`; };
  return (
    <>
      {sheets.length === 0 ? (
        <Note kind="info" title="No score sheet is assigned to you this session">
          A sheet appears here when the department allocates you a course and the Academic Office opens the examination session. Until then there is nothing to enter, and nothing is shown as if there were.
        </Note>
      ) : owed.length ? (
        <Note kind="bad" title={owed.length === 1 ? "One score sheet is not entered" : `${owed.length} score sheets are not entered`} action={<>{first ? <Link href={`/results/sheets/${first.id}`} className="btn btn--urgent btn--sm">Enter {first.courseCode} marks</Link> : null} <Link href="/results/sheets" className="btn btn--ghost btn--sm">All score sheets</Link></>}>
          {owed.map((c) => <span key={c.id}><b className="tnum">{c.courseCode}</b> ({c.candidates} candidates)</span>).reduce<React.ReactNode[]>((acc, x, i) => (i ? [...acc, " and ", x] : [x]), [])} {owed.length === 1 ? "has" : "have"} no marks against {owed.length === 1 ? "it" : "them"}. A sheet that misses Senate waits for the next sitting, and those students carry an incomplete result into the next semester.
        </Note>
      ) : open.length ? (
        <Note kind="info" title={`${open.length} sheet${open.length === 1 ? " is" : "s are"} still with you`} action={<Link href="/results/sheets" className="btn btn--primary btn--sm">All score sheets</Link>}>
          Marks are entered but not yet attested. A sheet leaves this desk when every candidate carries a mark or an outcome and you submit it.
        </Note>
      ) : (
        <Note kind="ok" title="Every sheet you owe is entered" action={<Link href="/results/sheets" className="btn btn--ghost btn--sm">All score sheets</Link>}>
          All {sheets.length} of your sheets carry a mark or an outcome against every registered candidate. Nothing is waiting on you for this Senate.
        </Note>
      )}

      {queries ? (
        <Note kind="info" title={`${queries} result quer${queries === 1 ? "y" : "ies"} raised on your courses`}>
          A student has questioned a mark in a course you teach. Result queries are routed to and answered by your department on the record; a corrected mark flows back through the chain.
        </Note>
      ) : null}

      {open.length ? (
        <Panel title="Score-sheet deadlines" right={overdue.length ? `${overdue.length} overdue` : dueSoon.length ? `${dueSoon.length} due within a week` : "On track"}>
          <DTable cols={["Course", "Registered|mid", "Entered|mid", "Due|mid", "Deadline|num"]}
            rows={[...open].sort((a, b) => (a.daysToDue ?? 9999) - (b.daysToDue ?? 9999)).map((s) => {
              const late = (s.daysLate ?? 0) > 0;
              const soon = !late && dueSoon.includes(s);
              return [
                <span key="c"><strong className="tnum">{s.courseCode}</strong><div className="sub2">{s.courseTitle}</div></span>,
                <span className="tnum" key="r">{s.candidates}</span>,
                <span className="tnum" key="e" style={s.entered < s.candidates ? { color: "var(--red-ink)", fontWeight: 700 } : undefined}>{s.entered}</span>,
                <span className="tnum sub2" key="d">{s.dueOn ? new Date(s.dueOn).toLocaleDateString("en-GB", { day: "numeric", month: "short" }) : "—"}</span>,
                <Pil key="l" kind={late ? "bad" : soon ? "info" : "grey"}>{dueLabel(s)}</Pil>,
              ];
            })} texts={open.map((s) => `${s.courseCode} ${s.courseTitle}`)} />
          <PBody><div className="sub2">A sheet still at entry after its due date is overdue; a sheet that misses Senate waits for the next sitting, and its candidates carry an incomplete result.</div></PBody>
        </Panel>
      ) : null}

      <Panel title="Submitting your marks" right={first ? `${first.courseCode} — other courses under All score sheets` : "Two ways in — they meet at the same score sheet"}>
        <PBody>
          <div className="ways">
            <div className="way">
              <div className="way__h"><span className="way__i"><Ico name="doc" size={20} stroke="currentColor" w={1.9} /></span><span className="way__t">Download score sheet</span></div>
              <div className="way__s">Get this course’s live register as a CSV — every registered candidate already on it. Fill the two columns, <b>CA</b> and <b>Exam</b>, and leave the total, grade and point to the system. Or open the sheet and type the marks straight in.</div>
              <div className="way__b">{first ? <><a href={`/results/sheets/${first.id}/template`} className="btn btn--primary btn--sm">Download score sheet</a> <Link href={`/results/sheets/${first.id}`} className="btn btn--ghost btn--sm">Open the sheet</Link></> : <button className="btn btn--primary btn--sm" disabled>No sheet yet</button>}</div>
            </div>
            <div className="way">
              <div className="way__h"><span className="way__i"><Ico name="box" size={20} stroke="currentColor" w={1.9} /></span><span className="way__t">Upload computed score sheet</span></div>
              <div className="way__s">Filled the sheet offline? Upload it on the score sheet — it is <b>checked before anything is written</b>, and accepted whole or not at all. The total, grade and point are computed from your CA and Exam by the scheme in force; nobody types a grade.</div>
              <div className="way__b">{first ? <Link href={`/results/sheets/${first.id}`} className="btn btn--primary btn--sm">Upload computed score sheet</Link> : <button className="btn btn--primary btn--sm" disabled>No sheet yet</button>}</div>
            </div>
          </div>
        </PBody>
      </Panel>

      <Panel title="Your staff profile" right="Your CV as the University holds it">
        <PBody>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 12, alignItems: "center", justifyContent: "space-between" }}>
            <div className="sub2" style={{ maxWidth: 620 }}>
              Keep your own record current — a recent photograph, your department and responsibility, Google Scholar and research
              interests, and the lists that grow over a career: publications, grants, the postgraduates you have graduated,
              collaborations, conferences, assignments, innovations, patents, achievements and contributions to society.
            </div>
            <Link href="/me/profile" className="btn btn--primary btn--sm">Upload &amp; edit my profile</Link>
          </div>
        </PBody>
      </Panel>

      <Tiles items={[
        ["Courses this session", String(sheets.length), null, `${sheets.filter((s) => s.mine).length} as lecturer, ${sheets.filter((s) => !s.mine).length} as second examiner`],
        ["Candidates taught", String(candidates), null, "Across every roll"],
        ["Sheets outstanding", String(open.length), open.length ? "var(--red-ink)" : "var(--green-ink)", "Not yet attested"],
        ["Signed in as", me?.name ?? "Lecturer", null, me?.staffNumber ?? ""],
      ]} />

      <Panel title="Your teaching desks" right="Everything for your courses">
        <PBody>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
            <Link href="/me/teaching" className="btn btn--ghost btn--sm">My teaching & timetable</Link>
            <Link href="/results/sheets" className="btn btn--ghost btn--sm">All score sheets{open.length ? ` (${open.length})` : ""}</Link>
            <Link href="/lms" className="btn btn--ghost btn--sm">Course spaces</Link>
            <Link href="/registration/class-list" className="btn btn--ghost btn--sm">Registered students</Link>
            <Link href="/exams/question-bank" className="btn btn--ghost btn--sm">CBT question bank</Link>
            <Link href="/me/profile" className="btn btn--ghost btn--sm">My staff profile</Link>
          </div>
        </PBody>
      </Panel>

      <Panel title="My courses this session" right={`${session} · every course can be typed or uploaded`}>
        {sheets.length === 0 ? <div className="card__body sub2">Nothing allocated to you in {session}.</div> : (
          <DTable cols={["Course", "Units|mid", "Registered|mid", "CA entered|mid", "Marks entered|mid", "Result stage", "Enter marks|num"]}
            rows={sheets.map((s) => {
              const st = stageOf(s);
              return [
                <span key="c"><strong className="tnum">{s.courseCode}</strong><div className="sub2">{s.courseTitle}{s.mine ? "" : " · second examiner"}</div></span>,
                <span className="tnum" key="u">{s.units}</span>,
                <span className="tnum" key="n">{s.candidates}</span>,
                <span className="tnum sub2" key="ca">{s.caEntered}/{s.candidates}</span>,
                <span className="tnum" key="e" style={s.entered < s.candidates ? { color: "var(--red-ink)", fontWeight: 700 } : undefined}>{s.entered}</span>,
                <Pil key="p" kind={st.pill}>{st.text}</Pil>,
                <Link key="a" href={`/results/sheets/${s.id}`} className={`btn btn--sm btn--${st.kind}`}>{st.act}</Link>,
              ];
            })}
            texts={sheets.map((s) => `${s.courseCode} ${s.courseTitle}`)} />
        )}
      </Panel>

      <AllocationHistory rows={history} mode="me" session={session} />

      <Panel title="CBT question bank" right={noBank.length ? `${noBank.length} course${noBank.length === 1 ? "" : "s"} with no questions` : "Your current courses have questions"}>
        {sheets.length ? (
          <DTable cols={["Course", "Questions in bank|mid", "Readiness|num"]}
            rows={sheets.map((s) => [
              <span key="c"><strong className="tnum">{s.courseCode}</strong><div className="sub2">{s.courseTitle}</div></span>,
              <span className="tnum" key="q" style={(s.bankQuestions ?? 0) === 0 ? { color: "var(--red-ink)", fontWeight: 700 } : undefined}>{s.bankQuestions ?? 0}</span>,
              (s.bankQuestions ?? 0) === 0 ? <Pil kind="bad" key="s">None yet</Pil> : (s.bankQuestions ?? 0) < 20 ? <Pil kind="info" key="s">Thin</Pil> : <Pil kind="ok" key="s">Ready</Pil>,
            ])} texts={sheets.map((s) => `${s.courseCode} ${s.courseTitle}`)} />
        ) : <div className="card__body sub2">No course to check.</div>}
        <PBody><div className="sub2">A computer-based test draws a fresh paper per candidate from the bank, so a course with too few questions cannot randomise. Add questions on the <Link href="/exams/question-bank">CBT question bank</Link>.</div></PBody>
      </Panel>

      <div className="grid grid--2">
        <Panel title="Downloads" right="Generated from the approved registrations at the moment you ask">
          <PBody>
            <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              <Link href="/registration/class-list" className="btn btn--ghost">Class list and attendance register</Link>
              {first ? <Link href={`/results/sheets/${first.id}`} className="btn btn--ghost">Blank score sheet — {first.courseCode}</Link> : null}
              <Link href="/student/exams" className="btn btn--ghost" style={{ display: "none" }}>—</Link>
            </div>
            <div className="sub2" style={{ marginTop: 8 }}>Each is generated when you ask, so it is never out of date. The class list is the roll of account: a student who is not on it is not registered, whatever they tell you.</div>
          </PBody>
        </Panel>
        <Panel title="This week" right="From the slots the department gave your courses">
          <PBody>
            <div className="sub2">The teaching timetable is drawn on the class list screen from the slots recorded against each offering. Nothing is shown here that the department has not recorded.</div>
            <div style={{ marginTop: 8 }}><Link href="/registration/class-list" className="btn btn--ghost btn--sm">Open the class list</Link></div>
          </PBody>
        </Panel>
      </div>

      <Note kind="info" title="You cannot see a student who is not registered for your course">
        The class list, the score sheet and the attendance register are all built from approved registrations. It is the reason a mark can never be entered for a student who never registered — which is how ghost results enter a system that allows it.
      </Note>
    </>
  );
}
