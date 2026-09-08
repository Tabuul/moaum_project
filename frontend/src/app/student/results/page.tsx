import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { Results } from "@/lib/student-portal";
import { ResultsScreen } from "../Screens4";

/** s/results — what the published sheets say, and only those */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/results" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const r = await api<Results>("/api/v1/me/results");
  return (
    <Shell route="s/results" me={loaded.me}>
      {r.ok ? <ResultsScreen r={r.data} /> : <ProblemNotice problem={r.problem} />}
    </Shell>
  );
}
