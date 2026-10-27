/** V668: a transcript asked for without a portal account — the public doors' calls from the browser and the shapes they answer */

export const TRN_API = "/api/bff/api/v1/public/transcripts";

export interface TrnPolicy { kind: string; label: string; currency: string; physical_fee: number; international_fee: number; urgent_fee: number; sla_days: number; urgent_sla_days: number; fee_now: number | null }
export interface TrnOptions { policies: TrnPolicy[]; maxIdMb: number }
export interface TrnMade { ref: string; fee: number | null; reference: string | null; stage: string; statusPath: string }
export interface TrnStatus {
  ref: string; kind: string; kindLabel?: string; holder: string; matricNo: string; requestedBy: "GRADUATE" | "INSTITUTION"; requesterName: string; organisation?: string; email: string;
  stage: string; stageWords: string; closed: boolean; closedReason?: string; delivery: string; copies: number; express: boolean; destination: string; destinationName?: string;
  recipientEmail?: string; recipientAddress?: string; fee?: number; reference?: string; paid: boolean; paidAt?: string; referenceExpiresAt?: string; referenceExpired?: boolean;
  identityState: string; consentState: string; consentExpiresAt?: string; requestedAt: string; slaDueOn?: string;
  timeline?: { at: string; action: string; stage?: string }[];
}
export interface TrnConsent {
  ref: string; organisation?: string; requesterName: string; email: string; purpose?: string; recipientName?: string; recipientEmail?: string; recipientAddress?: string; delivery: string;
  holder: string; state: string; expiresAt?: string; decidedAt?: string; requestClosed: boolean;
}

/** one call to the public doors: the answer, or the problem in words for the person at the form */
export async function trnCall<T>(method: "GET" | "POST", path: string, body?: unknown): Promise<{ ok: true; data: T } | { ok: false; message: string; code?: string }> {
  try {
    const r = await fetch(`${TRN_API}${path}`, { method, cache: "no-store", headers: body === undefined ? undefined : { "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body) });
    const j = await r.json().catch(() => null);
    if (!r.ok) return { ok: false, message: (j && (j.detail || j.title)) || "That did not go through; try again.", code: j?.code };
    return { ok: true, data: j as T };
  } catch {
    return { ok: false, message: "The University's portal could not be reached; check your connection and try again." };
  }
}

export const naira = (n: number | string | null | undefined) => (n === null || n === undefined ? "—" : `₦${Number(n).toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`);
export const longDay = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
export const whenAt = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

export const RECIPIENTS: [string, string][] = [["INSTITUTION", "A university or other institution"], ["EMPLOYER", "An employer"], ["EMBASSY", "An embassy"], ["PROFESSIONAL_BODY", "A professional body"], ["OTHER", "Another organisation"]];
export const DELIVERIES: [string, string][] = [["DIGITAL", "By email (a secure link)"], ["PHYSICAL", "Printed and posted"], ["BOTH", "Both"]];
export const TIMELINE_WORDS: Record<string, string> = {
  REQUESTED: "Request received", PAID: "Payment confirmed", IDENTITY: "Identity checked", CONSENT: "Graduate's consent",
  RELEASED: "Transcript issued", DELIVERED: "Delivered", COMPLETED: "Completed", CANCELLED: "Cancelled",
};
