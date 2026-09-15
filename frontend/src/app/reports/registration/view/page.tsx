import { api } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import { ReportDoc } from "@/components/proto/ReportDoc";
import { ReportToolbar } from "@/components/proto/ReportToolbar";
import { ProblemNotice } from "@/components/ProblemNotice";
import { type ReportColumn, officeLabel, reportFor, sessionSlug } from "@/lib/report";

export const dynamic = "force-dynamic";

const spec = reportFor("registration")!;

interface Row { faculty: string; programme: string; expected: number; registered: number; not_registered: number; fee_blocked: number; cleared_idle: number }
interface Data { session: string; semester: number; rows: Row[]; totals: { expected: number; registered: number; not_registered: number; fee_blocked: number; cleared_idle: number }; schemeInForce: boolean }

const columns: ReportColumn[] = [
  { key: "faculty", label: "Faculty" },
  { key: "programme", label: "Programme" },
  { key: "expected", label: "Expected", align: "right", total: true },
  { key: "registered", label: "Registered", align: "right", total: true },
  { key: "not_registered", label: "Not registered", align: "right", total: true },
  { key: "fee_blocked", label: "Fee-blocked", align: "right", total: true },
  { key: "cleared_idle", label: "Cleared, idle", align: "right", total: true },
  { key: "pct", label: "% registered", align: "right" },
];

/** the registration & fees return: why students are not registered, by faculty and programme */
export default async function RegistrationReport({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "2026/2027";
  const semester = p.sem === "2" ? 2 : 1;
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Data>(`/api/v1/reports/registration-cause?session=${encodeURIComponent(session)}&semester=${semester}`),
  ]);
  if (!data.ok) return <div style={{ padding: 24 }}><ProblemNotice problem={data.problem} /></div>;
  const d = data.data;

  const pct = (r: { expected: number; registered: number }) => (r.expected ? `${Math.round((100 * r.registered) / r.expected)}%` : "—");
  const rows = d.rows.map((r) => ({ ...r, pct: pct(r) }));
  const sheetHeaders = columns.map((k) => k.label);
  const sheetRows = d.rows.map((r) => [r.faculty, r.programme, r.expected, r.registered, r.not_registered, r.fee_blocked, r.cleared_idle, pct(r)]);

  const t = d.totals;
  const note = d.schemeInForce
    ? `${t.not_registered.toLocaleString()} of ${t.expected.toLocaleString()} not registered for ${session} semester ${semester}: ${t.fee_blocked.toLocaleString()} fee-blocked (the Bursary has not cleared them — a payment plan, not a longer window, is the lever) and ${t.cleared_idle.toLocaleString()} cleared but idle (a reminder or a short window extension helps these). Expected is the active, matriculated cohort.`
    : `No clearance scheme is in force, so nobody can be cleared for registration — that is why the figures are low. All ${t.not_registered.toLocaleString()} non-registrants show as fee-blocked. The Bursar putting a clearance scheme in force will move the whole cohort at once; that is the first fix, before reading these figures per faculty.`;

  return (
    <ReportDoc
      title={spec.title}
      subtitle={`${spec.subtitle} · ${session} semester ${semester}`}
      session={session}
      columns={columns}
      rows={rows}
      totals={{ ...t, pct: t.expected ? `${Math.round((100 * t.registered) / t.expected)}%` : "—" }}
      issuedFor={officeLabel(me.ok ? me.data.activeOffice : null)}
      note={note}
      toolbar={<ReportToolbar headers={sheetHeaders} rows={sheetRows} filename={`registration-return-${sessionSlug(session)}-${semester}`} title={`${spec.title} · ${session} semester ${semester}`} />}
    />
  );
}
