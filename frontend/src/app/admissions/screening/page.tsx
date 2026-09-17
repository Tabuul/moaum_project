import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { intakeSession, type SessionRow } from "@/lib/sessions";
import { ScreeningRegister, type RegisterRow } from "./ScreeningRegister";

export const dynamic = "force-dynamic";

/** t/screening — the whole screening register for a session: everyone, the mark and its source (V159). */
export default async function ScreeningRegisterPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SessionRow[]>("/api/v1/ref/sessions"),
  ]);
  const list = sessions.ok ? sessions.data : [];
  const session = typeof p.session === "string" ? p.session : intakeSession(list);
  // session-scoped route: two raw path segments {session}/{year} (the session carries the slash)
  const view = await api<RegisterRow[]>(`/api/v1/admissions/sessions/${session}/screening-register`);
  return (
    <Shell route="t/screening" me={me.ok ? me.data : null}>
      {view.ok ? (
        <ScreeningRegister rows={view.data} session={session} sessions={list.map((s) => s.name)} />
      ) : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
