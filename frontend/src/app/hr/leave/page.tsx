import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LeaveDesk, type LeaveRow } from "./LeaveDesk";

export const dynamic = "force-dynamic";

/** t/leave — the office's leave approval queue. */
export default async function LeavePage() {
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ rows: LeaveRow[] }>("/api/v1/hr/leave")]);
  return (
    <Shell route="t/leave" me={me.ok ? me.data : null}>
      {list.ok ? <LeaveDesk rows={list.data.rows} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
