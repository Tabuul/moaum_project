"use client";
/** /track — the public tracking page (V251): a ticket number and the email it was raised with open the ticket's
 *  standing and its user-facing history. Nothing internal, no files, nothing without both. */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { PriorityPil, StatusPil, Timeline, when, type Event } from "@/lib/helpdesk";

interface Tracked { number: string; subject: string; category: string; status: string; priority: string; created_at: string; updated_at: string; resolved_at: string | null; closed_at: string | null; resolution_summary: string | null; requester_name: string; reopen_count: number; timeline: Event[] }

export default function TrackPage() {
  const [number, setNumber] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  const [t, setT] = useState<Tracked | null>(null);

  async function go(e: React.FormEvent) {
    e.preventDefault();
    if (!number.trim() || !email.trim()) return;
    setBusy(true); setProblem(null); setT(null);
    try {
      const r = await fetch("/api/bff/api/v1/helpdesk/track", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ number: number.trim().toUpperCase(), email: email.trim() }) });
      const j = (await r.json().catch(() => null)) as Tracked | Problem | null;
      if (!r.ok || !j || !("number" in j)) { setProblem(r.status === 404 ? "No ticket with that number was raised with that email address. Check both and try again." : "The ticket could not be looked up just now. Try again in a moment."); return; }
      setT(j);
    } catch { setProblem("The ticket could not be looked up just now. Try again in a moment."); }
    finally { setBusy(false); }
  }

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-8) var(--s-4)" }}>
      <div className="stack" style={{ width: "100%", maxWidth: 640 }}>
        <div className="card" style={{ overflow: "hidden" }}>
          <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
            <div className="grow">
              <div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
              <div className="phead__t ink-chrome">Track an ICT Support Ticket</div>
            </div>
          </div>
          <form onSubmit={go} className="card__body">
            <p className="m-0 ink-muted">Enter the ticket number you were given and the email address the ticket was raised with. Only the two together open it.</p>
            <Field id="tr-number" label="Ticket number"><input id="tr-number" className="ctl tnum" value={number} onChange={(e) => setNumber(e.target.value)} placeholder="TICK-2026-00000" autoComplete="off" autoCapitalize="characters" /></Field>
            <Field id="tr-email" label="Email address"><input id="tr-email" className="ctl" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" autoComplete="email" /></Field>
            {problem ? <div className="notice notice--bad"><div>{problem}</div></div> : null}
            <div className="row row--base"><Btn kind="primary" type="submit" disabled={busy || !number.trim() || !email.trim()}>{busy ? "Looking up…" : "Track Ticket"}</Btn><a className="lnk" href="/login">Sign in to the portal instead</a></div>
          </form>
        </div>
        {t ? (
          <div className="card" style={{ overflow: "hidden" }}>
            <div className="card__head">
              <div className="grow"><div className="eyebrow">{t.category}</div><div className="phead__t">{t.number}</div><div className="sub2">{t.subject}</div></div>
              <div className="row row--tight"><StatusPil status={t.status} /><PriorityPil priority={t.priority} /></div>
            </div>
            <div className="card__body">
              <div className="grid grid--2">
                <div className="kv"><span className="k">Raised</span><span className="v tnum">{when(t.created_at)}</span></div>
                <div className="kv"><span className="k">Last updated</span><span className="v tnum">{when(t.updated_at)}</span></div>
                <div className="kv"><span className="k">Resolution</span><span className="v">{t.resolution_summary ? <>{t.resolution_summary}<div className="sub2 tnum">{when(t.resolved_at)}</div></> : t.status === "CLOSED" ? "Closed without a resolution recorded" : "Not yet resolved"}</span></div>
                <div className="kv"><span className="k">Closed</span><span className="v tnum">{t.closed_at ? when(t.closed_at) : "—"}</span></div>
              </div>
              {t.status === "RESOLVED" ? <div className="notice notice--ok"><div>Your issue has been marked as resolved. Sign in to the portal to confirm the resolution, or to reopen the ticket if it is not settled.</div></div> : null}
              <div className="hr" />
              <div className="b600 mb-2">History</div>
              <Timeline events={t.timeline} showInternal={false} />
              {t.reopen_count ? <div className="sub2 mt-2"><Pil kind="grey">Reopened {t.reopen_count} time{t.reopen_count === 1 ? "" : "s"}</Pil></div> : null}
            </div>
          </div>
        ) : null}
      </div>
    </div>
  );
}
