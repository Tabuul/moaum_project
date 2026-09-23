import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { intakeSession } from "@/lib/sessions";
import { Senate, type SenateView } from "./Senate";

export const dynamic = "force-dynamic";

/** The Secretary's results-to-Senate desk: the award of degrees (Policy 33–34). */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, cal] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ sessions: { name: string; state: string }[]; current: string | null }>("/api/v1/pg/calendar"),
  ]);
  const sessions = cal.ok ? cal.data.sessions : [];
  const session = typeof p.session === "string" ? p.session : (cal.ok && cal.data.current) ? cal.data.current : intakeSession(sessions);
  const view = await api<SenateView>(`/api/v1/pg/secretary/senate?session=${encodeURIComponent(session)}`);
  return (
    <Shell route="t/pgsenate" me={me.ok ? me.data : null}>
      <Senate session={session} sessions={sessions} view={view.ok ? view.data : null} problem={view.ok ? null : view.problem} />
    </Shell>
  );
}
