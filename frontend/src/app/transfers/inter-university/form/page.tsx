import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Structure } from "../../bulk/TransferBulk";
import type { University } from "../UniversityTransfer";
import { UniversityTransferForm } from "./UniversityTransferForm";

export const dynamic = "force-dynamic";

/** t/iutform — V763: the inter-university transfer form: one student, coming in or going out, found by the number first, checked
 *  under V588's rules and registered as a batch of one for another officer of the Academic Office or the Registry to decide. */
export default async function UniversityTransferFormPage() {
  const [me, structure, universities, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Structure>("/api/v1/programme-swaps/structure"),
    api<University[]>("/api/v1/transfers/inter-university/universities"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  return (
    <Shell route="t/iutform" me={me.ok ? me.data : null}>
      {universities.ok
        ? <UniversityTransferForm structure={structure.ok ? structure.data : { faculties: [] }} universities={universities.data}
            sessions={sessions.ok ? sessions.data : []} office={me.ok ? me.data.activeOffice : null} />
        : <ProblemNotice problem={universities.problem} />}
    </Shell>
  );
}
