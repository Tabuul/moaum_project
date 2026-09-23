import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Overview, type OverviewData } from "./Overview";

export const dynamic = "force-dynamic";

/** t/overview — the session so far, in figures. */
export default async function OverviewPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const semester = typeof p.sem === "string" ? Number(p.sem) || 1 : 1;
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  const list = sessions.ok ? sessions.data : [];
  const session = typeof p.session === "string" ? p.session : (list.find((s) => s.state === "CURRENT")?.name ?? "2026/2027");
  const [data, due] = await Promise.all([
    api<OverviewData>(`/api/v1/reporting/overview?session=${encodeURIComponent(session)}&semester=${semester}`),
    api<{ overdue: number; dueSoon: number }>("/api/v1/reports/due"),
  ]);
  return (
    <Shell route="t/overview" me={me.ok ? me.data : null}>
      {data.ok ? <Overview d={data.data} semester={semester} session={session} sessions={list.map((s) => s.name)} due={due.ok ? due.data : null} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
