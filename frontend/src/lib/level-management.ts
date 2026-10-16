/**
 * A student's academic level at the ICT Support Desk (V500): what the API says of the student's level, the programme's levels and
 * the history, and the words the desk shows. The levels a student may be moved to, and every refusal, are the server's — the
 * screen only offers what the server listed and says what the server answered.
 */

export interface LevelOptions {
  currentLevel: number;
  entryLevel: number | null;
  finalLevel: number;
  postgraduate: boolean;
  levels: number[];
  otherLevels: number[];
  nextLevel: number | null;
  status: string;
  progressRefusal: string | null;
  correctRefusal: string | null;
}

export interface LevelChange {
  id: string;
  decided_at: string;
  previous_level: number | null;
  new_level: number;
  rule: string | null;
  reason: string;
  actor_office: string | null;
  session: string | null;
  semester: number | null;
  officer: string | null;
  ticket_number: string | null;
  batch_ref?: string | null;
}

export interface LevelState {
  student: {
    id: string; full_name: string; matric_no: string | null; jamb_reg_no: string | null; application_no: string | null;
    faculty: string | null; department: string | null; programme: string | null; programme_type: string | null;
    admission_session: string | null; current_level: number; status: string; study_mode: string | null; admission_route: string | null;
    entry_mode: string | null; entry_level: number | null;
  };
  session: string;
  semester: number;
  options: LevelOptions;
  position: { computed_level: number | null; spillover_state: string | null; classification: string | null; effective_cohort: string | null;
    expected_completion: string | null; graduation_state: string | null } | null;
  registrations: { session: string; semester: number; level: number; status: string; courses: number }[];
  history: LevelChange[];
  mayProgress: boolean;
  mayCorrect: boolean;
  scope: string;
}

export type LevelAction = "PROGRESS" | "CORRECTION";

/** a level change needs a reason in words, as a password reset does */
export const LEVEL_REASON_MIN = 10;
export const reasonOk = (s: string) => s.trim().length >= LEVEL_REASON_MIN;

/** the server's refusal without its code: "LEVEL_AT_FINAL: the student is …" → "The student is …" */
export function refusalWords(s: string | null | undefined): string {
  const t = String(s ?? "").replace(/^[A-Z][A-Z0-9_]+:\s*/, "").trim();
  return t ? t.charAt(0).toUpperCase() + t.slice(1) : "";
}

/** how a level change came about, in words */
export function ruleWord(rule: string | null | undefined): string {
  switch (rule) {
    case "LEVEL_PROGRESS": return "Progressed (ICT Support)";
    case "LEVEL_CORRECTION": return "Corrected (ICT Support)";
    case "LEVEL_SPILLOVER": return "Spillover correction";
    case "LEVEL_REGISTRATION": return "Correction from the registration";
    case "LEVEL_ARITHMETIC": return "Correction by the sessions counted";
    default: return rule ? "Registry decision" : "Level change";
  }
}

/** the student's levels as the registrations carry them, one per session, in order: "200 (2024/2025) → 300 (2025/2026)" */
export function levelPath(registrations: LevelState["registrations"]): { session: string; level: number }[] {
  const out: { session: string; level: number }[] = [];
  for (const r of [...registrations].sort((a, b) => a.session.localeCompare(b.session) || a.semester - b.semester)) {
    const last = out[out.length - 1];
    if (last && last.session === r.session) { last.level = Math.max(last.level, r.level); continue; }
    out.push({ session: r.session, level: r.level });
  }
  return out;
}

/** the registration of the session the change is made in, which the change leaves as it is: the warning the agent confirms */
export function registrationWarning(state: Pick<LevelState, "session" | "registrations">): string | null {
  const now = state.registrations.filter((r) => r.session === state.session).sort((a, b) => b.semester - a.semester)[0];
  if (!now) return null;
  const sem = now.semester === 1 ? "First" : now.semester === 2 ? "Second" : "Third";
  return `This student currently has a course registration for ${state.session} ${sem} Semester (${now.status.toLowerCase()}, ${now.level} Level, ${now.courses} course${now.courses === 1 ? "" : "s"}). `
    + "Changing the academic level may affect course eligibility and programme course selection. The registration is not deleted or changed; correct it afterwards through Course Registration support if it must change.";
}

/** the request's body */
export function levelBody(action: LevelAction, state: LevelState, level: number | null, reason: string, ticket: string | null, acknowledge: boolean) {
  return {
    action,
    level: action === "PROGRESS" ? state.options.nextLevel : level,
    expected: state.options.currentLevel,
    reason: reason.trim(),
    ticket: ticket || null,
    acknowledgeRegistration: acknowledge,
  };
}

/** the Level Change History filter */
export const HISTORY_ACTIONS = [
  ["", "Every change"],
  ["SUPPORT", "Made by ICT Support"],
  ["LEVEL_PROGRESS", "Progressed"],
  ["LEVEL_CORRECTION", "Corrected"],
  ["OTHER", "Registry and cohort corrections"],
] as const;
