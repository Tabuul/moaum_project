import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { ProgrammeChangeList } from "@/lib/programme-correction";
import { ProgrammeChanges } from "./ProgrammeChanges";

export const dynamic = "force-dynamic";

/** t/programmecodechanges — every correction of a programme's code (V716): the old and the new code, the programme, why, on which ticket,
 *  by whom and when, and its undoing; searchable by either code, the programme, the ticket or the remarks */
export default async function ProgrammeChangesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const q = typeof sp.q === "string" ? sp.q.slice(0, 120) : "";
  const page = typeof sp.page === "string" ? Math.max(1, Number(sp.page) || 1) : 1;
  const qs = new URLSearchParams();
  if (q) qs.set("q", q);
  qs.set("page", String(page));
  qs.set("size", "50");
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ProgrammeChangeList>(`/api/v1/catalogue/programme-code-changes?${qs.toString()}`)]);
  return (
    <Shell route="t/programmecodechanges" me={me.ok ? me.data : null}>
      {!list.ok ? <ProblemNotice problem={list.problem} /> : <ProgrammeChanges list={list.data} q={q} page={page} />}
    </Shell>
  );
}
