import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { SupportList } from "@/lib/support";
import { StudentSearch, type Filters } from "./StudentSearch";

export const dynamic = "force-dynamic";

/** The support desk's student search (V334): students within the agent's reach, found by the server a page at a time. */
export default async function SupportStudentsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const filters: Filters = { q: s("q"), fac: s("fac"), dept: s("dept"), prog: s("prog"), level: s("level"), status: s("status"), session: s("session"), size: s("size") || "50" };
  const page = Math.max(1, Number(s("page") || "1") || 1);
  const qs = new URLSearchParams();
  for (const [k, v] of Object.entries(filters)) if (v) qs.set(k, v);
  qs.set("page", String(page));
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<SupportList>(`/api/v1/helpdesk/support/students?${qs.toString()}`)]);
  return (
    <Shell route="t/supportstudents" me={me.ok ? me.data : null}>
      {!list.ok ? <ProblemNotice problem={list.problem} /> : <StudentSearch list={list.data} filters={filters} page={page} generatedBy={me.ok ? me.data.name ?? null : null} />}
    </Shell>
  );
}
