import "server-only";
import { API_URL } from "@/lib/api";
import { windowIsOpen } from "@/lib/transfer-application";

/** the tab reads as the CMS sign-in's does, with the portal's own name */
export const SIGN_IN_TITLE = "MOAUM Portal: Portal Login | Rev. Fr. Moses Orshio Adasu University, Makurdi";

export type SsoOption = { enabled: boolean; label: string } | null;

/**
 * V766: whether the inter-university transfer application is open (the Academic Office's window), for the sign-in page's line beside
 * the collaboration line — read from the public options as `window.open`, kept a minute as the page is; an API that does not answer
 * within three seconds, or at all, reads as closed and the line is not drawn.
 */
export async function transferOpen(): Promise<boolean> {
  try {
    const r = await fetch(`${API_URL}/api/v1/public/inter-university-transfer`, { next: { revalidate: 60 }, signal: AbortSignal.timeout(3000) });
    if (!r.ok) return false;
    const j = (await r.json()) as { window?: { open?: boolean | null; status?: string | null } | null };
    return windowIsOpen(j.window);
  } catch {
    return false;
  }
}

/**
 * Whether single sign-on is connected, and its button's label — the API's to say. Kept a minute where the page is cached
 * (the sign-in page); asked on each render where it is not (the bare address). An API that does not answer within three
 * seconds, or at all (a build has no API), reads as no single sign-on: the password form still works.
 */
export async function ssoOption(): Promise<SsoOption> {
  try {
    const r = await fetch(`${API_URL}/api/v1/auth/sso`, { next: { revalidate: 60 }, signal: AbortSignal.timeout(3000) });
    return r.ok ? ((await r.json()) as SsoOption) : null;
  } catch {
    return null;
  }
}
