/**
 * The calendar as the API serves it (GET /api/v1/calendar), and the few
 * things both the server page and the screen need to say about it: what a
 * semester is called, and how the prototype prints a date.
 */

export interface SessionRow {
  name: string;
  startsOn: string;
  endsOn: string;
  state: "PLANNED" | "CURRENT" | "CLOSED" | string;
  senateMinute: string | null;
  semesters: number;
  students: number;
}

export interface SemesterRow {
  session: string;
  number: number;
  lecturesFrom: string | null;
  lecturesTo: string | null;
  registrationOpens: string | null;
  registrationCloses: string | null;
  lateRegistrationCloses: string | null;
  examsFrom: string | null;
  examsTo: string | null;
  resultsDue: string | null;
  queryWindow: string | null;
  state: "NOT_YET_OPEN" | "OPEN" | "CLOSED" | string;
}

export interface LevelLimitRow {
  level: number;
  appliesTo: string;
  minUnits: number;
  maxUnits: number;
  carryoverCounts: boolean;
  instrument: string | null;
  /** the most units a student on probation registers at this level; null until the Registry sets it */
  probationMaxUnits?: number | null;
}

export interface CalendarData {
  sessions: SessionRow[];
  current: string | null;
  session: string | null;
  semesters: SemesterRow[];
  levelLimits: LevelLimitRow[];
}

export const SEMESTER_NAMES = ["First", "Second", "Third"];

/** "First", "Second", "Third" — and the number itself for anything else. */
export function semesterName(n: number): string {
  return SEMESTER_NAMES[n - 1] ?? String(n);
}

/** A date as the prototype prints one in a table: "24 Sept 2026", or an em dash. */
export function d(iso: string | null | undefined, withYear = true): string {
  if (!iso) return "—";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: withYear ? "numeric" : undefined });
}

/** "15 Sept – 5 Dec", the prototype's way of printing a window; an em dash when neither end is set. */
export function span(from: string | null, to: string | null): string {
  if (!from && !to) return "—";
  if (from && to) return `${d(from, false)} – ${d(to)}`;
  return d(from ?? to);
}

/** Whole days between two dates, for the tiles' captions. */
export function daysBetween(from: string | null, to: string | null): number | null {
  if (!from || !to) return null;
  const a = new Date(from).getTime();
  const b = new Date(to).getTime();
  if (Number.isNaN(a) || Number.isNaN(b)) return null;
  return Math.round((b - a) / 86400000);
}

/** true when today falls inside the window, both ends included. */
export function within(from: string | null, to: string | null, today = new Date()): boolean {
  if (!from || !to) return false;
  const iso = today.toISOString().slice(0, 10);
  return from <= iso && iso <= to;
}

export function withThousands(n: number): string {
  return n.toLocaleString("en-NG");
}
