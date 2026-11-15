/**
 * V698: the Staff ID Cards desk's addresses and words — the desk narrowed by faculty, unit, search and card, the print of every card
 * the narrowing holds, and what a bulk issue did. The API decides who is in service and issues the cards; this only says it. Node-tested.
 */
export interface StaffCardFilters { faculty: string | null; unit: string | null; q: string | null; card: string | null }

const query = (f: Partial<StaffCardFilters>, keys: (keyof StaffCardFilters)[]) => {
  const q = new URLSearchParams();
  for (const k of keys) { const v = f[k]; if (v) q.set(k, v); }
  return q.size ? `?${q.toString()}` : "";
};

/** the desk with its narrowing */
export const staffCardsHref = (f: Partial<StaffCardFilters>) => `/credentials/idcards/staff${query(f, ["faculty", "unit", "q", "card"])}`;

/** one PDF of every card in force the narrowing holds (whether a card is in force is not a narrowing of the print: it prints those that are) */
export const printAllHref = (f: Partial<StaffCardFilters>) => `/credentials/idcards/staff/pdf${query(f, ["faculty", "unit", "q"])}`;

/** what refused a card, in words */
export const REFUSAL_WORDS: Record<string, string> = {
  STAFF_CARD_NO_NUMBER: "no staff number on record",
  STAFF_CARD_ENDED: "has left the University",
  STAFF_CARD_LEFT: "is out of service in HR",
  STAFF_CARD_NO_OFFICE: "holds no office and is not on the HR staff register",
  STAFF_CARD_NO_PERSON: "no such member of staff",
};

/** a bulk issue's outcome in one line: "312 cards issued; 4 already had one; 2 refused (no staff number on record)" */
export function issueWords(tally: Record<string, number>): string {
  const issued = tally.ISSUED ?? 0;
  const had = tally.HAS_CARD ?? 0;
  const refused = Object.entries(tally).filter(([k]) => k !== "ISSUED" && k !== "HAS_CARD");
  const n = refused.reduce((a, [, v]) => a + v, 0);
  return [
    `${issued} card${issued === 1 ? "" : "s"} issued`,
    had ? `${had} already had one` : null,
    n ? `${n} refused (${refused.map(([k, v]) => `${v} ${REFUSAL_WORDS[k] ?? k.toLowerCase().replace(/_/g, " ")}`).join("; ")})` : null,
  ].filter(Boolean).join("; ");
}
