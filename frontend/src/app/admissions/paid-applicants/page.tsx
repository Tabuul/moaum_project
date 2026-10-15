import { api } from "@/lib/api";
import { intakeSession } from "@/lib/sessions";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { paidPath, paidQuery, readPaidFilters, type PaidOptions, type PaidPage, type PaidSummary } from "@/lib/paid-applicants";
import { PaidApplicants } from "./PaidApplicants";

export const dynamic = "force-dynamic";

/** t/paidapplicants — the Post-UTME paid applicants report (V479): the candidates of an admission session whose Post-UTME
 *  application fee the payment service has confirmed, filtered and counted on the server within the office's scope, and
 *  downloaded as a branded workbook or PDF */
export default async function PaidApplicantsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const filters = readPaidFilters(p);
  const page = typeof p.page === "string" && /^\d{1,5}$/.test(p.page) ? Number(p.page) : 0;
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  if (!filters.session) filters.session = intakeSession(sessions.ok ? sessions.data : []);
  const base = paidPath(filters.session);
  const [options, summary, list] = await Promise.all([
    api<PaidOptions>(`${base}/options`),
    api<PaidSummary>(`${base}/summary?${paidQuery(filters, {}, false)}`),
    api<PaidPage>(`${base}?${paidQuery(filters, { page, size: 50 }, false)}`),
  ]);
  // the sessions that hold applications, with the intake session and the one asked for
  const intake = intakeSession(sessions.ok ? sessions.data : []);
  return (
    <Shell route="t/paidapplicants" me={me.ok ? me.data : null} sub={`${filters.session} admission session`}>
      {!options.ok ? <ProblemNotice problem={options.problem} />
        : !summary.ok ? <ProblemNotice problem={summary.problem} />
        : !list.ok ? <ProblemNotice problem={list.problem} />
        : <PaidApplicants filters={filters} options={options.data} summary={summary.data} list={list.data}
            sessions={[...new Set([filters.session, intake, ...options.data.sessions])].filter(Boolean).sort().reverse()} />}
    </Shell>
  );
}
