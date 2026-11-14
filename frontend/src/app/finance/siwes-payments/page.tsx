import { api } from "@/lib/api";
import { sessionRows } from "@/lib/sessions-server";
import { currentSession } from "@/lib/sessions";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { ScopeStructure } from "@/components/proto/ScopeBar";
import { creditRow, readSiwesFilters, siwesQuery, type SiwesPaymentPage } from "@/lib/siwes";
import { SiwesPayments } from "./SiwesPayments";

export const dynamic = "force-dynamic";

/** t/siwespayments — V752: the SIWES registration fee's payments for the Bursary's reconciliation: only confirmed payments, each with
 *  the gateway and its reference, the receipt, the amount and where it was paid (the portal, or the old portal's SIWES payment that
 *  counts for its session) — never mixed with school fees or the GST fee — filtered by session, faculty, department, programme and
 *  source, totalled (what settles students' fees apart from what is held as credits), and exported; and the credits — a second payment
 *  for a session already paid — for the Bursar to refund, or reopen one settled in error. */
export default async function SiwesPaymentsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const asked = readSiwesFilters(sp);
  const page = typeof sp.page === "string" && /^\d{1,5}$/.test(sp.page) ? Number(sp.page) : 0;
  const sessions = await sessionRows();
  // the session the address names, else the University's current session (never a year written into the code)
  const session = asked.session ?? currentSession(sessions);
  const filters = { session, faculty: asked.faculty, department: asked.department, programme: asked.programme, source: asked.source };
  const [me, data, structure, credits] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SiwesPaymentPage>(`/api/v1/finance/siwes/payments?${siwesQuery(filters, { page, size: 50 })}`),
    api<ScopeStructure>("/api/v1/ref/structure"),
    api<Record<string, unknown>[]>(`/api/v1/finance/siwes/credits?${siwesQuery({ session })}`),
  ]);
  return (
    <Shell route="t/siwespayments" me={me.ok ? me.data : null} sub={`${session} · SIWES registration fee`}>
      {data.ok ? <SiwesPayments data={data.data} page={page} filters={filters} sessions={sessions.map((s) => s.name)} structure={structure.ok ? structure.data : { faculties: [] }}
          credits={credits.ok && Array.isArray(credits.data) ? credits.data.map(creditRow) : []} creditsProblem={credits.ok ? null : credits.problem}
          actingOffice={me.ok ? me.data.activeOffice ?? null : null} />
        : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
