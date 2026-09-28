/**
 * The calendar as the API serves it (GET /api/v1/calendar), and the few
 * things both the server page and the screen need to say about it: what a
 * semester is called, and how the prototype prints a date.
 */

export interface SessionRow {
  name: string;
  startsOn: string;
  endsOn: string;
  /** V289: DRAFT, PLANNED, CURRENT, CLOSED (read "Completed") or ARCHIVED */
  state: "DRAFT" | "PLANNED" | "CURRENT" | "CLOSED" | "ARCHIVED" | string;
  senateMinute: string | null;
  semesters: number;
  students: number;
  /** V289: MANUAL (the Registrar makes it current) or AUTOMATIC (the clock does, on transitionsOn) */
  transitionMode?: "MANUAL" | "AUTOMATIC" | string;
  transitionsOn?: string | null;
  madeCurrentAt?: string | null;
  completedAt?: string | null;
  archivedAt?: string | null;
  /** entrants whose entry session this is */
  freshStudents?: number;
}

/** one readiness check of the transition into a planned session (V289) */
export interface ReadinessCheck { code: string; ok: boolean; blocking: boolean; detail: string }

/** one attempt at a session transition (V289) */
export interface TransitionRow { id: string; from_session: string | null; to_session: string; outcome: "DONE" | "BLOCKED" | "ALREADY" | string; mode: string; reason: string | null; senate_minute: string | null; at: string; actor: string | null; actor_office: string | null }

/** the label the University reads for a session state: Draft, Planned, Current, Completed, Archived */
export function sessionLabel(state: string): string {
  return state === "DRAFT" ? "Draft" : state === "PLANNED" ? "Planned" : state === "CURRENT" ? "Current" : state === "CLOSED" ? "Completed" : state === "ARCHIVED" ? "Archived" : state;
}

/** the label for a semester state: Planned, Open, Completed, Archived */
export function semesterLabel(state: string): string {
  return state === "NOT_YET_OPEN" ? "Planned" : state === "OPEN" ? "Open" : state === "CLOSED" ? "Completed" : state === "ARCHIVED" ? "Archived" : state;
}

export interface SemesterRow {
  session: string;
  number: number;
  lecturesFrom: string | null;
  lecturesTo: string | null;
  registrationOpens: string | null;
  /** V287: the early registration window for the session's fresh students */
  freshRegistrationFrom?: string | null;
  registrationCloses: string | null;
  lateRegistrationCloses: string | null;
  examsFrom: string | null;
  examsTo: string | null;
  resultsDue: string | null;
  queryWindow: string | null;
  state: "NOT_YET_OPEN" | "OPEN" | "CLOSED" | "ARCHIVED" | string;
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
  /** V289: the next planned session after the current one */
  next?: string | null;
  session: string | null;
  semesters: SemesterRow[];
  levelLimits: LevelLimitRow[];
  /** V289: the last session transitions, newest first */
  transitions?: TransitionRow[];
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
