"use client";

/** tSecurity — security posture read from the record: the audit spine (entries, shards,
 *  and that every state table is attached to it) and the sign-in defence (attempts by
 *  outcome, and the accounts drawing failed attempts). Nothing here is a claim the system
 *  cannot substantiate from its own data. V437: the session timeout the Directorate of ICT
 *  sets (idle, warning, whether the person may continue), the sessions open now and today's
 *  ends, and the setting's history from the audit spine. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import type { SessionPolicy } from "@/lib/idle";

export interface Posture {
  audit: { entries: number; shards: number; unattached_tables: number; last_entry: string | null; chain_last_run?: string | null; chain_ok?: boolean | null };
  signins: { signed_in: number; bad_password: number; unknown_user: number; locked: number; total: number };
  topFailures: { username: string; attempts: number; last_at: string }[];
}

/** GET /api/v1/auth/session-policy/monitor */
export interface SessionMonitor {
  counts: { open_sessions: number; active: number; idle: number; expired_idle_today: number; signed_out_today: number; ended_today: number };
  sessions: { session_id: string; person_id: string; name: string; office: string; issued_at: string; last_seen_at: string; status: "ACTIVE" | "IDLE" }[];
}

/** GET /api/v1/auth/session-policy/history */
export interface PolicyChange {
  occurred_at: string; actor: string; actor_office?: string | null; reason?: string | null;
  was_enabled?: string | null; now_enabled?: string | null; was_idle?: string | null; now_idle?: string | null;
  was_warning?: string | null; now_warning?: string | null; now_continue?: string | null; why?: string | null;
}

function when(ts: string | null | undefined): string {
  if (!ts) return "—";
  return new Date(ts).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
}

export function Security({ p, policy = null, monitor = null, history = [], canSet = false }: {
  p: Posture; policy?: SessionPolicy | null; monitor?: SessionMonitor | null; history?: PolicyChange[]; canSet?: boolean;
}) {
  const a = p.audit;
  const s = p.signins;
  const failed = Number(s.bad_password) + Number(s.unknown_user) + Number(s.locked);

  return (
    <>
      <Note kind={Number(a.unattached_tables) === 0 ? "ok" : "bad"} title={Number(a.unattached_tables) === 0 ? "Every state table is on the audit spine" : `${a.unattached_tables} state table(s) not attached to the audit spine`}>
        The audit chain and the sign-in defence. Network, host and WAF controls are governed separately.
      </Note>
      <Tiles items={[
        ["Audit entries", Number(a.entries).toLocaleString(), null, `${a.shards} chain shard${Number(a.shards) === 1 ? "" : "s"}`],
        ["Unattached tables", String(a.unattached_tables), Number(a.unattached_tables) ? "var(--red-ink)" : "var(--green-ink)", Number(a.unattached_tables) ? "A state change could go unrecorded" : "All state is recorded"],
        ["Failed sign-ins, 7 days", String(failed), failed ? "var(--chrome)" : null, `${s.locked} lock-out${Number(s.locked) === 1 ? "" : "s"}`],
        ["Last audit entry", when(a.last_entry), null, "The chain is written on every change"],
        ["Chain last verified", a.chain_last_run ? when(a.chain_last_run) : "Not yet", a.chain_last_run ? (a.chain_ok === false ? "var(--red-ink)" : "var(--green-ink)") : "var(--chrome)", a.chain_last_run ? (a.chain_ok === false ? "A break was found: see the audit trail" : "Every shard held") : "The nightly job runs at 02:20; the desk may run it now"],
      ]} />

      {policy ? <SessionTimeout policy={policy} canSet={canSet} /> : null}

      {monitor ? (
        <Panel title="Sessions" right={<span className="sub2">Open now, by the timeout in force; and those ended today</span>}>
          <PBody>
            <Tiles items={[
              ["Active sessions", String(monitor.counts.active), "var(--green-ink)", "Seen within the idle timeout"],
              ["Idle sessions", String(monitor.counts.idle), monitor.counts.idle ? "var(--chrome)" : null, "Open, not seen within the timeout; the next request ends them"],
              ["Expired for inactivity today", String(monitor.counts.expired_idle_today), null, `${monitor.counts.ended_today} session${Number(monitor.counts.ended_today) === 1 ? "" : "s"} ended today in all`],
              ["Signed out today", String(monitor.counts.signed_out_today), null, "By the person"],
            ]} />
          </PBody>
          {monitor.sessions.length ? (
            <DTable cols={["Who", "Acting as", "Signed in|mid", "Last activity|mid", "Status|mid"]} rows={monitor.sessions.map((x) => [
              <span key="n" className="b600">{x.name}</span>,
              <span key="o" className="sub2">{x.office}</span>,
              <span key="i" className="sub2 tnum">{when(x.issued_at)}</span>,
              <span key="l" className="sub2 tnum">{when(x.last_seen_at)}</span>,
              <Pil key="s" kind={x.status === "ACTIVE" ? "ok" : "warn"}>{x.status === "ACTIVE" ? "Active" : "Idle"}</Pil>,
            ])} texts={monitor.sessions.map((x) => `${x.name} ${x.office} ${x.status}`)} title="Open sessions" />
          ) : <PBody><div className="sub2">No session is open.</div></PBody>}
        </Panel>
      ) : null}

      {canSet && history.length ? (
        <Panel title="Session timeout history" right={<span className="sub2">Every change, from the audit trail</span>}>
          <DTable cols={["When", "Change", "By", "Office", "Reason"]} rows={history.map((h) => [
            <span key="w" className="sub2 tnum">{when(h.occurred_at)}</span>,
            <span key="c" className="b600">
              {h.was_enabled !== h.now_enabled ? `${h.now_enabled === "true" ? "Enabled" : "Disabled"}` : "Changed"}
              {h.was_idle !== h.now_idle ? ` · idle ${h.was_idle ?? "?"} → ${h.now_idle ?? "?"} s` : ` · idle ${h.now_idle ?? "?"} s`}
              {h.was_warning !== h.now_warning ? ` · warning ${h.was_warning ?? "?"} → ${h.now_warning ?? "?"} s` : ` · warning ${h.now_warning ?? "?"} s`}
              {h.now_continue === "false" ? " · no continue" : ""}
            </span>,
            <span key="b">{h.actor}</span>,
            <span key="o" className="sub2">{h.actor_office ?? "—"}</span>,
            <span key="r" className="sub2">{h.why ?? h.reason ?? "—"}</span>,
          ])} texts={history.map((h) => `${h.actor} ${h.why ?? ""}`)} />
        </Panel>
      ) : null}

      <Panel title="The audit spine" right="Hash-chained, verified nightly across every shard">
        <PBody>
          <div className="sub2">
            The audit chain holds <b>{Number(a.entries).toLocaleString()}</b> entries across <b>{a.shards}</b> shard{Number(a.shards) === 1 ? "" : "s"};
            {Number(a.unattached_tables) === 0 ? " every state table is attached." : ` ${a.unattached_tables} table(s) are not yet attached.`}
            {" "}Recomputed nightly; a break is reported to the Registrar and the Directorate of ICT.
          </div>
        </PBody>
      </Panel>

      <Panel title="Sign-in defence" right="Last 7 days">
        <DTable cols={["Outcome", "Count|num"]} rows={[
          [<span key="a"><Pil kind="ok">Signed in</Pil></span>, <span className="tnum" key="c">{Number(s.signed_in).toLocaleString()}</span>],
          [<span key="a"><Pil kind="warn">Wrong password</Pil></span>, <span className="tnum" key="c">{Number(s.bad_password).toLocaleString()}</span>],
          [<span key="a"><Pil kind="grey">Unknown username</Pil></span>, <span className="tnum" key="c">{Number(s.unknown_user).toLocaleString()}</span>],
          [<span key="a"><Pil kind="bad">Locked out</Pil></span>, <span className="tnum" key="c">{Number(s.locked).toLocaleString()}</span>],
        ]} />
        <PBody><div className="sub2">Five failed attempts lock an account for fifteen minutes; privileged accounts complete a second step when single sign-on is connected.</div></PBody>
      </Panel>

      <Panel title="Accounts drawing failed attempts" right="Where a lock-out or a guessing attempt is concentrated">
        {p.topFailures.length ? (
          <DTable cols={["Account", "Failed attempts|num", "Last attempt|num"]} rows={p.topFailures.map((r) => [
            <span className="tnum" key="u">{r.username}</span>,
            <b className="tnum" key="a">{r.attempts}</b>,
            <span className="tnum sub2" key="l">{when(r.last_at)}</span>,
          ])} texts={p.topFailures.map((r) => r.username)} />
        ) : <PBody><div className="sub2">No failed sign-in attempts in the last seven days.</div></PBody>}
      </Panel>
    </>
  );
}

/** the session timeout: ON or OFF, the idle timeout and the warning before it, whether the person may continue — set here, enforced by the server on the next request */
function SessionTimeout({ policy, canSet }: { policy: SessionPolicy; canSet: boolean }) {
  const router = useRouter();
  const [f, setF] = useState({ enabled: policy.enabled, idle: String(policy.idleSeconds), warning: String(policy.warningSeconds), allow: policy.allowContinue !== false, reason: "" });
  const [busy, setBusy] = useState(false);
  const idle = Number(f.idle), warning = Number(f.warning);
  const error = !Number.isInteger(idle) || idle < 30 ? "The idle timeout is at least 30 seconds."
    : idle > 28800 ? "The idle timeout is at most eight hours (28,800 seconds)."
    : !Number.isInteger(warning) || warning < 5 ? "The warning comes at least 5 seconds before the timeout."
    : warning >= idle ? "Warning time must be shorter than the idle timeout." : null;
  const changed = f.enabled !== policy.enabled || idle !== policy.idleSeconds || warning !== policy.warningSeconds || f.allow !== (policy.allowContinue !== false);

  async function save() {
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/auth/session-policy", {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Session timeout: ${f.enabled ? "on" : "off"}, ${idle} s, warning ${warning} s`) },
        body: JSON.stringify({ enabled: f.enabled, idleSeconds: idle, warningSeconds: warning, allowContinue: f.allow, reason: f.reason.trim() || null }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      notify(f.enabled ? `Idle timeout ON: ${idle} seconds, warning ${warning} seconds before` : "Idle timeout OFF");
      setF({ ...f, reason: "" });
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const minutes = (n: number) => (n % 60 === 0 ? `${n / 60} minute${n === 60 ? "" : "s"}` : `${n} seconds`);
  return (
    <Panel title="Session timeout" right={<Pil kind={policy.enabled ? "ok" : "grey"}>{policy.enabled ? "ON" : "OFF"}</Pil>}>
      <PBody>
        <div className="sub2" style={{ lineHeight: 1.55 }}>
          {policy.enabled
            ? <>A session with no activity for <b>{minutes(policy.idleSeconds)}</b> is signed out; the person is warned <b>{policy.warningSeconds} seconds</b> before{policy.allowContinue !== false ? " and may continue" : ""}. The server ends an idle session on its next request whatever the browser shows.</>
            : <>Automatic sign-out after inactivity is off. Sessions end when the person signs out, when they are ended, or at their absolute end.</>}
          {policy.updatedAt ? <> Last set {when(policy.updatedAt)}{policy.updatedBy ? ` by ${policy.updatedBy}` : ""}{policy.updatedOffice ? ` (${policy.updatedOffice})` : ""}{policy.reason ? ` — ${policy.reason}` : ""}.</> : null}
        </div>
        {canSet ? (
          <>
            <div className="grid grid--3 mt-2">
              <div className="stack" style={{ gap: 6 }}>
                <label className="row row--tight" style={{ gap: 8 }}><input type="checkbox" checked={f.enabled} onChange={(e) => setF({ ...f, enabled: e.target.checked })} /> Enable automatic logout after inactivity</label>
                <label className="row row--tight" style={{ gap: 8 }}><input type="checkbox" checked={f.allow} onChange={(e) => setF({ ...f, allow: e.target.checked })} /> Allow users to continue the session from the warning</label>
              </div>
              <Field id="st-idle" label="Idle timeout (seconds)" hint="At least 30; at most 28,800 (eight hours). Default 120."><input id="st-idle" className="ctl tnum" inputMode="numeric" value={f.idle} onChange={(e) => setF({ ...f, idle: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
              <Field id="st-warn" label="Warning before logout (seconds)" hint="Shorter than the idle timeout. Default 30." error={error}><input id="st-warn" className="ctl tnum" inputMode="numeric" value={f.warning} onChange={(e) => setF({ ...f, warning: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
              <Field id="st-reason" label="Reason (optional)" className="rf--full"><input id="st-reason" className="ctl" maxLength={500} value={f.reason} placeholder="e.g. Testing · Go-live" onChange={(e) => setF({ ...f, reason: e.target.value })} /></Field>
            </div>
            <div className="row mt-2"><Btn kind="primary" disabled={busy || !!error || !changed} onClick={() => void save()}>{busy ? "Saving…" : "Save settings"}</Btn></div>
          </>
        ) : null}
      </PBody>
    </Panel>
  );
}
