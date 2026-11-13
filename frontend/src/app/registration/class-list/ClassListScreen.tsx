"use client";

/** rClasslist — proto/part17.html: one register, generated now, from approved registrations — all of them. */
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { csv, download, type ClassList } from "@/lib/results";
import { ScopeBar, semesterInSentence, thirdSemester, type Ceiling, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { semesterName } from "@/lib/student-portal";

export function ClassListScreen({ scope, structure, sessions, courses, roll, problem, ceiling }: {
  scope: Scope;
  structure: ScopeStructure;
  sessions: string[];
  courses: { code: string; title: string; semester: number }[];
  roll: ClassList | null;
  problem: Problem | null;
  ceiling?: Ceiling;
}) {
  const notCleared = roll ? roll.rows.filter((r) => !r.cleared) : [];
  const head = roll ? `${roll.courseCode} — ${roll.courseTitle}` : "";
  // V756: a class of semester 3 in a Summer session may hold the Summer's full-time students and the third semester's, as the bar says
  const semWord = (n: number, session: string) => (n === 3 ? semesterInSentence(thirdSemester(session, "REGULAR", structure.summerSessions)) : semesterName(n).toLowerCase());
  const sheet = (what: string) => {
    if (!roll) return;
    const rows: (string | number)[][] = [["Matriculation number", "Name", "Programme", "Level", "Basis", what === "examroll" ? "Cleared to sit" : what === "attreg" ? "Week 1" : "Clearance"]];
    for (const r of roll.rows) rows.push([r.number, `${r.surname}, ${r.otherNames}`, r.programmeName, r.level, r.basis, what === "attreg" ? "" : r.cleared ? "Cleared" : "Blocked — fees"]);
    download(`${roll.courseCode.replace(/\s/g, "")}-${what}-${roll.session.replace("/", "-")}.csv`, csv(rows));
  };

  return (
    <>
      {/* V756: the class list reads the regular (full-time) class of a course, so semester 3 of a Summer session is the Summer */}
      <ScopeBar withSummer stream="REGULAR" scope={scope} structure={structure} sessions={sessions} courses={courses} what="students" count={roll?.all ?? 0} of={roll?.all ?? 0} withCourse ceiling={ceiling} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!roll ? (
        <Note kind="info" title="Choose a course in the scope bar">
          Pick the department, then the course.
        </Note>
      ) : (
        <>
          <Tiles items={[
            ["Registered", String(roll.all), null, "Approved registrations only"],
            [roll.deptName, String(roll.own), null, "The owning department"],
            ["Other programmes", String(roll.borrowed), "var(--chrome)", roll.fromProgrammes.length ? `Across ${roll.fromProgrammes.length} programme${roll.fromProgrammes.length === 1 ? "" : "s"}` : "None"],
            ["Cleared to sit", String(roll.all - notCleared.length), notCleared.length ? "var(--red-ink)" : "var(--green-ink)", notCleared.length ? `${notCleared.length} blocked at the Bursary` : "Everyone"],
          ]} />
          <Note kind="info" title="This list is generated now, from approved registrations — all of them" action={<><Btn kind="primary" onClick={() => sheet("classlist")}>Download class list</Btn> <Btn kind="ghost" onClick={() => sheet("attreg")}>Attendance register</Btn> <Btn kind="ghost" onClick={() => sheet("examroll")}>Examination roll</Btn></>}>
            {roll.fromProgrammes.length ? `Includes ${roll.fromProgrammes.join(", ")} as well as the owning programmes.` : null}
          </Note>
          <Panel title={head} right={`${roll.all} registered · ${roll.borrowed} from other programmes${roll.lecturer ? ` · ${roll.lecturer}` : ""}`}>
            <DTable
              cols={["Matriculation number", "Name", "Programme", "Level|mid", "Basis|mid", "Attendance|mid", "Clearance|num"]}
              rows={roll.rows.map((r) => [
                <span className="tnum" key="m">{r.number}</span>,
                <strong key="n">{r.surname}, {r.otherNames}</strong>,
                r.deptCode === roll.deptCode ? <span className="sub2" key="p">{r.programmeName}</span> : <Pil kind="info" key="p">{r.programmeName}</Pil>,
                <span className="tnum" key="l">{r.level}</span>,
                r.basis === "Core" ? <span className="sub2" key="b">Core</span> : <Pil kind="info" key="b">{r.basis}</Pil>,
                <span className="sub2 tnum" key="a">—</span>,
                r.cleared ? <Pil kind="ok" key="c">Cleared</Pil> : <Pil kind="bad" key="c">Blocked — fees</Pil>,
              ])}
              texts={roll.rows.map((r) => `${r.number} ${r.surname} ${r.otherNames} ${r.programmeName}`)}
            />
            {!roll.rows.length ? <PBody><div className="sub2">Nobody has an approved registration for this course in {roll.session}, {semWord(roll.semester, roll.session)} semester.</div></PBody> : null}
          </Panel>
          {notCleared.length ? (
            <Note kind="bad" title={`${notCleared.length} registered student${notCleared.length === 1 ? " is" : "s are"} not cleared to sit the examination`}>
              {notCleared.slice(0, 3).map((r) => r.number).join(", ")}{notCleared.length > 3 ? ` and ${notCleared.length - 3} more` : ""} will appear on the examination roll marked as not cleared.
            </Note>
          ) : null}
        </>
      )}
    </>
  );
}
