import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { OfficeDetail } from "@/lib/transfer-application";
import { TransferApplicationDetail, type University } from "./TransferApplicationDetail";

export const dynamic = "force-dynamic";

/** t/iutapp — V766: one online inter-university transfer application on the Registry's desk (the Academic Office, the Registrar, the
 *  Deputy Registrar; Records reads it): with V763's own check of the transfer it would register, from submission until it is decided */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const ok = /^[0-9a-f-]{36}$/i.test(id);
  const [me, view, universities] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    ok ? api<OfficeDetail>(`/api/v1/transfer-applications/office/applications/${id}`) : null,
    api<University[]>("/api/v1/transfers/inter-university/universities"),
  ]);
  return (
    <Shell route="t/iutapp" me={me.ok ? me.data : null} sub={view && view.ok ? `${view.data.applicationNo} · ${view.data.session}` : undefined}>
      {!view ? <ProblemNotice problem={{ status: 404, title: "No such application" }} />
        : view.ok ? <TransferApplicationDetail view={view.data} desk="registry" office={me.ok ? me.data.activeOffice : null}
            universities={universities.ok ? universities.data : []} back={`/transfers/inter-university/applications?session=${encodeURIComponent(view.data.session)}`} />
        : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
