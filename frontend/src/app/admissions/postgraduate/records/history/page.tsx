import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { RecentRow } from "@/lib/pg-records";
import { PgChangeHistory } from "./PgChangeHistory";

export const dynamic = "force-dynamic";

/** /admissions/postgraduate/records/history — V715: the latest corrections of postgraduate applicant and student records */
export default async function PgChangeHistoryPage() {
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ rows: RecentRow[]; limit: number }>("/api/v1/pg/records/history?limit=300"),
  ]);
  return (
    <Shell route="t/pgedithistory" me={me.ok ? me.data : null}>
      {data.ok ? <PgChangeHistory rows={data.data.rows} limit={data.data.limit} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
