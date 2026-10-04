import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "./load";

export const dynamic = "force-dynamic";
import { Dashboard } from "./Screens1";
import type { GstView } from "@/lib/student-portal";
import { PgDashboard, type PgSummary } from "./PgDashboard";

/** s/dashboard — the student's own record, as the register holds it. A postgraduate gets their own
 *  home (V202), not a continuation of the undergraduate one. */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) {
    return <Shell route="s/dashboard" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  }
  if (loaded.student.entryMode === "POSTGRADUATE") {
    const pg = await api<PgSummary>("/api/v1/pg/coursework/summary");
    return <Shell route="s/dashboard" me={loaded.me} sub={`${loaded.student.session} session`}><PgDashboard s={loaded.student} pg={pg.ok ? pg.data : null} /></Shell>;
  }
  // V314: the GST & EPS card — the fee, whether it is paid, and whether the GST/EPS courses are registered or locked
  const gst = await api<GstView>(`/api/v1/me/gst?session=${encodeURIComponent(loaded.student.session)}`);
  return <Shell route="s/dashboard" me={loaded.me} sub={`${loaded.student.session} session`}><Dashboard s={loaded.student} gst={gst.ok ? gst.data : null} /></Shell>;
}
