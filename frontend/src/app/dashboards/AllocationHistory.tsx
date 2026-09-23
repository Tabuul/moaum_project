"use client";

/** The history of teaching allocation, every session on record — the lecturer's own courses (mode "me") or
 *  the department's (mode "department"): session, semester, course, who carried it, the second examiner,
 *  the class size and where its score sheet reached. Read from the register; nothing here is kept apart. */
import { Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface AllocationRow {
  id: string; session: string; semester: number; course_code: string; title: string; units: number; level: number;
  allocated_on: string | null; lecturer_id: string | null; lecturer: string | null; second_examiner: string | null;
  co_lecturers: string | null; students: number; stage: string | null; role: string | null;
}

const STAGE: Record<string, [string, "ok" | "info" | "grey" | "warn"]> = {
  ENTRY: ["Entry", "grey"], VERIFICATION: ["Verification", "info"], DEPT_BOARD: ["Department Board", "info"], FACULTY_SCRUTINY: ["Faculty scrutiny", "info"],
  FACULTY_COMPILATION: ["Faculty compilation", "info"], FACULTY_BOARD: ["Faculty Board", "info"], RECORDS: ["Records", "info"], SENATE: ["Senate", "info"], PUBLISHED: ["Published", "ok"],
};

export function AllocationHistory({ rows, mode, session }: { rows: AllocationRow[]; mode: "me" | "department"; session: string }) {
  const sessions = [...new Set(rows.map((r) => r.session))];
  const past = rows.filter((r) => r.session !== session).length;
  const title = mode === "me" ? "My allocation history" : "Allocation history of the department";
  const right = rows.length
    ? `${sessions.length} session${sessions.length === 1 ? "" : "s"} · ${rows.length} course${rows.length === 1 ? "" : "s"}${past ? ` · ${past} before ${session}` : ""}`
    : "Nothing allocated yet";
  const cols = mode === "me"
    ? ["Session", "Sem|mid", "Course", "Title", "Units|num", "Role|mid", "Second examiner", "Students|num", "Sheet|mid"]
    : ["Session", "Sem|mid", "Course", "Title", "Lecturer", "Co-lecturers", "Second examiner", "Students|num", "Sheet|mid"];
  return (
    <Panel title={title} right={right}>
      {rows.length ? (
        <>
          <DTable cols={cols} rows={rows.map((r) => {
            const st = r.stage ? (STAGE[r.stage] ?? [r.stage, "grey" as const]) : null;
            const head = [
              <span key="s" className={r.session === session ? "" : "sub2"}>{r.session}{r.session === session ? <span className="sub2"> · current</span> : ""}</span>,
              <span key="m" className="tnum">{r.semester}</span>,
              <span key="c" className="tnum" style={{ fontWeight: 600 }}>{r.course_code}</span>,
              <span key="t">{r.title}<div className="sub2">{r.level} level · {r.units} unit{r.units === 1 ? "" : "s"}</div></span>,
            ];
            const tail = [
              <span key="x" className="tnum">{Number(r.students).toLocaleString()}</span>,
              st ? <Pil key="st" kind={st[1]}>{st[0]}</Pil> : <span key="st" className="sub2">no sheet</span>,
            ];
            return mode === "me"
              ? [...head, <span key="u" className="tnum">{r.units}</span>, <Pil key="r" kind={r.role === "Lecturer" ? "info" : "grey"}>{r.role ?? "—"}</Pil>, <span key="e" className="sub2">{r.second_examiner ?? "—"}</span>, ...tail]
              : [...head, <span key="l">{r.lecturer ?? <span className="sub2">not allocated</span>}</span>, <span key="co" className="sub2">{r.co_lecturers ?? "—"}</span>, <span key="e" className="sub2">{r.second_examiner ?? "—"}</span>, ...tail];
          })} texts={rows.map((r) => `${r.session} ${r.course_code} ${r.title} ${r.lecturer ?? ""} ${r.co_lecturers ?? ""} ${r.second_examiner ?? ""}`)} />
          <PBody><div className="sub2">{mode === "me"
            ? "Every course you have carried since allocation began on the portal, as lecturer, co-lecturer or second examiner, with where each score sheet reached."
            : "Every course the department has offered since allocation began on the portal, with who carried it. Search by session, course or name."}</div></PBody>
        </>
      ) : <PBody><div className="sub2">{mode === "me" ? "No course has been allocated to you on the portal yet." : "No course of the department has been allocated on the portal yet."}</div></PBody>}
    </Panel>
  );
}
