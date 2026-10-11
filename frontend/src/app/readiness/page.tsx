import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ReadinessView, type Readiness } from "./Readiness";

export const dynamic = "force-dynamic";

const SESSION = /^\d{4}\/\d{4}$/;

/** t/readiness — go-live readiness dashboard: the admission exercise of the intake session and the running session, each
 *  the API's default unless the address names one */
export default async function ReadinessPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const q = new URLSearchParams();
  if (typeof p.session === "string" && SESSION.test(p.session)) q.set("session", p.session);
  if (typeof p.intake === "string" && SESSION.test(p.intake)) q.set("intake", p.intake);
  const [me, sessions, view] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
    api<Readiness>(`/api/v1/platform/readiness${q.size ? `?${q}` : ""}`),
  ]);
  const list = sessions.ok ? sessions.data : [];
  return (
    <Shell route="t/readiness" me={me.ok ? me.data : null}>
      {view.ok ? <ReadinessView data={view.data} sessions={list.map((s) => s.name)} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
