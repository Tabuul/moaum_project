/** What the lecturer's screens share: the words for a sheet's standing, the counts the dashboard and the
 *  history read from the same list of sheets, and the shape of a notice the portal sent a member of staff. */
import { Pil } from "@/components/proto/ui";
import { STAGE_LABEL, type MySheet } from "@/lib/results";

/** the four standings a lecturer thinks in — what the register's stages come down to on their desk */
export type Standing = "NOT_STARTED" | "IN_PROGRESS" | "SUBMITTED" | "PUBLISHED";

export function standingOf(s: MySheet): Standing {
  if (s.stage === "PUBLISHED") return "PUBLISHED";
  if (s.stage !== "ENTRY") return "SUBMITTED";
  return s.entered === 0 ? "NOT_STARTED" : "IN_PROGRESS";
}

export const STANDING: Record<Standing, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  NOT_STARTED: ["Not started", "bad"],
  IN_PROGRESS: ["In progress", "warn"],
  SUBMITTED: ["Submitted — in approval", "info"],
  PUBLISHED: ["Published", "ok"],
};

/** the standing as a pill, with the desk the sheet is at when it is in approval */
export function StandingPil({ sheet }: { sheet: MySheet }) {
  const st = standingOf(sheet);
  const [word, kind] = STANDING[st];
  const desk = st === "SUBMITTED" ? STAGE_LABEL[sheet.stage]?.[0] : null;
  return <Pil kind={kind} title={desk ? `With ${desk}` : undefined}>{st === "SUBMITTED" && desk ? `At ${desk}` : word}</Pil>;
}

/** the counts every lecturer screen agrees on, read from one list of sheets */
export function tally(sheets: MySheet[]) {
  const by = (st: Standing) => sheets.filter((s) => standingOf(s) === st);
  return {
    courses: sheets.length,
    asLecturer: sheets.filter((s) => s.mine).length,
    students: sheets.reduce((n, s) => n + s.candidates, 0),
    notStarted: by("NOT_STARTED"),
    inProgress: by("IN_PROGRESS"),
    submitted: by("SUBMITTED"),
    published: by("PUBLISHED"),
    open: sheets.filter((s) => s.stage === "ENTRY"),
    queries: sheets.reduce((n, s) => n + (s.openQueries ?? 0), 0),
    held: sheets.reduce((n, s) => n + (s.heldScripts ?? 0), 0),
  };
}

export const dueWords = (s: MySheet) => {
  const d = s.daysToDue;
  if (s.stage !== "ENTRY") return "";
  if (d == null) return "No date set";
  if (d < 0) return `${-d} day${d === -1 ? "" : "s"} overdue`;
  return d === 0 ? "Due today" : `${d} day${d === 1 ? "" : "s"} to go`;
};

export const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
export const whenAt = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

/** the class list of a course in a session and semester, as the class-list screen addresses it */
export const classListHref = (course: string, session: string, sem: number | string) =>
  `/registration/class-list?course=${encodeURIComponent(course)}&session=${encodeURIComponent(session)}&sem=${sem}`;

/** a notice the portal queued for a member of staff, read back from the outbox (GET /api/v1/me/notices) */
export interface StaffNotice {
  id: string; channel: "EMAIL" | "SMS"; subject: string; body: string; about_kind: string | null; about_id: string | null;
  created_at: string; state: "QUEUED" | "SENT" | "FAILED"; sent_at: string | null;
}
