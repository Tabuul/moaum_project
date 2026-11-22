/** V766: one way the transfer application's screens call the API through the BFF — the applicant's portal and the desks alike: the
 *  answer, or the problem as the API said it (a refusal's code and words reach ProblemNotice as they are). A desk's write carries its
 *  reason (X-Reason), as every desk write does. */
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";

export type Answer<T> = { ok: true; data: T } | { ok: false; problem: Problem };

export const ME = "/api/bff/api/v1/transfer-applications/me";
export const OFFICE = "/api/bff/api/v1/transfer-applications/office";
export const FEES = "/api/bff/api/v1/finance/transfer-applications";

export async function call<T>(method: "GET" | "POST" | "PUT" | "DELETE", path: string, body?: unknown, reason?: string): Promise<Answer<T>> {
  const headers: Record<string, string> = {};
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (reason) headers["X-Reason"] = reasonHeader(reason);
  let r: Response;
  try {
    r = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), cache: "no-store" });
  } catch {
    return { ok: false, problem: { status: 503, title: "The portal could not be reached", detail: "Check the connection and try again." } };
  }
  const text = await r.text();
  let j: unknown = null;
  try { j = text ? JSON.parse(text) : null; } catch { j = null; }
  if (!r.ok) {
    return { ok: false, problem: j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText || "That did not go through" } };
  }
  return { ok: true, data: j as T };
}
