import "server-only";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { api } from "@/lib/api";
import type { Me as ShellMe } from "@/components/proto/Shell";
import type { Me } from "@/lib/student-portal";
import type { StudentGate } from "@/lib/biodata-gate";
import { SUPPORT_RETURN_COOKIE } from "@/lib/support-view";

/** V724: where finance.portal_access_state leaves a fresh admit that the student portal's fee gate holds — the acceptance fee's balance
 *  owed, the school fees not yet stated, or not paid as the gate asks */
const HELD_AT_THE_FEE_GATE = ["HELD_ACCEPTANCE_BALANCE", "HELD_FEES_UNPAID", "HELD_FEES_NOT_AVAILABLE"];

/** The student's record, read once per screen, and the shell's idea of who is signed in built from it. V423: while the
 *  biodata gate holds the student, every screen but the few that complete it (gateOpen) sends them to the biodata page,
 *  and the sidebar is the gate's — the API refuses the rest whatever happens here. */
export async function loadStudent(opts: { gateOpen?: boolean } = {}): Promise<{ me: ShellMe; student: Me; gate: StudentGate | null } | { me: ShellMe | null; student: null; problem: import("@/lib/api").Problem; gate: StudentGate | null }> {
  const [who, mine, gateRead] = await Promise.all([api<ShellMe>("/api/v1/iam/me"), api<Me>("/api/v1/me"), api<StudentGate>("/api/v1/me/biodata/completion")]);
  /* V485: a student whose password must change reaches only the change; the API refuses the rest whatever the address */
  if (!mine.ok && mine.problem.code === "PASSWORD_CHANGE_REQUIRED") redirect("/student/password");
  /* V724: a fresh admit the student portal's fee gate holds (the acceptance fee's balance owed, the school fees not yet stated, or not
     paid as the gate asks). The gate lets GET /me, the biodata completion and iam/me through whatever the state, so none of them is
     refused: GET /me says where the record stands (portalAccess, finance.portal_access_state read now), and a held student is sent to
     the sign-in, which opens the applicant dashboard on the JAMB or application number — the fees, and the acceptance balance, are
     paid there. proxy.ts does the same on a page navigation from the X-Portal-Access header, clearing the student cookies; this
     catches a client-side navigation it let through. ICT Support viewing the portal read-only (V521) pays nothing and is never sent. */
  const access = mine.ok ? (mine.data as Me & { portalAccess?: string | null }).portalAccess : null;
  if (access && HELD_AT_THE_FEE_GATE.includes(access) && !(await cookies()).get(SUPPORT_RETURN_COOKIE)?.value) {
    redirect("/login?next=%2Fapplicant%2Fadmission%23fees&reason=held-fees");
  }
  const gate = gateRead.ok ? gateRead.data : null;
  const held = gate?.gate === "REQUIRED";
  if (held && !opts.gateOpen) redirect("/student/biodata");
  /* an applicant who follows a link into the student portal is handed across, not bounced home */
  if (who.ok && who.data.activeOffice === "applicant") redirect("/applicant/to-student?next=/student/fees");
  if (who.ok && who.data.activeOffice !== "student") redirect("/");
  if (!mine.ok) {
    if (mine.problem.status === 401) redirect("/login");
    return { me: who.ok ? who.data : null, student: null, problem: mine.problem, gate };
  }
  const me: ShellMe = {
    actorId: who.ok ? who.data.actorId : mine.data.id,
    activeOffice: "student",
    offices: ["student"],
    name: mine.data.name,
    staffNumber: mine.data.matricNo ?? mine.data.admissionNo,
    sessionId: who.ok ? who.data.sessionId ?? null : null,
    waiting: {},
    // a postgraduate is a student to the API, but the sidebar is the School's: registration, results, research; a student the
    // biodata gate holds sees only what completes it
    menu: held ? "studentgate" : mine.data.entryMode === "POSTGRADUATE" ? "pgstudent" : null,
    unit: mine.data.entryMode === "POSTGRADUATE" ? mine.data.programme : null,
    // V606: an MBBS student's menu carries the College's own student area beside the University's
    // V735: and the Summer Semester page where a Summer is set the student may take (or one they took)
    flags: [...(mine.data.collegeArea ? ["college"] : []), ...(mine.data.summerArea ? ["summer"] : [])],
    // V575: a contact a department uploaded that the student has not confirmed, asked on every screen until answered
    contactConfirm: who.ok ? who.data.contactConfirm ?? null : null,
    // V430 "how do we reach you" and V441 the privacy policy: worked out for the student by iam/me, asked on the student's own
    // screens as on everyone else's (the password change page alone leaves them out: the password comes first)
    contactPrompt: who.ok ? who.data.contactPrompt ?? null : null,
    privacyPrompt: who.ok ? who.data.privacyPrompt ?? null : null,
  };
  return { me, student: mine.data, gate };
}
