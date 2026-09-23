import { api } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import type { FundingReport } from "@/lib/wallet";
import { ReportDoc } from "@/components/proto/ReportDoc";
import { ReportToolbar } from "@/components/proto/ReportToolbar";
import { ProblemNotice } from "@/components/ProblemNotice";
import { money } from "@/lib/format";
import { type ReportColumn, officeLabel, reportFor, sessionSlug } from "@/lib/report";

export const dynamic = "force-dynamic";

const spec = reportFor("funding")!;
const NATURE: Record<string, string> = { LOAN: "Loan (repayable)", GRANT: "Grant", SELF: "Own money" };

const columns: ReportColumn[] = [
  { key: "source", label: "Source" },
  { key: "nature", label: "Nature" },
  { key: "students", label: "Students", align: "right", total: true },
  { key: "credited", label: "Credited", align: "right", money: true, total: true },
];

/** the funding return: what students were funded with, by source and nature, with the wallet cash flow */
export default async function FundingReport({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "2026/2027";
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<FundingReport>(`/api/v1/funding/sessions/${session}/report`),
  ]);
  if (!data.ok) return <div style={{ padding: 24 }}><ProblemNotice problem={data.problem} /></div>;
  const d = data.data;
  const c = d.cashflow;

  const rows = d.bySource.map((r) => ({ source: r.name, nature: NATURE[r.nature] ?? r.nature, students: Number(r.students), credited: Number(r.credited) }));
  const totals = { students: rows.reduce((n, r) => n + r.students, 0), credited: rows.reduce((n, r) => n + r.credited, 0) };

  const sheetHeaders = ["Source", "Nature", "Students", "Credited (NGN)"];
  const sheetRows: (string | number | null)[][] = [
    ...d.bySource.map((r) => [r.name, NATURE[r.nature] ?? r.nature, Number(r.students), Number(r.credited)]),
    [],
    ["Cash flow", "", "", ""],
    ["Credited (loans + grants)", "", "", Number(c.credited)],
    ["Topped up by students", "", "", Number(c.topped_up)],
    ["Applied to school fees", "", "", Number(c.applied)],
    ["Confirmed as wallet payments", "", "", Number(c.settled_to_fees)],
    ["Reversed to source", "", "", Number(c.reversed)],
    ["Withdrawn to bank", "", "", Number(c.withdrawn)],
    ["Held in wallets", "", "", Number(c.held)],
  ];

  const note = `Funded ${money(Number(c.credited) + Number(c.topped_up))} for ${session} — ${money(Number(c.loans_in))} in loans, ${money(Number(c.grants_in))} in grants, ${money(Number(c.self_in))} in students' own money. `
    + `${money(Number(c.applied))} was applied to school fees, ${money(Number(c.withdrawn))} withdrawn to bank accounts, and ${money(Number(c.held))} is still held in wallets. `
    + (c.applied_matches
      ? `The wallet reconciles with school payments: every naira applied to fees is a confirmed payment on the main account (${money(Number(c.settled_to_fees))}).`
      : `The wallet does NOT reconcile: ${money(Number(c.applied))} applied against ${money(Number(c.settled_to_fees))} confirmed — investigate.`);

  return (
    <ReportDoc
      title={spec.title}
      subtitle={spec.subtitle}
      session={session}
      columns={columns}
      rows={rows as unknown as Record<string, string | number | null>[]}
      totals={totals}
      issuedFor={officeLabel(me.ok ? me.data.activeOffice : null)}
      note={note}
      toolbar={<ReportToolbar headers={sheetHeaders} rows={sheetRows} filename={`funding-return-${sessionSlug(session)}`} title={`${spec.title} · ${session}`} keep={{ report: "funding", period: session }} />}
    />
  );
}
