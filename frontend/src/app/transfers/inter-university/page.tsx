import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Structure } from "../bulk/TransferBulk";
import { UniversityTransfer, type Batch, type University } from "./UniversityTransfer";

export const dynamic = "force-dynamic";

/** t/iut — V588: inter-university transfer — students coming from another university and students leaving for one, from a
 *  spreadsheet: each row checked (the student found first, so no one is placed twice), previewed, prepared as a batch (IUT/…) for
 *  another officer to decide; the list of universities kept here. */
export default async function UniversityTransferPage() {
  const [me, structure, batches, universities] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Structure>("/api/v1/programme-swaps/structure"),
    api<Batch[]>("/api/v1/transfers/inter-university"),
    api<University[]>("/api/v1/transfers/inter-university/universities"),
  ]);
  return (
    <Shell route="t/iut" me={me.ok ? me.data : null}>
      {batches.ok
        ? <UniversityTransfer structure={structure.ok ? structure.data : { faculties: [] }} batches={batches.data} universities={universities.ok ? universities.data : []}
            office={me.ok ? me.data.activeOffice : null} me={me.ok ? me.data.actorId : null} />
        : <ProblemNotice problem={batches.problem} />}
    </Shell>
  );
}
