import { api } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import { ReportDoc } from "@/components/proto/ReportDoc";
import { ReportToolbar } from "@/components/proto/ReportToolbar";
import { ProblemNotice } from "@/components/ProblemNotice";
import { money } from "@/lib/format";
import { type ReportColumn, officeLabel, reportFor, sessionSlug } from "@/lib/report";

export const dynamic = "force-dynamic";

const spec = reportFor("revenue")!;

interface RevenueRow { category: string; payments: number; amount: number }
interface Revenue { session: string; rows: RevenueRow[]; totals: { payments: number; amount: number } }

const columns: ReportColumn[] = [
  { key: "category", label: "Category" },
  { key: "payments", label: "Payments", align: "right", total: true },
  { key: "amount", label: "Amount", align: "right", money: true, total: true },
];

/** the revenue return: fees confirmed for the session, by category */
export default async function RevenueReport({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "2026/2027";
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Revenue>(`/api/v1/reports/revenue?session=${encodeURIComponent(session)}`),
  ]);
  if (!data.ok) return <div style={{ padding: 24 }}><ProblemNotice problem={data.problem} /></div>;
  const d = data.data;

  const sheetHeaders = ["Category", "Payments", "Amount (NGN)"];
  const sheetRows: (string | number | null)[][] = d.rows.map((r) => [r.category, r.payments, Number(r.amount)]);

  return (
    <ReportDoc
      title={spec.title}
      subtitle={spec.subtitle}
      session={session}
      columns={columns}
      rows={d.rows as unknown as Record<string, string | number | null>[]}
      totals={d.totals}
      issuedFor={officeLabel(me.ok ? me.data.activeOffice : null)}
      note={`${d.totals.payments.toLocaleString()} payments confirmed for ${session}, totalling ${money(Number(d.totals.amount))}. Only payments the Bursary has confirmed against the bank record are counted; a reference not yet confirmed is not revenue.`}
      toolbar={<ReportToolbar headers={sheetHeaders} rows={sheetRows} filename={`revenue-return-${sessionSlug(session)}`} />}
    />
  );
}
