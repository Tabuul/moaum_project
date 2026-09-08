import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "./load";

export const dynamic = "force-dynamic";
import { Dashboard } from "./Screens1";

/** s/dashboard — the student's own record, as the register holds it */
export default async function Page() {
  const loaded = await loadStudent();
  return (
    <Shell route="s/dashboard" me={loaded.me}>
      {loaded.student ? <Dashboard s={loaded.student} /> : <ProblemNotice problem={loaded.problem} />}
    </Shell>
  );
}
