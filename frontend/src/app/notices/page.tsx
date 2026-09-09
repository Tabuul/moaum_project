import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Notices, type Outbox } from "./Notices";

export const dynamic = "force-dynamic";

/** t/notify and t/channels — the outbox: what waits, what went, and whether a provider is wired. */
export default async function NoticesPage() {
  const [me, outbox] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Outbox>("/api/v1/platform/notices")]);
  return (
    <Shell route={me.ok && me.data.activeOffice === "super" ? "t/channels" : "t/notify"} me={me.ok ? me.data : null}>
      {outbox.ok ? <Notices d={outbox.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={outbox.problem} />}
    </Shell>
  );
}
