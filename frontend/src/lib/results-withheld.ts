/** V667: results are withheld semester by semester — a semester's results show once the fees up to it are paid (or the session's own
 *  rule releases them). The server redacts the marks and names each withheld semester with what is outstanding on it; this file only
 *  words it. Node-tested. */

export interface WithheldSemester { session: string; semester: number; outstanding: number | string }

const SEM = ["", "first", "second", "third"];
const naira = (v: unknown) => `₦${Number(v ?? 0).toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
export const withheldName = (w: { session: string; semester: number }) => `${w.session} ${SEM[w.semester] ?? `semester ${w.semester}`} semester`;

/** the withheld semester, if this one is */
export function withheldOf(list: WithheldSemester[] | null | undefined, session: string, semester: number): WithheldSemester | null {
  return (list ?? []).find((w) => w.session === session && w.semester === semester) ?? null;
}

/** the note over the results: which semesters wait for their fees, and what is outstanding on each */
export function withheldNote(list: WithheldSemester[] | null | undefined): { title: string; body: string } | null {
  const ws = list ?? [];
  if (!ws.length) return null;
  const parts = ws.map((w) => Number(w.outstanding) >= 1 ? `${withheldName(w)} (${naira(w.outstanding)} outstanding)` : withheldName(w));
  const title = ws.length === 1
    ? `Your ${withheldName(ws[0])} results are withheld until its school fees are paid`
    : `Results of ${ws.length} semesters are withheld until their school fees are paid`;
  const body = `Withheld: ${parts.join("; ")}. They are released the moment the payment is confirmed; the semesters you have paid for are shown.`;
  return { title, body };
}

/** the line where a withheld semester's results would be */
export function withheldLine(w: WithheldSemester): string {
  return Number(w.outstanding) >= 1
    ? `Withheld until the school fees up to the ${withheldName(w).replace(/^\S+ /, "")} are paid: ${naira(w.outstanding)} outstanding.`
    : `Withheld until the school fees up to the ${withheldName(w).replace(/^\S+ /, "")} are paid.`;
}
