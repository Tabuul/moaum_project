import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { dispositionName } from "@/lib/summer";

/** What the Summer desk's screens share for talking to the API through the BFF from the browser: one way of sending an act, one of
 *  reading a list, one of saving a file the API made (the CSV exports, which the API records on the export log itself). */

export type DeskResult<T> = { ok: true; data: T } | { ok: false; problem: Problem };

const problemOf = (r: Response, j: unknown): Problem => (j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText || "That did not go through" });

/** an act: POST or PUT with a reason the audit trail keeps */
export async function call<T = Record<string, unknown>>(method: "POST" | "PUT", path: string, body: unknown, reason: string): Promise<DeskResult<T>> {
  try {
    const r = await fetch(`/api/bff/api/v1${path}`, {
      method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}),
    });
    const j = await r.json().catch(() => null);
    return r.ok ? { ok: true, data: (j ?? {}) as T } : { ok: false, problem: problemOf(r, j) };
  } catch {
    return { ok: false, problem: { status: 0, title: "The portal could not be reached", detail: "Check the connection and try again." } };
  }
}

/** a read the person asked for (the ids of everything a filter matches, one selection's detail) */
export async function read<T>(path: string): Promise<DeskResult<T>> {
  try {
    const r = await fetch(`/api/bff/api/v1${path}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    return r.ok ? { ok: true, data: j as T } : { ok: false, problem: problemOf(r, j) };
  } catch {
    return { ok: false, problem: { status: 0, title: "The portal could not be reached", detail: "Check the connection and try again." } };
  }
}

/** a file the API made, saved under the name it gave it; null when it was saved, else the refusal. The API writes the export on its
 *  log in the same transaction as it makes the file. */
export async function saveFile(path: string, fallbackName: string, reason: string): Promise<Problem | null> {
  try {
    const r = await fetch(`/api/bff/api/v1${path}`, { headers: { "X-Reason": reasonHeader(reason) }, cache: "no-store" });
    if (!r.ok) return problemOf(r, await r.json().catch(() => null));
    const blob = await r.blob();
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = dispositionName(r.headers.get("content-disposition"), fallbackName);
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    return null;
  } catch {
    return { status: 0, title: "The file could not be downloaded", detail: "Check the connection and try again." };
  }
}
