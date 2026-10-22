/** The school fees report: for a session, each faculty, department and level — students paid in full, students owing, amount paid,
 *  amount owing — and the grand total. The shapes /api/v1/finance/fee-report returns, and the rows the table and the downloads take. */

export interface FeeReportLine {
  faculty_code: string; faculty: string; dept_code: string; department: string; level: number | null;
  students: number; paid_students: number; owing_students: number; part_paid: number; no_fee: number;
  amount_due: number | string; amount_paid: number | string; amount_owing: number | string;
  /** V637: of those, the students charged the spillover lines (SP1/SP2), what they owe and paid — spillover fees shown apart */
  spill_students?: number; spill_due?: number | string; spill_paid?: number | string; spill_owing?: number | string;
}
export interface FeeReportTotal {
  students: number; paid_students: number; owing_students: number; part_paid: number; no_fee: number;
  amount_due: number | string; amount_paid: number | string; amount_owing: number | string;
  spill_students?: number; spill_due?: number | string; spill_paid?: number | string; spill_owing?: number | string;
}
export interface FeeReport {
  session: string; sessions: string[]; faculty?: string | null; department?: string | null;
  rows: FeeReportLine[]; total: FeeReportTotal; generatedAt: string;
}

/** the columns as the Bursary asked for them; S/N first, as every download */
export const FEE_REPORT_HEADERS = ["S/N", "Session", "Faculty", "Department", "Level", "Students paid", "Students owing", "Amount paid (₦)", "Amount owing (₦)",
  "Spillover students", "Spillover paid (₦)", "Spillover owing (₦)"];

const num = (v: number | string | null | undefined) => Number(v ?? 0);
/** naira to the kobo, as a number a spreadsheet can add */
export const naira = (v: number | string | null | undefined) => Math.round(num(v) * 100) / 100;

/** the report as rows for the downloads: numbered lines, then the grand total (no number) */
export function feeReportRows(r: Pick<FeeReport, "session" | "rows" | "total">): (string | number)[][] {
  const lines = r.rows.map((x, i) => [i + 1, r.session, x.faculty, x.department, x.level ?? "", num(x.paid_students), num(x.owing_students),
    naira(x.amount_paid), naira(x.amount_owing), num(x.spill_students), naira(x.spill_paid), naira(x.spill_owing)]);
  return [...lines, ["", "", "Grand total", "", "", num(r.total.paid_students), num(r.total.owing_students), naira(r.total.amount_paid), naira(r.total.amount_owing),
    num(r.total.spill_students), naira(r.total.spill_paid), naira(r.total.spill_owing)]];
}

/** the totals of the lines shown, so the grand total always adds up to what is on the page */
export function sumLines(rows: FeeReportLine[]): FeeReportTotal {
  return rows.reduce<FeeReportTotal>((t, x) => ({
    students: t.students + num(x.students), paid_students: t.paid_students + num(x.paid_students), owing_students: t.owing_students + num(x.owing_students),
    part_paid: t.part_paid + num(x.part_paid), no_fee: t.no_fee + num(x.no_fee),
    amount_due: naira(num(t.amount_due) + num(x.amount_due)), amount_paid: naira(num(t.amount_paid) + num(x.amount_paid)),
    amount_owing: naira(num(t.amount_owing) + num(x.amount_owing)),
  }), { students: 0, paid_students: 0, owing_students: 0, part_paid: 0, no_fee: 0, amount_due: 0, amount_paid: 0, amount_owing: 0 });
}

/** the page's own address for a session and scope: the link to share */
export function feeReportHref(session: string, fac: string, dept: string): string {
  const q = new URLSearchParams();
  if (session) q.set("session", session);
  if (fac) q.set("fac", fac);
  if (dept) q.set("dept", dept);
  return `/finance/fee-report${q.toString() ? `?${q.toString()}` : ""}`;
}
