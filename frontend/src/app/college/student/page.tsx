import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { loadStudent } from "../../student/load";
import { CollegeStudentDashboard } from "./CollegeDashboard";

export const dynamic = "force-dynamic";

/**
 * /college/student — where the login gate sends a College of Health Sciences student: a student whose
 * programme sits under the College (faculty.college_code = 'CHS') and who is at 200 level or above.
 * They sign in through the one University login; the gate routes them here.
 *
 * The menu is the trimmed "studentchs" variant (menus.ts) rather than the standard student menu: course
 * registration, timetable, attendance and examinations are the College's own academic system's screens,
 * not this portal's, until that system is linked in (a later phase) — so they are not offered here.
 */
export default async function CollegeStudentPage() {
  const loaded = await loadStudent();
  return (
    <Shell route="s/dashboard" me={loaded.me} menuKey="studentchs">
      {!loaded.student ? <ProblemNotice problem={loaded.problem} /> : <CollegeStudentDashboard s={loaded.student} />}
    </Shell>
  );
}
