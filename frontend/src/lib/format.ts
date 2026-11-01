/**
 * Pure formatters, safe to call from either a server component or a client one.
 *
 * These once lived in components/proto/blocks.tsx, which is "use client"; a
 * plain function exported from a client module cannot be *called* from a server
 * component (only rendered as a component or passed as a prop), so a server
 * dashboard that called money()/day() threw at render. They live here, with no
 * "use client", and blocks.tsx re-exports them so existing client imports keep
 * working unchanged.
 */

/** the money helper: ₦ and thousands */
export function money(n: number): string {
  return "₦" + n.toLocaleString("en-NG");
}

const MONTH_NO: Record<string, number> = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12 };
const fullYear = (y: number) => (y < 100 ? y + (y > 30 ? 1900 : 2000) : y);
const utc = (y: number, m: number, d: number): Date | null => {
  const t = new Date(Date.UTC(y, m - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d ? t : null;
};

/** V717: a date as Nigeria writes it, read day first — "12-09-2003" is 12 September 2003, never 9 December. ISO (with or without a
 *  time), day/month/year in figures with -, / or . and a two- or four-digit year, the month in words on either side ("12 Sep 2003",
 *  "September 12, 2003"); month first only when the figures allow nothing else ("09-13-2003"); null when it cannot be read.
 *  JavaScript's own Date reads "12-09-2003" month first, which is why nothing here hands it such text. The Date returned is at
 *  midnight UTC, so the calendar day is read back with the UTC getters (or formatted with timeZone: "UTC"). */
export function readDate(text: string | null | undefined): Date | null {
  const s = String(text ?? "").trim();
  if (!s) return null;
  let m = /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[T ].*)?$/.exec(s);
  if (m) {
    const t = utc(+m[1], +m[2], +m[3]);
    if (!t) return null;
    if (/[T ]/.test(s)) { const full = new Date(s); return Number.isNaN(full.getTime()) ? t : full; }
    return t;
  }
  m = /^(\d{1,2})[-/. ](\d{1,2})[-/. ](\d{2}|\d{4})$/.exec(s);
  if (m) {
    const a = +m[1], b = +m[2], y = fullYear(+m[3]);
    return a <= 12 && b > 12 ? utc(y, a, b) : utc(y, b, a);
  }
  m = /^(\d{1,2})(?:st|nd|rd|th)?[-/ ,.]+([A-Za-z]{3,9})\.?[-/ ,.]+(\d{2}|\d{4})$/.exec(s);
  if (m) { const mo = MONTH_NO[m[2].slice(0, 3).toLowerCase()]; return mo ? utc(fullYear(+m[3]), mo, +m[1]) : null; }
  m = /^([A-Za-z]{3,9})\.?[-/ ,.]+(\d{1,2})(?:st|nd|rd|th)?[-/ ,.]+(\d{2}|\d{4})$/.exec(s);
  if (m) { const mo = MONTH_NO[m[1].slice(0, 3).toLowerCase()]; return mo ? utc(fullYear(+m[3]), mo, +m[2]) : null; }
  return null;
}

/** V717: the same date as the API writes one, YYYY-MM-DD; "" when the text cannot be read */
export function isoDay(text: string | null | undefined): string {
  const d = readDate(text);
  return d ? `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}` : "";
}

/** V717: full years from a date of birth to a day (today unless given); null when the date cannot be read or is absurd */
export function ageAt(dob: string | null | undefined, on: Date = new Date()): number | null {
  const d = readDate(dob);
  if (!d) return null;
  let a = on.getUTCFullYear() - d.getUTCFullYear();
  if (on.getUTCMonth() < d.getUTCMonth() || (on.getUTCMonth() === d.getUTCMonth() && on.getUTCDate() < d.getUTCDate())) a--;
  return a >= 0 && a < 130 ? a : null;
}

/** a date as the prototype prints one: "12 Oct 2026" — read day first (V717: "12-09-2003" prints 12 Sep 2003) */
export function day(iso: string | null | undefined, withYear = true): string {
  if (!iso) return "—";
  const d = readDate(iso);
  if (!d) return iso;
  const timed = /\d[T ]\d/.test(iso);   // an instant keeps the local reading; a plain day is read as a calendar day
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: withYear ? "numeric" : undefined, ...(timed ? {} : { timeZone: "UTC" }) });
}
