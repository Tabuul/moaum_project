import { api } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import { ReportDoc } from "@/components/proto/ReportDoc";
import { ReportToolbar } from "@/components/proto/ReportToolbar";
import { ProblemNotice } from "@/components/ProblemNotice";
import { type ReportColumn, officeLabel, reportFor, sessionSlug } from "@/lib/report";

export const dynamic = "force-dynamic";

const spec = reportFor("staff-ratio")!;

interface Row {
  faculty: string; department_code: string; department: string;
  students: number; postgraduates: number; academic: number;
  professorial: number; senior: number; lecturers: number; junior: number; ratio: number | null;
}
interface Totals { students: number; postgraduates: number; academic: number; professorial: number; senior: number; lecturers: number; junior: number; ratio: number | null }
interface StaffRatio { rows: Row[]; totals: Totals }

const columns: ReportColumn[] = [
  { key: "faculty", label: "Faculty" },
  { key: "department", label: "Department" },
  { key: "students", label: "Students", align: "right", total: true },
  { key: "postgraduates", label: "of which PG", align: "right", total: true },
  { key: "academic", label: "Academic staff", align: "right", total: true },
  { key: "professorial", label: "Prof. / Reader", align: "right", total: true },
  { key: "senior", label: "Senior Lect.", align: "right", total: true },
  { key: "lecturers", label: "Lect. I / II", align: "right", total: true },
  { key: "junior", label: "Asst. / GA", align: "right", total: true },
  { key: "ratio_text", label: "Ratio", align: "right", total: true },
];

const ratioText = (r: number | null | undefined) => (r == null ? "—" : `1 : ${Number(r).toFixed(Number(r) % 1 === 0 ? 0 : 1)}`);

/** the staff/student ratio return: students on the books against academic staff, by department (V013, V137) */
export default async function StaffRatioReport({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "";
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<StaffRatio>("/api/v1/reports/staff-ratio")]);
  if (!data.ok) return <div style={{ padding: 24 }}><ProblemNotice problem={data.problem} /></div>;
  const d = data.data;
  const t = d.totals;
  const rows = d.rows.map((r) => ({ ...r, ratio_text: ratioText(r.ratio) }));
  const unstaffed = d.rows.filter((r) => Number(r.academic) === 0 && Number(r.students) > 0).length;
  const heavy = d.rows.filter((r) => r.ratio != null && Number(r.ratio) > 30).length;

  const sheetHeaders = ["Faculty", "Department code", "Department", "Students", "Postgraduates", "Academic staff", "Professor/Reader", "Senior Lecturer", "Lecturer I/II", "Assistant Lecturer/GA", "Students per staff"];
  const sheetRows: (string | number | null)[][] = d.rows.map((r) => [
    r.faculty, r.department_code, r.department, Number(r.students), Number(r.postgraduates), Number(r.academic),
    Number(r.professorial), Number(r.senior), Number(r.lecturers), Number(r.junior), r.ratio == null ? null : Number(r.ratio),
  ]);
  const today = new Date().toISOString().slice(0, 10);

  return (
    <ReportDoc
      title={spec.title}
      subtitle={`${spec.subtitle} — as at ${today}`}
      session={session || "as at today"}
      columns={columns}
      rows={rows as unknown as Record<string, string | number | null>[]}
      totals={{ ...t, ratio_text: ratioText(t.ratio) }}
      issuedFor={officeLabel(me.ok ? me.data.activeOffice : null)}
      note={`${Number(t.students).toLocaleString()} students on the books (${Number(t.postgraduates).toLocaleString()} postgraduate) against ${Number(t.academic).toLocaleString()} academic staff — ${ratioText(t.ratio)} overall. ${heavy ? `${heavy} department${heavy === 1 ? "" : "s"} exceed 1 : 30. ` : ""}${unstaffed ? `${unstaffed} department${unstaffed === 1 ? " has" : "s have"} students but no academic staff on the register — their staff have not been imported with a home department. ` : ""}Academic staff are those holding the lecturer, Head of Department or Dean office with a home department on the staff record; students are those admitted, active or on probation. The NUC guide is 1 : 10 for Medicine and Pharmacy, 1 : 20 for the Sciences and Engineering, and 1 : 30 for the Arts, Social and Management Sciences, Education and Law.`}
      toolbar={<ReportToolbar headers={sheetHeaders} rows={sheetRows} filename={`staff-student-ratio-${session ? sessionSlug(session) : today}`} title={`${spec.title} · ${today}`} keep={{ report: "staff-ratio", period: `as at ${today}` }} />}
    />
  );
}
