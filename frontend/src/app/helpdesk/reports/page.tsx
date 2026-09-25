import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Agent, Category } from "@/lib/helpdesk";
import type { Stats } from "../Desk";
import { Reports } from "./Reports";

export const dynamic = "force-dynamic";

/** t/helpdeskreports — the Director's figures: by date, category, status, faculty, department, requester, agent; response and resolution times */
export default async function HelpdeskReportsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const qs = new URLSearchParams();
  for (const k of ["from", "to", "category", "priority", "agent", "faculty", "department"]) if (s(k)) qs.set(k, s(k));
  const [me, stats, categories, agents, structure] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Stats>(`/api/v1/helpdesk/stats?${qs.toString()}`),
    api<Category[]>("/api/v1/helpdesk/categories"),
    api<Agent[]>("/api/v1/helpdesk/agents"),
    api<{ faculties: { code: string; name: string; departments: { code: string; name: string; facultyCode: string }[] }[] }>("/api/v1/ref/structure"),
  ]);
  const faculties = structure.ok ? structure.data.faculties.map((f) => ({ code: f.code, name: f.name })) : [];
  const departments = structure.ok ? structure.data.faculties.flatMap((f) => f.departments.map((d) => ({ code: d.code, name: d.name, faculty_code: f.code }))) : [];
  return (
    <Shell route="t/helpdeskreports" me={me.ok ? me.data : null}>
      {!stats.ok ? <ProblemNotice problem={stats.problem} /> : (
        <Reports stats={stats.data} categories={categories.ok ? categories.data : []} agents={agents.ok ? agents.data : []}
          faculties={faculties} departments={departments}
          filters={{ from: s("from"), to: s("to"), category: s("category"), priority: s("priority"), agent: s("agent"), faculty: s("faculty"), department: s("department") }} />
      )}
    </Shell>
  );
}
