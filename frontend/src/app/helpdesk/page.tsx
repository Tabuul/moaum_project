import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Activity, Agent, Category, TicketRow } from "@/lib/helpdesk";
import { Desk, type Stats } from "./Desk";

export const dynamic = "force-dynamic";

/** t/helpdesk — the ICT support desk: the figures, and the queue searched, filtered, sorted and paged on the server */
export default async function HelpdeskPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const qs = new URLSearchParams();
  for (const k of ["q", "status", "category", "priority", "agent", "from", "to", "sort", "dir", "page", "size"]) if (s(k)) qs.set(k, s(k));
  if (!s("status")) qs.set("status", "open");
  const [me, queue, stats, categories, agents, mine, activity] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ rows: TicketRow[]; total: number; page: number; size: number }>(`/api/v1/helpdesk/tickets?${qs.toString()}`),
    api<Stats>("/api/v1/helpdesk/stats"),
    api<Category[]>("/api/v1/helpdesk/categories"),
    api<Agent[]>("/api/v1/helpdesk/agents"),
    api<{ rows: TicketRow[]; total: number }>("/api/v1/helpdesk/tickets?agent=me&status=open&sort=due&dir=asc&size=5"),
    api<Activity[]>("/api/v1/helpdesk/activity?limit=20"),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/helpdesk" me={me.ok ? me.data : null}>
      {!queue.ok ? <ProblemNotice problem={queue.problem} /> : (
        <Desk me={me.ok ? me.data.actorId : ""} director={office === "ict" || office === "admin" || office === "super"}
          queue={queue.data} stats={stats.ok ? stats.data : null} categories={categories.ok ? categories.data : []} agents={agents.ok ? agents.data : []}
          mine={mine.ok ? mine.data : { rows: [], total: 0 }} activity={activity.ok ? activity.data : []}
          filters={{ q: s("q"), status: s("status") || "open", category: s("category"), priority: s("priority"), agent: s("agent"), from: s("from"), to: s("to"), sort: s("sort") || "updated", dir: s("dir") || "desc", size: s("size") || "20" }} />
      )}
    </Shell>
  );
}
