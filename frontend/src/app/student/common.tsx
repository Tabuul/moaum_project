"use client";

/** What every student screen shares: one way of posting an act to the API and refreshing the screen from what the register now says. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";

export function useAct() {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  async function act(key: string, method: "POST" | "PUT", path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1${path}`, {
        method,
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) },
        body: JSON.stringify(body ?? {}),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText });
        return null;
      }
      router.refresh();
      return (j ?? {}) as Record<string, unknown>;
    } finally {
      setBusy(null);
    }
  }
  return { act, busy, problem, setProblem };
}

export function when(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit" });
}

export function onDay(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
}

export function naira(n: number | string | null | undefined): string {
  if (n === null || n === undefined) return "—";
  return `₦${Number(n).toLocaleString("en-NG", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
}

/** Card and USSD through whichever gateway is wired, against a reference this portal generated. */
export function PayByCard({ reference, amount }: { reference: string; amount: number }) {
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  async function go() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/payments/checkout", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Checkout opened for ${reference}`) }, body: JSON.stringify({ reference }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText });
        return;
      }
      window.location.href = String((j as { url: string }).url);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <button type="button" className="btn btn--go" disabled={busy} onClick={() => void go()}>{busy ? "Opening the checkout…" : `Pay ${naira(amount)} by card or USSD`}</button>
      {problem ? (
        <div style={{ flexBasis: "100%" }}>
          <div className="notice notice--info" style={{ marginTop: 6 }}>
            <p><b>{problem.title ?? "Not now"}.</b> {problem.detail ?? ""} {problem.remedy ? <span className="sub2">{problem.remedy.message}</span> : null}</p>
          </div>
        </div>
      ) : null}
    </>
  );
}
