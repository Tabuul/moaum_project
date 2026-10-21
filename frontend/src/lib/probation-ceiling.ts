/**
 * V600: the probation unit ceiling (FR-REG-07) — the most units a student on probation registers at a level. Until the University
 * sets it for an undergraduate level (100–600, where probation standing is reached), a student on probation there registers up to
 * the level's maximum like everyone else; Session & Semester Setup says so, as the warning before a session's automatic start does.
 */

/** the undergraduate levels whose unit limit states no probation ceiling, in order */
export function probationUnset(limits: { level: number; probationMaxUnits?: number | null }[]): number[] {
  return limits.filter((l) => l.level >= 100 && l.level <= 600 && l.probationMaxUnits == null).map((l) => l.level).sort((a, b) => a - b);
}

/** the levels as the notice says them: "100, 200 and 300 Level" */
export function levelsWords(levels: number[]): string {
  if (!levels.length) return "";
  if (levels.length === 1) return `${levels[0]} Level`;
  return `${levels.slice(0, -1).join(", ")} and ${levels[levels.length - 1]} Level`;
}
