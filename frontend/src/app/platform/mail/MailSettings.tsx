"use client";

/** tMail — the mail server settings: IMAP, POP and SMTP for Microsoft 365. The password is written
 *  once, encrypted, and never read back; the screen sees only that one is set. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface MailConfig {
  smtp_host: string | null; smtp_port: number | null; smtp_encryption: string | null;
  imap_host: string | null; imap_port: number | null; imap_encryption: string | null;
  pop_host: string | null; pop_port: number | null; pop_encryption: string | null;
  username: string | null; from_address: string | null;
  password_set: boolean; set_at: string | null; set_by_name: string | null; configKeyPresent: boolean;
}

const ENC = ["STARTTLS", "SSL", "NONE"];
const when = (s: string | null) => (s ? new Date(s).toLocaleString("en-GB") : "");

export function MailSettings({ config, actingOffice }: { config: MailConfig; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["ict", "admin", "super"].includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [f, setF] = useState({
    smtpHost: config.smtp_host ?? "smtp.office365.com", smtpPort: String(config.smtp_port ?? 587), smtpEncryption: config.smtp_encryption ?? "STARTTLS",
    imapHost: config.imap_host ?? "outlook.office365.com", imapPort: String(config.imap_port ?? 993), imapEncryption: config.imap_encryption ?? "SSL",
    popHost: config.pop_host ?? "outlook.office365.com", popPort: String(config.pop_port ?? 995), popEncryption: config.pop_encryption ?? "SSL",
    username: config.username ?? "", fromAddress: config.from_address ?? "", password: "",
  });
  const set = (k: keyof typeof f, v: string) => setF({ ...f, [k]: v });

  async function send(path: string, body: unknown, reason: string, method = "PUT"): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/platform${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  const trio = (label: string, hostK: keyof typeof f, portK: keyof typeof f, encK: keyof typeof f, hint: string) => (
    <Panel title={label} right={hint}>
      <PBody>
        <div className="grid grid--3">
          <Field id={hostK} label="Server"><input id={hostK} className="ctl tnum" value={f[hostK]} onChange={(e) => set(hostK, e.target.value)} disabled={!may} autoComplete="off" /></Field>
          <Field id={portK} label="Port"><input id={portK} className="ctl tnum" inputMode="numeric" value={f[portK]} onChange={(e) => set(portK, e.target.value.replace(/[^0-9]/g, ""))} disabled={!may} autoComplete="off" /></Field>
          <Field id={encK} label="Encryption"><select id={encK} className="ctl" value={f[encK]} onChange={(e) => set(encK, e.target.value)} disabled={!may}>{ENC.map((x) => <option key={x} value={x}>{x}</option>)}</select></Field>
        </div>
      </PBody>
    </Panel>
  );

  return (
    <>
      <Note kind="info" title="Manual mail server settings for Microsoft 365">
        The IMAP, POP and SMTP parameters of the mail account the portal sends from. The account password is written once, encrypted at rest with the portal&rsquo;s own passphrase, and never shown again &mdash; the same rule as a payment gateway key. The defaults below are the standard Microsoft 365 servers; change them for another provider.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}
      {!config.configKeyPresent ? (
        <Note kind="bad" title="No passphrase to encrypt the password with">Set MOAUM_CONFIG_KEY (or MOAUM_AUTH_HMAC_SECRET) on the API service before saving a password; the servers and account can be saved without it.</Note>
      ) : null}

      {trio("SMTP — outgoing (sending)", "smtpHost", "smtpPort", "smtpEncryption", "smtp.office365.com · 587 · STARTTLS")}
      {trio("IMAP — incoming", "imapHost", "imapPort", "imapEncryption", "outlook.office365.com · 993 · SSL/TLS")}
      {trio("POP — incoming", "popHost", "popPort", "popEncryption", "outlook.office365.com · 995 · SSL/TLS")}

      <Panel title="The account" right={config.password_set ? <Pil kind="ok">Password set</Pil> : <Pil kind="grey">No password</Pil>}>
        <PBody>
          {config.password_set ? <div className="sub2" style={{ marginBottom: 8 }}>A password is set{config.set_at ? ` — ${when(config.set_at)}` : ""}{config.set_by_name ? ` by ${config.set_by_name}` : ""}. Leave the password blank to keep it; type a new one to replace it.</div> : null}
          <div className="grid grid--2">
            <Field id="username" label="Username" hint="The full email address"><input id="username" className="ctl tnum" value={f.username} onChange={(e) => set("username", e.target.value)} disabled={!may} autoComplete="off" placeholder="portal@moaum.edu.ng" /></Field>
            <Field id="fromAddress" label="From address" hint="What recipients see; blank uses the username"><input id="fromAddress" className="ctl tnum" value={f.fromAddress} onChange={(e) => set("fromAddress", e.target.value)} disabled={!may} autoComplete="off" placeholder="MOAUM Portal <portal@moaum.edu.ng>" /></Field>
          </div>
          <Field id="password" label="Password or app password" hint="Pasted once; it is never displayed after this. Microsoft 365 often needs an app password.">
            <input id="password" className="ctl tnum" type="password" value={f.password} onChange={(e) => set("password", e.target.value)} disabled={!may} autoComplete="off" placeholder={config.password_set ? "•••••••• (leave blank to keep)" : ""} />
          </Field>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <Btn kind="primary" disabled={!may || busy} onClick={async () => {
              const j = await send("/mail", {
                smtpHost: f.smtpHost, smtpPort: Number(f.smtpPort) || null, smtpEncryption: f.smtpEncryption,
                imapHost: f.imapHost, imapPort: Number(f.imapPort) || null, imapEncryption: f.imapEncryption,
                popHost: f.popHost, popPort: Number(f.popPort) || null, popEncryption: f.popEncryption,
                username: f.username, fromAddress: f.fromAddress, password: f.password || null,
              }, "Mail server settings stated");
              if (j) { setSaid("Mail server settings saved"); setF({ ...f, password: "" }); }
            }}>{busy ? "Saving…" : "Save the settings"}</Btn>
            {config.password_set ? <Btn kind="ghost" disabled={!may || busy} onClick={async () => { if (window.confirm("Clear the stored mail password? Sending stops until a new one is set.") && await send("/mail/clear-password", {}, "Mail password cleared", "POST")) setSaid("Mail password cleared"); }}>Clear the password</Btn> : null}
          </div>
        </PBody>
      </Panel>

      <Note kind="info" title="Sending over SMTP arrives with the mail transport">
        These settings are stored now. The portal&rsquo;s notice sender uses them to send over Microsoft 365 once the SMTP transport is enabled on the API. Until then the outbox holds each notice and this screen keeps the settings ready.
      </Note>
    </>
  );
}
