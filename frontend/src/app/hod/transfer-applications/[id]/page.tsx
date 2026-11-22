import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { forDepartment, type OfficeDetail } from "@/lib/transfer-application";
import { TransferApplicationDetail } from "@/app/transfers/inter-university/applications/[id]/TransferApplicationDetail";

export const dynamic = "force-dynamic";

/** t/iuthodapp — V766: one transfer applicant on the department's desk: the particulars without the contact, the documents (one by one,
 *  or all as one PDF) and the recommendation. The API opens it only to the department of the programme applied for (or the College
 *  Dean, V734) once it has reached them. */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const ok = /^[0-9a-f-]{36}$/i.test(id);
  const [me, view] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    ok ? api<OfficeDetail>(`/api/v1/transfer-applications/office/applications/${id}`) : null,
  ]);
  return (
    <Shell route="t/iuthodapp" me={me.ok ? me.data : null} sub={view && view.ok ? `${view.data.applicationNo} · ${view.data.session}` : undefined}>
      {!view ? <ProblemNotice problem={{ status: 404, title: "No such application" }} />
        : view.ok ? <TransferApplicationDetail view={forDepartment(view.data)} desk="hod" office={me.ok ? me.data.activeOffice : null} back="/hod/transfer-applications" />
        : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
