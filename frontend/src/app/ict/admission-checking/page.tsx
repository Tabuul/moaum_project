import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AdmissionChecking, type CheckingFilters, type CheckingPage, type CheckingReport } from "./AdmissionChecking";

export const dynamic = "force-dynamic";

const FILTERS = ["faculty", "department", "programme", "sex", "payment", "result", "checked", "from", "to"] as const;

/** t/admissionchecking — Admission Status Checking (V295): the Director of ICT's window for the admission exercise of a session,
 *  and the report of who is eligible, who has paid and who has checked, which the admissions offices read as well */
export default async function AdmissionCheckingPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "";
  const filters: CheckingFilters = {};
  const q = new URLSearchParams();
  if (session) q.set("session", session);
  for (const k of FILTERS) {
    const v = p[k];
    if (typeof v === "string" && v) { filters[k] = v; q.set(k, v); }
  }
  const [me, page, report] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<CheckingPage>(`/api/v1/portal-windows/admission-checking${session ? `?session=${encodeURIComponent(session)}` : ""}`),
    api<CheckingReport>(`/api/v1/portal-windows/admission-checking/report${q.toString() ? `?${q.toString()}` : ""}`),
  ]);
  return (
    <Shell route="t/admissionchecking" me={me.ok ? me.data : null}>
      {page.ok ? <AdmissionChecking page={page.data} report={report.ok ? report.data : null} filters={filters} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={page.problem} />}
    </Shell>
  );
}
