import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Note } from "@/components/proto/ui";
import { api } from "@/lib/api";
import { loadStudent } from "../load";
import type { PgSummary } from "../pg-common";
import type { OutstandingFees } from "@/lib/outstanding-fees";
import { Progress } from "./Progress";

export const dynamic = "force-dynamic";

/** s/pgprogress — the postgraduate student's academic progress and graduation eligibility, read from the record */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/pgprogress" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  if (loaded.student.entryMode !== "POSTGRADUATE") {
    return <Shell route="s/pgprogress" me={loaded.me}><Note kind="info" title="Postgraduate progress">This page is for postgraduate students.</Note></Shell>;
  }
  // V723: the fees requirement is graded across every session of the record, as the dashboard grades it
  const [pg, outstanding] = await Promise.all([api<PgSummary>("/api/v1/pg/coursework/summary"), api<OutstandingFees>("/api/v1/me/outstanding-fees")]);
  return (
    <Shell route="s/pgprogress" me={loaded.me}>
      {pg.ok ? <Progress s={loaded.student} pg={pg.data} outstanding={outstanding.ok ? outstanding.data : null} /> : <ProblemNotice problem={pg.problem} />}
    </Shell>
  );
}
