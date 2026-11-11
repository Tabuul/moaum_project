import { api } from "@/lib/api";
import { intakeSession } from "@/lib/sessions";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { acceptancePath, acceptanceQuery, readAcceptanceFilters, type AcceptanceOptions, type AcceptancePage, type AcceptanceSummary } from "@/lib/acceptance-fees";
import { AcceptanceFees } from "./AcceptanceFees";

export const dynamic = "force-dynamic";

/** t/acceptancefees — the acceptance fee monitor (V724): every released UTME and Direct Entry offer of an admission session
 *  with the acceptance fee as stated now, what is confirmed, the balance and a standing — not paid, awaiting the bank, the
 *  earlier fee paid and the balance owing, the balance paid, paid in full, paid above the fee (for the refund desk),
 *  confirmed without a reference — filtered and counted on the server within the office's scope, and downloaded as a
 *  branded workbook */
export default async function AcceptanceFeesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const filters = readAcceptanceFilters(p);
  const page = typeof p.page === "string" && /^\d{1,5}$/.test(p.page) ? Number(p.page) : 0;
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  // the admission session: the one candidates are admitted into, never a year written into the code
  const intake = intakeSession(sessions.ok ? sessions.data : []);
  if (!filters.session) filters.session = intake;
  const base = acceptancePath(filters.session);
  const [options, summary, list] = await Promise.all([
    api<AcceptanceOptions>(`${base}/options`),
    api<AcceptanceSummary>(`${base}/summary?${acceptanceQuery(filters, {}, false)}`),
    api<AcceptancePage>(`${base}?${acceptanceQuery(filters, { page, size: 50 }, false)}`),
  ]);
  const names = sessions.ok ? sessions.data.map((s) => s.name) : [];
  return (
    <Shell route="t/acceptancefees" me={me.ok ? me.data : null} sub={`${filters.session} admission session`}>
      {!options.ok ? <ProblemNotice problem={options.problem} />
        : !summary.ok ? <ProblemNotice problem={summary.problem} />
        : !list.ok ? <ProblemNotice problem={list.problem} />
        : <AcceptanceFees filters={filters} options={options.data} summary={summary.data} list={list.data}
            sessions={[...new Set([filters.session, intake, ...names])].filter(Boolean).sort().reverse()} />}
    </Shell>
  );
}
