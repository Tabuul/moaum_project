import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Swap } from "@/lib/programme-swap";
import { PgProgrammeChanges } from "./PgProgrammeChanges";

export const dynamic = "force-dynamic";

/** /admissions/postgraduate/programme-changes — V721: the School's report of postgraduate students' programme changes (the swaps
 *  of postgraduate students alone, whichever office made them) */
export default async function PgProgrammeChangesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const s = (k: string) => (typeof sp[k] === "string" ? (sp[k] as string) : "");
  const q = new URLSearchParams({ postgraduate: "true" });
  for (const k of ["status", "session", "q", "fromDate", "toDate"]) if (s(k)) q.set(k, s(k));
  const [me, swaps] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Swap[]>(`/api/v1/programme-swaps?${q.toString()}`)]);
  return (
    <Shell route="t/pgprogrammechanges" me={me.ok ? me.data : null}>
      {swaps.ok ? <PgProgrammeChanges rows={swaps.data} filters={{ status: s("status"), session: s("session"), q: s("q"), fromDate: s("fromDate"), toDate: s("toDate") }}
        generatedBy={me.ok ? me.data.name ?? null : null} /> : <ProblemNotice problem={swaps.problem} />}
    </Shell>
  );
}
