"use client";

/** the programme swap screens' requests (V578): read and write through the BFF, the reason on every write, a refusal said as the server's */
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";

export const SWAPS = "/api/bff/api/v1/programme-swaps";

export type Answer<T> = { ok: true; data: T } | { ok: false; problem: Problem };

export async function swapGet<T>(path: string): Promise<Answer<T>> {
  const r = await fetch(`${SWAPS}${path}`, { cache: "no-store" });
  const j = await r.json().catch(() => null);
  return r.ok ? { ok: true, data: j as T } : { ok: false, problem: (j as Problem) ?? { status: r.status, title: r.statusText } };
}

export async function swapPost<T>(path: string, body: unknown, reason: string): Promise<Answer<T>> {
  const r = await fetch(`${SWAPS}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) },
    body: JSON.stringify(body ?? {}),
  });
  const j = await r.json().catch(() => null);
  return r.ok ? { ok: true, data: j as T } : { ok: false, problem: (j as Problem) ?? { status: r.status, title: r.statusText } };
}

/** a chosen file as a data URL, for the evidence upload */
export function fileAsDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const fr = new FileReader();
    fr.onload = () => resolve(String(fr.result));
    fr.onerror = () => reject(fr.error);
    fr.readAsDataURL(file);
  });
}
