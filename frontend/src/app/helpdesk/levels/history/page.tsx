import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LevelHistory, type LevelHistoryList } from "./LevelHistory";
import { SUPPORT_DESK_OFFICES } from "@/lib/level-management";

export const dynamic = "force-dynamic";

/** t/supportlevelhistory — Level Change History (V500): every change of a student's level within the reader's reach; V591: the
 *  Students Account Officer reads it too, every student */
export default async function LevelHistoryPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const str = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const date = (k: string) => (/^\d{4}-\d{2}-\d{2}$/.test(str(k)) ? str(k) : "");
  const action = /^(SUPPORT|OTHER|LEVEL_PROGRESS|LEVEL_CORRECTION)$/.test(str("action")) ? str("action") : "";
  const filters = { action, q: str("q").slice(0, 80), from: date("from"), to: date("to") };
  const page = /^\d{1,4}$/.test(str("page")) ? Math.max(1, Number(str("page"))) : 1;
  const qs = new URLSearchParams({ page: String(page), size: "50" });
  for (const [k, v] of Object.entries(filters)) if (v) qs.set(k, v);
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<LevelHistoryList>(`/api/v1/helpdesk/support/levels/history?${qs.toString()}`)]);
  const desk = SUPPORT_DESK_OFFICES.includes(me.ok ? me.data.activeOffice ?? "" : "");
  return (
    <Shell route="t/supportlevelhistory" me={me.ok ? me.data : null}>
      {list.ok ? <LevelHistory list={list.data} page={page} filters={filters} desk={desk} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
