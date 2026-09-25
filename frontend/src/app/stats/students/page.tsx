import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { readStatFilters, statQuery, type StatPage, type Which } from "@/lib/stats";
import { Detail } from "./Detail";

export const dynamic = "force-dynamic";

const WHICH = new Set(["ALL", "PAID", "REGISTERED", "PAID_NOT_REGISTERED", "NOT_PAID", "NO_CHARGE", "NOT_REGISTERED"]);

/** the students behind a figure: the same rows the statistics counted, paged, searched and exported */
export default async function StatStudentsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const filters = readStatFilters(p);
  const which = (typeof p.which === "string" && WHICH.has(p.which) ? p.which : "ALL") as Which;
  const q = typeof p.q === "string" ? p.q.slice(0, 80) : "";
  const page = typeof p.page === "string" && /^\d+$/.test(p.page) ? Number(p.page) : 0;
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<StatPage>(`/api/v1/stats/students?${statQuery(filters, { which, q, page, size: 50 })}`),
  ]);
  return (
    <Shell route="t/studentstats" me={me.ok ? me.data : null}>
      {data.ok ? <Detail data={data.data} filters={filters} which={which} q={q} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
