import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "./load";

export const dynamic = "force-dynamic";
import { Dashboard } from "./Screens1";
import type { GstView } from "@/lib/student-portal";
import { PgDashboard, type PgSummary } from "./PgDashboard";
import { BiodataCard, type BiodataStatus } from "./BiodataCard";
import type { OutstandingFees } from "@/lib/outstanding-fees";
import { showTransferCard, type TransferFeeView } from "@/lib/transfer-fee";
import { StudySession } from "./StudySession";
import { SummerCard } from "./SummerCard";
import type { MySummer } from "@/lib/summer";

/** s/dashboard — the student's own record, as the register holds it. A postgraduate gets their own
 *  home (V202), not a continuation of the undergraduate one. */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) {
    return <Shell route="s/dashboard" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  }
  // V425: where the biodata stands — a small card when it needs the student's attention, nothing when it is up to date
  const biodata = await api<BiodataStatus>("/api/v1/me/biodata-status");
  // V720: every outstanding school fee of the record — past sessions from the historical engine, the current one from the position
  const outstanding = await api<OutstandingFees>("/api/v1/me/outstanding-fees");
  const owed = outstanding.ok ? outstanding.data : null;
  if (loaded.student.entryMode === "POSTGRADUATE") {
    const pg = await api<PgSummary>("/api/v1/pg/coursework/summary");
    return <Shell route="s/dashboard" me={loaded.me} sub={`${loaded.student.session} session`}><BiodataCard b={biodata.ok ? biodata.data : null} /><PgDashboard s={loaded.student} pg={pg.ok ? pg.data : null} outstanding={owed} /></Shell>;
  }
  // V314: the GST & EPS card — the fee, whether it is paid, and whether the GST/EPS courses are registered or locked
  // V727: the transfer card — the fee, what is paid here and on the old portal, the balance — only with an application or old-portal credit
  // V735: the Summer Semester card — read only where the menu carries the Summer page (registration.summer_area)
  const [gst, mine, summer] = await Promise.all([
    api<GstView>(`/api/v1/me/gst?session=${encodeURIComponent(loaded.student.session)}`),
    api<TransferFeeView>("/api/v1/me/transfer"),
    loaded.student.summerArea ? api<MySummer>("/api/v1/me/summer") : null,
  ]);
  // only what the card reads reaches the page (the programmes list the transfer page offers stays behind)
  const transfer: TransferFeeView | null = mine.ok && showTransferCard(mine.data, loaded.student.session)
    ? { applications: mine.data.applications.map((a) => ({ id: a.id, state: a.state, session: a.session ?? null })), fee: mine.data.fee ?? null,
        payment: mine.data.payment ?? null, credit: mine.data.credit ?? null }
    : null;
  return <Shell route="s/dashboard" me={loaded.me} sub={`${loaded.student.session} session`}><BiodataCard b={biodata.ok ? biodata.data : null} /><StudySession /><SummerCard d={summer && summer.ok ? summer.data : null} /><Dashboard s={loaded.student} gst={gst.ok ? gst.data : null} outstanding={owed} transfer={transfer} /></Shell>;
}
