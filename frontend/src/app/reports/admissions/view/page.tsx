import { api } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import type { AdmissionCycle } from "@/lib/matriculation";
import { ReportDoc } from "@/components/proto/ReportDoc";
import { ReportToolbar } from "@/components/proto/ReportToolbar";
import { ProblemNotice } from "@/components/ProblemNotice";
import { type ReportColumn, officeLabel, reportFor, sessionSlug } from "@/lib/report";

export const dynamic = "force-dynamic";

const spec = reportFor("admissions")!;

const columns: ReportColumn[] = [
  { key: "faculty", label: "Faculty" },
  { key: "programme", label: "Programme" },
  { key: "applied", label: "Applied", align: "right", total: true },
  { key: "quota", label: "Quota", align: "right", total: true },
  { key: "offered", label: "Offered", align: "right", total: true },
  { key: "accepted", label: "Accepted", align: "right", total: true },
  { key: "cutoff", label: "Cut-off", align: "right" },
];

/** the admissions return: applications, offers and acceptances by programme */
export default async function AdmissionsReport({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "2026/2027";
  const [me, cycle] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<AdmissionCycle>(`/api/v1/admissions/sessions/${session}/cycle`),
  ]);
  if (!cycle.ok) return <div style={{ padding: "var(--s-6)" }}><ProblemNotice problem={cycle.problem} /></div>;
  const c = cycle.data;

  const progs = [...c.programmes].sort((a, b) => a.facultyName.localeCompare(b.facultyName) || a.name.localeCompare(b.name));
  const rows = progs.map((x) => ({
    faculty: x.facultyName, programme: x.name,
    applied: x.applied, quota: x.quota, offered: x.offered, accepted: x.accepted, cutoff: x.cutoff,
  }));
  const sum = (k: "applied" | "quota" | "offered" | "accepted") => progs.reduce((n, x) => n + (Number(x[k]) || 0), 0);
  const totals = { applied: sum("applied"), quota: sum("quota"), offered: sum("offered"), accepted: sum("accepted") };

  const sheetHeaders = columns.map((k) => k.label);
  const sheetRows = rows.map((r) => columns.map((k) => r[k.key as keyof typeof r] ?? ""));

  return (
    <ReportDoc
      title={spec.title}
      subtitle={spec.subtitle}
      session={session}
      columns={columns}
      rows={rows}
      totals={totals}
      issuedFor={officeLabel(me.ok ? me.data.activeOffice : null)}
      note={`${c.applications.toLocaleString()} applications on the committed list, ${c.screened.toLocaleString()} carrying a screening aggregate; ${c.offers.toLocaleString()} offers and ${c.accepted.toLocaleString()} acceptances${c.capacity != null ? ` against ${c.capacity.toLocaleString()} places` : ""}.`}
      toolbar={<ReportToolbar headers={sheetHeaders} rows={sheetRows} filename={`admissions-return-${sessionSlug(session)}`} title={`${spec.title} · ${session}`} keep={{ report: "admissions", period: session }} />}
    />
  );
}
