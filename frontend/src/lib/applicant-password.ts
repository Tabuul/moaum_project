/** V687: Post-UTME applicant passwords — the applicant's own change, and what the Applicant Passwords desk shows of a reset */

/** why a new password cannot be saved yet, or null: eight characters or more, typed twice alike */
export function newPasswordProblem(next: string, again: string): string | null {
  if (next.length < 8) return "A password is eight characters or more.";
  if (next !== again) return "Type the new password twice, the same both times.";
  return null;
}

/** the desk's words for a reset's method */
export const RESET_METHOD: Record<string, string> = { TEMPORARY_PASSWORD: "Temporary password", RESET_LINK: "Reset link sent" };

/** the desk's words for the account's state */
export function accountState(a: { locked: boolean; must_change?: boolean; mustChange?: boolean; firstSignIn?: boolean }): [string, "ok" | "warn" | "bad" | "grey"] {
  if (a.locked) return ["Locked (failed sign-ins)", "bad"];
  if (a.must_change ?? a.mustChange) return ["Temporary password, change pending", "warn"];
  if (a.firstSignIn) return ["First sign-in not yet made", "grey"];
  return ["Active", "ok"];
}

/** a reset's reason is written down in words: ten characters or more */
export function reasonProblem(reason: string): string | null {
  return reason.trim().length >= 10 ? null : "Say why the password is reset, in ten characters or more.";
}
