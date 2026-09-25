import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Review, type ReviewData } from "./Review";

export const dynamic = "force-dynamic";

/** the examiner's project: the candidate and the work, the documents released, and the assessment form */
export default async function ReviewPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [me, r] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ReviewData>(`/api/v1/examiners/me/projects/${encodeURIComponent(id)}`, { reason: "project opened by the examiner" })]);
  return (
    <Shell route="x/projects" me={me.ok ? me.data : null}>
      {r.ok ? <Review d={r.data} /> : <ProblemNotice problem={r.problem} />}
    </Shell>
  );
}
