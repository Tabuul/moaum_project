"use client";

/** V575: a contact a department uploaded for the student and the student has not confirmed — shown on the first screen. Until it
 *  is confirmed no password reset link goes to it. The student has a six-digit code sent to it and enters it here, or says it is
 *  not theirs (the University stops using it). Nothing is locked meanwhile; the prompt stays until each one is answered. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn } from "@/components/proto/ui";

export interface ContactConfirmData { email: string | null; phone: string | null }

type Field = "EMAIL" | "PHONE";
const WORD: Record<Field, string> = { EMAIL: "e-mail address", PHONE: "phone number" };

async function post(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
  const r = await fetch(`/api/bff/api/v1/me/contact/${path}`, {
    method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body),
  });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
  return j as Record<string, unknown>;
}

function One({ field, value, onDone }: { field: Field; value: string; onDone: () => void }) {
  const [sent, setSent] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);

  async function send() {
    setBusy(true);
    try {
      const j = await post("confirm/code", { field }, `A code to confirm my ${WORD[field]}`);
      if (j) { setSent(String(j.sentTo ?? value)); notify(`A code was sent to ${String(j.sentTo ?? value)}`); }
    } finally { setBusy(false); }
  }

  async function confirm() {
    setBusy(true);
    try {
      const j = await post("confirm", { field, code: code.trim() }, `My ${WORD[field]} confirmed`);
      if (!j) return;
      if (j.outcome === "CONFIRMED") { notify(`Your ${WORD[field]} is confirmed`); onDone(); return; }
      if (j.outcome === "WRONG") notifyProblem({ status: 400, title: "That code is not the one sent.", detail: "Check the latest message and try again." });
      else { notifyProblem({ status: 400, title: "That code has run out.", detail: "Ask for a new one." }); setSent(null); setCode(""); }
    } finally { setBusy(false); }
  }

  async function notMine() {
    setBusy(true);
    try {
      const j = await post("not-mine", { field }, `This ${WORD[field]} is not mine`);
      if (j) { notify(`The ${WORD[field]} is taken off your record`); onDone(); }
    } finally { setBusy(false); }
  }

  return (
    <div className="row row--wrap row--tight" style={{ alignItems: "center", gap: 8, marginTop: 6 }}>
      <span><b className="tnum">{value}</b> <span className="sub2">({WORD[field]})</span></span>
      {sent ? (
        <form className="row row--tight" style={{ gap: 6 }} onSubmit={(e) => { e.preventDefault(); void confirm(); }}>
          <input className="ctl tnum" inputMode="numeric" autoComplete="one-time-code" maxLength={6} placeholder="6-digit code" aria-label={`Code sent to your ${WORD[field]}`}
            value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))} style={{ width: 120 }} />
          <Btn kind="primary" size="sm" type="submit" disabled={busy || code.length !== 6}>Confirm</Btn>
          <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void send()}>Send again</Btn>
        </form>
      ) : (
        <>
          <Btn kind="primary" size="sm" disabled={busy} onClick={() => void send()}>Send me a code</Btn>
          <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void notMine()}>This is not mine</Btn>
        </>
      )}
    </div>
  );
}

export function ContactConfirm({ c }: { c: ContactConfirmData }) {
  const router = useRouter();
  const [done, setDone] = useState<Record<Field, boolean>>({ EMAIL: false, PHONE: false });
  const left = (["EMAIL", "PHONE"] as Field[]).filter((f) => !done[f] && (f === "EMAIL" ? c.email : c.phone));
  if (!left.length) return null;
  const finish = (f: Field) => { setDone((d) => ({ ...d, [f]: true })); router.refresh(); };
  return (
    <div className="notice notice--warn" role="region" aria-label="Confirm your contact">
      <div style={{ flex: 1 }}>
        <div className="notice__t">Is this yours?</div>
        <p>
          Your department gave the University {left.length === 2 ? "this e-mail address and phone number" : `this ${WORD[left[0]]}`} for you. Confirm it with a code sent to it,
          or tell us it is not yours. Until it is confirmed, no password reset link is sent to it.
        </p>
        {left.map((f) => <One key={f} field={f} value={(f === "EMAIL" ? c.email : c.phone) as string} onDone={() => finish(f)} />)}
      </div>
    </div>
  );
}
