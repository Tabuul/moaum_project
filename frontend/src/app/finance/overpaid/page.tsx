import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { rowsQuery, type OverpaidFigures, type OverpaidRows } from "@/lib/overpaid";
import { OverpaidDesk } from "./OverpaidDesk";

export const dynamic = "force-dynamic";

const TABS = ["students", "approvals", "returned"] as const;

/** t/overpaid — V781: school fees paid above the charge, by cause, reconciled from the Bursar's dashboard: a wallet credit asked for by
 *  one officer and approved by another, or a refund; what holds a student back is said beside the student. ?session= opens a session,
 *  ?tab= a tab, and ?cause= ?state= ?held= ?bulk= ?faculty= ?department= ?q= ?page= the list of students. */
export default async function OverpaidPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const filters: Record<string, string> = {};
  for (const k of ["session", "tab", "cause", "state", "held", "bulk", "faculty", "department", "q", "page"]) if (s(k)) filters[k] = s(k);
  const tab = (TABS as readonly string[]).includes(filters.tab) ? (filters.tab as (typeof TABS)[number]) : "students";
  const ses = filters.session ? `?session=${encodeURIComponent(filters.session)}` : "";
  const [me, figures, rows] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<OverpaidFigures>(`/api/v1/finance/overpaid/figures${ses}`),
    tab === "students" ? api<OverpaidRows>(`/api/v1/finance/overpaid/rows?${rowsQuery(filters)}`) : Promise.resolve(null),
  ]);
  return (
    <Shell route="t/overpaid" me={me.ok ? me.data : null}>
      {figures.ok ? (
        <OverpaidDesk figures={figures.data} rows={rows ? (rows.ok ? rows.data : null) : null} rowsProblem={rows && !rows.ok ? rows.problem : null} filters={{ ...filters, tab }}
          actingOffice={me.ok ? me.data.activeOffice ?? null : null} />
      ) : <ProblemNotice problem={figures.problem} />}
    </Shell>
  );
}
