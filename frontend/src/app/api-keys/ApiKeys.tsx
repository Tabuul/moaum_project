"use client";

/** pApi — proto/part…: every API consumer is named, scoped and rate-limited, and no key
 *  lives longer than a year. A key is shown once at issue; only its hash is kept. V511: the key is checked on the integration
 *  door (/api/integration/v1, header X-API-Key) within its consumer's scopes and daily quota, and every call is logged. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Key { id: string; last4: string; issued_at: string; expires_at: string; revoked_at: string | null; live: boolean; due: boolean }
export interface Consumer {
  id: string; name: string; owner: string; scopes: string; quota_day: number | null; status: string; created_at: string; keys: Key[];
  /** V511: the calls answered today (Lagos day), the last call, the calls refused in the last seven days */
  calls_today?: number; last_call_at?: string | null; refused_week?: number;
}
/** V511: a scope a consumer may hold, what it reads, and the integration path it opens */
export interface Scope { code: string; label: string; reads: string; path: string }
/** V511: a call on the integration door */
export interface Call { at: string; consumer: string | null; last4: string | null; scope: string; subject: string | null; outcome: string; ip: string | null }
const OUTCOME: Record<string, string> = { OK: "Answered", NOT_FOUND: "Not found", BAD_KEY: "Bad key", NO_SCOPE: "No scope", OVER_QUOTA: "Over quota", BAD_REQUEST: "Bad request" };

function day(iso: string): string { return new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }); }

export function ApiKeys({ consumers, scopes = [], calls = [] }: { consumers: Consumer[]; scopes?: Scope[]; calls?: Call[] }) {
  const router = useRouter();
  const [add, setAdd] = useState(false);
  const [f, setF] = useState({ name: "", owner: "", scopes: "", quotaDay: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [issued, setIssued] = useState<string | null>(null);

  const liveKeys = consumers.reduce((n, c) => n + c.keys.filter((k) => k.live).length, 0);
  const dueKeys = consumers.reduce((n, c) => n + c.keys.filter((k) => k.due).length, 0);

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/apimgmt${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="Every client is named, scoped and rate-limited, and no key lives longer than a year">
        A key is shown once, at issue; only its hash is kept. To rotate, issue the new key, then revoke the old one once the consumer has switched.
      </Note>

      <Panel title="The integration door" right={`${scopes.length} scope${scopes.length === 1 ? "" : "s"}`}>
        <PBody>
          <div className="sub2">A consumer calls with its key in the <span className="tnum">X-API-Key</span> header. The key answers only within its consumer&rsquo;s scopes and daily quota (counted to midnight, Lagos time); a key revoked or expired answers nothing; every call, answered or refused, is logged below.</div>
          {scopes.map((s) => (
            <div key={s.code} className="mt-2"><b className="tnum">{s.code}</b> · {s.label}<div className="sub2 tnum">{s.path}</div><div className="sub2">{s.reads}</div></div>
          ))}
        </PBody>
      </Panel>

      {said ? <Note kind="ok" title={said} /> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <Tiles items={[
        ["Consumers", String(consumers.filter((c) => c.status === "ACTIVE").length), null, `${consumers.length} in all`],
        ["Live keys", String(liveKeys), null, "Not expired or revoked"],
        ["Due for rotation", String(dueKeys), dueKeys ? "var(--red-ink)" : "var(--green-ink)", dueKeys ? "Within 14 days" : "None"],
        ["", "", null, ""],
      ]} />

      <div><Btn kind="primary" size="md" onClick={() => { setF({ name: "", owner: "", scopes: "", quotaDay: "" }); setErr(null); setAdd(true); }}>+ Register a consumer</Btn></div>

      {consumers.length ? consumers.map((c) => (
        <Panel key={c.id} title={c.name} right={`${c.owner} · ${c.status === "ACTIVE" ? "active" : "deprecated"}`}>
          <PBody>
            <KvGrid cls="grid--3" pairs={[
              ["Scopes", <span className="sub2 tnum" key="s">{c.scopes}</span>],
              ["Daily quota", <span className="tnum" key="q">{c.quota_day ? c.quota_day.toLocaleString() : "—"}</span>],
              ["Registered", day(c.created_at)],
              ["Calls today", <span className="tnum" key="t">{(c.calls_today ?? 0).toLocaleString()}{c.quota_day ? ` of ${c.quota_day.toLocaleString()}` : ""}</span>],
              ["Last call", c.last_call_at ? day(c.last_call_at) : "—"],
              ["Refused, last 7 days", <span className={`tnum${c.refused_week ? " ink-red b700" : ""}`} key="r">{(c.refused_week ?? 0).toLocaleString()}</span>],
            ]} />
            <div className="row mt-1">
              {c.status === "ACTIVE" ? <Btn kind="primary" disabled={busy} onClick={() => { const dstr = window.prompt("Days until this key expires (max 366):", "365"); if (dstr === null) return; void send(`/consumers/${c.id}/keys`, { days: Number(dstr) || 365 }, `Issue an API key for ${c.name}`).then((j) => { if (j && typeof j.key === "string") setIssued(j.key); }); }}>Issue a key</Btn> : null}
              {c.status === "ACTIVE" ? <Btn kind="ghost" disabled={busy} onClick={() => { if (window.confirm(`Deprecate ${c.name}? Its live keys are revoked.`)) void send(`/consumers/${c.id}/deprecate`, {}, `Deprecate consumer ${c.name}`).then((j) => { if (j) setSaid(`${c.name} deprecated`); }); }}>Deprecate</Btn> : null}
            </div>
          </PBody>
          {c.keys.length ? (
            <DTable cols={["Key", "Issued|mid", "Expires|mid", "State|num"]} rows={c.keys.map((k) => [
              <span className="tnum sub2" key="k">••••{k.last4}</span>,
              <span className="tnum sub2" key="i">{day(k.issued_at)}</span>,
              <span className={`tnum${k.due ? " ink-red b700" : ""}`} key="e">{day(k.expires_at)}</span>,
              k.revoked_at ? <Pil kind="grey" key="s">Revoked</Pil> : !k.live ? <Pil kind="bad" key="s">Expired</Pil> : k.due ? <span key="s" className="row row--inline row--tight"><Pil kind="bad">Due to rotate</Pil><Btn kind="ghost" disabled={busy} onClick={() => { if (window.confirm("Revoke this key now? Do it after the consumer has switched to a new one.")) void send(`/keys/${k.id}/revoke`, {}, "Revoke API key"); }}>Revoke</Btn></span> : <span key="s" className="row row--inline row--tight"><Pil kind="ok">Live</Pil><Btn kind="ghost" disabled={busy} onClick={() => { if (window.confirm("Revoke this key now?")) void send(`/keys/${k.id}/revoke`, {}, "Revoke API key"); }}>Revoke</Btn></span>,
            ])} />
          ) : <PBody><div className="sub2">No key issued yet.</div></PBody>}
        </Panel>
      )) : <Panel title="Consumers"><PBody><div className="sub2">No consumer is registered. Register one to issue it a scoped, dated key.</div></PBody></Panel>}

      <Panel title="Latest calls on the integration door" right={`${calls.length} shown`}>
        {calls.length ? (
          <DTable pageSize={25} cols={["When|mid", "Consumer", "Key", "Scope", "Asked", "Outcome", "From"]} rows={calls.map((c, i) => [
            <span key={`w${i}`} className="tnum sub2">{new Date(c.at).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })}</span>,
            <span key={`c${i}`}>{c.consumer ?? "—"}</span>, <span key={`k${i}`} className="tnum sub2">{c.last4 ? `••••${c.last4}` : "—"}</span>,
            <span key={`s${i}`} className="tnum sub2">{c.scope}</span>, <span key={`a${i}`} className="tnum">{c.subject ?? "—"}</span>,
            <Pil key={`o${i}`} kind={c.outcome === "OK" ? "ok" : c.outcome === "NOT_FOUND" ? "grey" : "bad"}>{OUTCOME[c.outcome] ?? c.outcome}</Pil>,
            <span key={`f${i}`} className="tnum sub2">{c.ip ?? "—"}</span>,
          ])} />
        ) : <PBody><div className="sub2">No call yet.</div></PBody>}
      </Panel>

      {add ? (
        <Modal title="Register a consumer" sub="A scope without a lawful basis is rejected at design review" onClose={() => setAdd(false)}
          foot={<><Btn kind="ghost" onClick={() => setAdd(false)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy || !f.name.trim() || !f.owner.trim() || !f.scopes.trim()} onClick={async () => { const j = await send("/consumers", { name: f.name, owner: f.owner, scopes: f.scopes, quotaDay: f.quotaDay ? Number(f.quotaDay) : null }, `Register consumer ${f.name}`); if (j) { setSaid(`${f.name} registered`); setAdd(false); } }}>Register</Btn></>}>
          {err ? <ProblemNotice problem={err} /> : null}
          <div className="grid grid--2">
            <Field id="ac-name" label="Client name"><input id="ac-name" className="ctl" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} placeholder="Mobile app" autoComplete="off" /></Field>
            <Field id="ac-owner" label="Owner"><input id="ac-owner" className="ctl" value={f.owner} onChange={(e) => setF({ ...f, owner: e.target.value })} placeholder="ICT Directorate" autoComplete="off" /></Field>
          </div>
          <Field id="ac-scopes" label="Scopes" hint="Only a scope on the list; each grants exactly what it reads">
            <div className="stack" id="ac-scopes" style={{ gap: 4 }}>
              {scopes.map((s) => {
                const on = f.scopes.split(/\s+/).includes(s.code);
                return (
                  <label key={s.code} className="row row--inline row--tight"><input type="checkbox" checked={on}
                    onChange={(e) => { const set = new Set(f.scopes.split(/\s+/).filter(Boolean)); if (e.target.checked) set.add(s.code); else set.delete(s.code); setF({ ...f, scopes: Array.from(set).join(" ") }); }} />
                    <span><b className="tnum">{s.code}</b> · {s.label}</span></label>
                );
              })}
            </div>
          </Field>
          <Field id="ac-quota" label="Daily quota" hint="Optional; requests per day"><input id="ac-quota" className="ctl tnum" value={f.quotaDay} inputMode="numeric" onChange={(e) => setF({ ...f, quotaDay: e.target.value })} /></Field>
        </Modal>
      ) : null}

      {issued ? (
        <Modal title="The key, shown once" sub="Copy it now — it is never displayed again" onClose={() => setIssued(null)}
          foot={<Btn kind="primary" onClick={() => setIssued(null)}>I have copied it</Btn>}>
          <Note kind="bad" title="This is the only time this key is shown">Only its hash is kept. If it is lost, revoke it and issue another.</Note>
          <div className="ctl tnum" style={{ userSelect: "all", wordBreak: "break-all", padding: "var(--s-2) var(--s-3)" }}>{issued}</div>
        </Modal>
      ) : null}
    </>
  );
}
