/** V654: the historical fees desk's calls to the API (through the BFF), each change carrying its reason */
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";

export const HF = "/api/bff/api/v1/finance/historical";

export async function hfCall<T>(path: string, init?: { method?: "GET" | "POST" | "PUT"; body?: unknown; reason?: string }): Promise<{ ok: true; data: T } | { ok: false; problem: Problem }> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (init?.reason) headers["X-Reason"] = reasonHeader(init.reason);
  try {
    const r = await fetch(`${HF}${path}`, { method: init?.method ?? "GET", cache: "no-store", headers, body: init?.body === undefined ? undefined : JSON.stringify(init.body) });
    const j = await r.json().catch(() => null);
    if (!r.ok) return { ok: false, problem: j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText } };
    return { ok: true, data: j as T };
  } catch {
    return { ok: false, problem: { status: 0, title: "The portal could not reach the server" } };
  }
}

/** a file read as a data URL for the evidence upload */
export function readDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result));
    r.onerror = () => reject(r.error);
    r.readAsDataURL(file);
  });
}
