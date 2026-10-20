import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { TicketResets, type OpRow } from "./TicketResets";

export const dynamic = "force-dynamic";

/** t/supportpwtickets — V582: the password resets made from login and password tickets (PWR-TKT/…), each with its tickets and
 *  results; the login issue report and the reset operations report. The resets themselves are made on the desk's queue. */
export default async function TicketResetsPage() {
  const [me, ops] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<OpRow[]>("/api/v1/helpdesk/tickets/password-reset/operations"),
  ]);
  return (
    <Shell route="t/supportpwtickets" me={me.ok ? me.data : null}>
      {ops.ok ? <TicketResets ops={ops.data} /> : <ProblemNotice problem={ops.problem} />}
    </Shell>
  );
}
