import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { intakeSession, type SessionRow } from "@/lib/sessions";
import type { DashboardData } from "@/lib/hostel";
import { HostelDashboard } from "./HostelDashboard";

export const dynamic = "force-dynamic";

/** the session the hostel desk opens on: asked for, else the current one */
export async function hostelSession(p: Record<string, string | string[] | undefined>): Promise<{ session: string; sessions: string[] }> {
  const sessions = await api<SessionRow[]>("/api/v1/ref/sessions");
  const list = sessions.ok ? sessions.data : [];
  const asked = typeof p.session === "string" && /^\d{4}\/\d{4}$/.test(p.session) ? p.session : "";
  return { session: asked || list.find((s) => s.state === "CURRENT")?.name || intakeSession(list), sessions: list.map((s) => s.name) };
}

/** t/hostel — the accommodation desk (V030 + V261): the figures, the charts, what waits, and the doors to every part of the stay */
export default async function HostelPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const { session, sessions } = await hostelSession(p);
  const [me, view] = await Promise.all([api<Me>("/api/v1/iam/me"), api<DashboardData>(`/api/v1/hostel/sessions/${session}/dashboard`)]);
  return (
    <Shell route="t/hostel" me={me.ok ? me.data : null}>
      {view.ok ? <HostelDashboard data={view.data} session={session} sessions={sessions} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
