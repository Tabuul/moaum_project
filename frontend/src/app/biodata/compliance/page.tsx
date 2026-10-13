import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Compliance, type ComplianceSummary, type StudentsPage, type StaffPage } from "./Compliance";
import type { ComplianceOverview } from "@/lib/biodata-gate";

export const dynamic = "force-dynamic";

/** t/compliance — where every student's biodata stands (V426): the counts, the students behind each, the data-quality picture;
 *  a Dean or Head within their own faculty or department. */
export default async function ComplianceRoute({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const one = (k: string) => { const v = q[k]; return (Array.isArray(v) ? v[0] : v) ?? ""; };
  const filters = { status: one("status"), faculty: one("faculty"), department: one("department"), programme: one("programme"), level: one("level"), session: one("session"), entryMode: one("entryMode"), migrated: one("migrated"), q: one("q"), page: one("page") || "1",
    missing: one("missing"), sex: one("sex") };
  const p = new URLSearchParams();
  (Object.keys(filters) as (keyof typeof filters)[]).forEach((k) => { if (filters[k]) p.set(k, filters[k]); });
  p.set("size", "200");
  const scope = new URLSearchParams();
  if (filters.faculty) scope.set("faculty", filters.faculty);
  if (filters.department) scope.set("department", filters.department);
  // V430: the staff reach panel, for the offices that read the staff (a Dean or Head reads students only)
  const staffFilters = { status: one("staffStatus"), office: one("office"), q: one("sq"), page: one("spage") || "1" };
  const sp = new URLSearchParams();
  if (staffFilters.status) sp.set("status", staffFilters.status);
  if (staffFilters.office) sp.set("office", staffFilters.office);
  if (staffFilters.q) sp.set("q", staffFilters.q);
  sp.set("page", staffFilters.page);
  sp.set("size", "100");
  const [me, summary, students, staff, admin] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ComplianceSummary>(`/api/v1/biodata/compliance${scope.toString() ? `?${scope}` : ""}`),
    api<StudentsPage>(`/api/v1/biodata/compliance/students?${p}`),
    api<StaffPage>(`/api/v1/biodata/compliance/staff?${sp}`),
    // V434: the switch, the required items, the exceptions and the history — the same screen
    api<ComplianceOverview>("/api/v1/biodata-compliance"),
  ]);
  return (
    <Shell route="t/compliance" me={me.ok ? me.data : null}>
      {summary.ok ? <Compliance d={summary.data} students={students.ok ? students.data : null} filters={filters} actingOffice={me.ok ? me.data.activeOffice : null}
        staff={staff.ok ? staff.data : null} staffFilters={staffFilters} admin={admin.ok ? admin.data : null} /> : <ProblemNotice problem={summary.problem} />}
    </Shell>
  );
}
