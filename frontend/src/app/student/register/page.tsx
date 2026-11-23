import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { RegistrationView } from "@/lib/student-portal";
import type { MySiwes } from "@/lib/siwes";
import { Register } from "../Screens3";

/** s/register — the eligible set, the carryovers, the Bursary's gate */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/register" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const session = typeof q.session === "string" && /^\d{4}\/\d{4}$/.test(q.session) ? q.session : loaded.student.session;
  const semester = q.semester === "2" ? 2 : q.semester === "3" ? 3 : 1;
  // V752: a Second Semester the SIWES rule may bind reads the student's SIWES too — the page then sends them to the SIWES page.
  // V777: and every semester's form, where the student's menu carries SIWES: a SIWES course on the form is locked on the fee, and
  // the form names the fee and says whether it can be paid now (the SIWES window) — the one call, only for a student of SIWES
  const [v, siwes] = await Promise.all([
    api<RegistrationView>(`/api/v1/me/registration?session=${encodeURIComponent(session)}&semester=${semester}`),
    loaded.student.siwesArea ? api<MySiwes>(`/api/v1/me/siwes?session=${encodeURIComponent(session)}`) : null,
  ]);
  const semName = (n: number) => (n === 1 ? "First" : n === 2 ? "Second" : "Third") + " semester";
  // the subtitle names the student's real level and the semester being registered, not the static demo one
  const sub = v.ok ? `${v.data.level} Level · ${semName(v.data.semester)}` : undefined;
  return (
    <Shell route="s/register" me={loaded.me} sub={sub}>
      {/* V518: a fresh screen for each session and semester — switching semesters kept the first semester's choice, out of sight, and
          the save sent it with the second semester's */}
      {v.ok ? <Register key={`${v.data.session}|${v.data.semester}`} s={loaded.student} v={v.data} siwes={siwes && siwes.ok ? siwes.data : null} /> : <ProblemNotice problem={v.problem} />}
    </Shell>
  );
}
