import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ExportLog, type ExportLogView } from "./ExportLog";

export const dynamic = "force-dynamic";

const KEYS = ["from", "to", "office", "format", "q", "unusual", "page"] as const;

/** t/exportlog — V523: who exported which report, for Internal Audit. */
export default async function ExportLogPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const filters: Record<string, string> = {};
  for (const k of KEYS) {
    const v = p[k];
    if (typeof v === "string" && v.trim()) filters[k] = v.trim();
  }
  const q = new URLSearchParams(filters);
  const [me, view] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ExportLogView>(`/api/v1/exports${q.toString() ? `?${q.toString()}` : ""}`),
  ]);
  return (
    <Shell route="t/exportlog" me={me.ok ? me.data : null}>
      {view.ok ? <ExportLog d={view.data} filters={filters} maySet={me.ok && ["audit", "super"].includes(me.data.activeOffice ?? "")} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
