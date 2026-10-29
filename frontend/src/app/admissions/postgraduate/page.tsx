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
    api<{ sessions: { name: string; state: string }[]; current: string | null; intake?: string | null }>("/api/v1/pg/calendar"),
  ]);
  // the PG School keeps its own calendar (V224); the applications desk opens on the session applicants are admitted into
  // (V452: the intake, 2026/2027 while 2025/2026 runs), else the School's current one
  const pgSessions = cal.ok ? cal.data.sessions : [];
  const session = typeof p.session === "string" ? p.session
    : (cal.ok && cal.data.intake) ? cal.data.intake
    : (cal.ok && cal.data.current) ? cal.data.current
    : intakeSession(pgSessions);
  // V694: the list narrowed on the server — by where the document upload stands, to those who applied more than once — and its order
  const documents = typeof p.documents === "string" && ["COMPLETE", "PENDING", "NONE", "FEE_UNPAID"].includes(p.documents) ? p.documents : null;
  const duplicates = p.duplicates === "1";
  const sort = p.sort === "applied" ? "applied" : null;
  const q = new URLSearchParams({ session });
  if (documents) q.set("documents", documents);
  if (duplicates) q.set("duplicates", "true");
  if (sort) q.set("sort", sort);
  const view = await api<PgView>(`/api/v1/pg/applications?${q.toString()}`);
  return (
    <Shell route="t/pgadmissions" me={me.ok ? me.data : null}>
      <PgAdmissions
        session={session}
        sessions={pgSessions}
        view={view.ok ? view.data : null}
        filters={{ documents, duplicates, sort }}
        problem={view.ok ? null : view.problem}
        actingOffice={me.ok ? me.data.activeOffice : null}
      />
    </Shell>
  );
}
