/** An applicant's email and phone as a spreadsheet cell holds them (V296) — the same reading the database makes
 *  (admissions.first_email, admissions.first_mobile), so the desk can say before the upload which rows carry a usable
 *  contact and which will stand on a placeholder. */

/** the migration's placeholder email (V168): never a real address */
export const PLACEHOLDER_EMAIL = /@migrate\.moau\.local$/;

/** the first usable email address in a cell, lower-cased: a second address, "mailto:", a name in angle brackets and trailing
 *  punctuation set aside; null when there is none */
export function firstEmail(cell: string | null | undefined): string | null {
  for (const raw of String(cell ?? "").split(/[\s,;/|<>()"']+/)) {
    const t = raw.replace(/^mailto:/i, "").replace(/[.,;:]+$/, "").toLowerCase();
    if (/^[^\s@]+@[^\s@]+\.[a-z]{2,}$/.test(t) && !PLACEHOLDER_EMAIL.test(t)) return t;
  }
  return null;
}

/** the first Nigerian mobile number in a cell as 0XXXXXXXXXX — 070, 080, 081, 090 or 091, written with or without the 0 (as a
 *  spreadsheet keeps it), as +234 or 234, with spaces or dashes, the first of several; null when there is none */
export function firstMobile(cell: string | null | undefined): string | null {
  const m = /(?<![0-9])((?:\+?234[\s-]*0?|0)?[\s-]*[789][01](?:[\s-]*[0-9]){8})(?![0-9])/.exec(String(cell ?? ""));
  if (!m) return null;
  return "0" + m[1].replace(/[^0-9]/g, "").slice(-10);
}
