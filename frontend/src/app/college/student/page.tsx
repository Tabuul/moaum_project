import Link from "next/link";
import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Note, Panel, PBody } from "@/components/proto/ui";
import { loadStudent } from "../../student/load";

export const dynamic = "force-dynamic";

/**
 * /college/student — where the login gate sends a College of Health Sciences student: a student whose
 * programme sits under the College (faculty.college_code = 'CHS') and who is at 200 level or above.
 * They sign in through the one University login; the gate routes them here.
 *
 * This is the seam for the College module developer to build the student-facing College dashboard
 * (clinical postings, professional examinations, College results). The student's standard record —
 * fees, registration, results, transcript — remains at /student.
 */
export default async function CollegeStudentPage() {
  const loaded = await loadStudent();
  return (
    <Shell route="s/dashboard" me={loaded.me}>
      {!loaded.student ? (
        <ProblemNotice problem={loaded.problem} />
      ) : (
        <>
          <Note kind="info" title={`Welcome, ${loaded.student.name} — College of Health Sciences`}>
            You are a College of Health Sciences student. Your College dashboard is being built here.
          </Note>
          <Panel title="College of Health Sciences">
            <PBody>
              <div className="sub2" style={{ marginBottom: 10 }}>
                This is the College student dashboard area — clinical postings, professional examinations and
                College results will appear here. Your standard student record (fees, registration, results and
                the transcript) remains available in the main portal.
              </div>
              <Link href="/student" className="btn btn--primary btn--sm">Open my student record</Link>
            </PBody>
          </Panel>
        </>
      )}
    </Shell>
  );
}
