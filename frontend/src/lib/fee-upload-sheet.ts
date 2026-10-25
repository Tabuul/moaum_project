/**
 * V653: the session's fee lines as a one-row-per-fee sheet the structure upload reads back (lib/fee-matrix parseFeeFlat): one row
 * a line, the faculty by code, the programme by code, the level, the PG stage by its label (800 B — Year 2), fresh or returning
 * for a line that names a category without a stage, the entry mode, the semester, indigeneship, the spillover year, the fee group,
 * the kind, the item and the amount. Uploaded back unchanged, every line reads "the same"; an amount or a stage changed reads as
 * that change in the preview before anything is replaced.
 */

export interface UploadLine {
  item: string; amount: number | string; level: number | null; entry_mode: string | null; faculty_code: string | null; programme_code: string | null;
  programme_name?: string | null; fee_group: string | null; semester: number | null; indigene: string | null; spillover: boolean; spill_year?: number | null;
  kind?: string | null; pg_stage?: string | null; pg_stage_label?: string | null; fee_category?: string | null; status?: string | null;
}

export const UPLOAD_SHEET_HEADERS = ["Faculty", "Programme code", "Programme", "Level", "PG stage", "Fresh or returning", "Entry mode", "Semester", "Indigene",
  "Spillover", "Fee group", "Kind", "Item", "Amount"];

const KIND: Record<string, string> = { LATE_PAYMENT: "Late payment", LATE_REGISTRATION: "Late registration" };

/** the lines in force, in the order the report reads them: University-wide first, then by faculty, programme, level and stage */
export function uploadSheetRows(lines: UploadLine[]): (string | number)[][] {
  const live = lines.filter((l) => (l.status ?? "ACTIVE") === "ACTIVE");
  const key = (l: UploadLine) => [l.faculty_code ?? "", l.programme_code ?? "", String(l.semester ?? 0), String(l.spillover ? 9999 : l.level ?? 0).padStart(4, "0"),
    l.pg_stage ?? "", l.entry_mode ?? "", l.indigene ?? "", l.item].join("|");
  return [...live].sort((a, b) => (key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0)).map((l) => [
    l.faculty_code ?? "All faculties",
    l.programme_code ?? "",
    l.programme_name ?? (l.programme_code ? "" : "All programmes"),
    l.level ?? "",
    l.pg_stage ? l.pg_stage_label ?? l.pg_stage : "",
    !l.pg_stage && l.fee_category ? (l.fee_category === "FRESH" ? "Fresh" : "Returning") : "",
    l.entry_mode ?? "",
    l.semester ?? "",
    l.indigene === "INDIGENE" ? "Indigene" : l.indigene === "NON_INDIGENE" ? "Non-indigene" : "",
    l.spill_year ? `SP${l.spill_year}` : l.spillover ? "Yes" : "",
    l.fee_group ?? "",
    KIND[l.kind ?? ""] ?? "",
    l.item,
    Number(l.amount),
  ]);
}
