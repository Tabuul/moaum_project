import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { SittingReport, type ReportView } from "@/components/cbt/SittingReport";

export const dynamic = "force-dynamic";

/** t/invigilate — a sitting's report (V375): filed by its chief invigilator, read by the office, added to by the office */
export default async function Page({ params }: { params: Promise<{ sitting: string }> }) {
  const { sitting } = await params;
  const [me, view] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ReportView>(`/api/v1/cbt/sittings/${encodeURIComponent(sitting)}/report`)]);
  return (
    <Shell route="t/invigilate" me={me.ok ? me.data : null}>
      {view.ok ? <SittingReport initial={view.data} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
