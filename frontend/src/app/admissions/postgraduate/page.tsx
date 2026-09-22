import { intakeSession } from "@/lib/sessions";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { PgAdmissions, type PgView } from "./PgAdmissions";

export const dynamic = "force-dynamic";

/** Postgraduate admissions desks (V202): the department and School decide, then admit onto the register. */
export default async function PgAdmissionsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, cal] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ sessions: { name: string; state: string }[]; current: string | null }>("/api/v1/pg/calendar"),
  ]);
  // the PG School keeps its own calendar (V224): default to its current/intake session, not the University's
  const pgSessions = cal.ok ? cal.data.sessions : [];
  const session = typeof p.session === "string" ? p.session
    : (cal.ok && cal.data.current) ? cal.data.current
    : intakeSession(pgSessions);
  const view = await api<PgView>(`/api/v1/pg/applications?session=${encodeURIComponent(session)}`);
  return (
    <Shell route="t/pgadmissions" me={me.ok ? me.data : null}>
      <PgAdmissions
        session={session}
        view={view.ok ? view.data : null}
        problem={view.ok ? null : view.problem}
        actingOffice={me.ok ? me.data.activeOffice : null}
      />
    </Shell>
  );
}
