"use client";

/** What every student screen shares: one way of posting an act to the API and refreshing the screen from what the register now says. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { Btn, Note } from "@/components/proto/ui";
import { QuicktellerPay } from "@/components/QuicktellerPay";
import { PAY_LABEL, isQuicktellerCheckout, type QuicktellerCheckout } from "@/lib/quickteller";
import { OnlyThisReference, PaymentStarted, useReferenceState } from "@/components/PaymentStarted";

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

/**
 * Card and USSD through whichever gateway is wired; when more than one is on, the payer picks.
 * Pay on Quickteller (V299) opens the University's biller page on quickteller.com in a new tab,
 * the reference (and the amount) filled in; Interswitch's report confirms the payment.
 * Oct 2026: a reference Quickteller was already told may be paid, with no payment reported, leads with "I've paid — check
 * now" and keeps paying as the second choice (PaymentStarted).
 */
/** V635: what the portal answers when an expired reference is regenerated — the same reference payable again (REOPENED), a new one
 *  for what is owed now (NEW: school fees or the GST fee, part paid since), or the one still open (OPEN) */
export type Renewed = { reference: string; amount: number | string; expiresAt: string; purpose: string; outcome: "REOPENED" | "NEW" | "OPEN" };

/** V635: regenerate an expired, unpaid reference — school fees, the GST fee and every payment the student started. The server decides
 *  whether what it pays for is still owed; the screen is read again afterwards. */
export function RenewReference({ reference, onDone, label = "Regenerate", kind = "primary" }: { reference: string; onDone?: (r: Renewed) => void; label?: string; kind?: "primary" | "ghost" }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  async function renew() {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/me/fees/references/${encodeURIComponent(reference)}/renew`, { method: "POST", headers: { "X-Reason": reasonHeader(`Payment reference ${reference} regenerated by the student`) } });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        const p = j && typeof j === "object" && "status" in j ? (j as Problem & { code?: string }) : { status: r.status, title: "The reference could not be regenerated" };
        // Oct 2026: what it paid for is paid, or no longer owed — said as such, not as the request's status
        const settled = "code" in p && ["REFERENCE_NOTHING_OWED", "REFERENCE_PAID", "GST_ALREADY_PAID"].includes(String(p.code));
        notifyProblem(settled ? { ...p, title: "Nothing to pay" } : p);
        if (settled) router.refresh();
        return;
      }
      const x = j as Renewed;
      notify(x.reference === reference
        ? `${reference} can be paid again until ${when(x.expiresAt)}.`
        : `${reference} is replaced by ${x.reference} for ${naira(x.amount)}, payable until ${when(x.expiresAt)}.`);
      onDone?.(x);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }
  return <Btn kind={kind} size="sm" busy={busy} busyLabel="Regenerating…" disabled={busy} onClick={() => void renew()}>{label}</Btn>;
}

export function PayByCard({ reference, amount }: { reference: string; amount: number }) {
  const state = useReferenceState(reference);
  // V635: an expired reference is regenerated here, then paid — the same reference, or the new one the portal gives
  const [renewed, setRenewed] = useState<Renewed | null>(null);
  const [payAnyway, setPayAnyway] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [choices, setChoices] = useState<string[] | null>(null);
  const [qt, setQt] = useState<QuicktellerCheckout | null>(null);
  // V367: whether any gateway would take this payment, asked once: with none wired the payer is told how to pay instead of a button that cannot work
  const [wired, setWired] = useState<boolean | null>(null);
  useEffect(() => {
    let alive = true;
    void fetch(`/api/bff/api/v1/payments/gateways?reference=${encodeURIComponent(reference)}`)
      .then((r) => (r.ok ? r.json() : null))
      .then((j: Record<string, boolean> | null) => { if (alive && j) setWired(Object.values(j).some(Boolean)); })
      .catch(() => undefined);
    return () => { alive = false; };
  }, [reference]);
  async function go(gateway?: string) {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/payments/checkout", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Checkout opened for ${reference}`) }, body: JSON.stringify(gateway ? { reference, gateway } : { reference }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(asProblem(j, r)); notifyProblem(asProblem(j, r));
        return;
      }
      if (isQuicktellerCheckout(j)) { setQt(j); setChoices(null); return; }
      window.location.href = String((j as { url: string }).url);
    } finally {
      setBusy(false);
    }
  }
  async function start() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/payments/gateways?reference=${encodeURIComponent(reference)}`);
      const j = (await r.json().catch(() => null)) as Record<string, boolean> | null;
      const on = j ? Object.keys(j).filter((k) => j[k]) : [];
      if (on.length > 1) { setChoices(on); setBusy(false); return; }
      await go(on[0]);
    } catch {
      setBusy(false);
      await go();
    }
  }
  if (qt) return <QuicktellerPay qt={qt} onClose={() => setQt(null)} />;
  if (renewed && renewed.reference !== reference) {
    return (
      <>
        <div className="sub2" style={{ flexBasis: "100%" }}>New reference <b className="tnum">{renewed.reference}</b> · {naira(renewed.amount)} · payable until {when(renewed.expiresAt)}.</div>
        <PayByCard reference={renewed.reference} amount={Number(renewed.amount)} />
      </>
    );
  }
  if (state && state.expired && !state.confirmed && !renewed) {
    return (
      <Note kind="bad" title={`Reference ${reference} has expired`} action={state.renewable ? <RenewReference reference={reference} onDone={setRenewed} /> : null}>
        {state.expiresAt ? `It was payable until ${when(state.expiresAt)}. ` : ""}{state.renewable ? "Regenerate it to pay; it is free of charge, and nothing paid against it is lost." : "Generate a new one; it is free of charge."}
      </Note>
    );
  }
  const begun = !!state?.startedAt && !state.confirmed;
  if (state && begun && !payAnyway) {
    return <PaymentStarted reference={reference} state={state} onPay={() => setPayAnyway(true)}
      report={{ href: `/student/support?office=bursar&subject=${encodeURIComponent(`Payment not confirmed: ${reference}`)}`, label: "Report it to the Bursary" }} />;
  }
  if (wired === false) {
    return (
      <>
        <Note kind="info" title="Card and USSD payment is not open yet">
          Pay {naira(amount)} against reference <b className="tnum">{reference}</b> at a bank branch or by bank transfer, quoting the reference.
        </Note>
        <OnlyThisReference reference={reference} again={begun} />
      </>
    );
  }
  return (
    <>
      {choices ? (
        <div className="row">
          <span className="sub2">Pay {naira(amount)} with</span>
          {choices.map((g) => <Btn key={g} kind="go" size="md" disabled={busy} onClick={() => void go(g)}>{PAY_LABEL[g] ?? g}</Btn>)}
          <Btn kind="ghost" size="md" disabled={busy} onClick={() => setChoices(null)}>Cancel</Btn>
        </div>
      ) : (
        <Btn kind="go" size="md" disabled={busy} onClick={() => void start()}>{busy ? "Opening the checkout…" : `Pay ${naira(amount)} by card or USSD`}</Btn>
      )}
      <OnlyThisReference reference={reference} again={begun} />
      {problem ? (
        <div className="mt-2" style={{ flexBasis: "100%" }}>
          <Note kind="info" title={`${problem.title ?? "Not now"}.`}>{problem.detail ?? ""} {problem.remedy ? <span className="sub2">{problem.remedy.message}</span> : null}</Note>
        </div>
      ) : null}
    </>
  );
}
