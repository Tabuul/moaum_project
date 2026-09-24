import { api } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import { ReportDoc } from "@/components/proto/ReportDoc";
import { ReportToolbar } from "@/components/proto/ReportToolbar";
import { ProblemNotice } from "@/components/ProblemNotice";
import { type ReportColumn, officeLabel } from "@/lib/report";
import { STAFF_HEADERS, STAFF_KEYS, registerQuery, staffSheetRow, words, type RegisterPage, type StaffOptions, type StaffRow } from "@/lib/registers";

export const dynamic = "force-dynamic";

const columns: ReportColumn[] = [
  { key: "no", label: "Staff no." },
  { key: "name", label: "Name" },
  { key: "rank", label: "Rank" },
  { key: "department", label: "Department" },
  { key: "faculty", label: "Faculty" },
  { key: "category", label: "Category" },
  { key: "status", label: "Status" },
  { key: "appointed", label: "First appointment" },
];

/** the staff register as a branded, printable return — every row the filters matched (up to 5,000) */
export default async function StaffRegisterView({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const q = registerQuery(p, STAFF_KEYS);
  const me = await api<Me>("/api/v1/iam/me");
  const rows: StaffRow[] = [];
  let total = 0;
  for (let page = 1; page <= 10; page++) {
    const r = await api<RegisterPage<StaffRow, StaffOptions>>(`/api/v1/reports/registers/staff?${q}${q ? "&" : ""}page=${page}&size=500&options=false`);
    if (!r.ok) return <div style={{ padding: "var(--s-6)" }}><ProblemNotice problem={r.problem} /></div>;
    total = Number(r.data.total);
    rows.push(...r.data.rows);
    if (rows.length >= total || r.data.rows.length === 0) break;
  }
  const filters = STAFF_KEYS.filter((k) => typeof p[k] === "string" && (p[k] as string).trim()).map((k) => `${k}: ${p[k]}`).join(" · ");
  const shown = rows.map((r) => ({
    no: r.staff_number, name: `${r.surname}, ${r.given_names}`, rank: r.rank ? words(r.rank) : "—", department: r.department ?? r.department_code ?? "—",
    faculty: r.faculty ?? "—", category: r.category === "ACADEMIC" ? "Academic" : "Non-teaching", status: words(r.status),
    appointed: r.date_first_appointment ?? r.appointment_date ?? "—",
  }));
  return (
    <ReportDoc
      title="Staff register"
      subtitle={`${rows.length < total ? `PARTIAL — the first ${rows.length.toLocaleString()} of ${total.toLocaleString()} rows · ` : ""}${filters ? `Filtered — ${filters}` : "Every member of staff on the register"}`}
      session={`as at ${new Date().toISOString().slice(0, 10)}`}
      columns={columns}
      rows={shown as unknown as Record<string, string | number | null>[]}
      issuedFor={officeLabel(me.ok ? me.data.activeOffice : null)}
      note={`${total.toLocaleString()} member${total === 1 ? "" : "s"} of staff matched${rows.length < total ? `; the first ${rows.length.toLocaleString()} are printed — narrow the filters or take the Excel download for the whole set` : ""}. Rank, department and first appointment come from the HR staff record; grade and category from the employment record where one exists.`}
      toolbar={<ReportToolbar headers={STAFF_HEADERS} rows={rows.map(staffSheetRow)} filename={`staff-register-${new Date().toISOString().slice(0, 10)}`} title="Staff register" keep={{ report: "staff", period: `as at ${new Date().toISOString().slice(0, 10)}`, subtitle: rows.length < total ? `PARTIAL — the first ${rows.length.toLocaleString()} of ${total.toLocaleString()} rows; narrow the filters or take the Excel export for the whole set` : (filters || undefined) }} />}
    />
  );
}
