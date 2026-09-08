import "server-only";
import { redirect } from "next/navigation";
import { api } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import type { Application } from "@/lib/applicant";

/**
 * The applicant's application, read once per screen, and the shell's idea of
 * who is signed in built from it: the applicant's name from JAMB, the one
 * office they hold. A staff session landing here is sent to its own home.
 */
export async function loadApplication(): Promise<{ me: Me; app: Application } | { me: Me | null; app: null; problem: import("@/lib/api").Problem }> {
  const [who, mine] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Application>("/api/v1/applicant/me")]);
  if (who.ok && who.data.activeOffice !== "applicant") redirect("/");
  if (!mine.ok) {
    if (mine.problem.status === 401) redirect("/login");
    return { me: who.ok ? who.data : null, app: null, problem: mine.problem };
  }
  const me: Me = {
    actorId: who.ok ? who.data.actorId : mine.data.id,
    activeOffice: "applicant",
    offices: ["applicant"],
    name: mine.data.name,
    staffNumber: mine.data.applicationNo,
    sessionId: who.ok ? who.data.sessionId ?? null : null,
    waiting: {},
  };
  return { me, app: mine.data };
}
