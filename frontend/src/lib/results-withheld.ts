/** V667: results are withheld semester by semester — a semester's results show once the fees up to it are paid (or the session's own
 *  rule releases them). The server redacts the marks and names each withheld semester with what is outstanding on it; this file only
 *  words it. Node-tested.
 *  V756: a Summer semester's results are never held by the school fees up to it — only by a balance owed for an earlier session, where
 *  the Bursar's scheme lets that balance block every result (finance.results_cleared) — so it is named the Summer semester and worded so. */

export interface WithheldSemester {
  session: string; semester: number; outstanding: number | string;
  /** V756: semester 3 was this student's Summer Semester (registration.is_summer_for) */
  summer?: boolean;
}

const SEM = ["", "first", "second", "third"];
const naira = (v: unknown) => `₦${Number(v ?? 0).toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const isSummer = (w: { semester: number; summer?: boolean }) => Boolean(w.summer) && Number(w.semester) === 3;
export const withheldName = (w: { session: string; semester: number; summer?: boolean }) =>
  `${w.session} ${isSummer(w) ? "Summer" : (SEM[w.semester] ?? `semester ${w.semester}`)} semester`;

/** V756: each withheld semester with whether it was the student's Summer — its own flag, else semester 3 of a session among the answer's
 *  summerSessions (the sessions whose semester 3 was this student's Summer) */
export function withSummer(list: WithheldSemester[] | null | undefined, summerSessions: readonly string[] | null | undefined): WithheldSemester[] {
  return (list ?? []).map((w) => ({ ...w, summer: w.summer ?? (Number(w.semester) === 3 && (summerSessions ?? []).includes(w.session)) }));
}

/** the withheld semester, if this one is */
export function withheldOf(list: WithheldSemester[] | null | undefined, session: string, semester: number): WithheldSemester | null {
  return (list ?? []).find((w) => w.session === session && w.semester === semester) ?? null;
}

/** the note over the results: which semesters wait for their fees, and what is outstanding on each */
export function withheldNote(list: WithheldSemester[] | null | undefined): { title: string; body: string } | null {
  const ws = list ?? [];
  if (!ws.length) return null;
  // V756: a Summer's outstanding figure is its session's fees, not the earlier balance that holds it, so it is not quoted
  const parts = ws.map((w) => isSummer(w) ? `${withheldName(w)} (held by a balance owed for an earlier session)`
    : Number(w.outstanding) >= 1 ? `${withheldName(w)} (${naira(w.outstanding)} outstanding)` : withheldName(w));
  const title = ws.length === 1
    ? isSummer(ws[0])
      ? `Your ${withheldName(ws[0])} results are withheld while a balance from an earlier session is owed`
      : `Your ${withheldName(ws[0])} results are withheld until its school fees are paid`
    : ws.some(isSummer)
      ? `Results of ${ws.length} semesters are withheld until the fees owed are paid`
      : `Results of ${ws.length} semesters are withheld until their school fees are paid`;
  const body = `Withheld: ${parts.join("; ")}. They are released the moment the payment is confirmed; the semesters you have paid for are shown.`;
  return { title, body };
}

/** the line where a withheld semester's results would be */
export function withheldLine(w: WithheldSemester): string {
  if (isSummer(w)) {
    return "Withheld while a balance from an earlier session is owed: under the Bursar's rule on arrears, the Summer semester's results are released once that balance is paid.";
  }
  return Number(w.outstanding) >= 1
    ? `Withheld until the school fees up to the ${withheldName(w).replace(/^\S+ /, "")} are paid: ${naira(w.outstanding)} outstanding.`
    : `Withheld until the school fees up to the ${withheldName(w).replace(/^\S+ /, "")} are paid.`;
}
