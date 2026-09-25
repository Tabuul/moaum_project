import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { DocumentRow, Policy } from "@/lib/documents";
import { Office } from "./Office";

export const dynamic = "force-dynamic";

export interface OfficeData { dashboard: string; policies: Policy[]; flagged: DocumentRow[]; suspected: { code: string; attempts: number; first_seen: string; last_seen: string }[]; awaitingCertificate: { student_id: string; student_name: string; student_number: string; session: string; award: string; cgpa: number; class_of_degree: string; cleared: boolean; programme: string | null }[] }

/** t/documents — the documents office (V262): the figures, what waits, graduates awaiting a certificate, flagged and suspected documents, revenue and processing */
export default async function DocumentsOfficePage() {
  const [me, view] = await Promise.all([api<Me>("/api/v1/iam/me"), api<OfficeData>("/api/v1/documents/dashboard")]);
  return (
    <Shell route="t/documents" me={me.ok ? me.data : null}>
      {view.ok ? <Office data={view.data} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
