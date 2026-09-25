"use client";

/** Course history — every course the department has allocated to this lecturer, session by session: the role
 *  they carried it in, the class size, the second examiner, and where the score sheet reached. A past course
 *  opens its registered students as they stood that session, and its sheets in the score sheet history. */
import { useState } from "react";
import Link from "next/link";
import type { AllocationRow } from "@/app/dashboards/AllocationHistory";
import { LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { semesterName } from "@/lib/student-portal";
import { classListHref } from "@/lib/lecturer";
import { STAGE_LABEL } from "@/lib/results";

const ROLE_PIL: Record<string, "ok" | "info" | "grey"> = { Lecturer: "ok", "Second examiner": "info", "Co-lecturer": "info" };

export function CourseHistory({ rows, current }: { rows: AllocationRow[]; current: string | null }) {
  const sessions = [...new Set(rows.map((r) => r.session))].sort().reverse();
  const levels = [...new Set(rows.map((r) => r.level))].sort((a, b) => a - b);
  const roles = [...new Set(rows.map((r) => r.role ?? "Lecturer"))];
  const [session, setSession] = useState("");
  const [sem, setSem] = useState("");
  const [level, setLevel] = useState("");
  const [role, setRole] = useState("");
  const shown = rows.filter((r) => (!session || r.session === session) && (!sem || String(r.semester) === sem) && (!level || String(r.level) === level) && (!role || (r.role ?? "Lecturer") === role));
  const students = rows.reduce((n, r) => n + (r.students ?? 0), 0);
  const distinct = new Set(rows.map((r) => r.course_code)).size;
  const published = rows.filter((r) => r.stage === "PUBLISHED").length;

  return (
    <>
      <PageHead title="Course History" description="Every course allocated to you, this session and before, with the class each one had and where its results reached. Read from the register of allocation; nothing here is kept apart."
        actions={<><LinkBtn kind="primary" href="/me/teaching">This Session&rsquo;s Timetable</LinkBtn><LinkBtn href="/results/sheets/history">Score Sheet History</LinkBtn></>} />
      <Tiles items={[
        ["Courses taught", String(rows.length), null, `${distinct} distinct course${distinct === 1 ? "" : "s"} over ${sessions.length} session${sessions.length === 1 ? "" : "s"}`],
        ["Students taught", String(students), null, "Registered across every class"],
        ["Results published", String(published), published ? "var(--green-ink)" : null, "Sheets approved by Senate"],
        ["As lecturer", String(rows.filter((r) => (r.role ?? "Lecturer") === "Lecturer").length), null, `${rows.filter((r) => (r.role ?? "Lecturer") !== "Lecturer").length} as second examiner or co-lecturer`],
      ]} />
      <div className="scope">
        <div className="scope__f"><Field id="ch-session" label="Session">
          <select id="ch-session" className="ctl" value={session} onChange={(e) => setSession(e.target.value)}>
            <option value="">Every session</option>{sessions.map((s) => <option key={s} value={s}>{s}{s === current ? " (current)" : ""}</option>)}
          </select>
        </Field></div>
        <div className="scope__f"><Field id="ch-sem" label="Semester">
          <select id="ch-sem" className="ctl" value={sem} onChange={(e) => setSem(e.target.value)}>
            <option value="">Both</option><option value="1">First</option><option value="2">Second</option>
          </select>
        </Field></div>
        <div className="scope__f"><Field id="ch-level" label="Level">
          <select id="ch-level" className="ctl" value={level} onChange={(e) => setLevel(e.target.value)}>
            <option value="">Every level</option>{levels.map((l) => <option key={l} value={String(l)}>{l} level</option>)}
          </select>
        </Field></div>
        <div className="scope__f"><Field id="ch-role" label="Role">
          <select id="ch-role" className="ctl" value={role} onChange={(e) => setRole(e.target.value)}>
            <option value="">Every role</option>{roles.map((r) => <option key={r} value={r}>{r}</option>)}
          </select>
        </Field></div>
      </div>

      <Panel title="Courses" right={`${shown.length} of ${rows.length}`}>
        {rows.length === 0 ? (
          <PBody><Note kind="info" title="Nothing has been allocated to you yet">A course appears here once your Head of Department allocates it to you for a session, and stays on your record after the session ends.</Note></PBody>
        ) : shown.length === 0 ? (
          <PBody><div className="sub2">Nothing matches these filters.</div></PBody>
        ) : (
          <DTable pageSize={0} cols={["Session", "Sem|mid", "Course", "Level|mid", "Units|mid", "Role|mid", "Second examiner", "Students|mid", "Result", "|num"]}
            rows={shown.map((r) => {
              const st = r.stage ? STAGE_LABEL[r.stage]?.[0] ?? r.stage : null;
              return [
                <span key="s" className={`tnum${r.session === current ? " b600" : " sub2"}`}>{r.session}{r.session === current ? <div className="sub2">current</div> : null}</span>,
                <span key="m" className="tnum" title={`${semesterName(r.semester)} semester`}>{r.semester}</span>,
                <span key="c"><span className="b600 tnum">{r.course_code}</span><div className="sub2">{r.title}{r.co_lecturers ? ` · with ${r.co_lecturers}` : ""}</div></span>,
                <span key="l" className="tnum">{r.level}</span>,
                <span key="u" className="tnum">{r.units}</span>,
                <Pil key="r" kind={ROLE_PIL[r.role ?? "Lecturer"] ?? "grey"}>{r.role ?? "Lecturer"}</Pil>,
                <span key="x" className="sub2">{r.second_examiner ?? "—"}</span>,
                <span key="n" className="tnum">{r.students}</span>,
                st ? <Pil key="st" kind={r.stage === "PUBLISHED" ? "ok" : r.stage === "ENTRY" ? "grey" : "info"}>{st}</Pil> : <span key="st" className="sub2">No sheet</span>,
                <span key="a" className="row row--inline row--tight" style={{ justifyContent: "flex-end" }}>
                  <LinkBtn href={classListHref(r.course_code, r.session, r.semester)} title="The students registered for this course that session">Students</LinkBtn>
                  {r.stage ? <LinkBtn href={`/results/sheets/history?session=${encodeURIComponent(r.session)}&sem=${r.semester}`} title="The sheets of this session in your score sheet history">Sheets</LinkBtn> : null}
                </span>,
              ];
            })}
            texts={shown.map((r) => `${r.session} ${r.course_code} ${r.title} ${r.role ?? ""} ${r.level}`)} />
        )}
      </Panel>
      <Note kind="info" title="A past class is read as it stood">
        <span className="blk">Students opens the class list of that course in that session and semester, built from the registrations approved at the time. Sheets opens the score sheets of that session, each with every version of every mark.</span>
        <span className="blk">Your allocation is the Head of Department&rsquo;s to make and change on the <Link className="lnk" href="/me/teaching">teaching and timetable</Link> record; nothing on this page is edited here.</span>
      </Note>
    </>
  );
}
