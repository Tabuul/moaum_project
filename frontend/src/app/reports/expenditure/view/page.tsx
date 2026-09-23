import { api } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import { ReportDoc } from "@/components/proto/ReportDoc";
import { ReportToolbar } from "@/components/proto/ReportToolbar";
import { ProblemNotice } from "@/components/ProblemNotice";
import { money } from "@/lib/format";
import { type ReportColumn, officeLabel, reportFor } from "@/lib/report";

export const dynamic = "force-dynamic";

const spec = reportFor("expenditure")!;

interface Row { cost_centre: string; budget: number; committed: number; spent: number; available: number }
interface Expenditure { year: number; rows: Row[]; totals: { budget: number; committed: number; spent: number; available: number } }

const columns: ReportColumn[] = [
  { key: "cost_centre", label: "Cost centre" },
  { key: "budget", label: "Budget", align: "right", money: true, total: true },
  { key: "committed", label: "Committed", align: "right", money: true, total: true },
  { key: "spent", label: "Spent", align: "right", money: true, total: true },
  { key: "available", label: "Available", align: "right", money: true, total: true },
  { key: "utilisation", label: "Utilisation", align: "right" },
];

/** the expenditure return: the financial year's budget, commitments, spending and balance by cost centre (V045) */
export default async function ExpenditureReport({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "2026/2027";
  const year = /^\d{4}/.test(session) ? Number(session.slice(0, 4)) : new Date().getFullYear();
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Expenditure>(`/api/v1/reports/expenditure?year=${year}`),
  ]);
  if (!data.ok) return <div style={{ padding: 24 }}><ProblemNotice problem={data.problem} /></div>;
  const d = data.data;
  const pct = (r: { budget: number; committed: number; spent: number }) => {
    const b = Number(r.budget);
    return b > 0 ? `${Math.round(((Number(r.committed) + Number(r.spent)) / b) * 100)}%` : "—";
  };
  const rows = d.rows.map((r) => ({ ...r, utilisation: pct(r) }));

  const sheetHeaders = ["Cost centre", "Budget (NGN)", "Committed (NGN)", "Spent (NGN)", "Available (NGN)", "Utilisation"];
  const sheetRows: (string | number | null)[][] = d.rows.map((r) => [r.cost_centre, Number(r.budget), Number(r.committed), Number(r.spent), Number(r.available), pct(r)]);

  return (
    <ReportDoc
      title={spec.title}
      subtitle={`${spec.subtitle} — financial year ${d.year}`}
      session={session}
      columns={columns}
      rows={rows as unknown as Record<string, string | number | null>[]}
      totals={{ ...d.totals, utilisation: pct(d.totals) }}
      issuedFor={officeLabel(me.ok ? me.data.activeOffice : null)}
      note={`Financial year ${d.year}: ${money(Number(d.totals.budget))} budgeted, ${money(Number(d.totals.committed))} committed at approval and ${money(Number(d.totals.spent))} paid, leaving ${money(Number(d.totals.available))} available. Commitment accounting — budget is consumed at approval, not at payment.`}
      toolbar={<ReportToolbar headers={sheetHeaders} rows={sheetRows} filename={`expenditure-return-${d.year}`} title={`${spec.title} · ${d.year}`} keep={{ report: "expenditure", period: String(d.year) }} />}
    />
  );
}
