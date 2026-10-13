import { API_URL } from "@/lib/api";

/** V441: an applicant who ticked the Privacy Policy box at registration — the acceptance recorded as their own act, with the
 *  token the registration just issued, against the version published now; a failure here is not a failure of the registration
 *  (the next sign-in asks again). Server side only. */
export async function recordRegistrationAcceptance(token: string, forwardedFor: string | null, userAgent: string | null): Promise<void> {
  try {
    const pub = await fetch(`${API_URL}/api/v1/public/legal/privacy-policy`, { cache: "no-store" });
    if (!pub.ok) return;
    const doc = (await pub.json()) as { id?: string };
    if (!doc.id) return;
    await fetch(`${API_URL}/api/v1/privacy/acceptance`, {
      method: "POST",
      headers: {
        "content-type": "application/json", authorization: `Bearer ${token}`, "x-active-office": "applicant",
        "x-reason": "Privacy Policy accepted at registration", "x-forwarded-for": forwardedFor ?? "", "user-agent": userAgent ?? "",
      },
      body: JSON.stringify({ documentId: doc.id, channel: "REGISTRATION" }),
      cache: "no-store",
    });
  } catch {
    /* the sign-in prompt asks again */
  }
}
