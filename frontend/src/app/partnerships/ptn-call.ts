/** V658: the partnerships desk's calls to the API (through the BFF), each change carrying its reason */
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";

export const PTN = "/api/bff/api/v1/partnerships";

export async function ptnCall<T>(path: string, init?: { method?: "GET" | "POST" | "PUT" | "DELETE"; body?: unknown; reason?: string }): Promise<{ ok: true; data: T } | { ok: false; problem: Problem }> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (init?.reason) headers["X-Reason"] = reasonHeader(init.reason);
  try {
    const r = await fetch(`${PTN}${path}`, { method: init?.method ?? "GET", cache: "no-store", headers, body: init?.body === undefined ? undefined : JSON.stringify(init.body) });
    const j = await r.json().catch(() => null);
    if (!r.ok) return { ok: false, problem: j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText } };
    return { ok: true, data: j as T };
  } catch {
    return { ok: false, problem: { status: 0, title: "The portal could not reach the server" } };
  }
}

export function readDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => { const r = new FileReader(); r.onload = () => resolve(String(r.result)); r.onerror = () => reject(r.error); r.readAsDataURL(file); });
}

export interface DeskData {
  office: string; permissions: string[]; figures: Record<string, number>;
  desks: { code: string; label: string; active: boolean; lead_person: string | null; lead_name: string | null }[];
  groups: { code: string; label: string }[]; categories: { code: string; grp: string; label: string }[];
  faculties: { code: string; name: string }[]; departments: { code: string; name: string; faculty_code: string }[];
  reviewerOffices: { code: string; label: string }[]; owners: { id: string; name: string }[];
  ddItems: { code: string; label: string }[]; outcomeKinds: { code: string; label: string }[];
  settings: Record<string, unknown>;
}
export const can = (d: { permissions: string[] } | null | undefined, p: string) => !!d && d.permissions.includes(p);
