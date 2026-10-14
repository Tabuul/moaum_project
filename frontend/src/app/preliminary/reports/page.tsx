import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { PrelimSummary } from "../PrelimDesk";
import { PrelimReports } from "./PrelimReports";

export const dynamic = "force-dynamic";

/** prelim/reports — the Preliminary Science reports (V446), within the reader's scope */
export default async function PrelimReportsPage() {
  const [me, summary] = await Promise.all([api<Me>("/api/v1/iam/me"), api<PrelimSummary>("/api/v1/admissions/preliminary/summary")]);
  const office = (me.ok ? me.data.activeOffice : null) ?? "";
  return (
    <Shell route="prelim/reports" me={me.ok ? me.data : null}>
      {!summary.ok ? <ProblemNotice problem={summary.problem} /> : (
        <PrelimReports session={summary.data.session} sessions={summary.data.sessions} generatedBy={me.ok ? me.data.name ?? null : null}
          payments={["prelim", "academic", "registrar", "dregistrar", "super", "admin"].includes(office)} />
      )}
    </Shell>
  );
}
