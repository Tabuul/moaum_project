import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { BulkHistory } from "../BulkReset";
import { BulkHistoryList, type HistoryFilters } from "./BulkHistoryList";

export const dynamic = "force-dynamic";

/** the bulk password resets (V559), newest first — the agent's own, or every one for the Head of the Support Desk, the Director of
 *  ICT and readers of the reset history — by date, status, reference, the officer or a ticket number */
export default async function BulkHistoryPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const str = (k: string) => (typeof p[k] === "string" ? (p[k] as string).trim() : "");
  const date = (k: string) => (/^\d{4}-\d{2}-\d{2}$/.test(str(k)) ? str(k) : "");
  const f: HistoryFilters = {
    from: date("from"), to: date("to"), status: /^[A-Z_]{1,30}$/.test(str("status")) ? str("status") : "", q: str("q").slice(0, 80),
    page: /^\d{1,4}$/.test(str("page")) ? Math.max(1, Number(str("page"))) : 1,
  };
  const qs = new URLSearchParams({ page: String(f.page), size: "50" });
  for (const k of ["from", "to", "status", "q"] as const) if (f[k]) qs.set(k, f[k]);
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<BulkHistory>(`/api/v1/helpdesk/support/password-reset/bulk?${qs.toString()}`)]);
  return (
    <Shell route="t/supportpwbulk" me={me.ok ? me.data : null}>
      {list.ok ? <BulkHistoryList f={f} list={list.data} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
