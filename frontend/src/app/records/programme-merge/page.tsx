import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { MergeProgramme, MergeRecord, MergeSuggestion } from "@/lib/programme-merge";
import { ProgrammeMerge } from "./ProgrammeMerge";

export const dynamic = "force-dynamic";

/** t/programmemerge — V574: duplicate programmes merged into one, with their students: the merges proposed, their effect shown
 *  before they are made, the merges made and undone. */
export default async function ProgrammeMergePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const category = p.category === "UNDER GRADUATE" ? "UNDER GRADUATE" : "POST GRADUATE";
  const [me, s, h] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ category: string; suggestions: MergeSuggestion[]; programmes: MergeProgramme[] }>(`/api/v1/records/programme-merge/suggestions?category=${encodeURIComponent(category)}`),
    api<MergeRecord[]>("/api/v1/records/programme-merge/history"),
  ]);
  const history = h.ok ? h.data : [];
  // a merge made or undone brings new proposals: the screen starts again from them
  const key = `${category}|${history.length}|${history.filter((m) => m.undone_at).length}`;
  return (
    <Shell route="t/programmemerge" me={me.ok ? me.data : null}>
      {s.ok
        ? <ProgrammeMerge key={key} category={category} suggestions={s.data.suggestions} programmes={s.data.programmes} history={history}
            office={me.ok ? me.data.activeOffice : null} />
        : <ProblemNotice problem={s.problem} />}
    </Shell>
  );
}
