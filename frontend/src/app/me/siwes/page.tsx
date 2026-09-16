import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { MySiwes, type MySiwesStudent } from "./MySiwes";

export const dynamic = "force-dynamic";

/** r/mysiwes — the students assigned to the acting supervisor, to record each one's assessment. */
export default async function MySiwesPage() {
  const [me, mine] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<MySiwesStudent[]>("/api/v1/siwes/mine"),
  ]);
  return (
    <Shell route="r/mysiwes" me={me.ok ? me.data : null}>
      {!mine.ok ? <ProblemNotice problem={mine.problem} /> : <MySiwes students={mine.data} />}
    </Shell>
  );
}
