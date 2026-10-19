import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Reach, type ReachFilters, type ReachList } from "./Reach";

export const dynamic = "force-dynamic";

/** t/supportreach — Students we cannot reach (V565): the current students within the reader's reach with no e-mail, no phone or
 *  neither on record, by faculty and a page of them, to put right at the desk or send to the departments */
export default async function ReachPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const str = (k: string) => (typeof p[k] === "string" ? (p[k] as string).trim() : "");
  const f: ReachFilters = {
    kind: ["NEITHER", "NO_EMAIL", "NO_PHONE"].includes(str("kind")) ? str("kind") : "NEITHER",
    fac: /^[A-Z]{1,10}$/.test(str("fac")) ? str("fac") : "", level: /^\d{3}$/.test(str("level")) ? str("level") : "", q: str("q").slice(0, 80),
    page: /^\d{1,4}$/.test(str("page")) ? Math.max(1, Number(str("page"))) : 1,
  };
  const qs = new URLSearchParams({ kind: f.kind, page: String(f.page), size: "50" });
  for (const k of ["fac", "level", "q"] as const) if (f[k]) qs.set(k, f[k]);
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ReachList>(`/api/v1/helpdesk/support/reach?${qs.toString()}`)]);
  return (
    <Shell route="t/supportreach" me={me.ok ? me.data : null}>
      {list.ok ? <Reach f={f} list={list.data} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
