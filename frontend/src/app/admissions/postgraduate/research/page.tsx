import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { PgResearch, type ResearchList } from "./PgResearch";

export const dynamic = "force-dynamic";

/** Research & thesis desk (V209): the School runs a candidate's research from supervision to award. */
export default async function PgResearchPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const stage = typeof p.stage === "string" ? p.stage : "";
  const [me, view] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ResearchList>(`/api/v1/pg/research${stage ? `?stage=${encodeURIComponent(stage)}` : ""}`),
  ]);
  return (
    <Shell route="t/pgresearch" me={me.ok ? me.data : null}>
      <PgResearch
        initialStage={stage}
        view={view.ok ? view.data : null}
        problem={view.ok ? null : view.problem}
        actingOffice={me.ok ? me.data.activeOffice : null}
      />
    </Shell>
  );
}
