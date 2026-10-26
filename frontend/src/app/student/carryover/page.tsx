import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { Results } from "@/lib/student-portal";
import type { CarryHistory } from "@/lib/carry-over";
import { Carryover } from "../Screens5";

/** s/carryover — what must be repeated */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/carryover" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  // V666: the attempts behind each carry-over, and the courses cleared since
  const [d, h] = await Promise.all([api<Results>("/api/v1/me/results"), api<CarryHistory>("/api/v1/me/carryovers/history")]);
  return (
    <Shell route="s/carryover" me={loaded.me}>
      {d.ok ? <Carryover r={d.data} history={h.ok ? h.data : null} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
