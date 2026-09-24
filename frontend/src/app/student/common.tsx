"use client";

/** What every student screen shares: one way of posting an act to the API and refreshing the screen from what the register now says. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";

export function useAct() {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  // `success` is the popup shown when the act succeeds (default "Saved"); pass "" to suppress it.
  async function act(key: string, method: "POST" | "PUT", path: string, body: unknown, reason: string, success = "Saved"): Promise<Record<string, unknown> | null> {
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
        const p = j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText };
        setProblem(p);
        notify(p.detail || p.title || "That did not go through", "bad");
        return null;
      }
      router.refresh();
      if (success) {
        notify(success);
      }
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

const GATEWAY_LABEL: Record<string, string> = { paystack: "Paystack", flutterwave: "Flutterwave", quickteller: "Quickteller", paydirect: "Quickteller PayDirect" };

/** a failed checkout as something readable: the portal's own Problem when it sent one, else the server's
 *  plain error (Spring's {status, error, message}), else the HTTP status — never a blank notice */
export function asProblem(j: unknown, r: Response): Problem {
  if (j && typeof j === "object") {
    const o = j as Record<string, unknown>;
    if (typeof o.title === "string" && o.title) return o as unknown as Problem;
    const title = (typeof o.error === "string" && o.error) || (typeof o.message === "string" && o.message) || null;
    const detail = typeof o.message === "string" && o.message !== title ? o.message : undefined;
    if (title) return { status: r.status, title: `The checkout could not be opened (${title})`, detail };
  }
  return { status: r.status, title: `The checkout could not be opened (HTTP ${r.status})`, detail: "Try again in a moment, or pay by transfer or at a branch against the reference." };
}

interface Paydirect { gateway: string; billerName: string; billerCode: string; prn: string; payLink: string | null; ussd: string }

/** Card and USSD through whichever gateway is wired; when more than one is on, the payer picks. */
export function PayByCard({ reference, amount }: { reference: string; amount: number }) {
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [choices, setChoices] = useState<string[] | null>(null);
  const [pd, setPd] = useState<Paydirect | null>(null);
  const [checkMsg, setCheckMsg] = useState<string | null>(null);
  async function check(prn: string) {
    setBusy(true);
    setProblem(null);
    setCheckMsg(null);
    try {
      const r = await fetch("/api/bff/api/v1/payments/verify", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Checked ${prn}`) }, body: JSON.stringify({ reference: prn }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      const outcome = String((j as { outcome?: string })?.outcome ?? "");
      if (outcome === "confirmed" || outcome === "already confirmed") { window.location.reload(); return; }
      setCheckMsg("Not confirmed yet. If you have just paid, it can take a few minutes to reach the University — wait a moment and check again.");
    } finally {
      setBusy(false);
    }
  }
  async function go(gateway?: string) {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/payments/checkout", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Checkout opened for ${reference}`) }, body: JSON.stringify(gateway ? { reference, gateway } : { reference }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(asProblem(j, r));
        return;
      }
      if (j && (j as Paydirect).gateway === "paydirect") { setPd(j as Paydirect); setChoices(null); return; }
      window.location.href = String((j as { url: string }).url);
    } finally {
      setBusy(false);
    }
  }
  async function start() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/payments/gateways");
      const j = (await r.json().catch(() => null)) as Record<string, boolean> | null;
      const on = j ? Object.keys(j).filter((k) => j[k]) : [];
      if (on.length > 1) { setChoices(on); setBusy(false); return; }
      await go(on[0]);
    } catch {
      setBusy(false);
      await go();
    }
  }
  return (
    <>
      {pd ? (
        <div className="notice notice--info mt-2">
          <p><b>Pay {naira(amount)} to {pd.billerName} on Quickteller.</b></p>
          <p>Your Payment Reference Number (PRN) is <b className="tnum">{pd.prn}</b>. Enter it on any of these — the payment reaches the University and clears your fee automatically:</p>
          <ul style={{ margin: "6px 0 0 18px" }}>
            <li>Online: {pd.payLink ? <a href={pd.payLink} target="_blank" rel="noreferrer">{pd.payLink}</a> : <>Quickteller, biller code <b className="tnum">{pd.billerCode}</b></>}</li>
            <li>USSD: <b className="tnum">{pd.ussd}</b></li>
            <li>Any bank branch or ATM: quote biller code <b className="tnum">{pd.billerCode}</b> and the PRN above.</li>
          </ul>
          <p className="sub2 mt-2">Keep the PRN. After you pay, use &ldquo;I&rsquo;ve paid&rdquo; below — or it is confirmed automatically once the collection reaches the University; the receipt then shows on your Fees page.</p>
          <div className="row">
            <button type="button" className="btn btn--go btn--sm" disabled={busy} onClick={() => void check(pd.prn)}>{busy ? "Checking…" : "I've paid — check now"}</button>
            <button type="button" className="btn btn--ghost btn--sm" disabled={busy} onClick={() => setPd(null)}>Choose another way to pay</button>
          </div>
          {checkMsg ? <p className="sub2 mt-2">{checkMsg}</p> : null}
        </div>
      ) : choices ? (
        <div className="row">
          <span className="sub2">Pay {naira(amount)} with</span>
          {choices.map((g) => <button key={g} type="button" className="btn btn--go" disabled={busy} onClick={() => void go(g)}>{GATEWAY_LABEL[g] ?? g}</button>)}
          <button type="button" className="btn btn--ghost" disabled={busy} onClick={() => setChoices(null)}>Cancel</button>
        </div>
      ) : (
        <button type="button" className="btn btn--go" disabled={busy} onClick={() => void start()}>{busy ? "Opening the checkout…" : `Pay ${naira(amount)} by card or USSD`}</button>
      )}
      {problem ? (
        <div style={{ flexBasis: "100%" }}>
          <div className="notice notice--info mt-2">
            <p><b>{problem.title ?? "Not now"}.</b> {problem.detail ?? ""} {problem.remedy ? <span className="sub2">{problem.remedy.message}</span> : null}</p>
          </div>
        </div>
      ) : null}
    </>
  );
}
