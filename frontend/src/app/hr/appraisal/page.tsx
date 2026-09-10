import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Appraisal, type PromotionRow } from "./Appraisal";

export const dynamic = "force-dynamic";

/** t/appraisal — appraisal and promotion eligibility. */
export default async function AppraisalPage() {
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ cycle: string; rows: PromotionRow[] }>("/api/v1/hr/appraisal")]);
  return (
    <Shell route="t/appraisal" me={me.ok ? me.data : null}>
      {data.ok ? <Appraisal cycle={data.data.cycle} rows={data.data.rows} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
