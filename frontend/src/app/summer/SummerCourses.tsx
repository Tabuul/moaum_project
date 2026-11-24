"use client";

/** V735 · the Summer's classes: every course a student is registered in for the Summer, with its lecturer, the numbers who owed it in
 *  each semester, and its score sheet. Lecturers are allocated on Teaching Allocation (semester: Summer). */
import Link from "next/link";
import { Panel, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { classListHref } from "@/lib/lecturer";
import { semesterWord } from "@/lib/summer";

export interface SummerCourseRow {
  offering_id: string; course_code: string; title: string | null; units: number | null; course_semester: number | null; dept_code: string | null;
  department: string | null; lecturer: string | null; registered: number; failed_in_first: number; failed_in_second: number; sheets: number;
  sheet_stage: string | null;
}

/** V741: the offices that may open a class list (the API's /registration/class-list readers) */
const CLASS_LIST = ["academic", "registrar", "dregistrar", "dvc", "vc", "records", "dean", "hod", "exams", "facultyexams", "facultyofficer", "lecturer", "ict", "admin", "super"];

export function SummerCourses({ session, courses, actingOffice }: { session: string; courses: SummerCourseRow[]; actingOffice: string | null }) {
  return (
    <Panel title="The Summer's classes" right="Allocate lecturers on Teaching Allocation (semester: Summer)">
      <DTable pageSize={50} cols={["Course", "Title", "Units|num", "Course's semester", "Department", "Lecturer", "Registered|num", "Failed in the first · second", "Score sheet"]} rows={courses.map((c) => [
        CLASS_LIST.includes(actingOffice ?? "")
          ? <Link key="c" className="lnk tnum b700" href={classListHref(c.course_code, session, 3)} title="The students registered in this Summer class">{c.course_code}</Link>
          : <b key="c" className="tnum">{c.course_code}</b>,
        <span key="t">{c.title ?? "—"}</span>,
        <span key="u" className="tnum">{c.units ?? "—"}</span>,
        <span key="s">{semesterWord(c.course_semester)}</span>,
        <span key="d" className="sub2">{c.department ?? c.dept_code ?? "—"}</span>,
        c.lecturer ? <span key="l">{c.lecturer}</span> : <Pil key="l" kind="warn">NOT ALLOCATED</Pil>,
        <span key="r" className="tnum">{c.registered}</span>,
        <span key="f" className="tnum">{c.failed_in_first} · {c.failed_in_second}</span>,
        <span key="sh" className="sub2">{c.sheets ? (c.sheet_stage ?? "made").toLowerCase() : "—"}</span>,
      ])} texts={courses.map((c) => `${c.course_code} ${c.title ?? ""} ${c.department ?? ""} ${c.lecturer ?? ""}`)} />
    </Panel>
  );
}
