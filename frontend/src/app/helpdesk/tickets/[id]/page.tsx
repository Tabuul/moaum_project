import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Agent, Ticket } from "@/lib/helpdesk";
import { DeskTicket } from "./DeskTicket";

export const dynamic = "force-dynamic";

/** the desk's view of one ticket: reading it opens it (SUBMITTED → OPENED, recorded), then every act the desk can take */
export default async function DeskTicketPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [me, t, agents] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Ticket>(`/api/v1/helpdesk/tickets/${encodeURIComponent(id)}`, { reason: "ticket read by the ICT desk" }),
    api<Agent[]>("/api/v1/helpdesk/agents"),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/helpdesk" me={me.ok ? me.data : null}>
      {t.ok ? <DeskTicket t={t.data} me={me.ok ? me.data.actorId : ""} director={office === "ict" || office === "admin" || office === "super"} agents={agents.ok ? agents.data : []} /> : <ProblemNotice problem={t.problem} />}
    </Shell>
  );
}
