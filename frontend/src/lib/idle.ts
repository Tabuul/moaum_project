/** V437 — the idle session timeout, as the browser sees it: the policy the server enforces, the activity shared between a
 *  person's tabs, and the forms that hold unsaved work. The countdown the browser draws is for the person; the server's
 *  clock and platform.session_policy decide, on every request. */

/** GET /api/v1/auth/session-policy */
export interface SessionPolicy {
  enabled: boolean;
  idleSeconds: number;
  warningSeconds: number;
  allowContinue: boolean;
  updatedAt?: string | null;
  updatedBy?: string | null;
  updatedOffice?: string | null;
  reason?: string | null;
}

/** when the person last did something, shared by every tab of this browser (ms since the epoch) */
export const IDLE_LAST_KEY = "moaum_idle_last";
/** written by the tab that ended the session for inactivity, so the others follow it to the sign-in */
export const IDLE_EXPIRED_KEY = "moaum_idle_expired";
/** the policy as last read, kept for a few minutes so a navigation does not read it again */
export const IDLE_POLICY_KEY = "moaum_idle_policy";
/** the header a request the browser sends on its own carries: it is never the person's activity */
export const BACKGROUND_HEADER = "X-Background";

/** pages where the ordinary idle timeout does not run: an examination room is the CBT engine's, with its own clock and recovery */
export function idleExempt(pathname: string): boolean {
  return /\/cbt\/room\//.test(pathname) || pathname.startsWith("/login") || pathname.startsWith("/post-utme/cbt");
}

/** the problem code the API answers when the session ended for inactivity */
export const EXPIRED_IDLE = "SESSION_EXPIRED_IDLE";

/* ── unsaved work: a form says when it holds changes, and how to save them, so the warning can say so ── */
type Saver = () => Promise<unknown> | unknown;
const unsaved = new Map<string, Saver | null>();

/** a form with unsaved changes registers under its key (and unregisters when saved or unmounted) */
export function markUnsaved(key: string, dirty: boolean, save?: Saver): void {
  if (dirty) unsaved.set(key, save ?? null);
  else unsaved.delete(key);
}

export function hasUnsaved(): boolean {
  return unsaved.size > 0;
}

export function canSaveUnsaved(): boolean {
  return [...unsaved.values()].some((s) => s !== null);
}

/** every registered form saved, where it said how */
export async function saveUnsaved(): Promise<void> {
  for (const [key, save] of [...unsaved.entries()]) {
    if (!save) continue;
    try {
      await save();
      unsaved.delete(key);
    } catch {
      /* the form shows its own problem; the person decides what to do */
    }
  }
}

/** mm:ss */
export function clock(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  return `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
}
