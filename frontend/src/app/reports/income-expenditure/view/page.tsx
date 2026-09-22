import { api } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import { ReportDoc } from "@/components/proto/ReportDoc";
import { ReportToolbar } from "@/components/proto/ReportToolbar";
import { ProblemNotice } from "@/components/ProblemNotice";
import { money } from "@/lib/format";
import { type ReportColumn, officeLabel, reportFor } from "@/lib/report";

export const dynamic = "force-dynamic";

const spec = reportFor("income-expenditure")!;

interface Line { section: string; code: string; name: string; amount: number }
interface Statement {
  year: number; from: string; to: string; lines: Line[];
  totals: { income: number; expense: number; surplus: number };
  budget: { budget: number; committed: number; spent: number; available: number };
}

const columns: ReportColumn[] = [
  { key: "section", label: "Section" },
  { key: "code", label: "Account", align: "left" },
  { key: "name", label: "Head" },
  { key: "amount", label: "Amount", align: "right", money: true },
];

/** the income & expenditure statement: every income and expense head for the financial year, the
 *  surplus or deficit, and the year's spending against budget — read off the general ledger (V145) */
export default async function IncomeExpenditureReport({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "2026/2027";
  const year = /^\d{4}/.test(session) ? Number(session.slice(0, 4)) : new Date().getFullYear();
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Statement>(`/api/v1/reports/income-expenditure?year=${year}`),
  ]);
  if (!data.ok) return <div style={{ padding: 24 }}><ProblemNotice problem={data.problem} /></div>;
  const d = data.data;
  const income = d.lines.filter((l) => String(l.section).toUpperCase() === "INCOME");
  const expense = d.lines.filter((l) => String(l.section).toUpperCase() !== "INCOME");
  const surplus = Number(d.totals.surplus);

  // the statement's rows: income heads and their total, expense heads and their total, then the result
  const rows: Record<string, string | number | null>[] = [
    ...income.map((l) => ({ section: "Income", code: l.code, name: l.name, amount: Number(l.amount) })),
    { section: "Income", code: "", name: "Total income", amount: Number(d.totals.income) },
    ...expense.map((l) => ({ section: "Expenditure", code: l.code, name: l.name, amount: Number(l.amount) })),
    { section: "Expenditure", code: "", name: "Total expenditure", amount: Number(d.totals.expense) },
    { section: "Result", code: "", name: surplus >= 0 ? "Surplus for the year" : "Deficit for the year", amount: surplus },
    { section: "Budget", code: "", name: "Expenditure budget for the year", amount: Number(d.budget.budget) },
    { section: "Budget", code: "", name: "Committed at approval", amount: Number(d.budget.committed) },
    { section: "Budget", code: "", name: "Paid", amount: Number(d.budget.spent) },
    { section: "Budget", code: "", name: "Available", amount: Number(d.budget.available) },
  ];

  const sheetHeaders = ["Section", "Account", "Head", "Amount (NGN)"];
  const sheetRows: (string | number | null)[][] = rows.map((r) => [r.section, r.code, r.name, r.amount]);

  return (
    <ReportDoc
      title={spec.title}
      subtitle={`${spec.subtitle} — financial year ${d.year} (1 Jan to 31 Dec)`}
      session={session}
      columns={columns}
      rows={rows}
      issuedFor={officeLabel(me.ok ? me.data.activeOffice : null)}
      note={`Financial year ${d.year}: income ${money(Number(d.totals.income))} against expenditure ${money(Number(d.totals.expense))} — a ${surplus >= 0 ? "surplus" : "deficit"} of ${money(Math.abs(surplus))}. Read off the general ledger's income and expense accounts; the expenditure budget and what has been committed and paid against it are shown beneath (commitment accounting).`}
      toolbar={<ReportToolbar headers={sheetHeaders} rows={sheetRows} filename={`income-expenditure-${d.year}`} title={`${spec.title} · ${d.year}`} />}
    />
  );
}
