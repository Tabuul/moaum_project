import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { intakeSession, type SessionRow } from "@/lib/sessions";
import type { Overview } from "@/lib/putme";
import { Setup } from "./Setup";

export const dynamic = "force-dynamic";

/** t/putme-cbt › setup — the examination named, its centres, rooms and workstations, its days, slots and centres, the programmes it screens */
export default async function PutmeSetupPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, sessions] = await Promise.all([api<Me>("/api/v1/iam/me"), api<SessionRow[]>("/api/v1/ref/sessions")]);
  const list = sessions.ok ? sessions.data : [];
  const session = typeof p.session === "string" && /^\d{4}\/\d{4}$/.test(p.session) ? p.session : intakeSession(list);
  const view = await api<Overview>(`/api/v1/admissions/sessions/${session}/putme`);
  return (
    <Shell route="t/putme-cbt" me={me.ok ? me.data : null}>
      {view.ok ? <Setup view={view.data} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
