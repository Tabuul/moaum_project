import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Batch, Figures } from "@/lib/fee-history-recon";
import { FeeHistoryRecon } from "./FeeHistoryRecon";

export const dynamic = "force-dynamic";

/** /finance/fee-history-reconciliation — V647: old-portal school-fees payments named by a JAMB number, held and reconciled */
export default async function FeeHistoryReconPage() {
  const [me, figures, batches] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Figures>("/api/v1/finance/fee-history-reconciliation/figures"),
    api<Batch[]>("/api/v1/finance/fee-history-reconciliation/batches"),
  ]);
  return (
    <Shell route="t/feehistoryrecon" me={me.ok ? me.data : null}>
      {figures.ok ? (
        <FeeHistoryRecon figures={figures.data} batches={batches.ok ? batches.data : []} office={me.ok ? me.data.activeOffice ?? null : null} me={me.ok ? me.data.actorId ?? null : null} />
      ) : <ProblemNotice problem={figures.problem} />}
    </Shell>
  );
}
