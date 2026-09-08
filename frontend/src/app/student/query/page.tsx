import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { Queries } from "@/lib/student-portal";
import { Query } from "../Screens5";

/** s/query — one mark, one course, answered on the record */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/query" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const d = await api<Queries>("/api/v1/me/queries");
  return (
    <Shell route="s/query" me={loaded.me}>
      {d.ok ? <Query q={d.data} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
