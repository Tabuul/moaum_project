/** A session as /ref/sessions returns it (ordered by name DESC). */
export interface SessionRow { name: string; state: string }

/**
 * The intake (admission) session — the one candidates are admitted INTO. Students are admitted into
 * the coming session while the current one runs, so admissions screens default here, not to CURRENT.
 * It is the next PLANNED session (the list is ordered name-descending, so the first PLANNED is the
 * latest/upcoming one); falling back to CURRENT, then the newest session, then a sensible literal.
 */
export function intakeSession(sessions: SessionRow[]): string {
  return (
    sessions.find((s) => s.state === "PLANNED")?.name ??
    sessions.find((s) => s.state === "CURRENT")?.name ??
    sessions[0]?.name ??
    "2026/2027"
  );
}
