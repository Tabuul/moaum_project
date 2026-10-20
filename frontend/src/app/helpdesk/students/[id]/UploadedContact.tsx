"use client";

/** V575: on the desk's Reach panel, a phone or e-mail a department uploaded that the student has not confirmed. No reset link goes
 *  to it until it is confirmed; an agent with contact editing confirms it after checking it with the student, saying how. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Pil } from "@/components/proto/ui";

export function UploadedContact({ id, field, may, ticket }: { id: string; field: "EMAIL" | "PHONE"; may: boolean; ticket: string | null }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [why, setWhy] = useState("");
  const [busy, setBusy] = useState(false);
  const word = field === "EMAIL" ? "e-mail address" : "phone number";

  async function confirm() {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/helpdesk/support/students/${encodeURIComponent(id)}/contact/confirm`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Uploaded ${word} confirmed with the student: ${why.trim()}`) },
        body: JSON.stringify({ field, reason: why.trim(), ticket }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(`The ${word} is confirmed: reset links may go to it`);
      setOpen(false);
      router.refresh();
    } finally { setBusy(false); }
  }

  return (
    <div className="stack" style={{ gap: 4, alignItems: "flex-end" }}>
      <Pil kind="warn">From an upload — not confirmed</Pil>
      {may && !open ? <Btn kind="ghost" size="sm" onClick={() => setOpen(true)}>Confirmed with the student</Btn> : null}
      {may && open ? (
        <form className="row row--tight" style={{ gap: 6, flexWrap: "wrap", justifyContent: "flex-end" }} onSubmit={(e) => { e.preventDefault(); void confirm(); }}>
          <input className="ctl" style={{ minWidth: 220 }} placeholder="How it was checked (10 characters or more)" aria-label={`How the ${word} was checked`}
            value={why} onChange={(e) => setWhy(e.target.value)} maxLength={2000} />
          <Btn kind="primary" size="sm" type="submit" disabled={busy || why.trim().length < 10}>Confirm</Btn>
          <Btn kind="ghost" size="sm" disabled={busy} onClick={() => setOpen(false)}>Cancel</Btn>
        </form>
      ) : null}
    </div>
  );
}
