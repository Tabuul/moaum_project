"use client";

/**
 * Oct 2026: a reference Quickteller has already been told may be paid ("Reference valid" on the Bursary's log) with no
 * payment reported for it — the payer pressed Continue on Quickteller's page or at a bank. That is not a payment: it counts
 * only when Interswitch reports it. So the pay block leads with "I've paid — check now", keeps paying as the second choice
 * with a warning never to pay the same reference twice, and after a day points to the office that can trace the payment.
 * Also the one line every pay block carries: only this reference pays it (Quickteller refuses any other number, and its
 * refusal carries no words of ours).
 */
import { useEffect, useState } from "react";
import { Btn } from "@/components/proto/ui";

const DAY_MS = 24 * 60 * 60 * 1000;

export interface ReferenceState {
  confirmed: boolean;
  /** when Quickteller was last told the reference may be paid, while no payment is reported */
  startedAt: string | null;
  /** a day or more since then */
  longAgo: boolean;
}

async function readState(reference: string): Promise<ReferenceState | null> {
  const r = await fetch(`/api/bff/api/v1/payments/state?reference=${encodeURIComponent(reference)}`, { cache: "no-store" });
  if (!r.ok) return null;
  const j = (await r.json().catch(() => null)) as { confirmed?: boolean; startedAt?: string | null } | null;
  if (!j) return null;
  const startedAt = j.startedAt ?? null;
  return { confirmed: !!j.confirmed, startedAt, longAgo: !!startedAt && Date.now() - Date.parse(startedAt) >= DAY_MS };
}

/** the reference as the University's record has it, read once when the pay block opens */
export function useReferenceState(reference: string): ReferenceState | null {
  const [state, setState] = useState<ReferenceState | null>(null);
  useEffect(() => {
    let alive = true;
    readState(reference).then((s) => { if (alive) setState(s); }).catch(() => undefined);
    return () => { alive = false; };
  }, [reference]);
  return state;
}

function at(iso: string): string {
  const d = new Date(iso);
  return `${d.toLocaleDateString("en-GB", { day: "numeric", month: "short" })} at ${d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })}`;
}

/** a payment begun on Quickteller and not yet reported: check first, pay again only when nothing was paid */
export function PaymentStarted({ reference, state, onPay, report }: {
  reference: string;
  state: ReferenceState;
  /** the payer did not complete it: the ordinary pay controls */
  onPay: () => void;
  /** where a payment still unconfirmed after a day is reported */
  report: { href: string; label: string };
}) {
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  async function check() {
    setBusy(true);
    setSaid(null);
    try {
      const s = await readState(reference);
      if (s?.confirmed) {
        window.location.reload();
        return;
      }
      setSaid(s ? "Not confirmed yet. Interswitch usually reports a payment within minutes; wait a little and check again. Do not pay the same reference twice."
        : "The portal could not be reached just now. Wait a moment and check again.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="notice notice--info mt-2" style={{ flexBasis: "100%" }}>
      <div style={{ minWidth: 0 }}>
        <div className="notice__t">You started paying on Quickteller on {at(state.startedAt ?? "")}</div>
        <p>
          The payment of <b className="tnum">{reference}</b> counts only when Interswitch reports it to the University, usually within minutes.
          If money has left your account for it, do not pay again: check here instead.
        </p>
        <div className="row mt-2">
          <Btn kind="primary" size="md" disabled={busy} onClick={() => void check()}>{busy ? "Checking…" : "I've paid — check now"}</Btn>
          <Btn kind="ghost" size="md" disabled={busy} onClick={onPay}>I did not complete the payment — pay now</Btn>
        </div>
        {state.longAgo ? (
          <p className="sub2 mt-2">Paid, and still not confirmed a day later? <a className="lnk" href={report.href}>{report.label}</a> with this reference and your bank&rsquo;s debit details, so the payment can be traced.</p>
        ) : null}
        {said ? <p className="sub2 mt-2"><b>{said}</b></p> : null}
      </div>
    </div>
  );
}

/** the line under every pay button: only this reference pays it */
export function OnlyThisReference({ reference, again }: { reference: string; again?: boolean }) {
  return (
    <div className="sub2 mt-1" style={{ flexBasis: "100%" }}>
      {again ? <><b>Pay only if no money left your account for this reference: the same reference is never paid twice.</b> </> : null}
      On Quickteller or at a bank, enter exactly <b className="tnum">{reference}</b>. Any other number, such as one starting with PR, is refused and pays nothing.
    </div>
  );
}
