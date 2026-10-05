import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Ticket } from "@/lib/helpdesk";
import { OfficeTicket } from "./OfficeTicket";

export const dynamic = "force-dynamic";

/** the office's view of one ticket it was asked to decide: the agent's question, the whole conversation, and the answer (V328) */
export default async function OfficeTicketPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [me, t] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Ticket>(`/api/v1/helpdesk/office/tickets/${encodeURIComponent(id)}`, { reason: "ticket read by the office it waits on" }),
  ]);
  return (
    <Shell route="t/helpdeskoffice" me={me.ok ? me.data : null}>
      {t.ok ? <OfficeTicket t={t.data} /> : <ProblemNotice problem={t.problem} />}
    </Shell>
  );
}
