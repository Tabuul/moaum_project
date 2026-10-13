"use client";

/** pNotify / tChannels — proto/part…: the outbox. A message is marked sent only when the
 *  provider acknowledges it; nothing is pretended. Failed notices can be put back in the queue.
 *  V425: the history searched (channel, state, what it is about, words, a day range), the picture by
 *  channel, and the portal as a channel of its own. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { QueueManagement, type Clearance, type Delivery, type OpenJob, type Pending, type Receipt } from "./QueueManagement";
import { ProviderHealth, type ProviderRow, type ProviderSettings } from "./ProviderHealth";

export interface Recent {
  id: string; channel: string; recipient: string; subject: string; created_at: string; state: string; attempts: number; sent_at: string | null; last_error: string | null;
  about_kind?: string | null; about_name?: string | null; template_key?: string | null; priority?: string | null; event_key?: string | null;
  cancel_reason?: string | null;
  /** V438: the provider's word after accepting the message */
  delivery_state?: string | null; delivered_at?: string | null; delivery_detail?: string | null;
}
export interface ByChannel { channel: string; total: number; sent: number; queued: number; failed: number; cancelled?: number; delivered?: number; bounced?: number; invalid: number; week: number; week_sent: number; week_failed: number }
export interface Outbox {
  queued: number; sent: number; failed: number; cancelled?: number; sentToday: number; emailProvider: boolean; smsProvider: boolean; recent: Recent[]; byChannel?: ByChannel[];
  /** V436: the delivery switches, what waits now, the jobs that would still write to the queue, the last clearance */
  delivery?: Delivery; pending?: Pending[]; jobs?: OpenJob[]; lastClearance?: Clearance | null;
  /** V438: the providers' delivery reports, and the receipt door's token (operators only) */
  receipts?: Receipt[]; receiptToken?: string | null;
  /** V442: each channel's health and the watch's settings */
  providers?: ProviderRow[]; providerSettings?: ProviderSettings | null;
}
export interface Filters { channel: string; state: string; kind: string; q: string; from: string; to: string }

function when(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "2-digit", month: "short" }) + " " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

const KINDS: [string, string][] = [["", "Anyone"], ["student", "Students"], ["person", "Staff"], ["application", "Applicants"], ["jupeb_application", "JUPEB applicants"], ["pg_application", "PG applicants"], ["test", "Test messages"]];

export function Notices({ d, actingOffice, filters }: { d: Outbox; actingOffice: string | null; filters: Filters }) {
  const router = useRouter();
  const may = ["ict", "admin", "super"].includes(actingOffice ?? "");
  const mayClear = ["ict", "super"].includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [f, setF] = useState<Filters>(filters);
  const noProvider = !d.emailProvider && !d.smsProvider;
  const filtered = Object.values(filters).some((v) => v);

  async function retry(path: string, reason: string) {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/platform/notices${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: "{}" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setSaid(`${(j as { requeued?: number })?.requeued ?? 0} notice(s) put back in the queue`);
      notify(`${(j as { requeued?: number })?.requeued ?? 0} notice(s) requeued`);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  function search(next: Filters) {
    const p = new URLSearchParams();
    (Object.keys(next) as (keyof Filters)[]).forEach((k) => { if (next[k]) p.set(k, next[k]); });
    router.push(`/notices${p.toString() ? `?${p}` : ""}`);
  }

  const by = d.byChannel ?? [];
  const row = (c: string) => by.find((b) => b.channel === c);

  return (
    <>
      <Note kind={noProvider ? "bad" : "info"} title={noProvider ? "No provider is wired, so nothing is being sent" : "A notice is marked sent only when the provider acknowledges it"}>
        The portal is a channel of its own: a portal notice is delivered on the person&rsquo;s dashboard the moment it is queued. The words every message uses are on{" "}
        <a href="/notices/templates">Notification templates</a>.
      </Note>

      {said ? <Note kind="ok" title={said}>The dispatcher tries the queue again within the half-minute.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Tiles items={[
        ["Waiting", String(d.queued), d.queued ? "var(--chrome)" : null, "In the outbox"],
        ["Sent today", String(d.sentToday), null, "Acknowledged by a provider"],
        ["Failed", String(d.failed), d.failed ? "var(--red-ink)" : "var(--green-ink)", d.failed ? "After five attempts, or an address that is not one" : "None"],
        ["Sent, all time", String(d.sent), null, "On the record"],
      ]} />

      {by.length ? (
        <Panel title="By channel" right="All time, and the last seven days">
          <DTable cols={["Channel", "Total|num", "Sent|num", "Delivered|num", "Bounced|num", "Waiting|num", "Failed|num", "Cancelled|num", "Bad addresses|num", "Last 7 days|num", "Sent, 7 days|num", "Failed, 7 days|num"]}
            rows={["EMAIL", "SMS", "PORTAL"].filter((c) => row(c)).map((c) => { const b = row(c)!; return [
              <b key="c">{c === "PORTAL" ? "Portal" : c === "EMAIL" ? "Email" : "SMS"}</b>,
              <span className="tnum" key="t">{b.total}</span>, <span className="tnum" key="s">{b.sent}</span>,
              <span className="tnum" key="d">{b.delivered ?? 0}</span>, <span className="tnum" key="b" style={b.bounced ? { color: "var(--red-ink)" } : undefined}>{b.bounced ?? 0}</span>,
              <span className="tnum" key="q">{b.queued}</span>,
              <span className="tnum" key="f" style={b.failed ? { color: "var(--red-ink)" } : undefined}>{b.failed}</span>,
              <span className="tnum" key="x">{b.cancelled ?? 0}</span>,
              <span className="tnum" key="i">{b.invalid}</span>, <span className="tnum" key="w">{b.week}</span>, <span className="tnum" key="ws">{b.week_sent}</span>,
              <span className="tnum" key="wf">{b.week_failed}</span>]; })} />
        </Panel>
      ) : null}

      <Panel title="Providers" right="Set on the Mail server and SMS gateway screens, or as service variables on the API">
        <PBody>
          <KvGrid cls="grid--2" pairs={[
            ["Email provider", d.emailProvider ? <Pil kind="ok" key="e">Wired</Pil> : <span className="sub2" key="e">None — the Mail server screen, or MOAUM_NOTICES_EMAIL_URL</span>],
            ["SMS provider", d.smsProvider ? <Pil kind="ok" key="s">Wired</Pil> : <span className="sub2" key="s">None — the SMS gateway screen, or MOAUM_NOTICES_SMS_URL</span>],
          ]} />
        </PBody>
      </Panel>

      {d.providers?.length ? <ProviderHealth rows={d.providers} settings={d.providerSettings ?? null} may={may} /> : null}

      {d.delivery ? <QueueManagement delivery={d.delivery} pending={d.pending ?? []} jobs={d.jobs ?? []} last={d.lastClearance ?? null} may={may} mayClear={mayClear} receipts={d.receipts ?? []} receiptToken={d.receiptToken ?? null} /> : null}

      <Panel title="History" right={filtered ? `${d.recent.length} matching, newest first` : `${d.recent.length} most recent`}>
        <PBody style={{ borderBottom: "1px solid var(--line-2)" }}>
          <form className="row row--wrap row--tight" onSubmit={(e) => { e.preventDefault(); search(f); }}>
            <select className="ctl" aria-label="Channel" value={f.channel} onChange={(e) => setF({ ...f, channel: e.target.value })}>
              <option value="">Any channel</option><option value="EMAIL">Email</option><option value="SMS">SMS</option><option value="PORTAL">Portal</option>
            </select>
            <select className="ctl" aria-label="State" value={f.state} onChange={(e) => setF({ ...f, state: e.target.value })}>
              <option value="">Any state</option><option value="QUEUED">Waiting</option><option value="SENT">Sent</option><option value="FAILED">Failed</option><option value="CANCELLED">Cancelled</option>
            </select>
            <select className="ctl" aria-label="About" value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value })}>
              {KINDS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
            </select>
            <input className="ctl" aria-label="Words" placeholder="Address, subject or template" value={f.q} onChange={(e) => setF({ ...f, q: e.target.value })} style={{ minWidth: 220 }} />
            <input className="ctl" type="date" aria-label="From" value={f.from} onChange={(e) => setF({ ...f, from: e.target.value })} />
            <input className="ctl" type="date" aria-label="To" value={f.to} onChange={(e) => setF({ ...f, to: e.target.value })} />
            <Btn kind="secondary" size="sm" type="submit">Search</Btn>
            {filtered ? <LinkBtn kind="ghost" size="sm" href="/notices">Clear</LinkBtn> : null}
          </form>
        </PBody>
        {may && d.failed ? <PBody style={{ borderBottom: "1px solid var(--line-2)" }}><Btn kind="ghost" disabled={busy} onClick={() => void retry("/retry-failed", "Requeue all failed notices")}>Put the failed back in the queue (not the bad addresses)</Btn></PBody> : null}
        {d.recent.length ? (
          <DTable cols={["When|mid", "To", "Notice", "Channel|mid", "Attempts|mid", "State|num"]} rows={d.recent.map((n) => [
            <span className="tnum sub2" key="w">{when(n.created_at)}</span>,
            <span key="t"><span className="sub2">{n.recipient}</span>{n.about_name ? <div className="sub2">{n.about_name}</div> : null}</span>,
            <span key="s">{n.subject}{n.template_key ? <div className="sub2">{n.template_key}</div> : null}</span>,
            <span className="sub2" key="c">{n.channel === "PORTAL" ? "Portal" : n.channel}</span>,
            <span className="tnum" key="a">{n.attempts}</span>,
            n.state === "SENT" ? (
              <span key="x" className="row row--inline row--tight" title={n.delivery_detail ?? ""}>
                <Pil kind={n.delivery_state === "BOUNCED" || n.delivery_state === "UNDELIVERED" ? "bad" : "ok"}>
                  {n.channel === "PORTAL" ? "Delivered" : n.delivery_state === "DELIVERED" ? "Delivered" : n.delivery_state === "BOUNCED" ? "Bounced" : n.delivery_state === "UNDELIVERED" ? "Undelivered" : "Sent"}
                </Pil>
              </span>
            ) : n.state === "FAILED" ? (
              <span key="x" className="row row--inline row--tight">
                <Pil kind="bad">{n.last_error === "INVALID_EMAIL" ? "Not an e-mail" : n.last_error === "INVALID_PHONE" ? "Not a phone" : "Failed"}</Pil>
                {n.last_error && !["INVALID_EMAIL", "INVALID_PHONE"].includes(n.last_error) ? <span className="sub2">{n.last_error}</span> : null}
                {may && !["INVALID_EMAIL", "INVALID_PHONE"].includes(n.last_error ?? "") ? <Btn kind="ghost" disabled={busy} onClick={() => void retry(`/${n.id}/retry`, `Requeue notice to ${n.recipient}`)}>Requeue</Btn> : null}
              </span>
            ) : n.state === "CANCELLED" ? <span key="x" title={n.cancel_reason ?? ""}><Pil kind="grey">Cancelled</Pil></span> : <Pil kind="info" key="x">Queued</Pil>,
          ])} texts={d.recent.map((n) => `${n.recipient} ${n.about_name ?? ""} ${n.subject} ${n.state} ${n.template_key ?? ""}`)} />
        ) : <PBody><div className="sub2">{filtered ? "Nothing matches." : "The outbox is empty."}</div></PBody>}
      </Panel>
    </>
  );
}
