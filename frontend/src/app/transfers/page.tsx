import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Transfers, type TransferRow, type Programme } from "./Transfers";

export const dynamic = "force-dynamic";

/** t/transfers — the inter-departmental transfer queue: committee, Senate, register. */
export default async function TransfersPage() {
  const [me, list, progs] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ rows: TransferRow[] }>("/api/v1/transfers"),
    api<Programme[]>("/api/v1/transfers/programmes"),
  ]);
  return (
    <Shell route="t/transfers" me={me.ok ? me.data : null}>
      {list.ok ? (
        <Transfers
          rows={list.data.rows}
          programmes={progs.ok ? progs.data : []}
          actingOffice={me.ok ? me.data.activeOffice : null}
        />
      ) : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
