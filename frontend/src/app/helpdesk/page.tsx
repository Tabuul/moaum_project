import { Suspense } from "react";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { HEADS, type Agent, type Category, type Counts, type Queue, type TicketRow } from "@/lib/helpdesk";
import { Desk, type Faculty } from "./Desk";
import { DeskLater, DeskLaterFallback } from "./DeskLater";

export const dynamic = "force-dynamic";

/** t/helpdesk — the ICT support desk, ticket-first (October 2026): the queue, its search, filters and counts are read first and
 *  rendered at once; the operations and the figures stream in below through a Suspense boundary, so an analytics query
 *  that is slow — or fails — never delays or hides a ticket. Every list is paged, filtered and searched on the server. */
export default async function HelpdeskPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const qs = new URLSearchParams();
  for (const k of ["q", "category", "priority", "agent", "queue", "faculty", "department", "from", "to", "dir", "page", "size"]) if (s(k)) qs.set(k, s(k));
  // the desk's questions ride on their own parameters; the ticket's states on `status`
  const status = s("status") || "open";
  if (status === "escalated") { qs.set("status", "open"); qs.set("escalated", "true"); }
  else if (status === "overdue") { qs.set("status", "open"); qs.set("overdue", "true"); }
  else qs.set("status", status);
  qs.set("sort", s("sort") || "priority");
  const [me, queue, counts, categories, agents, queues, structure] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ rows: TicketRow[]; total: number; page: number; size: number }>(`/api/v1/helpdesk/tickets?${qs.toString()}`),
    api<Counts>("/api/v1/helpdesk/counts"),
    api<Category[]>("/api/v1/helpdesk/categories"),
    api<Agent[]>("/api/v1/helpdesk/agents"),
    api<Queue[]>("/api/v1/helpdesk/queues"),
    api<{ faculties: { code: string; name: string; departments: { code: string; name: string }[] }[] }>("/api/v1/ref/structure"),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  const head = HEADS.includes(office ?? "");
  const faculties: Faculty[] = structure.ok ? structure.data.faculties.map((f) => ({ code: f.code, name: f.name, departments: f.departments.map((d) => ({ code: d.code, name: d.name })) })) : [];
  return (
    <Shell route="t/helpdesk" me={me.ok ? me.data : null}>
      {!queue.ok ? <ProblemNotice problem={queue.problem} /> : (
        <Desk me={me.ok ? me.data.actorId : ""} head={head}
          queue={queue.data} counts={counts.ok ? counts.data : null} categories={categories.ok ? categories.data : []} agents={agents.ok ? agents.data : []}
          queues={queues.ok ? queues.data : []} faculties={faculties}
          filters={{ q: s("q"), status, category: s("category"), priority: s("priority"), agent: s("agent"), queue: s("queue"), faculty: s("faculty"), department: s("department"), from: s("from"), to: s("to"), sort: s("sort") || "priority", dir: s("dir") || "desc", size: s("size") || "20" }} />
      )}
      <Suspense fallback={<DeskLaterFallback />}>
        <DeskLater head={head} queues={queues.ok ? queues.data : []} />
      </Suspense>
    </Shell>
  );
}
