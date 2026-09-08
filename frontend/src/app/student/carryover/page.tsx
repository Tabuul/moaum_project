import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { Results } from "@/lib/student-portal";
import { Carryover } from "../Screens5";

/** s/carryover — what must be repeated */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/carryover" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const d = await api<Results>("/api/v1/me/results");
  return (
    <Shell route="s/carryover" me={loaded.me}>
      {d.ok ? <Carryover r={d.data} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
