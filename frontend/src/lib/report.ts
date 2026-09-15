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
}

export const REPORTS: ReportSpec[] = [
  {
    slug: "admissions",
    title: "Admissions return",
    subtitle: "Applications, offers and acceptances by faculty and programme",
    offices: ["academic", "registrar", "dregistrar", "records", "dvc", "vc", "ict", "admin", "super"],
  },
  {
    slug: "enrolment",
    title: "Enrolment return",
    subtitle: "The session's cohort by faculty, programme and level, split by sex",
    offices: ["academic", "registrar", "dregistrar", "records", "dvc", "vc", "ict", "admin", "super"],
  },
  {
    slug: "registration",
    title: "Registration & fees return",
    subtitle: "Not-registered students by faculty and programme, split into fee-blocked and cleared-but-idle",
    offices: ["academic", "registrar", "dregistrar", "records", "bursar", "dvc", "vc", "ict", "admin", "super"],
  },
  {
    slug: "carryovers",
    title: "Carryover return",
    subtitle: "Outstanding carryovers by faculty, programme and course — the re-sit load, as at today",
    offices: ["academic", "registrar", "dregistrar", "records", "dvc", "vc", "ict", "admin", "super"],
  },
  {
    slug: "revenue",
    title: "Revenue return",
    subtitle: "Fees confirmed for the session, by category",
    offices: ["bursar", "registrar", "dregistrar", "academic", "audit", "ict", "admin", "super", "vc", "dvc"],
  },
  {
    slug: "funding",
    title: "Funding return",
    subtitle: "Student funding by source and nature, and the wallet cash flow",
    offices: ["bursar", "audit", "deputyaudit", "registrar", "dregistrar", "academic", "ict", "admin", "super", "vc", "dvc"],
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
