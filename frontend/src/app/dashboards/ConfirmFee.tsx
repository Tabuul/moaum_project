"use client";

/** The Secretary confirms a postgraduate fee paid outside the gateway (a bank slip), against the application the
 *  reference was generated for. The API refuses a reference that belongs to another application. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn } from "@/components/proto/ui";

export function ConfirmFee({ applicationId, reference, who }: { applicationId: string; reference: string; who: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  async function confirm() {
    if (!window.confirm(`Confirm ${reference} as paid by bank for ${who}?`)) return;
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/pg/applications/${applicationId}/confirm-fee`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Fee ${reference} confirmed by bank`) },
        body: JSON.stringify({ reference, channel: "bank" }),
      });
      if (!r.ok) { notifyProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }); return; }
      notify(`${reference} confirmed`);
      router.refresh();
    } finally { setBusy(false); }
  }
  return <Btn kind="primary" size="sm" disabled={busy} onClick={() => void confirm()}>{busy ? "Confirming…" : "Confirm Paid"}</Btn>;
}
