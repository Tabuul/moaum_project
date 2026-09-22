import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Budget, type BudgetView, type Statement } from "./Budget";

export const dynamic = "force-dynamic";

/** t/budget — budget performance by cost centre (commitment accounting), and the income and expenditure statement. */
export default async function BudgetPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const year = typeof p.year === "string" ? p.year : "";
  const [me, view] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<BudgetView>(`/api/v1/expenditure/budget${year ? `?year=${encodeURIComponent(year)}` : ""}`),
  ]);
  /* the income and expenditure statement for the same financial year (proto bBudget's second panel) */
  const ie = view.ok ? await api<Statement>(`/api/v1/reports/income-expenditure?year=${view.data.year}`) : null;
  return (
    <Shell route="t/budget" me={me.ok ? me.data : null}>
      {view.ok ? <Budget d={view.data} ie={ie && ie.ok ? ie.data : null} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
