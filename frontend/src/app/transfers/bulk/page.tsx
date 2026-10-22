import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { TransferBulk, type Batch, type Structure } from "./TransferBulk";

export const dynamic = "force-dynamic";

/** t/transferbulk — V587: bulk inter-departmental transfer — a department's students in a template, the filled file checked row by
 *  row against each student's current record and the target, previewed, and made as a batch of programme swaps (IDT/…) that move
 *  the students at once (V633). */
export default async function TransferBulkPage() {
  const [me, structure, batches] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Structure>("/api/v1/programme-swaps/structure"),
    api<Batch[]>("/api/v1/transfers/bulk"),
  ]);
  return (
    <Shell route="t/transferbulk" me={me.ok ? me.data : null}>
      {batches.ok
        ? <TransferBulk structure={structure.ok ? structure.data : { faculties: [] }} batches={batches.data} office={me.ok ? me.data.activeOffice : null}
            me={me.ok ? me.data.actorId : null} />
        : <ProblemNotice problem={batches.problem} />}
    </Shell>
  );
}
