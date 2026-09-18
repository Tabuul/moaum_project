import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { RegistrationView } from "@/lib/student-portal";
import { Register } from "../Screens3";

/** s/register — the eligible set, the carryovers, the Bursary's gate */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/register" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const session = typeof q.session === "string" && /^\d{4}\/\d{4}$/.test(q.session) ? q.session : loaded.student.session;
  const semester = q.semester === "2" ? 2 : q.semester === "3" ? 3 : 1;
  const v = await api<RegistrationView>(`/api/v1/me/registration?session=${encodeURIComponent(session)}&semester=${semester}`);
  const semName = (n: number) => (n === 1 ? "First" : n === 2 ? "Second" : "Third") + " semester";
  // the subtitle names the student's real level and the semester being registered, not the static demo one
  const sub = v.ok ? `${v.data.level} Level · ${semName(v.data.semester)}` : undefined;
  return (
    <Shell route="s/register" me={loaded.me} sub={sub}>
      {v.ok ? <Register s={loaded.student} v={v.data} /> : <ProblemNotice problem={v.problem} />}
    </Shell>
  );
}
