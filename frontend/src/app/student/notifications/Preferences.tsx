"use client";

/** V426: the student's own switches for e-mail and SMS on optional messages (announcements); results, payments, admission
 *  decisions, windows and the biodata reminder are mandatory and always sent. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface Prefs { email: boolean; sms: boolean }

export function Preferences({ prefs, email, phone, base = "/api/bff/api/v1/me/notifications/preferences" }: { prefs: Prefs; email: string | null; phone: string | null; base?: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [p, setP] = useState<Prefs>(prefs);

  async function set(next: Partial<Prefs>) {
    setBusy(true);
    try {
      const r = await fetch(base, { method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Notification preference changed") }, body: JSON.stringify(next) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setP(j as Prefs);
      notify("Saved");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const toggle = (k: keyof Prefs) => (
    <label className="row row--inline row--tight" key={k}>
      <input type="checkbox" checked={p[k]} disabled={busy} onChange={(e) => void set({ [k]: e.target.checked })} /> {p[k] ? "On" : "Off"}
    </label>
  );

  return (
    <Panel title="How we reach you">
      <DTable cols={["Channel", "Transactional|mid", "Announcements|mid"]} rows={[
        [<span key="e">Email · {email ?? "none on file"}</span>, <Pil kind="ok" key="t">Always on</Pil>, email ? toggle("email") : <Pil kind="bad" key="a">No address</Pil>],
        [<span key="s">SMS · {phone ?? "none on file"}</span>, <Pil kind="ok" key="t">Always on</Pil>, phone ? toggle("sms") : <Pil kind="bad" key="a">No number</Pil>],
        [<span key="i">In-app</span>, <Pil kind="ok" key="t">Always on</Pil>, <Pil kind="ok" key="a">On</Pil>],
      ]} />
      <PBody><div className="sub2">Change the address and number on your profile. Results, payments, admission decisions, portal windows and the biodata reminder are always sent; the switches cover announcements.</div></PBody>
    </Panel>
  );
}
