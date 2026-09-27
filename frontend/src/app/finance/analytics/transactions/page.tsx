import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Transactions } from "./Transactions";
import { finQuery, readFinFilters, type FinPage } from "@/lib/analytics";

export const dynamic = "force-dynamic";

/** t/fintransactions — the confirmed payments behind a figure, newest first, with the filters that counted them */
export default async function TransactionsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const filters = readFinFilters(params);
  const page = typeof params.page === "string" ? Math.max(0, Number(params.page) || 0) : 0;
  const studentId = typeof params.studentId === "string" ? params.studentId : "";
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<FinPage>(`/api/v1/analytics/finance/transactions?${finQuery(filters, { page, size: 50, studentId }, true)}`)]);
  return (
    <Shell route="t/fintransactions" me={me.ok ? me.data : null}>
      {data.ok ? <Transactions data={data.data} filters={filters} studentId={studentId} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
