import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Config } from "@/lib/pg-academic";
import { PgStages } from "./PgStages";

export const dynamic = "force-dynamic";

const TABS = ["stages", "students", "restarts", "reconcile", "quality", "setup"] as const;

/** t/pgstages — V651: postgraduate stages and cycles: the students of each stage, progression, extension, restart, reconciliation */
export default async function PgStagesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const tab = typeof p.tab === "string" && (TABS as readonly string[]).includes(p.tab) ? (p.tab as (typeof TABS)[number]) : "stages";
  const stage = typeof p.stage === "string" ? p.stage : "";
  const [me, config] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Config>("/api/v1/pg/academic/config")]);
  return (
    <Shell route="t/pgstages" me={me.ok ? me.data : null}>
      {config.ok ? <PgStages config={config.data} initialTab={tab} initialStage={stage} initialQ={typeof p.q === "string" ? p.q : ""} /> : <ProblemNotice problem={config.problem} />}
    </Shell>
  );
}
