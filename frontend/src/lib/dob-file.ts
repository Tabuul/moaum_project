/** V721: the old portal's date-of-birth file read in the browser — a matriculation or JAMB number column and a date-of-birth column
 *  found by name, the rows handed to the register's reader as written (the server reads the date day first and recognises the old
 *  misreading); the register's answer shown row by row. */

export interface DobFileRow { row: number; matric: string; jamb: string; dob: string }

const MATRIC = [/matric/, /reg\.?\s*(no|number)/, /registration/, /mat\.?\s*no/, /matno/];
const JAMB = [/jamb/, /utme\s*reg/];
const DOB = [/birth/, /^dob$/, /d\.o\.b/, /date\s*of\s*birth/];

const isJamb = (h: string) => JAMB.some((n) => n.test(h));
/** the first header the names match; a JAMB column is never read as the matriculation column ("JAMB Reg Number" says reg number too) */
const find = (header: string[], names: RegExp[], notJamb = false) => header.findIndex((h) => (!notJamb || !isJamb(h)) && names.some((n) => n.test(h)));

/** the rows of a sheet: {row, matric, jamb, dob}; an error when neither number column nor the date column is there */
export function dobFileRows(grid: string[][]): { rows: DobFileRow[]; empty: number } | { err: string } {
  if (!grid.length) return { err: "The file has no rows in it." };
  const header = grid[0].map((h) => String(h ?? "").trim().toLowerCase());
  const m = find(header, MATRIC, true), j = find(header, JAMB), d = find(header, DOB);
  if ((m < 0 && j < 0) || d < 0) {
    return { err: `The file needs a matriculation (or JAMB) number column and a date-of-birth column. The header read was: ${grid[0].slice(0, 8).join(", ")}` };
  }
  const rows: DobFileRow[] = [];
  let empty = 0;
  for (let i = 1; i < grid.length; i++) {
    const r = grid[i];
    const matric = m >= 0 ? String(r[m] ?? "").trim() : "";
    const jamb = j >= 0 ? String(r[j] ?? "").trim() : "";
    const dob = String(r[d] ?? "").trim();
    if (!matric && !jamb) { if (r.some((c) => String(c ?? "").trim())) empty++; continue; }
    rows.push({ row: i + 1, matric, jamb, dob });
  }
  return { rows, empty };
}

export type DobAction = "AGREES" | "FILLED" | "CORRECTED" | "DIFFERS" | "UNREADABLE" | "NO_STUDENT" | "AMBIGUOUS";

export interface DobResultRow {
  row_no: number; matric_no: string | null; jamb_reg_no: string | null; student_id: string | null; surname: string | null; other_names: string | null;
  programme_code: string | null; file_text: string | null; file_date: string | null; held: string | null; form_value: string | null; action: DobAction;
}
export interface DobResult { applied: boolean; total: number; counts: Partial<Record<DobAction, number>>; rows: DobResultRow[] }

export const ACTION_WORDS: Record<DobAction, { word: string; done: string; kind: "ok" | "info" | "bad" | "grey" | "warn" }> = {
  AGREES: { word: "Agrees", done: "Agrees", kind: "ok" },
  FILLED: { word: "To fill", done: "Filled from the file", kind: "info" },
  CORRECTED: { word: "To correct (held the misreading)", done: "Corrected", kind: "info" },
  DIFFERS: { word: "Differs — for the Registry", done: "Differs — left", kind: "bad" },
  UNREADABLE: { word: "No date in the file", done: "No date in the file", kind: "bad" },
  NO_STUDENT: { word: "No record under that number", done: "No record under that number", kind: "grey" },
  AMBIGUOUS: { word: "Two records under that number", done: "Two records under that number", kind: "warn" },
};

/** what a commit would write, or wrote */
export const pendingOf = (r: DobResult) => (r.counts.FILLED ?? 0) + (r.counts.CORRECTED ?? 0);
