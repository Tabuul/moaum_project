/** V687: Post-UTME applicant passwords — the applicant's own change, and what the Applicant Passwords desk shows of a reset.
 *  V706: a reset puts the password back to the JAMB number (the application number where there is none); postgraduate applicants'
 *  passwords are reset to the application number. */

/** why a new password cannot be saved yet, or null: eight characters or more, typed twice alike */
export function newPasswordProblem(next: string, again: string): string | null {
  if (next.length < 8) return "A password is eight characters or more.";
  if (next !== again) return "Type the new password twice, the same both times.";
  return null;
}

/** the desk's words for a reset's method */
export const RESET_METHOD: Record<string, string> = {
  TEMPORARY_PASSWORD: "Temporary password",
  RESET_LINK: "Reset link sent",
  DEFAULT_NUMBER: "Back to the JAMB or application number",
};

/** the postgraduate desk's words for a reset's method */
export const PG_RESET_METHOD: Record<string, string> = { DEFAULT_NUMBER: "Back to the application number" };

/** the number an undergraduate applicant's password is reset to, in words */
export function defaultNumberWords(kind: string | null | undefined): string {
  return kind === "APPLICATION" ? "application number" : "JAMB number";
}

/** the desk's words for an undergraduate account's state; on the first password (the number), after a reset or never yet signed in */
export function accountState(a: {
  locked: boolean; must_change?: boolean; mustChange?: boolean; firstSignIn?: boolean; on_default?: boolean; onDefault?: boolean;
}): [string, "ok" | "warn" | "bad" | "grey"] {
  if (a.locked) return ["Locked (failed sign-ins)", "bad"];
  const onDefault = a.on_default ?? a.onDefault ?? a.firstSignIn ?? false;
  const must = a.must_change ?? a.mustChange ?? false;
  if (must && onDefault) return ["Reset to the number, change pending", "warn"];
  if (must) return ["Temporary password, change pending", "warn"];
  if (onDefault) return ["First sign-in not yet made", "grey"];
  return ["Active", "ok"];
}

/** the postgraduate desk's words for an account's state */
export function pgAccountState(a: { locked: boolean; must_change?: boolean; mustChange?: boolean }): [string, "ok" | "warn" | "bad"] {
  if (a.locked) return ["Locked (failed sign-ins)", "bad"];
  if (a.must_change ?? a.mustChange) return ["Reset to the application number, change pending", "warn"];
  return ["Active", "ok"];
}

/** a reset's reason is written down in words: ten characters or more */
export function reasonProblem(reason: string): string | null {
  return reason.trim().length >= 10 ? null : "Say why the password is reset, in ten characters or more.";
}
