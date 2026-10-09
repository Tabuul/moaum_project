/** A session as /ref/sessions returns it (ordered by name DESC). */
export interface SessionRow { name: string; state: string }

/**
 * The intake (admission) session — the one candidates are admitted INTO. Students are admitted into
 * the coming session while the current one runs, so admissions screens default here, not to CURRENT.
 * It is the first PLANNED session after the University's current one (the CURRENT session, else the
 * latest that is not planned, else the latest), falling back to that current one, then a sensible
 * literal. The same rule as policy.intake_session() (V378), which the public Post-UTME page reads.
 */
export function intakeSession(sessions: SessionRow[]): string {
  const names = sessions.map((s) => s.name).sort();
  const current =
    sessions.find((s) => s.state === "CURRENT")?.name ??
    names.filter((n) => sessions.find((s) => s.name === n)?.state !== "PLANNED").at(-1) ??
    names.at(-1);
  const next = sessions
    .filter((s) => s.state === "PLANNED" && (!current || s.name > current))
    .map((s) => s.name)
    .sort()[0];
  return next ?? current ?? "2026/2027";
}
