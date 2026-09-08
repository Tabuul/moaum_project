import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../../../load";

export const dynamic = "force-dynamic";
import type { Results } from "@/lib/student-portal";
import { Slip } from "../../../Screens4";

/** s/slip — one semester's statement of results */
export default async function Page({ params }: { params: Promise<{ session: string; semester: string }> }) {
  const p = await params;
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/slip" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const r = await api<Results>("/api/v1/me/results");
  return (
    <Shell route="s/slip" me={loaded.me}>
      {r.ok ? <Slip r={r.data} session={decodeURIComponent(p.session)} semester={Number(p.semester)} /> : <ProblemNotice problem={r.problem} />}
    </Shell>
  );
}
