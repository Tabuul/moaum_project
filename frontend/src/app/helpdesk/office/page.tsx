import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { TicketRow } from "@/lib/helpdesk";
import { Office } from "./Office";

export const dynamic = "force-dynamic";

export interface OfficeData { offices: { code: string; label: string }[]; waiting: TicketRow[]; answered: TicketRow[] }

/** t/helpdeskoffice — a University office's view of the support desk: the tickets the desk has referred to it for a decision,
 *  and those it answered (V328). Support asks; the office decides; the answer goes back to the agent on the ticket. */
export default async function HelpdeskOfficePage() {
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<OfficeData>("/api/v1/helpdesk/office/tickets"),
  ]);
  return (
    <Shell route="t/helpdeskoffice" me={me.ok ? me.data : null}>
      {data.ok ? <Office data={data.data} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
