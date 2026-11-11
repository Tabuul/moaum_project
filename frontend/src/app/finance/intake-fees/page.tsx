import { api } from "@/lib/api";
import { intakeSession } from "@/lib/sessions";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { intakePath, intakeQuery, readIntakeFilters, type Coverage, type IntakeOptions, type IntakePage, type IntakeSummary, type PortalGate } from "@/lib/intake-fees";
import { IntakeFees } from "./IntakeFees";

export const dynamic = "force-dynamic";

/** t/intakefees — the school-fee readiness monitor (V724): for an intake session, the undergraduate programmes with and
 *  without a fee line in force reaching their freshers (UTME at 100 Level, Direct Entry at 200), by faculty; and every
 *  fresher of the session on the register with the state of their school fees and of their student portal — held until
 *  the fees are stated and paid, cleared, let through by exception — filtered and counted on the server, each row a
 *  door to the student's record, the list downloaded as a branded workbook */
export default async function IntakeFeesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const filters = readIntakeFilters(p);
  const page = typeof p.page === "string" && /^\d{1,5}$/.test(p.page) ? Number(p.page) : 0;
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  // the intake session: the one freshers are admitted into, never a year written into the code
  const intake = intakeSession(sessions.ok ? sessions.data : []);
  if (!filters.session) filters.session = intake;
  const base = intakePath(filters.session);
  // V724: the figures are counted with the list's own filters — faculty, programme, entry mode, search — so the tiles agree with
  // the list; the two states are left out (the server drops them too), so each state tile stays a door
  const summaryQuery = intakeQuery({ ...filters, feeState: "", portalState: "" }, {}, true);
  const [coverage, summary, options, list, gate] = await Promise.all([
    api<Coverage>(`${base}/coverage`),
    api<IntakeSummary>(`${base}/summary${summaryQuery ? `?${summaryQuery}` : ""}`),
    api<IntakeOptions>(`${base}/options`),
    api<IntakePage>(`${base}?${intakeQuery(filters, { page, size: 50 }, true)}`),
    // the gate's rule, for the words at the top; the panel that sets it is Fee Setup's. Refused to an office outside its
    // readers: the monitor still reads without it
    api<PortalGate>("/api/v1/finance/portal-gate"),
  ]);
  const names = sessions.ok ? sessions.data.map((s) => s.name) : [];
  return (
    <Shell route="t/intakefees" me={me.ok ? me.data : null} sub={`${filters.session} entry session`}>
      {!coverage.ok ? <ProblemNotice problem={coverage.problem} />
        : !summary.ok ? <ProblemNotice problem={summary.problem} />
        : !options.ok ? <ProblemNotice problem={options.problem} />
        : !list.ok ? <ProblemNotice problem={list.problem} />
        : <IntakeFees filters={filters} coverage={coverage.data} summary={summary.data} options={options.data} list={list.data}
            gate={gate.ok ? gate.data : null} actingOffice={me.ok ? me.data.activeOffice : null}
            sessions={[...new Set([filters.session, intake, ...names])].filter(Boolean).sort().reverse()} />}
    </Shell>
  );
}
