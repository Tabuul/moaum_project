import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PutmeScores } from "@/components/cbt/PutmeScores";
import type { PutmeScoresPage } from "@/lib/putme-cbt";
import { putmeSession } from "@/app/ict/putme-scores/page";

export const dynamic = "force-dynamic";

/** t/putmefiles — the Academic Office's Post-UTME score files (V385): received, downloaded, previewed and imported into the screening scores */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const session = await putmeSession(q.session);
  const [me, page] = await Promise.all([api<Me>("/api/v1/iam/me"), api<PutmeScoresPage>(`/api/v1/admissions/sessions/${session}/putme-scores?size=1`)]);
  return (
    <Shell route="t/putmefiles" me={me.ok ? me.data : null}>
      {page.ok ? <PutmeScores page={page.data} mode="academic" acting={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={page.problem} />}
    </Shell>
  );
}
