/** The statutory returns the portal produces, and the plumbing they share.
 *  A return is a branded, printable view of the register (ReportDoc) plus the
 *  same rows as CSV. The data comes from the reports API and the admissions
 *  cycle; nothing here writes. */

export type Align = "left" | "right" | "center";

/** one column of a report table: how it is labelled, aligned, and whether it is summed in the totals row */
export interface ReportColumn {
  key: string;
  label: string;
  align?: Align;
  money?: boolean;
  total?: boolean;
}

/** the reports the portal offers, keyed by slug — used by the index screen and the view pages */
export interface ReportSpec {
  slug: string;
  title: string;
  subtitle: string;
  /** the offices whose sidebar carries this return (activeOffice codes) */
  offices: string[];
  /** who owns the return, and how often it is taken — the Standard reports table (proto gReports) */
  owner: string;
  frequency: string;
  /** what the return is for, in the regulator's or management's own words */
  purpose: string;
}

export const REPORTS: ReportSpec[] = [
  {
    slug: "admissions",
    title: "Admissions return",
    subtitle: "Applications, offers and acceptances by faculty and programme",
    offices: ["academic", "registrar", "dregistrar", "records", "dvc", "vc", "ict", "admin", "super"],
    owner: "Registry", frequency: "Per session", purpose: "JAMB / CAPS and Council",
  },
  {
    slug: "enrolment",
    title: "Enrolment by programme, level and sex",
    subtitle: "The session's cohort by faculty, programme and level, split by sex",
    offices: ["academic", "registrar", "dregistrar", "records", "dvc", "vc", "ict", "admin", "super"],
    owner: "Registry", frequency: "Per session", purpose: "NUC statutory return",
  },
  {
    slug: "registration",
    title: "Registration & fees return",
    subtitle: "Not-registered students by faculty and programme, split into fee-blocked and cleared-but-idle",
    offices: ["academic", "registrar", "dregistrar", "records", "bursar", "dvc", "vc", "ict", "admin", "super"],
    owner: "Registry", frequency: "Per semester", purpose: "Management",
  },
  {
    slug: "carryovers",
    title: "Carryover return",
    subtitle: "Outstanding carryovers by faculty, programme and course — the re-sit load, as at today",
    offices: ["academic", "registrar", "dregistrar", "records", "dvc", "vc", "ict", "admin", "super"],
    owner: "Exams & Records", frequency: "Per session", purpose: "Senate",
  },
  {
    slug: "revenue",
    title: "IGR collections by revenue head",
    subtitle: "Fees confirmed for the session, by category — the University's internally generated revenue",
    offices: ["bursar", "registrar", "dregistrar", "academic", "audit", "ict", "admin", "super", "vc", "dvc"],
    owner: "Bursary", frequency: "Monthly", purpose: "State treasury return",
  },
  {
    slug: "funding",
    title: "Funding return",
    subtitle: "Student funding by source and nature, and the wallet cash flow",
    offices: ["bursar", "audit", "deputyaudit", "registrar", "dregistrar", "academic", "ict", "admin", "super", "vc", "dvc"],
    owner: "Bursary", frequency: "Per session", purpose: "Management",
  },
  {
    slug: "expenditure",
    title: "Expenditure by cost centre",
    subtitle: "The financial year's budget, commitments, spending and balance by cost centre",
    offices: ["bursar", "audit", "deputyaudit", "ict", "admin", "super", "vc", "dvc"],
    owner: "Bursary", frequency: "Monthly", purpose: "Council finance committee",
  },
  {
    slug: "income-expenditure",
    title: "Income & expenditure statement",
    subtitle: "Every income and expense head for the financial year, the surplus or deficit, and spending against budget",
    offices: ["bursar", "audit", "deputyaudit", "ict", "admin", "super", "vc", "dvc"],
    owner: "Bursary", frequency: "Monthly", purpose: "Council and management",
  },
];

export function reportFor(slug: string): ReportSpec | undefined {
  return REPORTS.find((r) => r.slug === slug);
}

const OFFICE_LABELS: Record<string, string> = {
  academic: "Academic Affairs", registrar: "Registry", dregistrar: "Registry",
  records: "Exams & Records", bursar: "Bursary", audit: "Internal Audit",
  ict: "ICT Directorate", admin: "Administration", super: "System Administration",
  vc: "Vice-Chancellor's Office", dvc: "Deputy Vice-Chancellor's Office",
};

/** the readable name of an office, for the return's footing; falls back to the code */
export function officeLabel(code: string | null | undefined): string {
  if (!code) return "the University";
  return OFFICE_LABELS[code] ?? code;
}

/** one field escaped for CSV: quote when it carries a comma, quote or newline; double any inner quote */
function cell(v: string | number | null | undefined): string {
  const s = v == null ? "" : String(v);
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/** a CSV with a BOM so Excel reads UTF-8, CRLF line endings, and a header row */
export function toCsv(headers: string[], rows: (string | number | null | undefined)[][]): string {
  const lines = [headers.map(cell).join(","), ...rows.map((r) => r.map(cell).join(","))];
  return "﻿" + lines.join("\r\n") + "\r\n";
}

/** a filename-safe slug of a session, e.g. "2026/2027" → "2026-2027" */
export function sessionSlug(session: string): string {
  return session.replace(/[^0-9A-Za-z]+/g, "-");
}
