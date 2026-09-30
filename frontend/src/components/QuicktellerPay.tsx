"use client";

/**
 * Pay on Quickteller (V299): the link to the University's biller page on
 * quickteller.com, the portal's reference (and the amount) already in it. The
 * page opens in a new tab, so this one stays open to come back to; the payment
 * is confirmed when Interswitch reports it, and "I've paid — check now" re-reads
 * the reference rather than trusting anybody's word.
 */
import { useState } from "react";
import { AFTER_PAYING, type QuicktellerCheckout } from "@/lib/quickteller";
import { Btn } from "@/components/proto/ui";

function naira(n: number | string): string {
  return `₦${Number(n).toLocaleString("en-NG", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
}

export function QuicktellerPay({ qt, onClose }: { qt: QuicktellerCheckout; onClose: () => void }) {
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  async function check() {
    setBusy(true);
    setSaid(null);
    try {
      // the reference as the University's record has it: Quickteller's payments are confirmed by Interswitch's report, not asked of a card gateway
      const r = await fetch(`/api/bff/api/v1/payments/state?reference=${encodeURIComponent(qt.reference)}`, { cache: "no-store" });
      const j = (await r.json().catch(() => null)) as { confirmed?: boolean } | null;
      if (r.ok && j?.confirmed) {
        window.location.reload();
        return;
      }
      setSaid("Not confirmed yet. If you have just paid, it can take a few minutes for Interswitch to report it to the University — wait a moment and check again. Do not pay the same reference twice.");
    } catch {
      setSaid("The portal could not be reached just now. Wait a moment and check again.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="notice notice--info mt-2" style={{ flexBasis: "100%" }}>
      <div style={{ minWidth: 0 }}>
        <div className="notice__t">Pay {naira(qt.amount)} on Quickteller{qt.biller ? ` · ${qt.biller}` : ""}</div>
        <p>
          Your payment reference <b className="tnum">{qt.reference}</b>{qt.withAmount === false ? " is" : " and the amount are"} filled in for you on Quickteller&rsquo;s page.
          Quickteller checks the reference with the University when you press <b>Continue</b>; pay by card, bank transfer, USSD or your Quickteller wallet.
        </p>
        <div className="row mt-2">
          <a className="btn btn--go btn--md" style={{ textDecoration: "none" }} href={qt.url} target="_blank" rel="noopener noreferrer">Continue to Quickteller &#8599;</a>
          <Btn kind="ghost" size="md" disabled={busy} onClick={() => void check()}>{busy ? "Checking…" : "I've paid — check now"}</Btn>
          <Btn kind="ghost" size="md" disabled={busy} onClick={onClose}>Choose another way to pay</Btn>
        </div>
        <p className="sub2 mt-2">{AFTER_PAYING}</p>
        {said ? <p className="sub2 mt-2"><b>{said}</b></p> : null}
      </div>
    </div>
  );
}
