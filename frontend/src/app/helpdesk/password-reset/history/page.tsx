import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { AuditList } from "@/app/helpdesk/audit/SupportAudit";
import type { ResetsByAgent } from "@/lib/password-reset";
import { ResetHistory } from "./ResetHistory";

export const dynamic = "force-dynamic";

/** t/supportpwhistory — Password Reset History (V485): the support ledger's password resets and unlocks, within the reader's reach;
 *  for the Head, each agent's resets today and this week (V528) */
export default async function ResetHistoryPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const str = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const date = (k: string) => (/^\d{4}-\d{2}-\d{2}$/.test(str(k)) ? str(k) : "");
  const page = /^\d{1,4}$/.test(str("page")) ? Math.max(1, Number(str("page"))) : 1;
  const qs = new URLSearchParams({ module: "AUTHENTICATION", page: String(page), size: "50" });
  if (date("from")) qs.set("from", date("from"));
  if (date("to")) qs.set("to", date("to"));
  // V528: each agent's resets, for the Head and the Director of ICT (refused, and not shown, for an agent)
  const [me, list, byAgent] = await Promise.all([api<Me>("/api/v1/iam/me"), api<AuditList>(`/api/v1/helpdesk/support/actions?${qs.toString()}`),
    api<ResetsByAgent>("/api/v1/helpdesk/admin/password-resets/by-agent")]);
  return (
    <Shell route="t/supportpwhistory" me={me.ok ? me.data : null}>
      {list.ok ? <ResetHistory list={list.data} page={page} from={date("from")} to={date("to")} byAgent={byAgent.ok ? byAgent.data : null} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
