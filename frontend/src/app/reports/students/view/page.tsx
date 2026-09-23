import { api } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import { ReportDoc } from "@/components/proto/ReportDoc";
import { ReportToolbar } from "@/components/proto/ReportToolbar";
import { ProblemNotice } from "@/components/ProblemNotice";
import { type ReportColumn, officeLabel } from "@/lib/report";
import { STUDENT_HEADERS, STUDENT_KEYS, registerQuery, studentSheetRow, words, type RegisterPage, type StudentOptions, type StudentRow } from "@/lib/registers";

export const dynamic = "force-dynamic";

const columns: ReportColumn[] = [
  { key: "no", label: "Matric / admission no." },
  { key: "name", label: "Name" },
  { key: "sex", label: "Sex", align: "center" },
  { key: "faculty", label: "Faculty" },
  { key: "programme", label: "Programme" },
  { key: "level", label: "Level", align: "right" },
  { key: "status", label: "Status" },
  { key: "entry", label: "Entry" },
];

/** the student register as a branded, printable return — every row the filters matched (up to 5,000) */
export default async function StudentsRegisterView({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const q = registerQuery(p, STUDENT_KEYS);
  const me = await api<Me>("/api/v1/iam/me");
  const rows: StudentRow[] = [];
  let total = 0;
  for (let page = 1; page <= 10; page++) {
    const r = await api<RegisterPage<StudentRow, StudentOptions>>(`/api/v1/reports/registers/students?${q}${q ? "&" : ""}page=${page}&size=500&options=false`);
    if (!r.ok) return <div style={{ padding: 24 }}><ProblemNotice problem={r.problem} /></div>;
    total = Number(r.data.total);
    rows.push(...r.data.rows);
    if (rows.length >= total || r.data.rows.length === 0) break;
  }
  const filters = STUDENT_KEYS.filter((k) => typeof p[k] === "string" && (p[k] as string).trim()).map((k) => `${k}: ${p[k]}`).join(" · ");
  const shown = rows.map((r) => ({
    no: r.matric_no ?? r.admission_no ?? "—", name: `${r.surname}, ${r.other_names}`, sex: r.sex ?? "—", faculty: r.faculty,
    programme: r.programme, level: r.level, status: words(r.status), entry: `${words(r.entry_mode)} · ${r.entry_session}`,
  }));
  return (
    <ReportDoc
      title="Student register"
      subtitle={`${rows.length < total ? `PARTIAL — the first ${rows.length.toLocaleString()} of ${total.toLocaleString()} rows · ` : ""}${filters ? `Filtered — ${filters}` : "Every student on the register"}`}
      session={`as at ${new Date().toISOString().slice(0, 10)}`}
      columns={columns}
      rows={shown as unknown as Record<string, string | number | null>[]}
      issuedFor={officeLabel(me.ok ? me.data.activeOffice : null)}
      note={`${total.toLocaleString()} student${total === 1 ? "" : "s"} matched${rows.length < total ? `; the first ${rows.length.toLocaleString()} are printed — narrow the filters or take the Excel download for the whole set` : ""}. Read off the register at the moment of printing; it is not a copy.`}
      toolbar={<ReportToolbar headers={STUDENT_HEADERS} rows={rows.map(studentSheetRow)} filename={`student-register-${new Date().toISOString().slice(0, 10)}`} title="Student register" keep={{ report: "students", period: `as at ${new Date().toISOString().slice(0, 10)}`, subtitle: rows.length < total ? `PARTIAL — the first ${rows.length.toLocaleString()} of ${total.toLocaleString()} rows; narrow the filters or take the Excel export for the whole set` : (filters || undefined) }} />}
    />
  );
}
