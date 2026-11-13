"use client";

/** V430: "how do we reach you" — shown on the first screen while the portal holds no usable e-mail or phone for the person.
 *  One line, two fields, Save or Not now (seven days). The answer is the contact they already keep: a student's own
 *  contact, a staff member's record. Nobody is locked out.
 *  V749: a member of staff gives the phone here and nothing else — a new staff e-mail address is verified by a code sent to it, at
 *  My identity, the old one kept until then — so the staff banner has no e-mail box and its save sends no e-mail: the API keeps
 *  the address on record as it stands then, so one verified or corrected since the banner was drawn never refuses the phone. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { contactPromptBody, contactPromptPlan } from "@/lib/identity";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn } from "@/components/proto/ui";

export interface ContactPromptData { state: string; kind: "student" | "person"; email: string | null; phone: string | null; email_ok: boolean; phone_ok: boolean }

export function ContactPrompt({ p }: { p: ContactPromptData }) {
  const router = useRouter();
  const plan = contactPromptPlan(p);
  const [email, setEmail] = useState(p.email_ok ? p.email ?? "" : "");
  const [phone, setPhone] = useState(p.phone_ok ? p.phone ?? "" : "");
  const [busy, setBusy] = useState(false);
  const [gone, setGone] = useState(false);
  if (gone) return null;
  const missing = [p.email_ok ? null : "e-mail address", p.phone_ok ? null : "phone number"].filter(Boolean).join(" and ");

  async function save() {
    setBusy(true);
    try {
      const url = p.kind === "student" ? "/api/bff/api/v1/me/contact" : "/api/bff/api/v1/staff/contact";
      // a member of staff's e-mail is never changed here, nor sent: the API keeps the one on record as it stands when saved
      const body = contactPromptBody(p.kind, email, phone);
      const r = await fetch(url, { method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("How we reach you, given at sign-in") }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify("Thank you — the portal can now reach you");
      setGone(true);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  async function later() {
    setBusy(true);
    try {
      await fetch("/api/bff/api/v1/me/contact-prompt/skip", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Contact prompt put off") }, body: "{}" });
      setGone(true);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="notice notice--warn" role="region" aria-label="How do we reach you">
      <div style={{ flex: 1 }}>
        <div className="notice__t">How do we reach you?</div>
        <p>
          The portal has no usable {missing} for you, so notices, results, payment confirmations and password resets cannot reach you.
          {plan.emailAtIdentity ? " Your e-mail address is verified by a code sent to it, at My identity." : " One line, and it is done."}
        </p>
        <form className="row row--wrap row--tight" onSubmit={(e) => { e.preventDefault(); if (plan.phoneBox) void save(); }}>
          {plan.emailBox ? <input className="ctl" type="email" placeholder="E-mail address" aria-label="E-mail address" value={email} onChange={(e) => setEmail(e.target.value)} style={{ minWidth: 220 }} /> : null}
          {plan.phoneBox ? <input className="ctl tnum" type="tel" placeholder="Phone, e.g. 0801 234 5678" aria-label="Phone number" value={phone} onChange={(e) => setPhone(e.target.value)} style={{ minWidth: 180 }} /> : null}
          {plan.phoneBox ? <Btn kind="primary" size="sm" type="submit" disabled={busy || (!(plan.emailBox && email.trim()) && !phone.trim())}>Save</Btn> : null}
          {plan.emailAtIdentity ? <LinkBtn kind={plan.phoneBox ? "ghost" : "primary"} size="sm" href="/me/identity#email">Add your e-mail at My identity</LinkBtn> : null}
          <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void later()}>Not now</Btn>
        </form>
      </div>
    </div>
  );
}
