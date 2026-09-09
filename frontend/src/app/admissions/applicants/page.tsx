import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Applicants, type ApplicantsView } from "./Applicants";

export const dynamic = "force-dynamic";

/** the applicants on committed admission lists — the admitted pool for post-UTME registration. */
export default async function ApplicantsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const q = typeof p.q === "string" ? p.q : "";
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  const session = typeof p.session === "string" ? p.session : (sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name : null) ?? "2026/2027";
  const view = await api<ApplicantsView>(`/api/v1/admissions/applicants?session=${encodeURIComponent(session)}${q ? `&q=${encodeURIComponent(q)}` : ""}`);
  return (
    <Shell route="t/admissions" me={me.ok ? me.data : null}>
      {view.ok ? <Applicants d={view.data} session={session} q={q} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
