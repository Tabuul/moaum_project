import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { EditPage } from "@/lib/pg-records";
import { PgApplicantEdit } from "./PgApplicantEdit";

export const dynamic = "force-dynamic";

/** /admissions/postgraduate/applications/[id]/edit — V715: the postgraduate applicant's record, read whole and corrected; ?section= opens a section */
export default async function PgApplicantEditPage({ params, searchParams }: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { id } = await params;
  const sp = await searchParams;
  const [me, page] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<EditPage>(`/api/v1/pg/records/applications/${encodeURIComponent(id)}/edit`),
  ]);
  return (
    <Shell route="t/pgrecords" me={me.ok ? me.data : null}>
      {page.ok ? <PgApplicantEdit page={page.data} initialSection={typeof sp.section === "string" ? sp.section : null} /> : <ProblemNotice problem={page.problem} />}
    </Shell>
  );
}
