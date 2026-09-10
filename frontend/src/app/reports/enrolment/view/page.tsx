import { api } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import { ReportDoc } from "@/components/proto/ReportDoc";
import { ReportToolbar } from "@/components/proto/ReportToolbar";
import { ProblemNotice } from "@/components/ProblemNotice";
import { type ReportColumn, officeLabel, reportFor, sessionSlug } from "@/lib/report";

export const dynamic = "force-dynamic";

const spec = reportFor("enrolment")!;

interface EnrolmentRow { faculty: string; programme: string; level: number; male: number; female: number; unstated: number; total: number }
interface Enrolment { session: string; rows: EnrolmentRow[]; totals: { male: number; female: number; unstated: number; total: number } }

const columns: ReportColumn[] = [
  { key: "faculty", label: "Faculty" },
  { key: "programme", label: "Programme" },
  { key: "level", label: "Level", align: "right" },
  { key: "male", label: "Male", align: "right", total: true },
  { key: "female", label: "Female", align: "right", total: true },
  { key: "unstated", label: "Unstated", align: "right", total: true },
  { key: "total", label: "Total", align: "right", total: true },
];

/** the enrolment return: the session's admitted cohort by faculty, programme and level */
export default async function EnrolmentReport({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "2026/2027";
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Enrolment>(`/api/v1/reports/enrolment?session=${encodeURIComponent(session)}`),
  ]);
  if (!data.ok) return <div style={{ padding: 24 }}><ProblemNotice problem={data.problem} /></div>;
  const d = data.data;

  const rows = d.rows.map((r) => ({ ...r, level: `${r.level} Level` }));
  const sheetHeaders = columns.map((k) => k.label);
  const sheetRows = d.rows.map((r) => columns.map((k) => r[k.key as keyof EnrolmentRow] ?? ""));

  return (
    <ReportDoc
      title={spec.title}
      subtitle={spec.subtitle}
      session={session}
      columns={columns}
      rows={rows}
      totals={d.totals}
      issuedFor={officeLabel(me.ok ? me.data.activeOffice : null)}
      note={`${d.totals.total.toLocaleString()} students in the ${session} cohort — ${d.totals.male.toLocaleString()} male, ${d.totals.female.toLocaleString()} female${d.totals.unstated ? `, ${d.totals.unstated.toLocaleString()} unstated` : ""}. Those withdrawn, expelled, transferred out or deceased are not counted.`}
      toolbar={<ReportToolbar headers={sheetHeaders} rows={sheetRows} filename={`enrolment-return-${sessionSlug(session)}`} title={`${spec.title} · ${session}`} />}
    />
  );
}
