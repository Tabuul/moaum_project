"use client";

/** rClasslist — proto/part17.html: one register, generated now, from approved registrations — all of them. */
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { csv, download, type ClassList } from "@/lib/results";
import { ScopeBar, type Ceiling, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, Note, Panel, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

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
  const sheet = (what: string) => {
    if (!roll) return;
    const rows: (string | number)[][] = [["Matriculation number", "Name", "Programme", "Level", "Basis", what === "examroll" ? "Cleared to sit" : what === "attreg" ? "Week 1" : "Clearance"]];
    for (const r of roll.rows) rows.push([r.number, `${r.surname}, ${r.otherNames}`, r.programmeName, r.level, r.basis, what === "attreg" ? "" : r.cleared ? "Cleared" : "Blocked — fees"]);
    download(`${roll.courseCode.replace(/\s/g, "")}-${what}-${roll.session.replace("/", "-")}.csv`, csv(rows));
  };

  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} courses={courses} what="students" count={roll?.all ?? 0} of={roll?.all ?? 0} withCourse ceiling={ceiling} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!roll ? (
        <Note kind="info" title="Choose a course in the scope bar">
          The class list is the roll of an offering: every approved registration for one course in one session and semester. Pick the department, then the course, and the list is generated from the register as it stands now.
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
            It is not a file somebody exported in September. Add or drop a registration and this list changes. It is also not filtered to this department: {roll.courseCode} is registered by {roll.fromProgrammes.length ? `${roll.fromProgrammes.join(", ")} as well as the owning programmes, and they` : "the owning programmes, and its students"} appear here and on every roll drawn from it.
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
            {!roll.rows.length ? <div className="card__body"><div className="sub2">Nobody has an approved registration for this course in {roll.session}, semester {roll.semester}.</div></div> : null}
          </Panel>
          {notCleared.length ? (
            <Note kind="bad" title={`${notCleared.length} registered student${notCleared.length === 1 ? " is" : "s are"} not cleared to sit the examination`}>
              {notCleared.slice(0, 3).map((r) => r.number).join(", ")}{notCleared.length > 3 ? ` and ${notCleared.length - 3} more` : ""} appear on the class list because they are registered, and they will appear on the examination roll marked as not cleared. The invigilator does not adjudicate that at the door — the Bursary does, before the day.
            </Note>
          ) : null}
        </>
      )}
    </>
  );
}
