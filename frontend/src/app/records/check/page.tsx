import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { RecordsCheck, type RecordsCheckData } from "./RecordsCheck";
import type { TellProgress } from "./RecordsActions";

export const dynamic = "force-dynamic";

/** t/recordcheck — V536: the Registry's records check, the live students whose record is inconsistent and who corrects each. */
export default async function RecordsCheckPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const q = new URLSearchParams();
  for (const k of ["issue", "faculty"] as const) {
    const v = p[k];
    if (typeof v === "string" && v.trim()) q.set(k, v.trim());
  }
  // V548: where the students with no state of origin stand, when that issue is shown
  const [me, data, progress] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<RecordsCheckData>(`/api/v1/records/issues${q.toString() ? `?${q.toString()}` : ""}`),
    q.get("issue")?.toUpperCase() === "NO_STATE_OF_ORIGIN" ? api<TellProgress>(`/api/v1/records/issues/notices?issue=NO_STATE_OF_ORIGIN${q.get("faculty") ? `&faculty=${encodeURIComponent(q.get("faculty") ?? "")}` : ""}`) : Promise.resolve(null),
  ]);
  return (
    <Shell route="t/recordcheck" me={me.ok ? me.data : null}>
      {data.ok ? <RecordsCheck d={data.data} office={me.ok ? me.data.activeOffice : null} progress={progress?.ok ? progress.data : null} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
