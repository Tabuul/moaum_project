import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { RegistrationView } from "@/lib/student-portal";
import type { MySiwes } from "@/lib/siwes";
import { Form } from "../Screens3";

/** s/form — the course form, once approved; V752: a Second Semester that is the student's SIWES registration prints as the SIWES
 *  course registration form */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/form" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const session = typeof q.session === "string" && /^\d{4}\/\d{4}$/.test(q.session) ? q.session : loaded.student.session;
  const semester = q.semester === "2" ? 2 : q.semester === "3" ? 3 : 1;
  const [v, siwes] = await Promise.all([
    api<RegistrationView>(`/api/v1/me/registration?session=${encodeURIComponent(session)}&semester=${semester}`),
    semester === 2 && loaded.student.entryMode !== "POSTGRADUATE" ? api<MySiwes>(`/api/v1/me/siwes?session=${encodeURIComponent(session)}`) : null,
  ]);
  return (
    <Shell route="s/form" me={loaded.me}>
      {v.ok ? <Form s={loaded.student} v={v.data} siwes={siwes && siwes.ok ? siwes.data : null} /> : <ProblemNotice problem={v.problem} />}
    </Shell>
  );
}
