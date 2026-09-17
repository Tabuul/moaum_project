import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { intakeSession } from "@/lib/sessions";
import { ReadinessView, type Readiness } from "./Readiness";

export const dynamic = "force-dynamic";

/** t/readiness — go-live readiness dashboard. */
export default async function ReadinessPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  const list = sessions.ok ? sessions.data : [];
  const session = typeof p.session === "string" ? p.session : intakeSession(list);
  const view = await api<Readiness>(`/api/v1/platform/readiness?session=${encodeURIComponent(session)}`);
  return (
    <Shell route="t/readiness" me={me.ok ? me.data : null}>
      {view.ok ? <ReadinessView data={view.data} sessions={list.map((s) => s.name)} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
