import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AuditRevenue, type Bursary, type Revenue } from "./AuditRevenue";

export const dynamic = "force-dynamic";

/** t/auditrevenue — the audit directorate's read of collection: portal and Bursary in one answer. */
export default async function AuditRevenuePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "2026/2027";
  const [me, bursary, revenue] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Bursary>(`/api/v1/finance/bursary?session=${encodeURIComponent(session)}`),
    api<Revenue>(`/api/v1/reports/revenue?session=${encodeURIComponent(session)}`),
  ]);
  return (
    <Shell route="t/auditrevenue" me={me.ok ? me.data : null}>
      {bursary.ok ? (
        <AuditRevenue session={session} bursary={bursary.data} revenue={revenue.ok ? revenue.data : null} />
      ) : <ProblemNotice problem={bursary.problem} />}
    </Shell>
  );
}
