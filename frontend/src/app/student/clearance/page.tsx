import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { MyClearance } from "@/lib/clearance";
import { loadStudent } from "../load";
import { MyClearanceScreen } from "./MyClearance";

export const dynamic = "force-dynamic";

/** s/clearance — My Clearance (V415): each office's word on the student's fresh or final clearance, what to do and the
 *  documents asked for, the alumni details for final clearance, and the certificate once every office has cleared. */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/clearance" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const c = await api<MyClearance>("/api/v1/me/clearance");
  return (
    <Shell route="s/clearance" me={loaded.me}>
      {c.ok ? <MyClearanceScreen data={c.data} /> : <ProblemNotice problem={c.problem} />}
    </Shell>
  );
}
