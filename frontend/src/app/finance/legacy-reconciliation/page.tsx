import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { CreditRequestRow, OutstandingPaymentRow, OutstandingRow, ReconFigures } from "@/lib/legacy-reconciliation";
import { LegacyReconciliation } from "./LegacyReconciliation";

export const dynamic = "force-dynamic";

/** t/legacyrecon — legacy financial reconciliation (V625): the old portal's outstanding fees of a session, student by student (what the
 *  student owes and what the University holds, kept apart), the old portal's OUTSTANDING FEES payments the officer verifies and the
 *  Bursar credits to the wallet (V631), the e-wallet top-ups (the V583 desk's figures), the wallet credit requests the Students Account
 *  Officer confirms and the Bursar decides, and the history; the reports */
export default async function LegacyReconciliationPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const filters: Record<string, string> = {};
  for (const k of ["tab", "session", "state", "status", "q", "fac", "dept"]) if (s(k)) filters[k] = s(k);
  const tab = filters.tab || "overview";
  const ses = filters.session ? `session=${encodeURIComponent(filters.session)}` : "";
  const oq = new URLSearchParams();
  for (const k of ["session", "state", "q", "fac", "dept"]) if (filters[k]) oq.set(k, filters[k]);
  const rq = new URLSearchParams();
  for (const k of ["status", "session", "q", "fac", "dept"]) if (filters[k]) rq.set(k, filters[k]);
  if (tab === "history" && !filters.status) rq.delete("status");
  // V631: the old portal's OUTSTANDING FEES payments, every session unless one is chosen
  const pq = new URLSearchParams();
  for (const k of ["status", "session", "q", "fac", "dept"]) if (filters[k]) pq.set(k, filters[k]);
  pq.set("limit", "2000");
  const [me, figures, sessions, outstanding, requests, structure, payments] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ReconFigures>(`/api/v1/finance/legacy-reconciliation/figures${ses ? `?${ses}` : ""}`),
    api<string[]>("/api/v1/finance/legacy-reconciliation/sessions"),
    tab === "outstanding" ? api<OutstandingRow[]>(`/api/v1/finance/legacy-reconciliation/outstanding?${oq.toString()}`) : Promise.resolve(null),
    tab === "requests" || tab === "history" || tab === "overview" ? api<CreditRequestRow[]>(`/api/v1/finance/legacy-reconciliation/requests?${rq.toString()}`) : Promise.resolve(null),
    api<{ faculty_code: string; faculty: string; dept_code: string; department: string }[]>("/api/v1/finance/fee-report/structure"),
    tab === "payments" ? api<OutstandingPaymentRow[]>(`/api/v1/finance/legacy-reconciliation/outstanding-payments?${pq.toString()}`) : Promise.resolve(null),
  ]);
  return (
    <Shell route="t/legacyrecon" me={me.ok ? me.data : null}>
      {figures.ok ? (
        <LegacyReconciliation figures={figures.data} sessions={sessions.ok ? sessions.data : []} filters={filters}
          outstanding={outstanding ? (outstanding.ok ? outstanding.data : []) : null} outstandingProblem={outstanding && !outstanding.ok ? outstanding.problem : null}
          requests={requests ? (requests.ok ? requests.data : []) : null} requestsProblem={requests && !requests.ok ? requests.problem : null}
          payments={payments ? (payments.ok ? payments.data : []) : null} paymentsProblem={payments && !payments.ok ? payments.problem : null}
          structure={structure.ok ? structure.data : []} actingOffice={me.ok ? me.data.activeOffice ?? null : null} me={me.ok ? me.data.name ?? null : null} />
      ) : <ProblemNotice problem={figures.problem} />}
    </Shell>
  );
}
