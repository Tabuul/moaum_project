import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { HEADS, type Agent, type Queue, type Ticket } from "@/lib/helpdesk";
import { DeskTicket } from "./DeskTicket";

export const dynamic = "force-dynamic";

/** the desk's view of one ticket: reading it opens it (SUBMITTED → OPENED, recorded), then every act the desk can take; the agents
 *  are read against the ticket, so the assign dialog says which of them the routing would choose (V328) */
export default async function DeskTicketPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [me, t, agents, queues] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Ticket>(`/api/v1/helpdesk/tickets/${encodeURIComponent(id)}`, { reason: "ticket read by the ICT desk" }),
    api<Agent[]>(`/api/v1/helpdesk/agents?ticket=${encodeURIComponent(id)}`),
    api<Queue[]>("/api/v1/helpdesk/queues"),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/helpdesk" me={me.ok ? me.data : null}>
      {t.ok ? <DeskTicket t={t.data} me={me.ok ? me.data.actorId : ""} head={HEADS.includes(office ?? "")} agents={agents.ok ? agents.data : []} queues={queues.ok ? queues.data.filter((q) => q.active) : []} /> : <ProblemNotice problem={t.problem} />}
    </Shell>
  );
}
