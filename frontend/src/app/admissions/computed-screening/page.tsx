import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { intakeSession } from "@/lib/sessions";
import { ComputedPostUtme, type Computed } from "./ComputedPostUtme";

export const dynamic = "force-dynamic";

/** t/postutme — the Academic Office's computed Post-UTME for candidates who did not sit it (V090). */
export default async function ComputedScreeningPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  const list = sessions.ok ? sessions.data : [];
  const session = typeof p.session === "string" ? p.session : intakeSession(list);
  // session-scoped route: two raw path segments {session}/{year} (the session carries the slash)
  const view = await api<Computed[]>(`/api/v1/admissions/sessions/${session}/post-utme-computed`);
  return (
    <Shell route="t/postutme" me={me.ok ? me.data : null}>
      {view.ok ? (
        <ComputedPostUtme rows={view.data} session={session} sessions={list.map((s) => s.name)} />
      ) : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
