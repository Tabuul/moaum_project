"use client";
/** V658: a new private link for a submitted enquiry, sent to the address it was submitted from (the same answer whether or not they match) */
import { useState } from "react";
import { Btn, Note } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";

export function LinkRequest() {
  const [reference, setReference] = useState("");
  const [email, setEmail] = useState("");
  const [hp, setHp] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function send(e: React.FormEvent) {
    e.preventDefault();
    setError(null); setDone(null);
    if (!/^PTN\/\d{4}\/\d{6}$/i.test(reference.trim())) { setError("Reference: enter it as it appears in your acknowledgement, such as PTN/2026/000125."); return; }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(email.trim())) { setError("Email address: enter the address the enquiry was submitted from."); return; }
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/public/partnerships/link", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ reference: reference.trim().toUpperCase(), email: email.trim(), website2: hp }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setError((j && (j.detail || j.title)) || "The request did not go through; try again."); return; }
      setDone("If the reference and the email address match an enquiry, a new private link has been sent to that address. The earlier link no longer works.");
    } catch { setError("The request did not go through; try again."); }
    finally { setBusy(false); }
  }

  return (
    <form onSubmit={send} className="stack" noValidate>
      <div className="ptn-row">
        <Field id="lk-ref" label="Reference" required error={error?.startsWith("Reference") ? error : null}>
          <input id="lk-ref" className="ctl tnum" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="PTN/2026/000125" autoComplete="off" maxLength={20} />
        </Field>
        <Field id="lk-email" label="Email address" required error={error?.startsWith("Email") ? error : null}>
          <input id="lk-email" className="ctl" type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" maxLength={200} />
        </Field>
      </div>
      <div className="ptn-hp" aria-hidden="true"><label htmlFor="lk-website2">Leave this empty</label><input id="lk-website2" tabIndex={-1} autoComplete="off" value={hp} onChange={(e) => setHp(e.target.value)} /></div>
      {error && !error.startsWith("Reference") && !error.startsWith("Email") ? <Note kind="bad" title={error} /> : null}
      {done ? <Note kind="ok" title={done} /> : null}
      <div><Btn kind="secondary" type="submit" busy={busy} busyLabel="Sending…">Send a new link</Btn></div>
    </form>
  );
}
