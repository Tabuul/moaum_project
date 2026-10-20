/** V587: bulk inter-departmental transfer — the template's columns, the department's students written into it, a filled file read
 *  back by its column names (wherever the header row sits under the branding), and the shapes the API answers with. Node-tested. */

/** the template's columns: what the row says, under the names the database reads them by */
export const COLUMNS: [string, string][] = [
  ["matric_no", "Student Matriculation Number"], ["jamb_reg_no", "JAMB Number"], ["student", "Student Name"],
  ["old_faculty", "Old Faculty Code"], ["old_dept", "Old Department Code"], ["old_programme", "Old Programme Code"], ["old_level", "Old Level"],
  ["new_faculty", "New Faculty Code"], ["new_dept", "New Department Code"], ["new_programme", "New Programme Code"], ["new_level", "New Level"],
  ["effective_session", "Effective Session"], ["effective_semester", "Effective Semester"], ["transfer_type", "Transfer Type"],
  ["reason", "Reason"], ["approval_ref", "Approval Reference"], ["remarks", "Remarks"],
];

export interface TemplateStudent { matric_no: string | null; jamb_reg_no: string | null; student: string; faculty_code: string; dept_code: string; programme_code: string; programme: string; current_level: number; status: string }

/** the template's rows: each student's current placement in the OLD columns, the NEW ones left for the Academic Office to fill */
export function templateRows(students: TemplateStudent[], session: string): (string | number)[][] {
  return students.map((s) => [s.matric_no ?? "", s.jamb_reg_no ?? "", s.student, s.faculty_code, s.dept_code, s.programme_code, s.current_level,
    "", "", "", "", session, "", "INTER_DEPARTMENTAL", "", "", ""]);
}

const norm = (s: string) => s.toLowerCase().replace(/[^a-z]/g, "");
const KEYS = new Map(COLUMNS.flatMap(([k, label]) => [[norm(label), k], [norm(k), k]] as [string, string][]));
// the names a column may also carry
KEYS.set(norm("Matriculation Number"), "matric_no"); KEYS.set(norm("Matric No"), "matric_no"); KEYS.set(norm("JAMB"), "jamb_reg_no"); KEYS.set(norm("Name"), "student");

/** a filled file read back: the header row found (the branding sits above it), each row by its column names, empty rows left out */
export function readTransferSheet(grid: string[][]): { rows: Record<string, string>[]; problem: string | null } {
  const hi = grid.slice(0, 30).findIndex((r) => {
    const keys = r.map((c) => KEYS.get(norm(String(c ?? ""))));
    return keys.includes("matric_no") && keys.includes("new_programme");
  });
  if (hi < 0) return { rows: [], problem: "No header naming “Student Matriculation Number” and “New Programme Code” was found in the first 30 rows. Use the template." };
  const head = grid[hi].map((c) => KEYS.get(norm(String(c ?? ""))) ?? null);
  const rows: Record<string, string>[] = [];
  for (const r of grid.slice(hi + 1)) {
    const row: Record<string, string> = {};
    head.forEach((k, i) => { if (k) { const v = String(r[i] ?? "").trim(); if (v) row[k] = v; } });
    if (row.matric_no || row.jamb_reg_no) rows.push(row);
  }
  return { rows, problem: rows.length ? null : "The file has no row with a matriculation or JAMB number." };
}

export interface Place { faculty: string | null; dept: string | null; programme: string | null; level: number | null; programmeName?: string | null }
export interface Finding { code: string; text: string }
export interface CheckedRow {
  row: number; status: "VALID" | "WARNING" | "INVALID"; studentId: string | null; matchedBy: string | null; student: string | null; matricNo: string | null;
  current: Place | null; uploadedOld: Place; new: Place; transferType: string | null; session: string; reason: string | null; problems: Finding[]; warnings: (Finding | { code: string; text?: string })[];
}
export interface Validation { total: number; valid: number; warnings: number; invalid: number; duplicates: number; rows: CheckedRow[] }

export const STATUS: Record<CheckedRow["status"], [string, "ok" | "warn" | "bad"]> = {
  VALID: ["Valid", "ok"], WARNING: ["Valid — look at", "warn"], INVALID: ["Invalid", "bad"],
};

/** what a row says in one line: its problems, else its review points */
export function rowWords(r: Pick<CheckedRow, "problems" | "warnings">): string {
  if (r.problems.length) return r.problems.map((p) => p.text).join("; ");
  return r.warnings.map((w) => ("text" in w && w.text ? w.text : w.code)).join("; ");
}

/** the error report: every row as it was checked, its status and why */
export function errorReportRows(rows: CheckedRow[]): (string | number)[][] {
  return rows.map((r) => [r.row, r.student ?? "", r.matricNo ?? "", STATUS[r.status][0],
    r.current ? `${r.current.dept ?? ""} / ${r.current.programme ?? ""} / ${r.current.level ?? ""}` : "",
    `${r.uploadedOld.dept ?? ""} / ${r.uploadedOld.programme ?? ""} / ${r.uploadedOld.level ?? ""}`,
    `${r.new.dept ?? ""} / ${r.new.programme ?? ""} / ${r.new.level ?? ""}`, rowWords(r)]);
}
