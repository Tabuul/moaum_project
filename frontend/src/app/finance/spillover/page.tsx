import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { SpilloverStudents, type SpilloverList } from "./SpilloverStudents";

export const dynamic = "force-dynamic";

/** t/spillover — the Bursary's spillover students (V637): every student in study charged the spillover lines for a session (SP1/SP2 at the
 *  final level, or above it), the semesters a course is registered in, the carry-overs, due, paid, owing; the address is the link to share */
export default async function SpilloverPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const filters: Record<string, string> = {};
  for (const k of ["session", "fac", "dept", "year", "state", "q"]) if (s(k)) filters[k] = s(k);
  const qs = new URLSearchParams(filters);
  const [me, data, structure] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SpilloverList>(`/api/v1/finance/spillover?${qs.toString()}`),
    api<{ faculty_code: string; faculty: string; dept_code: string; department: string }[]>("/api/v1/finance/fee-report/structure"),
  ]);
  return (
    <Shell route="t/spillover" me={me.ok ? me.data : null}>
      {data.ok ? <SpilloverStudents data={data.data} structure={structure.ok ? structure.data : []} filters={filters} generatedBy={me.ok ? me.data.name ?? null : null} />
        : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
