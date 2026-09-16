import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Accounting, type Overview, type Account, type TrialBalance, type Statement, type Journal } from "./Accounting";

export const dynamic = "force-dynamic";

/** t/accounts — the Bursary's books: chart of accounts, trial balance, income & expenditure, balance sheet, journals */
export default async function AccountingPage() {
  const [me, overview, chart, trial, ie, bs, journals] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Overview>("/api/v1/finance/accounting/overview"),
    api<Account[]>("/api/v1/finance/accounting/chart"),
    api<TrialBalance>("/api/v1/finance/accounting/trial-balance"),
    api<Statement>("/api/v1/finance/accounting/income-expenditure"),
    api<Statement>("/api/v1/finance/accounting/balance-sheet"),
    api<Journal[]>("/api/v1/finance/accounting/journals"),
  ]);
  const bad = [overview, chart, trial, ie, bs, journals].find((r) => !r.ok);
  return (
    <Shell route="t/accounts" me={me.ok ? me.data : null}>
      {bad && !bad.ok ? (
        <ProblemNotice problem={bad.problem} />
      ) : overview.ok && chart.ok && trial.ok && ie.ok && bs.ok && journals.ok ? (
        <Accounting
          overview={overview.data}
          chart={chart.data}
          trial={trial.data}
          ie={ie.data}
          bs={bs.data}
          journals={journals.data}
          actingOffice={me.ok ? me.data.activeOffice : null}
        />
      ) : null}
    </Shell>
  );
}
