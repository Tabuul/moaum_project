import "server-only";
import { redirect } from "next/navigation";
import { api } from "@/lib/api";
import type { Me as ShellMe } from "@/components/proto/Shell";
import { loadStudent } from "@/app/student/load";

/** Who is on the requester's side of the ICT desk: a student reads the student shell, everyone else their office's.
 *  The menu id decides which sidebar item lights up; both point at /tickets. */
export async function requester(): Promise<{ me: ShellMe | null; route: string }> {
  const who = await api<ShellMe>("/api/v1/iam/me");
  if (!who.ok) {
    if (who.problem.status === 401) redirect("/login");
    return { me: null, route: "r/tickets" };
  }
  if (who.data.activeOffice === "student") {
    const loaded = await loadStudent();
    return { me: loaded.me, route: "s/tickets" };
  }
  return { me: who.data, route: "r/tickets" };
}
