import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { loadStudent } from "./load";

export const dynamic = "force-dynamic";
import { Dashboard } from "./Screens1";
import { PgDashboard } from "./PgDashboard";

/** s/dashboard — the student's own record, as the register holds it. A postgraduate gets their own
 *  home (V202), not a continuation of the undergraduate one. */
export default async function Page() {
  const loaded = await loadStudent();
  return (
    <Shell route="s/dashboard" me={loaded.me}>
      {loaded.student
        ? (loaded.student.entryMode === "POSTGRADUATE" ? <PgDashboard s={loaded.student} /> : <Dashboard s={loaded.student} />)
        : <ProblemNotice problem={loaded.problem} />}
    </Shell>
  );
}
