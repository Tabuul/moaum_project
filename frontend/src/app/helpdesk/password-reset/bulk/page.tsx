import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Summary } from "@/lib/ticket-reset";
import { LoginTicketReset, type TicketPage } from "./LoginTicketReset";

export const dynamic = "force-dynamic";

/** t/supportpwbulk — Bulk Password Reset (V594): the open Login Issues tickets within the agent's reach — a student's own, and a
 *  request from the sign-in page with the student holding the number given — the eligible selected all at once and reset together
 *  by the reset from tickets (V582), every ticket resolved with it; the students without a ticket stay a link away (V559) */
export default async function BulkResetPage() {
  const [me, summary, first] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Summary>("/api/v1/helpdesk/tickets/password-reset/summary"),
    api<TicketPage>("/api/v1/helpdesk/tickets?issue=login&status=open&sort=created&dir=asc&page=1&size=50"),
  ]);
  return (
    <Shell route="t/supportpwbulk" me={me.ok ? me.data : null}>
      {first.ok
        ? <LoginTicketReset first={first.data} summary={summary.ok ? summary.data : null} />
        : <ProblemNotice problem={first.problem} />}
    </Shell>
  );
}
