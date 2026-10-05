/** V325 — the acting office's scope, explained by the API (GET /api/v1/iam/me/scope): what the newest live grant
 *  holds, what the desk resolved to and through which source, and when the grant itself did not answer, why. */

export interface ScopeGrant {
  id: string;
  scopeKind: string;
  scopeId: string | null;
  validFrom: string;
  validTo: string | null;
  instrument: string;
}

export type ScopeSource = "OFFICE_GRANT" | "PROGRAMME_GRANT" | "LECTURER_GRANT" | "STAFF_RECORD";
export type ScopeReason = "NO_LIVE_GRANT" | "GRANT_NOT_BOUNDED" | "SCOPE_BLANK" | "SCOPE_NOT_ON_REGISTER" | "SCOPE_ENDED";

export interface OfficeScopeState {
  office: string | null;
  /** false for an office that is not held over a department or a faculty: nothing to explain */
  bounded: boolean;
  kind?: "department" | "faculty" | null;
  resolved: boolean;
  code?: string | null;
  name?: string | null;
  source?: ScopeSource | null;
  reason?: ScopeReason | null;
  programmeCode?: string | null;
  programmeName?: string | null;
  grant?: ScopeGrant | null;
}

/** what a grant is bounded to, in the console's words */
export const BOUND_WORD: Record<string, string> = {
  institution: "the University", college: "a College", faculty: "a faculty", department: "a department", programme: "a programme",
  course: "own courses", unit: "a unit", platform: "the platform", level: "a level",
};

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** a date on the record, the same on the server and in the browser (no locale) */
export function dayWord(iso: string | null | undefined): string {
  if (!iso) return "—";
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  if (!m) return iso;
  return `${Number(m[3])} ${MONTHS[Number(m[2]) - 1] ?? m[2]} ${m[1]}`;
}

/** the grant in one phrase: "your Head of Department grant from 4 Oct 2026 (Letter REG/…)" */
export function grantWord(s: OfficeScopeState, officeLabel: string): string {
  const g = s.grant;
  if (!g) return `your ${officeLabel} grant`;
  return `your ${officeLabel} grant from ${dayWord(g.validFrom)}${g.validTo ? ` to ${dayWord(g.validTo)}` : ""} (${g.instrument})`;
}

/** the one sentence that says why the grant itself did not answer; null when it did */
export function scopeReasonWord(s: OfficeScopeState, officeLabel: string): string | null {
  const kind = s.kind ?? "department";
  const g = s.grant;
  const who = grantWord(s, officeLabel);
  const Who = who.charAt(0).toUpperCase() + who.slice(1);
  switch (s.reason) {
    case "NO_LIVE_GRANT":
      return `No ${officeLabel} grant stands for you today: the office your sign-in carries was granted before and has since ended, or is dated later than today.`;
    case "GRANT_NOT_BOUNDED":
      return `${Who} is bounded to ${BOUND_WORD[g?.scopeKind ?? ""] ?? g?.scopeKind ?? "something else"}, not to a ${kind}.`;
    case "SCOPE_BLANK":
      return `${Who} is bounded to a ${kind}, but none was chosen.`;
    case "SCOPE_NOT_ON_REGISTER":
      return `${Who} is bounded to “${g?.scopeId ?? ""}”, and no ${kind} on the register has that code or name.`;
    case "SCOPE_ENDED":
      return `${Who} is bounded to “${g?.scopeId ?? ""}”, a ${kind === "department" ? "department the register has since ended" : "programme the register has since archived"}.`;
    default:
      return null;
  }
}

/** what the Registry does about it */
export function scopeRemedyWord(s: OfficeScopeState): string {
  const kind = s.kind ?? "department";
  if (s.reason === "NO_LIVE_GRANT") {
    return "If the Registry has just made or amended the grant, sign out and sign in again; a sign-in carries the offices held on the day it is made. Otherwise ask the Registry to grant the office on Users & Roles.";
  }
  return `Ask the Registry to amend the grant on Users & Roles — choosing the ${kind} from the register — then this fills in.`;
}

/** the source a desk read its scope from, when it was not the office's own grant */
export function scopeSourceWord(s: OfficeScopeState): string | null {
  switch (s.source) {
    case "PROGRAMME_GRANT": return "the programme the grant names";
    case "LECTURER_GRANT": return "your lecturer grant";
    case "STAFF_RECORD": return "your staff record";
    default: return null;
  }
}
