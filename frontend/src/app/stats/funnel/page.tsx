import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { FunnelRows, type FunnelPage } from "./FunnelRows";

export const dynamic = "force-dynamic";

/** the applicants at a stage of the admission funnel, within the acting office's scope */
export default async function FunnelPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const one = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const q = new URLSearchParams();
  for (const k of ["session", "stage", "fac", "dept", "prog", "sex", "entry", "q"]) if (one(k)) q.set(k, one(k));
  const page = Math.max(0, Number(one("page")) || 0);
  q.set("page", String(page));
  q.set("size", "50");
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<FunnelPage>(`/api/v1/analytics/admissions/funnel/rows?${q.toString()}`)]);
  return (
    <Shell route="t/studentstats" me={me.ok ? me.data : null}>
      {data.ok ? <FunnelRows data={data.data} params={{ session: one("session"), stage: one("stage"), fac: one("fac"), dept: one("dept"), prog: one("prog"), sex: one("sex"), entry: one("entry"), q: one("q") }} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
