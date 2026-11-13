import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../../../load";

export const dynamic = "force-dynamic";
import { isSummer, semesterText } from "@/lib/student-portal";
import type { Results } from "@/lib/student-portal";
import { Slip } from "../../../Screens4";

/** s/slip — one semester's statement of results */
export default async function Page({ params }: { params: Promise<{ session: string; semester: string }> }) {
  const p = await params;
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/slip" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const r = await api<Results>("/api/v1/me/results");
  // V754, V756: semester 3 of the student's Summer session is the Summer semester
  const summer = r.ok && isSummer(r.data.summerSessions, decodeURIComponent(p.session), Number(p.semester));
  return (
    <Shell route="s/slip" me={loaded.me} sub={`${decodeURIComponent(p.session)} · ${semesterText(Number(p.semester), summer)}`}>
      {r.ok ? <Slip r={r.data} session={decodeURIComponent(p.session)} semester={Number(p.semester)} /> : <ProblemNotice problem={r.problem} />}
    </Shell>
  );
}
