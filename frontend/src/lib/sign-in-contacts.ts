/**
 * V599: the e-mails and phones the sign-in help saved to student records that held none (V596). They reach no notice until the
 * student confirms them with a code at sign-in or the desk confirms them with the student; the desk refuses one that is not the
 * student's. Beside them, for the Head of the desk and the Director of ICT, the student numbers checked on the sign-in page by
 * connection, with the day's figure past which a connection is refused and the different numbers at which the Head is told.
 */

export interface SignInContact {
  student_id: string; name: string; number: string | null; programme: string | null; department: string | null; faculty: string | null;
  level: number | null; status: string; field: "EMAIL" | "PHONE"; value: string;
  ticket_id: string | null; ticket_number: string | null; ticket_status: string | null; asked_by: string | null; asked_email: string | null; saved_at: string;
}
export interface SignInContacts { rows: SignInContact[]; mayDecide: boolean; scope: string | null; head: boolean }
export interface LookupRow { source: string; checks: number; numbers: number; found: number; first_at: string; last_at: string; told: boolean; refused: boolean }
export interface Lookups { day: string; rows: LookupRow[]; daily: number | null; alert: number | null }

export const fieldWord = (field: string) => (field === "EMAIL" ? "e-mail address" : "phone number");

/** where an unconfirmed contact on the record came from: the sign-in page or a department's upload; null when it is confirmed */
export function contactSource(pending: boolean | null | undefined, fromSignIn: boolean | null | undefined): "SIGN_IN" | "UPLOAD" | null {
  if (!pending) return null;
  return fromSignIn ? "SIGN_IN" : "UPLOAD";
}

/** a figure as the form takes it: empty (none), or a whole number from 1 to 10,000 */
export function figureOk(text: string): boolean {
  const t = text.trim();
  return t === "" || (/^\d{1,5}$/.test(t) && Number(t) >= 1 && Number(t) <= 10000);
}

/** a figure as the API takes it: null for none */
export const figureValue = (text: string): number | null => (text.trim() === "" ? null : Number(text.trim()));

/** how a connection's day reads: refused past the day's figure, the Head told, near the alert figure, or nothing to see */
export function lookupState(row: Pick<LookupRow, "numbers" | "told" | "refused">, alert: number | null): "REFUSED" | "TOLD" | "NEAR" | "QUIET" {
  if (row.refused) return "REFUSED";
  if (row.told) return "TOLD";
  if (alert != null && alert > 0 && Number(row.numbers) * 2 >= alert) return "NEAR";
  return "QUIET";
}
