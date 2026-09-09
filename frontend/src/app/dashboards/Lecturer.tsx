/** rLecturer — proto/part17.html: what the lecturer owes, two ways in, the courses this semester. */
import Link from "next/link";
import type { Me } from "@/components/proto/Shell";
import { stageOf, type MySheet } from "@/lib/results";
import { Ico, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export function LecturerDashboard({ me, sheets, session }: { me: Me | null; sheets: MySheet[]; session: string }) {
  const owed = sheets.filter((s) => s.stage === "ENTRY" && s.entered === 0);
  const open = sheets.filter((s) => s.stage === "ENTRY");
  const first = owed[0] ?? open[0] ?? sheets[0] ?? null;
  const candidates = sheets.reduce((n, s) => n + s.candidates, 0);
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

      <Panel title="Submitting your marks" right="Two ways in — they meet at the same score sheet">
        <PBody>
          <div className="ways">
            <div className="way">
              <div className="way__h"><span className="way__i"><Ico name="doc" size={20} stroke="currentColor" w={1.9} /></span><span className="way__t">Type them in</span></div>
              <div className="way__s">Every registered candidate is already on the sheet. Two boxes each — CA and examination — and the total, grade and point appear when you save. Enter or ↓ moves down the column, so a whole roll is entered from the keyboard.</div>
              <div className="way__b">{first ? <Link href={`/results/sheets/${first.id}`} className="btn btn--primary btn--sm">Open the score sheet</Link> : <button className="btn btn--primary btn--sm" disabled>No sheet yet</button>}</div>
            </div>
            <div className="way">
              <div className="way__h"><span className="way__i"><Ico name="box" size={20} stroke="currentColor" w={1.9} /></span><span className="way__t">Upload in bulk</span></div>
              <div className="way__s">Already keep the marks in Excel? Download the template from the sheet — it is this course’s live register — fill two columns, save as CSV and upload it there. The file is <b>checked before anything is written</b>, and accepted whole or not at all.</div>
              <div className="way__b">{first ? <Link href={`/results/sheets/${first.id}`} className="btn btn--primary btn--sm">Upload a completed sheet</Link> : <button className="btn btn--primary btn--sm" disabled>No sheet yet</button>}</div>
            </div>
          </div>
        </PBody>
      </Panel>

      <Tiles items={[
        ["Courses this session", String(sheets.length), null, `${sheets.filter((s) => s.mine).length} as lecturer, ${sheets.filter((s) => !s.mine).length} as second examiner`],
        ["Candidates taught", String(candidates), null, "Across every roll"],
        ["Sheets outstanding", String(open.length), open.length ? "var(--red-ink)" : "var(--green-ink)", "Not yet attested"],
        ["Signed in as", me?.name ?? "Lecturer", null, me?.staffNumber ?? ""],
      ]} />

      <Panel title="My courses this session" right={`${session} · every course can be typed or uploaded`}>
        {sheets.length === 0 ? <div className="card__body sub2">Nothing allocated to you in {session}.</div> : (
          <DTable cols={["Course", "Units|mid", "Registered|mid", "Marks entered|mid", "Result stage", "Enter marks|num"]}
            rows={sheets.map((s) => {
              const st = stageOf(s);
              return [
                <span key="c"><strong className="tnum">{s.courseCode}</strong><div className="sub2">{s.courseTitle}{s.mine ? "" : " · second examiner"}</div></span>,
                <span className="tnum" key="u">{s.units}</span>,
                <span className="tnum" key="n">{s.candidates}</span>,
                <span className="tnum" key="e" style={s.entered < s.candidates ? { color: "var(--red-ink)", fontWeight: 700 } : undefined}>{s.entered}</span>,
                <Pil key="p" kind={st.pill}>{st.text}</Pil>,
                <Link key="a" href={`/results/sheets/${s.id}`} className={`btn btn--sm btn--${st.kind}`}>{st.act}</Link>,
              ];
            })}
            texts={sheets.map((s) => `${s.courseCode} ${s.courseTitle}`)} />
        )}
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
        <Panel title="This week" right="From the slots the department gave your offerings">
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
