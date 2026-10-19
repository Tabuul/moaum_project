import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Operation } from "@/lib/bulk-reset";
import { BulkOperation } from "./BulkOperation";

export const dynamic = "force-dynamic";

/** one bulk password reset (V559): who made it, why, when, and each student's result — for the one who made it, the Head of the
 *  Support Desk, the Director of ICT and readers of the reset history */
export default async function BulkOperationPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [me, op] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Operation>(`/api/v1/helpdesk/support/password-reset/bulk/${encodeURIComponent(id)}`),
  ]);
  return (
    <Shell route="t/supportpwbulk" me={me.ok ? me.data : null}>
      {op.ok ? <BulkOperation op={op.data} /> : <ProblemNotice problem={op.problem} />}
    </Shell>
  );
}
