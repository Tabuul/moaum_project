import { api } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import { ReportDoc } from "@/components/proto/ReportDoc";
import { ReportToolbar } from "@/components/proto/ReportToolbar";
import { ProblemNotice } from "@/components/ProblemNotice";
import { type ReportColumn, officeLabel, reportFor, sessionSlug } from "@/lib/report";

export const dynamic = "force-dynamic";

const spec = reportFor("postgraduate")!;

interface Row {
  faculty: string; programme_code: string; programme: string; award: string;
  applications: number; offered: number; accepted: number; admitted: number;
  on_register: number; female: number; male: number; full_time: number; part_time: number;
  researching: number; awarded: number;
}
interface Totals { applications: number; offered: number; accepted: number; admitted: number; on_register: number; female: number; male: number; full_time: number; part_time: number; researching: number; awarded: number }
interface Postgraduate { session: string; rows: Row[]; totals: Totals }

const columns: ReportColumn[] = [
  { key: "faculty", label: "Faculty" },
  { key: "programme", label: "Programme" },
  { key: "award", label: "Award", align: "center" },
  { key: "applications", label: "Applied", align: "right", total: true },
  { key: "offered", label: "Offered", align: "right", total: true },
  { key: "accepted", label: "Accepted", align: "right", total: true },
  { key: "admitted", label: "Admitted", align: "right", total: true },
  { key: "on_register", label: "On register", align: "right", total: true },
  { key: "female", label: "F", align: "right", total: true },
  { key: "male", label: "M", align: "right", total: true },
  { key: "full_time", label: "Full-time", align: "right", total: true },
  { key: "part_time", label: "Part-time", align: "right", total: true },
  { key: "researching", label: "In research", align: "right", total: true },
  { key: "awarded", label: "Awarded", align: "right", total: true },
];

/** the postgraduate return: the session's admissions funnel and the register by programme (V202, V211, V209) */
export default async function PostgraduateReport({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const asked = typeof p.session === "string" ? p.session : "";
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Postgraduate>(`/api/v1/reports/postgraduate${asked ? `?session=${encodeURIComponent(asked)}` : ""}`),
  ]);
  if (!data.ok) return <div style={{ padding: 24 }}><ProblemNotice problem={data.problem} /></div>;
  const d = data.data;
  const t = d.totals;
  const pct = (a: number, b: number) => (Number(b) > 0 ? `${Math.round((100 * Number(a)) / Number(b))}%` : "—");

  const sheetHeaders = ["Faculty", "Programme code", "Programme", "Award", "Applied", "Offered", "Accepted", "Admitted", "On register", "Female", "Male", "Full-time", "Part-time", "In research", "Awarded"];
  const sheetRows: (string | number | null)[][] = d.rows.map((r) => [
    r.faculty, r.programme_code, r.programme, r.award, Number(r.applications), Number(r.offered), Number(r.accepted), Number(r.admitted),
    Number(r.on_register), Number(r.female), Number(r.male), Number(r.full_time), Number(r.part_time), Number(r.researching), Number(r.awarded),
  ]);

  return (
    <ReportDoc
      title={spec.title}
      subtitle={`${spec.subtitle} — ${d.session}`}
      session={d.session}
      columns={columns}
      rows={d.rows as unknown as Record<string, string | number | null>[]}
      totals={{ ...t }}
      issuedFor={officeLabel(me.ok ? me.data.activeOffice : null)}
      note={`${d.session}: ${Number(t.applications).toLocaleString()} applications, ${Number(t.offered).toLocaleString()} offered (${pct(t.offered, t.applications)} of applications), ${Number(t.accepted).toLocaleString()} accepted and ${Number(t.admitted).toLocaleString()} admitted to the register. ${Number(t.on_register).toLocaleString()} postgraduates are on the books across every entry session — ${Number(t.full_time).toLocaleString()} full-time and ${Number(t.part_time).toLocaleString()} part-time registered this session — of whom ${Number(t.researching).toLocaleString()} are at a research stage and ${Number(t.awarded).toLocaleString()} have been awarded.`}
      toolbar={<ReportToolbar headers={sheetHeaders} rows={sheetRows} filename={`postgraduate-return-${sessionSlug(d.session)}`} title={`${spec.title} · ${d.session}`} keep={{ report: "postgraduate", period: d.session }} />}
    />
  );
}
