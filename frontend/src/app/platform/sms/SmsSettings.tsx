"use client";

/** tSms — the SMS gateway settings (eBulkSMS): username, sender ID and API key. The key is written
 *  once, encrypted, and never read back; the screen sees only that one is set. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface SmsConfig {
  provider: string | null; username: string | null; sender: string | null; enabled: boolean;
  api_key_set: boolean; set_at: string | null; set_by_name: string | null; configKeyPresent: boolean;
}

const when = (s: string | null) => (s ? new Date(s).toLocaleString("en-GB") : "");

export function SmsSettings({ config, actingOffice }: { config: SmsConfig; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["ict", "admin", "super"].includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [f, setF] = useState({
    username: config.username ?? "", sender: config.sender ?? "", enabled: config.enabled, apiKey: "",
  });
  const set = <K extends keyof typeof f>(k: K, v: (typeof f)[K]) => setF({ ...f, [k]: v });

  async function send(path: string, body: unknown, reason: string, method = "PUT"): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/platform${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="SMS gateway — eBulkSMS">
        The eBulkSMS account the portal sends text messages from. The API key is written once, encrypted at rest with the portal&rsquo;s own passphrase, and never shown again &mdash; the same rule as the mail password and a payment gateway key. When enabled, the portal&rsquo;s SMS notices go out through eBulkSMS instead of the generic relay.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}
      {!config.configKeyPresent ? (
        <Note kind="bad" title="No passphrase to encrypt the API key with">Set MOAUM_CONFIG_KEY (or MOAUM_AUTH_HMAC_SECRET) on the API service before saving the API key; the account and sender can be saved without it.</Note>
      ) : null}

      <Panel title="eBulkSMS account" right={config.api_key_set ? <Pil kind="ok">API key set</Pil> : <Pil kind="grey">No API key</Pil>}>
        <PBody>
          {config.api_key_set ? <div className="sub2 mb-2">An API key is set{config.set_at ? ` — ${when(config.set_at)}` : ""}{config.set_by_name ? ` by ${config.set_by_name}` : ""}. Leave the API key blank to keep it; type a new one to replace it.</div> : null}
          <div className="grid grid--2">
            <Field id="username" label="Username" hint="Your eBulkSMS account username"><input id="username" className="ctl tnum" value={f.username} onChange={(e) => set("username", e.target.value)} disabled={!may} autoComplete="off" placeholder="ebulksms username" /></Field>
            <Field id="sender" label="Sender ID" hint="Shown on the handset; up to 11 characters"><input id="sender" className="ctl tnum" maxLength={11} value={f.sender} onChange={(e) => set("sender", e.target.value)} disabled={!may} autoComplete="off" placeholder="MOAUM" /></Field>
          </div>
          <Field id="apiKey" label="API key" hint="Pasted once; it is never displayed after this.">
            <input id="apiKey" className="ctl tnum" type="password" value={f.apiKey} onChange={(e) => set("apiKey", e.target.value)} disabled={!may} autoComplete="off" placeholder={config.api_key_set ? "•••••••• (leave blank to keep)" : ""} />
          </Field>
          <label className="field row" style={{ flexDirection: "row" }}>
            <input type="checkbox" className="pchk" checked={f.enabled} onChange={(e) => set("enabled", e.target.checked)} disabled={!may} />
            <span>Send SMS notices through eBulkSMS</span>
          </label>
          <div className="row mt-2">
            <Btn kind="primary" disabled={!may || busy} onClick={async () => {
              const j = await send("/sms", { provider: "EBULKSMS", username: f.username, sender: f.sender, enabled: f.enabled, apiKey: f.apiKey || null }, "SMS gateway settings stated");
              if (j) { setSaid("SMS gateway settings saved"); setF({ ...f, apiKey: "" }); }
            }}>{busy ? "Saving…" : "Save the settings"}</Btn>
            {config.api_key_set ? <Btn kind="ghost" disabled={!may || busy} onClick={async () => { if (window.confirm("Clear the stored SMS API key? SMS sending falls back to the relay until a new key is set.") && await send("/sms/clear-key", {}, "SMS API key cleared", "POST")) setSaid("SMS API key cleared"); }}>Clear the API key</Btn> : null}
          </div>
        </PBody>
      </Panel>

      <Note kind="info" title="How SMS is chosen">
        When an API key is set and sending is enabled, SMS notices go through eBulkSMS. Otherwise the portal falls back to the generic relay if one is configured, and to the outbox if not. Nigerian numbers are normalised to the 234 form eBulkSMS expects.
      </Note>
    </>
  );
}
