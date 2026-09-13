import { api } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import { ReportDoc } from "@/components/proto/ReportDoc";
import { ReportToolbar } from "@/components/proto/ReportToolbar";
import { ProblemNotice } from "@/components/ProblemNotice";
import { type ReportColumn, officeLabel, reportFor, sessionSlug } from "@/lib/report";

export const dynamic = "force-dynamic";

const spec = reportFor("carryovers")!;

interface CarryRow { [k: string]: string | number; faculty: string; programme: string; course: string; title: string; units: number; students: number }
interface Carryovers { session: string; rows: CarryRow[]; totals: { students: number | string; units: number | string }; distinctStudents: number }

const columns: ReportColumn[] = [
  { key: "faculty", label: "Faculty" },
  { key: "programme", label: "Programme" },
  { key: "course", label: "Course" },
  { key: "title", label: "Title" },
  { key: "units", label: "Units", align: "right" },
  { key: "students", label: "Students carrying", align: "right", total: true },
];

/** the carryover return: for every active student, the courses whose latest published attempt is an F,
 *  grouped by faculty, programme and course — the re-sit load the department must offer. */
export default async function CarryoverReport({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "2026/2027";
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Carryovers>(`/api/v1/reports/carryovers?session=${encodeURIComponent(session)}`),
  ]);
  if (!data.ok) return <div style={{ padding: 24 }}><ProblemNotice problem={data.problem} /></div>;
  const d = data.data;

  const carried = Number(d.totals.students) || 0;
  const sheetHeaders = columns.map((k) => k.label);
  const sheetRows = d.rows.map((r) => columns.map((k) => r[k.key as keyof CarryRow] ?? ""));

  return (
    <ReportDoc
      title={spec.title}
      subtitle={spec.subtitle}
      session={session}
      columns={columns}
      rows={d.rows}
      totals={d.totals}
      issuedFor={officeLabel(me.ok ? me.data.activeOffice : null)}
      note={d.rows.length
        ? `${d.distinctStudents.toLocaleString()} active student${d.distinctStudents === 1 ? "" : "s"} carry ${carried.toLocaleString()} course-registration${carried === 1 ? "" : "s"} across ${d.rows.length} course${d.rows.length === 1 ? "" : "s"}. A carryover is a course whose most recent published result is an F, not yet passed; it is added to the student's registration automatically. Figures are as at today, not bound to a session.`
        : "No active student currently carries a course whose latest published result is an F."}
      toolbar={<ReportToolbar headers={sheetHeaders} rows={sheetRows} filename={`carryover-return-${sessionSlug(session)}`} title={`${spec.title} · ${session}`} />}
    />
  );
}
