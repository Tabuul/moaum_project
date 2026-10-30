/** Reading a hostel workbook for the import (V290, V705): which column is which, which rows are a footer, and the hostel's
 *  gender and location from another sheet of the same workbook. The University's own file (the old portal's export) calls a
 *  hostel a "Block": Block ID and Block Name name the hostel, and its gender is on the Hostel Blocks sheet. Pure functions,
 *  so the screen and its tests read the file alike. */

export type FieldKey = "hall_code" | "hall" | "hall_ref" | "block" | "floor" | "room" | "capacity" | "category" | "room_type" | "gender" | "hall_kind" | "location";

export const FIELDS: [FieldKey, string, RegExp][] = [
  ["hall_code", "Hostel code", /^(hostel|hall)[ _-]?(code|id)$|^code$/i],
  ["hall", "Hostel name", /^(hostel|hall)([ _-]?name)?$|^name$/i],
  ["hall_ref", "Hostel ID on the old portal", /^(old[ _-]?portal[ _-]?)?(hostel|hall)[ _-]?ref$|^legacy[ _-]?(id|ref)$/i],
  ["block", "Block / wing", /^(block|wing)/i],
  ["floor", "Floor", /^floor|^level$/i],
  ["room", "Room number", /^room([ _-]?(no|number|name))?$/i],
  ["capacity", "Capacity (beds)", /^(capacity|beds?|bed[ _-]?space|spaces?|occupancy)$/i],
  ["category", "Category", /^(category|type of room|use|purpose|reserved)/i],
  ["room_type", "Room type", /^room[ _-]?type$/i],
  ["gender", "Gender", /^(gender|sex)$/i],
  ["hall_kind", "Hostel kind", /^(kind|hostel[ _-]?kind)$/i],
  ["location", "Location", /^(location|campus|site)$/i],
];

const BLOCK_NAME = /^block[ _-]?name$/i;
const BLOCK_ID = /^block[ _-]?(id|no|number|code)$/i;
const ANY_ID = /^(block|hostel|hall)[ _-]?(id|no|number|code)$/i;

/** the header row: the first of the top fifteen with two or more recognised headings */
export function guessHeader(rows: string[][]): number {
  for (let i = 0; i < Math.min(rows.length, 15); i++) {
    const hits = rows[i].filter((c) => FIELDS.some(([, , re]) => re.test(c.trim())) || BLOCK_NAME.test(c.trim())).length;
    if (hits >= 2) return i;
  }
  return 0;
}

/** each field's column; the old portal's layout — "Block Name" and "Block ID" with no hostel column — reads the block as the hostel */
export function autoMap(head: string[]): Partial<Record<FieldKey, number>> {
  const m: Partial<Record<FieldKey, number>> = {};
  FIELDS.forEach(([k, , re]) => { const i = head.findIndex((c) => re.test(c.trim())); if (i >= 0) m[k] = i; });
  const blockName = head.findIndex((c) => BLOCK_NAME.test(c.trim()));
  if (m.hall === undefined && m.hall_code === undefined && blockName >= 0) {
    m.hall = blockName;
    const id = head.findIndex((c) => BLOCK_ID.test(c.trim()));
    if (id >= 0) m.hall_ref = id;
    delete m.block;
  }
  return m;
}

/** a footer under the data — "Total", "Source: …" — is not a room */
export function isFooter(row: string[]): boolean {
  const first = row.find((c) => c.trim() !== "")?.trim() ?? "";
  return /^(total|totals|grand total|source\b|note\b|notes\b)/i.test(first);
}

/** an ID as a workbook may write it: "1", "1.0", " 01 " are the hostel 1 */
export function cleanRef(v: string | undefined): string {
  const t = (v ?? "").trim();
  if (/^\d+(\.0+)?$/.test(t)) return String(Number(t));
  return t;
}

export interface HallDetails { sheet: string; byRef: Record<string, { gender: string; location: string }> }

/** the hostels' gender and location from another sheet that names them by the same ID (the old portal's Hostel Blocks sheet) */
export function hallDetailsFrom(sheets: { name: string; rows: string[][] }[], except: number): HallDetails | null {
  for (let s = 0; s < sheets.length; s++) {
    if (s === except) continue;
    const rows = sheets[s].rows;
    const h = guessHeader(rows);
    const head = rows[h] ?? [];
    const id = head.findIndex((c) => ANY_ID.test(c.trim()));
    const gender = head.findIndex((c) => /^(gender|sex)$/i.test(c.trim()));
    if (id < 0 || gender < 0) continue;
    const location = head.findIndex((c) => /^(location|campus|site)$/i.test(c.trim()));
    const byRef: HallDetails["byRef"] = {};
    for (const r of rows.slice(h + 1)) {
      const ref = cleanRef(r[id]);
      const g = (r[gender] ?? "").trim();
      // a note under the table ("Block Capacity comes from …") has no gender: it is not a hostel
      if (!ref || !g || isFooter(r)) continue;
      byRef[ref] = { gender: g, location: location >= 0 ? (r[location] ?? "").trim() : "" };
    }
    if (Object.keys(byRef).length) return { sheet: sheets[s].name, byRef };
  }
  return null;
}

/** the rows sent to the server: each mapped field, the hostel's ID cleaned, and its gender and location from the other sheet */
export function importRecords(body: string[][], map: Partial<Record<FieldKey, number>>, details: HallDetails | null): Record<string, string>[] {
  return body.map((r) => {
    const o: Record<string, string> = {};
    for (const [k] of FIELDS) { const i = map[k]; if (i !== undefined && i >= 0) o[k] = r[i] ?? ""; }
    if (o.hall_ref !== undefined) o.hall_ref = cleanRef(o.hall_ref);
    const d = o.hall_ref ? details?.byRef[o.hall_ref] : undefined;
    if (d) {
      if (d.gender && !o.gender) o.hall_sex = d.gender;
      if (d.location && !o.location) o.location = d.location;
    }
    return o;
  });
}
