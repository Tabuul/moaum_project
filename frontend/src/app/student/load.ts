import "server-only";
import { redirect } from "next/navigation";
import { api } from "@/lib/api";
import type { Me as ShellMe } from "@/components/proto/Shell";
import type { Me } from "@/lib/student-portal";
import type { StudentGate } from "@/lib/biodata-gate";

/** The student's record, read once per screen, and the shell's idea of who is signed in built from it. V423: while the
 *  biodata gate holds the student, every screen but the few that complete it (gateOpen) sends them to the biodata page,
 *  and the sidebar is the gate's — the API refuses the rest whatever happens here. */
export async function loadStudent(opts: { gateOpen?: boolean } = {}): Promise<{ me: ShellMe; student: Me; gate: StudentGate | null } | { me: ShellMe | null; student: null; problem: import("@/lib/api").Problem; gate: StudentGate | null }> {
  const [who, mine, gateRead] = await Promise.all([api<ShellMe>("/api/v1/iam/me"), api<Me>("/api/v1/me"), api<StudentGate>("/api/v1/me/biodata/completion")]);
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
  };
  return { me, student: mine.data, gate };
}
