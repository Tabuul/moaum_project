/**
 * V572: student phone numbers and e-mail addresses uploaded by the Registry and the departments. The file is the template the page
 * gives (the students missing a contact, with a Phone and an E-mail column to fill) or any sheet with a student-number column and
 * a phone or e-mail column; the header row is found within the first rows (the template's crest and title sit above it). What a
 * row does — filled, kept, refused — is the server's (people.load_contacts); the page says what the server answered.
 */

export interface ContactRow { number: string; phone: string; email: string }

export interface ContactResult {
  row_no: number; number_in: string; phone_in: string; email_in: string; student_id: string | null; name: string | null; number: string | null;
  programme: string | null; phone: string | null; email: string | null; phone_outcome: string; email_outcome: string; outcome: string; message: string;
}

export interface ContactLoad {
  scope: string; total: number; counts: Record<string, number>; fields: { phones: number; emails: number }; rows: ContactResult[]; uploadId?: string;
}

/** the template's columns, in order (S/N is added by the workbook) */
export const TEMPLATE_HEAD = ["Student number", "Name", "Faculty", "Department", "Programme", "Level", "Missing", "Phone", "E-mail"];

/** the row's outcome in words, and its pill */
export const OUTCOME: Record<string, [string, "ok" | "info" | "warn" | "bad" | "grey"]> = {
  FILLED: ["Filled", "ok"], ALREADY: ["Held already", "grey"], REFUSED: ["Refused", "bad"], NO_STUDENT: ["No such student", "bad"],
  AMBIGUOUS: ["More than one student", "bad"], OUTSIDE_SCOPE: ["Outside your reach", "bad"], DUPLICATE_ROW: ["Student repeated", "warn"],
  INCOMPLETE: ["Incomplete row", "warn"],
};

/** what is missing, in the template's words */
export function missingWord(noPhone: boolean, noEmail: boolean): string {
  return noPhone && noEmail ? "Phone and e-mail" : noPhone ? "Phone" : noEmail ? "E-mail" : "";
}

const norm = (c: unknown) => String(c ?? "").trim().toLowerCase().replace(/\s+/g, " ");
const isPhone = (h: string) => /\b(phone|mobile|gsm|telephone|tel)\b/.test(h);
const isEmail = (h: string) => /\be-?mail\b/.test(h);
const isNumber = (h: string) =>
  !isPhone(h) && !isEmail(h) && (/\b(matric|matriculation|admission|jamb|reg)\b/.test(h) || /^(student )?(number|no\.?|id)$/.test(h));

/**
 * The rows of a sheet: the header row found among the first fifteen (a student-number column and a phone or e-mail column), each
 * later row with a number or a contact read as (number, phone, e-mail). A phone a spreadsheet wrote as a number (8031234567, or
 * 8.03123E+9 kept to the digit) is passed as its digits; the server puts back a dropped leading 0.
 */
export function contactRows(grid: unknown[][]): { rows: ContactRow[]; error: string | null } {
  for (let h = 0; h < Math.min(15, grid.length); h++) {
    const head = (grid[h] ?? []).map(norm);
    const ni = head.findIndex(isNumber);
    const pi = head.findIndex(isPhone);
    const ei = head.findIndex(isEmail);
    if (ni < 0 || (pi < 0 && ei < 0)) continue;
    const rows = grid.slice(h + 1).map((g) => ({
      number: String(g?.[ni] ?? "").trim(),
      phone: pi < 0 ? "" : phoneText(g?.[pi]),
      email: ei < 0 ? "" : String(g?.[ei] ?? "").trim(),
    })).filter((r) => r.number || r.phone || r.email);
    return rows.length ? { rows, error: null } : { rows: [], error: "The file has its headings but no rows below them." };
  }
  return { rows: [], error: "The file needs a student number column (matriculation, admission or JAMB number) and a Phone or E-mail column." };
}

/** a phone cell as text: a number written in scientific form (8.031234567E9) back to its digits */
function phoneText(v: unknown): string {
  const s = String(v ?? "").trim();
  if (/^\d(\.\d+)?e\+?\d+$/i.test(s)) {
    const n = Number(s);
    if (Number.isFinite(n) && Number.isInteger(n)) return String(n);
  }
  return s;
}
