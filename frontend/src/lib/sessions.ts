/** A session as /ref/sessions returns it (ordered by name DESC). */
export interface SessionRow { name: string; state: string }

/**
 * The intake (admission) session — the one candidates are admitted INTO. Students are admitted into
 * the coming session while the current one runs, so admissions screens default here, not to CURRENT.
 * It is the first PLANNED session after the University's current one (the CURRENT session, else the
 * latest that is not planned, else the latest), falling back to that current one, then a sensible
 * literal. The same rule as policy.intake_session() (V378), which the public Post-UTME page reads.
 */
export function intakeSession(sessions: SessionRow[], today: Date = new Date()): string {
  const current = calendarSession(sessions);
  const next = sessions
    .filter((s) => s.state === "PLANNED" && (!current || s.name > current))
    .map((s) => s.name)
    .sort()[0];
  return next ?? current ?? sessionByDate(today);
}

/** the calendar's current session: the CURRENT one, else the latest that is not planned, else the latest; none on an
 *  empty calendar. The same rule as policy.university_current_session(). */
function calendarSession(sessions: SessionRow[]): string | undefined {
  const names = sessions.map((s) => s.name).sort();
  return sessions.find((s) => s.state === "CURRENT")?.name ??
    names.filter((n) => sessions.find((s) => s.name === n)?.state !== "PLANNED").at(-1) ??
    names.at(-1);
}

/**
 * The University's current session, the default of every screen that is not about admission — never a year written into
 * the code, which goes stale the day the next session begins. By the date only when the calendar holds no session.
 */
export function currentSession(sessions: SessionRow[], today: Date = new Date()): string {
  return calendarSession(sessions) ?? sessionByDate(today);
}

/** the session a date falls in: a session runs from September to August, so 11 October 2026 is in 2026/2027 */
export function sessionByDate(today: Date = new Date()): string {
  const y = today.getMonth() >= 8 ? today.getFullYear() : today.getFullYear() - 1;
  return `${y}/${y + 1}`;
}
