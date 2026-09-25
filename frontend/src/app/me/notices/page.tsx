import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { StaffNotice } from "@/lib/lecturer";
import { Notices } from "./Notices";

export const dynamic = "force-dynamic";

/** r/notices — every notice the portal sent this member of staff, read back from the outbox that sent it */
export default async function NoticesPage() {
  const [me, notices] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<StaffNotice[]>("/api/v1/me/notices?limit=200"),
  ]);
  return (
    <Shell route="r/notices" me={me.ok ? me.data : null}>
      {notices.ok ? <Notices items={notices.data} /> : <ProblemNotice problem={notices.problem} />}
    </Shell>
  );
}
