import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { RecordsCheck, type RecordsCheckData } from "./RecordsCheck";

export const dynamic = "force-dynamic";

/** t/recordcheck — V536: the Registry's records check, the live students whose record is inconsistent and who corrects each. */
export default async function RecordsCheckPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const q = new URLSearchParams();
  for (const k of ["issue", "faculty"] as const) {
    const v = p[k];
    if (typeof v === "string" && v.trim()) q.set(k, v.trim());
  }
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<RecordsCheckData>(`/api/v1/records/issues${q.toString() ? `?${q.toString()}` : ""}`),
  ]);
  return (
    <Shell route="t/recordcheck" me={me.ok ? me.data : null}>
      {data.ok ? <RecordsCheck d={data.data} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
