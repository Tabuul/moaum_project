import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { DefermentFull } from "@/lib/deferments";
import { Review } from "./Review";

export const dynamic = "force-dynamic";

/** one deferment request on the desk: the student, the request, the documents, the record behind it, the desk's act */
export default async function DefermentPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [me, d] = await Promise.all([api<Me>("/api/v1/iam/me"), api<DefermentFull>(`/api/v1/deferments/${id}`)]);
  return (
    <Shell route="t/deferments" me={me.ok ? me.data : null}>
      {d.ok ? <Review d={d.data} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
