import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";
import { MyExams } from "@/components/cbt/MyExams";
import type { MyExams as Data } from "@/lib/cbt";

export const dynamic = "force-dynamic";

/** s/cbt — the student's GST and EPS CBT examinations (V322) */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/cbt" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const session = typeof q.session === "string" && /^\d{4}\/\d{4}$/.test(q.session) ? q.session : loaded.student.session;
  const data = await api<Data>(`/api/v1/me/cbt?session=${encodeURIComponent(session)}`);
  return (
    <Shell route="s/cbt" me={loaded.me} sub={`${session} session`}>
      {data.ok ? <MyExams data={data.data} s={loaded.student} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
