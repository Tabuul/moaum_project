import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { FeeReport as Report } from "@/lib/fee-report";
import { FeeReport } from "./FeeReport";

export const dynamic = "force-dynamic";

/** t/feereport — the school fees report: for a session, each faculty, department and level — students paid in full and owing, amount
 *  paid and owing — with the grand total, downloadable; the address names the session and scope, so it is the link to share */
export default async function FeeReportPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const qs = new URLSearchParams();
  if (s("session")) qs.set("session", s("session"));
  if (s("fac")) qs.set("fac", s("fac"));
  if (s("dept")) qs.set("dept", s("dept"));
  const [me, data, structure] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Report>(`/api/v1/finance/fee-report?${qs.toString()}`),
    api<{ faculty_code: string; faculty: string; dept_code: string; department: string }[]>("/api/v1/finance/fee-report/structure"),
  ]);
  return (
    <Shell route="t/feereport" me={me.ok ? me.data : null}>
      {data.ok ? <FeeReport data={data.data} structure={structure.ok ? structure.data : []} fac={s("fac")} dept={s("dept")}
        generatedBy={me.ok ? me.data.name ?? null : null} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
