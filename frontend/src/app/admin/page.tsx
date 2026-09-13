import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Institution } from "./Institution";
import type { OverviewData } from "../overview/Overview";

export const dynamic = "force-dynamic";

/** r/admin — the whole institution, at one desk. Reuses the overview read model (RBI). */
export default async function AdminPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const semester = typeof p.sem === "string" ? Number(p.sem) || 1 : 1;
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  const list = sessions.ok ? sessions.data : [];
  const session = typeof p.session === "string" ? p.session : (list.find((s) => s.state === "CURRENT")?.name ?? "2026/2027");
  const data = await api<OverviewData>(`/api/v1/reporting/overview?session=${encodeURIComponent(session)}&semester=${semester}`);
  return (
    <Shell route="r/admin" me={me.ok ? me.data : null}>
      {data.ok ? <Institution d={data.data} semester={semester} session={session} sessions={list.map((s) => s.name)} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
