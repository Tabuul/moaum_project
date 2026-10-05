import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Posting, Queue, RoutingRule, Workload } from "@/lib/helpdesk";
import { Agents } from "./Agents";

export const dynamic = "force-dynamic";

export interface AgentsData {
  postings: Posting[];
  candidates: { id: string; name: string; staff_number: string | null; email: string | null; offices: string; postings: number }[];
  queues: { code: string; name: string; active: boolean }[];
  workload: Workload[];
}
export interface QueuesData { queues: Queue[]; offices: { code: string; label: string }[] }
export interface RoutingData {
  rules: RoutingRule[]; categories: { code: string; name: string; active: boolean }[]; queues: { code: string; name: string; active: boolean }[]; unrouted: { code: string; name: string }[];
}
export interface Structure { colleges?: { code: string; name: string }[]; faculties: { code: string; name: string; collegeCode?: string | null; departments: { code: string; name: string; facultyCode: string }[] }[] }

/** t/helpdeskagents — the Head of ICT Support Desk's: who is posted on which queue within what scope, the queues and the office each
 *  answers to, and the routing rules that send each category of problem to its queue (V328) */
export default async function HelpdeskAgentsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const tab = typeof p.tab === "string" && ["agents", "queues", "routing"].includes(p.tab) ? p.tab : "agents";
  const [me, agents, queues, routing, structure] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<AgentsData>("/api/v1/helpdesk/admin/agents"),
    api<QueuesData>("/api/v1/helpdesk/admin/queues"),
    api<RoutingData>("/api/v1/helpdesk/admin/routing"),
    api<Structure>("/api/v1/ref/structure"),
  ]);
  return (
    <Shell route="t/helpdeskagents" me={me.ok ? me.data : null}>
      {!agents.ok ? <ProblemNotice problem={agents.problem} /> : !queues.ok ? <ProblemNotice problem={queues.problem} /> : !routing.ok ? <ProblemNotice problem={routing.problem} /> : (
        <Agents tab={tab} agents={agents.data} queues={queues.data} routing={routing.data} structure={structure.ok ? structure.data : { faculties: [] }} />
      )}
    </Shell>
  );
}
