import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { ServiceRequest } from "@/app/student/support/Support";
import { SupportDesk } from "./SupportDesk";

export const dynamic = "force-dynamic";

/** t/support — the requests students have put to this office, the oldest open first */
export default async function SupportPage() {
  const [me, r] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ServiceRequest[]>("/api/v1/support/requests")]);
  return (
    <Shell route="t/support" me={me.ok ? me.data : null}>
      {r.ok ? <SupportDesk requests={r.data} /> : <ProblemNotice problem={r.problem} />}
    </Shell>
  );
}
