import { intakeSession } from "@/lib/sessions";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Screened, type ScreenedRow } from "./Screened";

export const dynamic = "force-dynamic";

/** The screened pool, from the Screened tile: an overview by faculty and course, and a per-course
 *  drill-in showing every admission criterion, exportable to Excel and PDF. */
export default async function ScreenedPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  const session = typeof p.session === "string" ? p.session : intakeSession(sessions.ok ? sessions.data : []);
  // session is YYYY/YYYY — two raw path segments, no encodeURIComponent
  const summary = await api<ScreenedRow[]>(`/api/v1/admissions/sessions/${session}/screened-summary`);

  return (
    <Shell route="t/admissions" me={me.ok ? me.data : null}>
      {summary.ok
        ? <Screened session={session} summary={summary.data} />
        : <ProblemNotice problem={summary.problem} />}
    </Shell>
  );
}
