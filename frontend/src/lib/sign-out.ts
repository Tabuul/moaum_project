"use client";

/**
 * The one sign-out, whoever asks for it — the Sign out button at the top right of every signed-in screen, the one at the
 * foot of the menu, or the inactivity watch (components/IdleWatch). The session is ended through the existing route
 * (/api/auth/sign-out: the API ends the session and the cookie is cleared); what this browser kept for the person is
 * forgotten (what they searched for; that they put off the privacy notice, so whoever signs in next is asked); and the
 * sign-in page replaces the screen with a full load, so nothing the screens held in memory survives and Back does not
 * bring a signed-in screen up from the router's cache. A sign-out the network refused still leaves this browser signed
 * out: the page moves on, and the server's own clocks end a session nobody uses.
 */
import { RECENT_SEARCHES_KEY } from "@/lib/student-recents";
import { POLICY_PUT_OFF_KEY } from "@/components/PolicyPrompt";

/** what this browser forgets of the person at sign-out (preferences such as the text size or a panel left open stay) */
function forgetOnThisDevice(): void {
  try { window.localStorage.removeItem(RECENT_SEARCHES_KEY); } catch { /* a browser that keeps nothing */ }
  try { window.sessionStorage.removeItem(POLICY_PUT_OFF_KEY); } catch { /* a browser that keeps nothing */ }
}

/** ends the session and opens `to` (the sign-in page by default) in place of the current screen */
export async function signOut(to = "/login"): Promise<void> {
  await fetch("/api/auth/sign-out", { method: "POST" }).catch(() => null);
  forgetOnThisDevice();
  window.location.replace(to);
}
