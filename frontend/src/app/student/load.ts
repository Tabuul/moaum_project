import "server-only";
import { redirect } from "next/navigation";
import { api } from "@/lib/api";
import type { Me as ShellMe } from "@/components/proto/Shell";
import type { Me } from "@/lib/student-portal";

/** The student's record, read once per screen, and the shell's idea of who is signed in built from it. */
export async function loadStudent(): Promise<{ me: ShellMe; student: Me } | { me: ShellMe | null; student: null; problem: import("@/lib/api").Problem }> {
  const [who, mine] = await Promise.all([api<ShellMe>("/api/v1/iam/me"), api<Me>("/api/v1/me")]);
  if (who.ok && who.data.activeOffice !== "student") redirect("/");
  if (!mine.ok) {
    if (mine.problem.status === 401) redirect("/login");
    return { me: who.ok ? who.data : null, student: null, problem: mine.problem };
  }
  const me: ShellMe = {
    actorId: who.ok ? who.data.actorId : mine.data.id,
    activeOffice: "student",
    offices: ["student"],
    name: mine.data.name,
    staffNumber: mine.data.matricNo ?? mine.data.admissionNo,
    sessionId: who.ok ? who.data.sessionId ?? null : null,
    waiting: {},
  };
  return { me, student: mine.data };
}
