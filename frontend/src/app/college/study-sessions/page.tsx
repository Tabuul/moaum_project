import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { StudySessions, type StudySessionsView } from "./StudySessions";

export const dynamic = "force-dynamic";

/** t/studysessions — V733: the MBBS students standing in a session of their own, every change, and an office's setting of one */
export default async function StudySessionsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const search = typeof sp.q === "string" ? sp.q : "";
  const [me, view] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<StudySessionsView>(`/api/v1/study-sessions${search ? `?search=${encodeURIComponent(search)}` : ""}`),
  ]);
  return (
    <Shell route="t/studysessions" me={me.ok ? me.data : null}>
      {view.ok ? <StudySessions view={view.data} search={search} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
