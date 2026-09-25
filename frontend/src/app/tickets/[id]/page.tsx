import { api } from "@/lib/api";
import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Ticket } from "@/lib/helpdesk";
import { requester } from "../who";
import { TicketView } from "./TicketView";

export const dynamic = "force-dynamic";

/** One of your tickets: what you reported, what the desk said, its history, and what you can do next */
export default async function MyTicketPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { me, route } = await requester();
  const t = await api<Ticket>(`/api/v1/helpdesk/my/tickets/${encodeURIComponent(id)}`);
  return (
    <Shell route={route} me={me}>
      {t.ok ? <TicketView t={t.data} /> : <ProblemNotice problem={t.problem} />}
    </Shell>
  );
}
