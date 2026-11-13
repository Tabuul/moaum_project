import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { StaffNotice } from "@/lib/lecturer";
import { noticesAwaitEmail, type StaffIdentityState } from "@/lib/identity";
import { Notices } from "./Notices";

export const dynamic = "force-dynamic";

/** r/notices — the notices about this member of staff, the e-mail sent to the address they verified and some notices of their work,
 *  read back from the outbox that sent them (V749, platform.person_notices); with the e-mail's state (GET /staff/identity — any member
 *  of staff, in service or not, verifies there), so a list read before the address is verified says why mail sent to it is missing */
export default async function NoticesPage() {
  const [me, notices, identity] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<StaffNotice[]>("/api/v1/me/notices?limit=200"),
    api<StaffIdentityState>("/api/v1/staff/identity"),
  ]);
  return (
    <Shell route="r/notices" me={me.ok ? me.data : null}>
      {notices.ok ? <Notices items={notices.data} awaitEmail={identity.ok && noticesAwaitEmail(identity.data)} /> : <ProblemNotice problem={notices.problem} />}
    </Shell>
  );
}
