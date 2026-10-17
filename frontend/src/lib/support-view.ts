/**
 * V521: ICT Support viewing a student's portal as the student, read-only. While it lasts the browser carries the student's session
 * (the API refuses every change made with it); the agent's own session waits in an httpOnly cookie and comes back on leaving.
 * The view's particulars ride in a cookie the page reads, for the banner that says whose portal this is and how to leave it.
 */
export const SUPPORT_RETURN_COOKIE = "moaum_support_return";
export const SUPPORT_RETURN_OFFICE_COOKIE = "moaum_support_return_office";
export const SUPPORT_VIEW_COOKIE = "moaum_support_view";

export interface SupportViewState {
  viewId: string;
  studentId: string;
  name: string;
  matricNo: string | null;
  endsAt: string;
  /** where the agent returns on leaving: the support record they opened it from */
  back: string;
}

/** the view's particulars from the cookie's value, or null */
export function readSupportView(raw: string | null | undefined): SupportViewState | null {
  // the value is written encoded; a cookie layer may encode it once more — read it at whichever depth it parses
  let text = raw ?? "";
  for (let i = 0; i < 3 && text; i++) {
    try {
      const v = JSON.parse(text) as SupportViewState;
      return v && typeof v.viewId === "string" && typeof v.studentId === "string" ? v : null;
    } catch { /* not yet JSON */ }
    try { text = decodeURIComponent(text); } catch { return null; }
  }
  return null;
}

/** a back address on this portal only — never another site */
export function safeBack(back: string | null | undefined, fallback: string): string {
  return back && back.startsWith("/") && !back.startsWith("//") ? back : fallback;
}

/** minutes and seconds left, for the banner */
export function timeLeft(endsAt: string, now: number): string {
  const ms = new Date(endsAt).getTime() - now;
  if (!Number.isFinite(ms) || ms <= 0) return "0:00";
  const s = Math.floor(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}
