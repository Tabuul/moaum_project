"use client";

/** Score sheet history — every sheet the lecturer has carried, this session and before: when it was due, how
 *  many times it came back, where it reached, and the marked sheet to take away once marks are on it. Filtered
 *  here by session, semester and standing; the list itself is the register's, never typed beside it. */
import { useState } from "react";
import Link from "next/link";
import type { MySheet } from "@/lib/results";
import { LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { semesterName } from "@/lib/student-portal";
import { STANDING, StandingPil, dayOf, standingOf, tally, type Standing } from "@/lib/lecturer";

export function SheetHistory({ sheets, current, initial }: { sheets: MySheet[]; current: string | null; initial: { session: string; sem: string; standing: string } }) {
  const sessions = [...new Set(sheets.map((s) => s.session))].sort().reverse();
  const [session, setSession] = useState(sessions.includes(initial.session) ? initial.session : "");
  const [sem, setSem] = useState(/^[123]$/.test(initial.sem) ? initial.sem : "");
  const [standing, setStanding] = useState<Standing | "">((Object.keys(STANDING) as Standing[]).includes(initial.standing as Standing) ? (initial.standing as Standing) : "");
  const shown = sheets.filter((s) => (!session || s.session === session) && (!sem || String(s.semester) === sem) && (!standing || standingOf(s) === standing));
  const t = tally(sheets);
  const past = sheets.filter((s) => s.session !== current).length;

  return (
    <>
      <PageHead title="Score Sheet History" description="Every score sheet you have carried, across sessions: its standing, its deadline, how many times it was returned, and the marked sheet to take away."
        actions={<><LinkBtn kind="primary" href="/results/sheets">Current Score Sheets</LinkBtn><LinkBtn href="/me/courses">Course History</LinkBtn></>} />
      <Tiles items={[
        ["Sheets on record", String(sheets.length), null, `${sessions.length} session${sessions.length === 1 ? "" : "s"}${past ? ` · ${past} before ${current ?? "this session"}` : ""}`],
        ["Published", String(t.published.length), t.published.length ? "var(--green-ink)" : null, "Approved by Senate"],
        ["In approval", String(t.submitted.length), t.submitted.length ? "var(--chrome)" : null, "Submitted, on the way to Senate"],
        ["Still with you", String(t.open.length), t.open.length ? "var(--red-ink)" : null, "At entry, not yet submitted"],
      ]} />
      <div className="scope">
        <div className="scope__f"><Field id="sh-session" label="Session">
          <select id="sh-session" className="ctl" value={session} onChange={(e) => setSession(e.target.value)}>
            <option value="">Every session</option>{sessions.map((s) => <option key={s} value={s}>{s}{s === current ? " (current)" : ""}</option>)}
          </select>
        </Field></div>
        <div className="scope__f"><Field id="sh-sem" label="Semester">
          <select id="sh-sem" className="ctl" value={sem} onChange={(e) => setSem(e.target.value)}>
            <option value="">Both</option><option value="1">First</option><option value="2">Second</option>
          </select>
        </Field></div>
        <div className="scope__f"><Field id="sh-standing" label="Standing">
          <select id="sh-standing" className="ctl" value={standing} onChange={(e) => setStanding(e.target.value as Standing | "")}>
            <option value="">Every standing</option>{(Object.keys(STANDING) as Standing[]).map((k) => <option key={k} value={k}>{STANDING[k][0]}</option>)}
          </select>
        </Field></div>
      </div>

      <Panel title="Score sheets" right={`${shown.length} of ${sheets.length}`}>
        {sheets.length === 0 ? (
          <PBody><Note kind="info" title="No score sheet is on your record yet">A sheet is generated over each course allocated to you when the Academic Office opens the examination session, and stays here for good.</Note></PBody>
        ) : shown.length === 0 ? (
          <PBody><div className="sub2">Nothing matches these filters.</div></PBody>
        ) : (
          <DTable pageSize={0} cols={["Session", "Sem|mid", "Course", "Registered|mid", "Entered|mid", "Graded|mid", "Standing", "Due|mid", "Returned|mid", "|num"]}
            rows={shown.map((s) => [
              <span key="s" className={`tnum${s.session === current ? " b600" : " sub2"}`}>{s.session}</span>,
              <span key="m" className="tnum" title={`${semesterName(s.semester)} semester`}>{s.semester}</span>,
              <span key="c"><Link className="lnk b600 tnum" href={`/results/sheets/${s.id}`}>{s.courseCode}</Link><div className="sub2">{s.courseTitle} · {s.units} unit{s.units === 1 ? "" : "s"}{s.mine ? "" : " · second examiner"}{s.secondExaminer && s.mine ? ` · 2nd examiner ${s.secondExaminer}` : ""}</div></span>,
              <span key="r" className="tnum">{s.candidates}</span>,
              <span key="e" className="tnum">{s.entered}</span>,
              <span key="g" className="tnum">{s.graded}</span>,
              <StandingPil key="st" sheet={s} />,
              <span key="d" className="tnum sub2">{dayOf(s.dueOn)}</span>,
              <span key="rt" className="tnum">{s.returnedTimes ? <Pil kind="warn">{s.returnedTimes}×</Pil> : <span className="sub2">—</span>}</span>,
              <span key="a" className="row row--inline row--tight" style={{ justifyContent: "flex-end" }}>
                {s.entered > 0 ? <a className="btn btn--ghost btn--sm" href={`/results/sheets/${s.id}/marked?format=xlsx`} title="The marked sheet with total, grade and point — Excel">Excel</a> : null}
                {s.entered > 0 ? <a className="btn btn--ghost btn--sm" href={`/results/sheets/${s.id}/marked?format=pdf`} title="The marked sheet with total, grade and point — PDF">PDF</a> : null}
                <LinkBtn kind={s.stage === "ENTRY" ? "primary" : "ghost"} href={`/results/sheets/${s.id}`}>{s.stage === "ENTRY" ? "Open" : "View"}</LinkBtn>
              </span>,
            ])}
            texts={shown.map((s) => `${s.session} ${s.courseCode} ${s.courseTitle} ${STANDING[standingOf(s)][0]}`)} />
        )}
      </Panel>
      <Note kind="info" title="A sheet keeps every version of every mark">
        Open a sheet to read its record: each mark with the versions it went through and the reason for each change, the desks it passed and what each one said, and every return. Nothing on a sheet is ever overwritten.
      </Note>
    </>
  );
}
