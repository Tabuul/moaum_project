"use client";

/** staffScores — proto/part5.html: the sheets assigned to you, counted from the rolls, never typed beside them. */
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { stageOf, type MySheet } from "@/lib/results";
import { Note, Panel, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { semesterText } from "@/lib/student-portal";

export { stageOf };

export function SheetsList({ sheets, session, sessions, sem, all }: { sheets: MySheet[]; session: string; sessions: string[]; sem: string; all: boolean }) {
  const queryNav = useQueryNav();
  const open = sheets.filter((s) => s.stage === "ENTRY");
  function go(next: { session?: string; sem?: string }) {
    const q = new URLSearchParams();
    q.set("session", next.session ?? session);
    if (next.sem ?? sem) q.set("sem", next.sem ?? sem);
    queryNav(`/results/sheets?${q.toString()}`);
  }
  return (
    <>
      <Note kind="info" title="This list is generated from the rolls, not typed beside them">
        Every figure below is counted from the same roll the score sheet is generated from — so the count here, the count on the dashboard and the number of rows on the sheet are one number read three times, and cannot drift apart. The stage is derived the same way: a sheet with nothing entered cannot show as approved.
      </Note>
      <div className="card"><div className="card__body" style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "flex-end" }}>
        <div className="field" style={{ minWidth: 160 }}>
          <label htmlFor="sh-session">Session</label>
          <select id="sh-session" className="ctl" value={session} onChange={(e) => go({ session: e.target.value })}>
            {(sessions.includes(session) ? sessions : [session, ...sessions]).map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
        </div>
        <div className="field" style={{ minWidth: 160 }}>
          <label htmlFor="sh-sem">Semester</label>
          <select id="sh-sem" className="ctl" value={sem} onChange={(e) => go({ sem: e.target.value })}>
            <option value="">Both</option><option value="1">First</option><option value="2">Second</option>
          </select>
        </div>
      </div></div>
      <Panel title={all ? "Score sheets in the session" : "Score sheets assigned to you"} right={<>{session}{sem ? ` · ${sem === "1" ? "First" : "Second"} semester` : ""} · {open.length ? <b style={{ color: "var(--red-ink)" }}>{open.length} still open</b> : "all submitted"}</>}>
        {sheets.length === 0 ? (
          <div className="card__body sub2">{all ? "No score sheet exists for this session yet. Sheets are generated when the Academic Office opens the examination session over the allocated offerings." : "No sheet is assigned to you in this session. A sheet appears here when the department allocates you a course and the examination session is opened."}</div>
        ) : (
          <DTable
            cols={["Course", "Candidates|mid", "Entered|mid", "Stage", all ? "Lecturer / second examiner" : "Second examiner", "|num"]}
            rows={sheets.map((s) => {
              const st = stageOf(s);
              const short = s.entered < s.candidates;
              return [
                <span key="c"><strong className="tnum">{s.courseCode}</strong><div className="sub2">{s.courseTitle} · {s.units} units{s.session !== session ? ` · ${s.session}` : ""} · {semesterText(s.semester)}</div></span>,
                <span className="tnum" key="n">{s.candidates}</span>,
                <span key="e"><span className="tnum" style={short ? { color: "var(--red-ink)", fontWeight: 600 } : undefined}>{s.entered}</span><span className="sub2 tnum"> of {s.candidates}</span></span>,
                <span key="s"><Pil kind={st.pill}>{st.text}</Pil>{s.daysLate ? <div className="sub2" style={{ color: "var(--red-ink)" }}>{s.daysLate} days overdue</div> : null}{s.returnedTimes ? <div className="sub2">Returned {s.returnedTimes === 1 ? "once" : `${s.returnedTimes} times`}</div> : null}</span>,
                <span className="sub2" key="x">{s.secondExaminer ?? "Not yet set"}</span>,
                <Link key="a" href={`/results/sheets/${s.id}`} className={`btn btn--sm btn--${st.kind}`}>{s.mine || all ? st.act : "View"}</Link>,
              ];
            })}
            texts={sheets.map((s) => `${s.courseCode} ${s.courseTitle} ${s.stage}`)}
          />
        )}
      </Panel>
      <Note kind="ok" title="A sheet that has left this desk is readable, not editable">
        Once a set is verified it belongs to the chain, not to the lecturer who entered it, and the button on its row reads <b>View</b> rather than Continue. Changing a mark in a verified set is a <b>result query</b> — raised, minuted and re-approved through the same chain that approved it — and not an edit. That is the difference between an amended result and an altered one.
      </Note>
    </>
  );
}
