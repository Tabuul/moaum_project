import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { intakeSession } from "@/lib/sessions";
import { TeachingView, type Teaching } from "./Teaching";

export const dynamic = "force-dynamic";

/** s/timetable — the lecturer's allocation and teaching timetable for a session. */
export default async function TeachingPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  const list = sessions.ok ? sessions.data : [];
  const current = list.find((s) => s.state === "CURRENT")?.name ?? intakeSession(list);
  const session = typeof p.session === "string" ? p.session : current;
  const view = await api<Teaching>(`/api/v1/me/teaching?session=${encodeURIComponent(session)}`);
  return (
    <Shell route="s/timetable" me={me.ok ? me.data : null}>
      {view.ok ? <TeachingView data={view.data} sessions={list.map((s) => s.name)} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
