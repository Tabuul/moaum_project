import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { RequestFull } from "@/lib/documents";
import { RequestScreen } from "./Request";

export const dynamic = "force-dynamic";

/** t/documents › request — one request: the student, the validation, the generated document reviewed field by field, the quality check, the release, the deliveries, the trail */
export default async function DocumentRequestPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [me, view] = await Promise.all([api<Me>("/api/v1/iam/me"), api<RequestFull>(`/api/v1/documents/requests/${id}`)]);
  return (
    <Shell route="t/documents" me={me.ok ? me.data : null}>
      {view.ok ? <RequestScreen r={view.data} office={me.ok ? me.data.activeOffice ?? null : null} actor={me.ok ? me.data.actorId : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
