import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import type { ComplianceOverview } from "@/lib/biodata-gate";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { BiodataComplianceScreen } from "./BiodataComplianceScreen";
import type { ComplianceFilters } from "./ComplianceFilterBar";

export const dynamic = "force-dynamic";

/** t/biodatagate — Biodata compliance (V423), under Portal Management: the ICT Director's switch for mandatory student
 *  biodata completion, the go-live readiness, what is missing and where, the required items, the exceptions and the
 *  history. The Registry and the Academic Office read the figures; a Dean or a Head of Department within their own. */
export default async function BiodataCompliancePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const s = (k: string) => (typeof params[k] === "string" ? (params[k] as string).trim() : "");
  const scoped = await loadScope({});
  const f: ComplianceFilters = {
    fac: scoped.ceiling.fac ?? s("fac"), dept: scoped.ceiling.dept ?? s("dept"), prog: scoped.ceiling.prog ?? s("prog"),
    level: s("level"), session: s("session"), sex: s("sex"),
  };
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(f)) if (v) q.set(k, v);
  const [me, ov] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ComplianceOverview>(`/api/v1/biodata-compliance?${q.toString()}`)]);
  return (
    <Shell route="t/biodatagate" me={me.ok ? me.data : null}>
      {ov.ok ? <BiodataComplianceScreen data={ov.data} filters={f} structure={scoped.structure} sessions={scoped.sessions} ceiling={scoped.ceiling} />
        : <ProblemNotice problem={ov.problem} />}
    </Shell>
  );
}
