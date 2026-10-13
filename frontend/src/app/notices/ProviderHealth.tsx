"use client";

/**
 * V442: the mail and SMS providers watched — each channel's state from the dispatcher's own counts and the outbox, the SMS
 * balance as eBulkSMS reported it, and the watch's settings. A problem (failing, stuck, low balance) is told to the
 * Directorate of ICT once per episode, on the channels that still work.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";

export interface ProviderRow {
  channel: string; state: string; since: string; delivery_on: boolean; tried: number; failed: number; last_error: string | null; last_error_at: string | null;
  last_ok_at: string | null; providers: string | null; waiting: number; oldest_waiting: string | null; balance: number | null; balance_raw: string | null;
  balance_at: string | null; alerted_state: string | null; alerted_at: string | null; checked_at: string | null;
}
export interface ProviderSettings { provider_watch: boolean; failing_share: number; failing_min: number; stuck_minutes: number; sms_low_balance: number }

const STATE: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info", string]> = {
  OK: ["OK", "ok", "Messages are going out."],
  IDLE: ["Idle", "grey", "Nothing has been asked of this channel in the last two hours."],
  OFF: ["Off", "grey", "Queue processing is paused or this channel's delivery is switched off: messages wait by design."],
  FAILING: ["Failing", "bad", "Most of what was tried in the last two hours failed: check the provider's account (credit, password, API key)."],
  STUCK: ["Stuck", "bad", "Messages wait and none has been tried: no provider is wired for this channel, or the dispatcher is not running."],
  LOW_BALANCE: ["Low balance", "warn", "The SMS account's balance is below the level set here: top it up before it runs out."],
};

function when(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "2-digit", month: "short" }) + " " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

export function ProviderHealth({ rows, settings, may }: { rows: ProviderRow[]; settings: ProviderSettings | null; may: boolean }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [low, setLow] = useState(String(settings?.sms_low_balance ?? 500));
  const [said, setSaid] = useState<string | null>(null);

  async function send(path: string, method: string, body: unknown, why: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/platform/notices${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(why);
      router.refresh();
      return j;
    } finally {
      setBusy(false);
    }
  }

  const lowOk = /^[0-9]+(\.[0-9]+)?$/.test(low.trim());
  const sms = rows.find((r) => r.channel === "SMS");
  return (
    <Panel title="Provider health" right={settings ? (settings.provider_watch ? "Watched every ten minutes; ICT told once per problem" : "Watch switched off") : ""}>
      <DTable cols={["Channel", "State|mid", "Since|mid", "Tried, 2 h|num", "Failed, 2 h|num", "Waiting|num", "Last error", "Told ICT|mid"]} rows={rows.map((r) => {
        const [label, kind, meaning] = STATE[r.state] ?? [r.state, "grey", ""];
        return [
          <b key="c">{r.channel === "EMAIL" ? "E-mail" : "SMS"}{r.providers ? <div className="sub2">{r.providers}</div> : null}</b>,
          <span key="s" title={meaning}><Pil kind={kind}>{label}</Pil></span>,
          <span key="w" className="tnum sub2">{when(r.since)}</span>,
          <span key="t" className="tnum">{r.tried}</span>,
          <span key="f" className="tnum" style={r.failed ? { color: "var(--red-ink)" } : undefined}>{r.failed}</span>,
          <span key="q" className="tnum">{r.waiting}{r.oldest_waiting ? <div className="sub2">since {when(r.oldest_waiting)}</div> : null}</span>,
          <span key="e" className="sub2">{r.last_error ? `${r.last_error} (${when(r.last_error_at)})` : "—"}</span>,
          <span key="a" className="sub2">{r.alerted_state ? `${(STATE[r.alerted_state]?.[0] ?? r.alerted_state).toLowerCase()} · ${when(r.alerted_at)}` : "—"}</span>,
        ];
      })} />
      <PBody>
        <div className="sub2">
          SMS balance: {sms?.balance != null ? <b className="tnum">{sms.balance}</b> : sms?.balance_raw ? <span>{sms.balance_raw}</span> : "not read (no eBulkSMS account set, or not read yet)"}
          {sms?.balance_at ? ` · read ${when(sms.balance_at)}` : ""}. Failing means at least {settings?.failing_min ?? 10} tried and {settings?.failing_share ?? 50}% failed in the last two
          clock hours; stuck means a message has waited {settings?.stuck_minutes ?? 30} minutes with nothing tried. The episode ends by itself when messages go out again.
        </div>
        {may ? (
          <div className="row row--wrap row--tight mt-1">
            <label className="row row--inline row--tight"><input type="checkbox" checked={settings?.provider_watch ?? true} disabled={busy}
              onChange={(e) => void send("/providers", "PUT", { watch: e.target.checked }, e.target.checked ? "Provider watch switched on" : "Provider watch switched off")} /> Watch the providers</label>
            <Field id="ph-low" label="Warn below (SMS units; 0: no warning)"><input id="ph-low" className="ctl tnum" value={low} onChange={(e) => setLow(e.target.value)} /></Field>
            <Btn kind="primary" size="sm" disabled={busy || !lowOk || Number(low) === Number(settings?.sms_low_balance)} onClick={() => void send("/providers", "PUT", { lowBalance: low.trim() }, `SMS balance warning set below ${low.trim()} units`)}>Save</Btn>
            <Btn kind="ghost" size="sm" disabled={busy} onClick={async () => {
              const j = await send("/providers/check", "POST", {}, "Providers checked now");
              if (j) setSaid(Number(j.told) > 0 ? `A problem was found: ${j.told} message${Number(j.told) === 1 ? "" : "s"} queued to the Directorate of ICT.` : "Checked: nothing new to tell.");
            }}>Check now</Btn>
          </div>
        ) : null}
        {said ? <div className="sub2 mt-1">{said}</div> : null}
      </PBody>
    </Panel>
  );
}
