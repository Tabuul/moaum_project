import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Faculty, Mismatch, Swap } from "@/lib/programme-swap";
import { ProgrammeSwap, type Summary } from "./ProgrammeSwap";

export const dynamic = "force-dynamic";

/** t/programmeswap — the programme swap desk (V578): the records whose placement looks wrong, the swaps prepared and decided, the report */
export default async function ProgrammeSwapPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const tab = s("tab") === "swaps" ? "swaps" : "desk";
  const scopeQs = new URLSearchParams();
  for (const k of ["fac", "dept"]) if (s(k)) scopeQs.set(k, s(k));
  const mm = new URLSearchParams(scopeQs);
  for (const k of ["prog", "class", "review", "q", "level", "status"]) if (s(k) && (k !== "status" || tab === "desk")) mm.set(k, s(k));
  if (s("page")) mm.set("page", s("page"));
  mm.set("size", "50");
  if (s("refresh") === "1") { mm.set("refresh", "true"); scopeQs.set("refresh", "true"); }
  const sw = new URLSearchParams(scopeQs);
  sw.delete("refresh");
  for (const k of ["status", "session", "from", "to", "level", "kind", "fromDate", "toDate", "q"]) if (s(k) && (k !== "status" || tab === "swaps")) sw.set(k, s(k));
  const [me, summary, structure, mismatches, swaps] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Summary>(`/api/v1/programme-swaps/summary?${scopeQs.toString()}`),
    api<{ faculties: Faculty[] }>("/api/v1/programme-swaps/structure"),
    tab === "desk" ? api<{ rows: Mismatch[]; total: number; page: number; size: number; asOf: string }>(`/api/v1/programme-swaps/mismatches?${mm.toString()}`) : Promise.resolve(null),
    tab === "swaps" ? api<Swap[]>(`/api/v1/programme-swaps?${sw.toString()}`) : Promise.resolve(null),
  ]);
  const filters: Record<string, string> = {};
  for (const k of ["fac", "dept", "prog", "class", "review", "q", "level", "status", "session", "from", "to", "kind", "fromDate", "toDate", "page"]) if (s(k)) filters[k] = s(k);
  return (
    <Shell route="t/programmeswap" me={me.ok ? me.data : null}>
      {summary.ok ? (
        <ProgrammeSwap tab={tab} summary={summary.data} faculties={structure.ok ? structure.data.faculties : []} filters={filters}
          mismatches={mismatches && mismatches.ok ? mismatches.data : null} swaps={swaps && swaps.ok ? swaps.data : null}
          problem={mismatches && !mismatches.ok ? mismatches.problem : swaps && !swaps.ok ? swaps.problem : null}
          actingOffice={me.ok ? me.data.activeOffice ?? null : null} generatedBy={me.ok ? me.data.name ?? null : null} />
      ) : <ProblemNotice problem={summary.problem} />}
    </Shell>
  );
}
