"use client";

/** tGateways — proto/part18.html: the gateways wired, a secret never read back, the webhook log, a test checkout (V037).
 *  V367: "Can the gateways take a payment now?" — each wired gateway asked a question that moves no money, and its answer read. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { EXCEPTIONS, OUTCOME, when, type GatewayConfig, type PaydirectDesk, type PaymentsDesk } from "@/lib/bursary";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PayOnQuickteller } from "./PayOnQuickteller";

/** V367: what a gateway's answer to the health question means */
const HEALTH: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info", string]> = {
  OK: ["Ready", "ok", "The gateway accepted the key or knew the merchant; a payment can be taken."],
  KEY_REFUSED: ["Key refused", "bad", "The gateway refused the secret key: set the right key on this screen (Directorate of ICT)."],
  MERCHANT_UNKNOWN: ["Merchant unknown", "bad", "Interswitch does not know this merchant or pay item: obtain the University's current merchant code from Interswitch."],
  UNEXPECTED: ["Unexpected answer", "warn", "The gateway answered something the portal does not recognise; read what it said."],
  UNREACHABLE: ["No answer", "bad", "The gateway could not be reached from the portal; try again, and check the server's network if it persists."],
  OFF: ["Not wired", "grey", "Nothing is set for this gateway."],
};
interface HealthRow { gateway: string; scope: string; state: string; said: string; http: number | null }

/** the gateways as the Bursary's desk names them */
const DESK_LABEL: Record<string, string> = { paystack: "Paystack", flutterwave: "Flutterwave", quickteller: "Quickteller WebPAY (card page)", paydirect: "Pay on Quickteller (biller page)" };

export function Gateways({ d, config, quickteller, paid, actingOffice }: { d: PaymentsDesk; config: GatewayConfig[]; quickteller: PaydirectDesk | null; paid: string | null; actingOffice: string | null }) {
  const router = useRouter();
  // the Bursary monitors, tests and verifies; only the Directorate of ICT and the Super
  // Administrator set or clear a gateway key — the key setup is off the Bursar's desk
  const may = ["bursar", "ict", "admin", "super"].includes(actingOffice ?? "");
  const mayConfigure = ["ict", "admin", "super"].includes(actingOffice ?? "");
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const [health, setHealth] = useState<{ checkedAt: string; online: boolean; rows: HealthRow[] } | null>(null);
  const [test, setTest] = useState({ number: "MOAUM/MTC/24/9903", amount: "100", gateway: d.gateways.find((g) => g.on && g.gateway !== "paydirect")?.gateway ?? "paystack" });
  const [ref, setRef] = useState("");
  const [keys, setKeys] = useState<Record<string, { secret: string; hash: string }>>({ paystack: { secret: "", hash: "" }, flutterwave: { secret: "", hash: "" } });
  // Quickteller on Interswitch WebPAY is not one string but a set — two merchants, each with a
  // product id, a pay item and a MAC key: the whole set is stored as one JSON secret. The ids
  // are the University's and are prefilled; the MAC keys are secrets and are pasted here only.
  const QT_EMPTY = { merchantCode: "", productId: "6498", payItemId: "101", macKey: "", chsMerchantCode: "", chsProductId: "6207", chsPayItemId: "101", chsMacKey: "", sandbox: false };
  const [qt, setQt] = useState(QT_EMPTY);
  // Pay on Quickteller (V299): the service username and password Interswitch sends with each payment notification
  const [pd, setPd] = useState({ user: "", pass: "" });
  const qtMain = d.gateways.find((g) => g.gateway === "quickteller")?.merchants ?? [];
  const on = d.gateways.filter((g) => g.on);
  const t = d.tiles;
  const apiBase = d.portalUrl.replace("moaum-portal", "moaum-api");
  // Quickteller's doors are given at the API's address as the API states it (through the portal when it has none of its own)
  const addressOf = (g: { gateway: string; webhook: string }) => (g.gateway === "paydirect" && quickteller ? quickteller.apiBase : apiBase) + g.webhook;

  async function send(path: string, body: unknown, reason: string, method: string = "POST"): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/payments${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="A secret key is written once and never read back">
        Set a key below on this screen, or as a service variable (MOAUM_PAYSTACK_SECRET, MOAUM_FLUTTERWAVE_SECRET, MOAUM_FLUTTERWAVE_HASH). A key set here is encrypted at rest and used in preference to the variable; either way, no screen and no member of staff can display it again. This panel says only whether a key is set and whether it is test or live.
      </Note>
      {paid ? <Note kind="ok" title={`Back from the gateway with ${paid}`} action={<Btn kind="primary" disabled={busy} onClick={async () => { const j = await send("/verify", { reference: paid }, `Verified ${paid} with the gateway`); if (j) setSaid(`The gateway says: ${j.outcome}`); }}>Ask the gateway now</Btn>}>The webhook confirms it on its own; the log below shows the event when it lands. Or ask the gateway directly.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}
      <Tiles items={[
        ["Gateways live", String(on.length), on.length ? "var(--green-ink)" : "var(--red-ink)", on.length ? on.map((g) => `${DESK_LABEL[g.gateway] ?? g.gateway} · ${g.mode.toLowerCase()}`).join(", ") : "Set a secret to wire one"],
        ["Events today", String(t.today), null, `${money(Number(t.settled_today))} settled today`],
        ["Settled, all time", String(t.settled), "var(--green-ink)", "Posted from a gateway's word, verified"],
        ["Exceptions open", String(t.exceptions), Number(t.exceptions) ? "var(--red-ink)" : null, `${t.bad_signatures} bad signature${Number(t.bad_signatures) === 1 ? "" : "s"} discarded`],
      ]} />
      <Panel title="Configured gateways" right="Test or live is read from the key's own prefix">
        <DTable cols={["Gateway", "Mode|mid", "Channels", "Webhook address", "Status|num"]} rows={d.gateways.map((g) => [
          <strong key="g">{DESK_LABEL[g.gateway] ?? g.gateway}</strong>,
          g.on ? <Pil kind={g.mode === "LIVE" ? "ok" : "info"} key="m">{g.mode === "LIVE" ? "Live" : "Test"}</Pil> : <Pil kind="grey" key="m">Off</Pil>,
          <span className="sub2" key="c">{g.channels}</span>,
          <span className="tnum sub2" key="w">{addressOf(g)}{g.validate ? <div>Reference check: {(quickteller ? quickteller.apiBase : apiBase) + g.validate}</div> : null}</span>,
          g.gateway === "paydirect"
            ? (g.on ? (g.hash ? <Pil kind="ok" key="s">Switched on</Pil> : <Pil kind="bad" key="s">On, notification credentials missing — payments wait for the collections import</Pil>) : <Pil kind="grey" key="s">Not switched on</Pil>)
            : g.on ? (g.gateway === "flutterwave" && !g.hash ? <Pil kind="bad" key="s">Secret set, hash missing — webhooks refused</Pil> : <Pil kind="ok" key="s">Wired</Pil>) : <Pil kind="grey" key="s">Not wired</Pil>,
        ])} />
        <PBody>
          <KvGrid cls="grid--2" pairs={[
            ["Paystack", "Settings → API Keys & Webhooks: set the webhook URL above; the secret key signs every event (x-paystack-signature). Test keys start sk_test_."],
            ["Flutterwave", "Settings → Webhooks: set the URL above and a secret hash; put the same hash in MOAUM_FLUTTERWAVE_HASH. Test keys start FLWSECK_TEST."],
            ["Return address", `${d.portalUrl}/student/fees?paid=… — the student's browser comes back here; the money is confirmed by the webhook or by verification, never by the browser.`],
            ["The reconciler", "Every ten minutes the portal asks the gateway about every checkout opened in the last three days with nothing confirmed behind it, and posts what the gateway answers. Pay on Quickteller is not asked: its payments come back by Interswitch's notification, or by the collections report."],
          ]} />
        </PBody>
      </Panel>
      {may ? (
        <Panel title="Can the gateways take a payment now?" right={<Btn kind="primary" size="sm" disabled={busy} onClick={async () => { const j = await send("/gateways/health", {}, "Gateways asked whether they can take a payment"); if (j) setHealth(j as unknown as { checkedAt: string; online: boolean; rows: HealthRow[] }); }}>{busy ? "Asking…" : "Test the gateways"}</Btn>}>
          <PBody>
            <div className="sub2">Each wired gateway is asked about a reference that cannot exist — nothing is charged and nothing is written against a student — and its answer is read: whether the key is accepted, whether Interswitch knows the merchant, whether it answers at all. Run it after a key is set or changed, and whenever a payer says the gateway does not open.</div>
            {health ? (
              <>
                <Note kind={health.online ? "ok" : "bad"} title={health.online ? "Payments can be taken online" : "No gateway can take a payment online now"}>
                  Asked {when(health.checkedAt)}. {health.online ? "At least one gateway answered as it should." : "Payers can still pay against their reference at a bank branch or by transfer; the Bursary confirms it against the bank's record."}
                </Note>
                <DTable cols={["Gateway", "Merchant / scope", "State|mid", "What it means", "What the gateway said"]} rows={health.rows.map((h, i) => {
                  const [w, k, m] = HEALTH[h.state] ?? [h.state, "grey", ""];
                  return [<strong key={"g" + i}>{DESK_LABEL[h.gateway] ?? h.gateway}</strong>, <span key={"s" + i} className="sub2">{h.scope}</span>, <Pil key={"p" + i} kind={k}>{w}</Pil>,
                    <span key={"m" + i} className="sub2">{m}</span>, <span key={"x" + i} className="sub2 tnum">{h.http ? `HTTP ${h.http} · ` : ""}{h.said || "—"}</span>];
                })} />
              </>
            ) : null}
          </PBody>
        </Panel>
      ) : null}
      {quickteller ? <PayOnQuickteller q={quickteller} may={may} busy={busy} send={send} say={setSaid} /> : null}
      {mayConfigure ? (
        <Panel title="Configure the keys" right="Directorate of ICT and Super Administrator only">
          <PBody>
            <Note kind="info" title="A key set here is encrypted at rest and read back never">
              You can set a gateway secret here instead of as a service variable. It is encrypted with the portal&rsquo;s own passphrase, decrypted only inside the API to call the gateway, and no screen ever shows it again &mdash; the same rule as a password. A service variable still works and is used when no key is set here. Setting a key is recorded against your name.
            </Note>
            <div className="grid grid--2">
              {config.map((c) => (
                <div className="card" key={c.gateway}><div className="card__body">
                  <div className="row">
                    <b>{DESK_LABEL[c.gateway] ?? c.gateway}</b>
                    {c.configured ? <Pil kind={c.mode === "LIVE" ? "ok" : "info"}>{c.gateway === "paydirect" ? "Credentials set" : c.mode === "LIVE" ? "Live key set" : "Test key set"}</Pil> : <Pil kind="grey">{c.gateway === "paydirect" ? "No credentials" : "No dashboard key"}</Pil>}
                    {c.configured ? <span className="sub2 tnum">{c.gateway === "paydirect" ? "username ends" : "ends"} {c.last4}</span> : null}
                  </div>
                  {c.configured ? <div className="sub2">Set {c.set_at ? when(c.set_at) : ""}{c.set_by_name ? " by " + c.set_by_name : ""}{c.gateway === "flutterwave" ? (c.has_hash ? " \u00b7 hash set" : " \u00b7 no hash yet") : ""}</div> : null}
                  {c.gateway === "paydirect" ? (
                    <>
                      <div className="sub2">Pay on Quickteller: the service username and password Interswitch sends with each payment notification, agreed with Interswitch for the biller. A notification that does not carry them is kept on the log and not believed; nothing is credited on it. The password is stored encrypted and shown never.{quickteller && !quickteller.credentials && c.configured ? " The value stored here is not a username and password (it may be the query credentials kept from before): set the two again." : ""}</div>
                      <div className="grid grid--2">
                        <Field id="pd-user" label="Service username"><input id="pd-user" className="ctl tnum" autoComplete="off" value={pd.user} onChange={(e) => setPd({ ...pd, user: e.target.value })} /></Field>
                        <Field id="pd-pass" label="Service password" hint="At least eight characters; pasted once, never displayed after this."><input id="pd-pass" className="ctl tnum" type="password" autoComplete="new-password" value={pd.pass} onChange={(e) => setPd({ ...pd, pass: e.target.value })} /></Field>
                      </div>
                      <div className="row">
                        <Btn kind="primary" disabled={busy || !pd.user.trim() || pd.pass.trim().length < 8} onClick={async () => { const j = await send("/gateways/paydirect/key", { secret: JSON.stringify({ serviceUsername: pd.user.trim(), servicePassword: pd.pass.trim() }), hash: null }, "Quickteller notification credentials set from the dashboard", "PUT"); if (j) { setSaid("Quickteller notification credentials set \u2014 username ending " + j.last4); setPd({ user: "", pass: "" }); } }}>{c.configured ? "Replace the credentials" : "Set the credentials"}</Btn>
                        {c.configured ? <Btn kind="ghost" disabled={busy} onClick={async () => { if (window.confirm("Clear the Quickteller notification credentials? No notification is believed until they are set again; payments wait for the collections import.") && await send("/gateways/paydirect/clear-key", {}, "Quickteller notification credentials cleared", "POST")) setSaid("Quickteller notification credentials cleared"); }}>Clear</Btn> : null}
                      </div>
                    </>
                  ) : c.gateway === "quickteller" ? (
                    <>
                      <div className="sub2">Quickteller on Interswitch WebPAY: the University&rsquo;s merchant and, for payers in the College of Health Sciences, the College&rsquo;s own. Interswitch identifies a merchant today by a <b>merchant code</b> (MX&hellip;) and a pay item; an older profile is identified by a <b>product id</b> and signs the form with a MAC key. Give the merchant code if the profile shows one, else the product id and the MAC key. The keys are stored encrypted and shown never. A payer&rsquo;s merchant is chosen by the College their programme is in.</div>
                      {qtMain.length ? <div className="sub2">Wired now: {qtMain.map((m) => `${m.scope} \u00b7 ${m.merchantCode ? `merchant ${m.merchantCode}` : `product ${m.productId}`} \u00b7 pay item ${m.payItemId}`).join(" \u00b7 ")}</div> : null}
                      <div className="grid grid--2">
                        <Field id="qt-mc" label="Merchant code (University)" hint="MX… from the Interswitch merchant profile; leave blank to use the product id below."><input id="qt-mc" className="ctl tnum" autoComplete="off" value={qt.merchantCode} onChange={(e) => setQt({ ...qt, merchantCode: e.target.value })} placeholder="MX…" /></Field>
                        <Field id="qt-pi" label="Pay item ID (University)" hint="The pay item on that merchant."><input id="qt-pi" className="ctl tnum" autoComplete="off" value={qt.payItemId} onChange={(e) => setQt({ ...qt, payItemId: e.target.value })} /></Field>
                        <Field id="qt-pid" label="Product ID (University, older profile)" hint="Used only when no merchant code is given."><input id="qt-pid" className="ctl tnum" autoComplete="off" value={qt.productId} onChange={(e) => setQt({ ...qt, productId: e.target.value })} /></Field>
                        <Field id="qt-mac" label="MAC key (University)" hint="Required with a product id; pasted once, never displayed after this."><input id="qt-mac" className="ctl tnum" type="password" autoComplete="off" value={qt.macKey} onChange={(e) => setQt({ ...qt, macKey: e.target.value })} /></Field>
                      </div>
                      <div className="grid grid--2">
                        <Field id="qt-cmc" label="Merchant code (College of Health Sciences)" hint="Optional: leave the College's fields alone if it has no merchant of its own."><input id="qt-cmc" className="ctl tnum" autoComplete="off" value={qt.chsMerchantCode} onChange={(e) => setQt({ ...qt, chsMerchantCode: e.target.value })} placeholder="MX…" /></Field>
                        <Field id="qt-cpi" label="Pay item ID (College of Health Sciences)"><input id="qt-cpi" className="ctl tnum" autoComplete="off" value={qt.chsPayItemId} onChange={(e) => setQt({ ...qt, chsPayItemId: e.target.value })} /></Field>
                        <Field id="qt-cpid" label="Product ID (College, older profile)"><input id="qt-cpid" className="ctl tnum" autoComplete="off" value={qt.chsProductId} onChange={(e) => setQt({ ...qt, chsProductId: e.target.value })} /></Field>
                        <Field id="qt-cmac" label="MAC key (College of Health Sciences)" hint="Required with the College's product id."><input id="qt-cmac" className="ctl tnum" type="password" autoComplete="off" value={qt.chsMacKey} onChange={(e) => setQt({ ...qt, chsMacKey: e.target.value })} /></Field>
                      </div>
                      <label className="sub2 row"><input type="checkbox" checked={qt.sandbox} onChange={(e) => setQt({ ...qt, sandbox: e.target.checked })} /> Sandbox (test) &mdash; leave unchecked for the live Interswitch endpoints</label>
                      <div className="row">
                        <Btn kind="primary" disabled={busy || !qt.payItemId.trim() || !(qt.merchantCode.trim() || (qt.productId.trim() && qt.macKey.trim()))} onClick={async () => { const chs = qt.chsMerchantCode.trim() || qt.chsMacKey.trim() ? { merchantCode: qt.chsMerchantCode.trim() || undefined, productId: qt.chsProductId.trim(), payItemId: qt.chsPayItemId.trim(), macKey: qt.chsMacKey.trim() } : undefined; const j = await send("/gateways/quickteller/key", { secret: JSON.stringify({ merchantCode: qt.merchantCode.trim() || undefined, productId: qt.productId.trim(), payItemId: qt.payItemId.trim(), macKey: qt.macKey.trim(), sandbox: qt.sandbox, chs }), hash: null }, "Quickteller WebPAY configuration set from the dashboard", "PUT"); if (j) { setSaid("Quickteller configured \u2014 " + j.mode + " \u00b7 University merchant ending " + j.last4 + (chs ? " \u00b7 College of Health Sciences merchant set" : "")); setQt(QT_EMPTY); } }}>{c.configured ? "Replace the configuration" : "Set the configuration"}</Btn>
                        {c.configured ? <Btn kind="ghost" disabled={busy} onClick={async () => { if (window.confirm("Clear the Quickteller configuration? The gateway turns off unless a service variable is set.") && await send("/gateways/quickteller/clear-key", {}, "Quickteller configuration cleared", "POST")) setSaid("Quickteller configuration cleared"); }}>Clear</Btn> : null}
                      </div>
                    </>
                  ) : (
                  <>
                  <Field id={"k-" + c.gateway} label="Secret key" hint="Pasted once; it is never displayed after this.">
                    <input id={"k-" + c.gateway} className="ctl tnum" type="password" autoComplete="off" value={keys[c.gateway]?.secret ?? ""} onChange={(e) => setKeys({ ...keys, [c.gateway]: { secret: e.target.value, hash: keys[c.gateway]?.hash ?? "" } })} placeholder={c.gateway === "paystack" ? "sk_test_\u2026 or sk_live_\u2026" : "FLWSECK_TEST-\u2026 or FLWSECK-\u2026"} />
                  </Field>
                  {c.gateway === "flutterwave" ? (
                    <Field id="k-flw-hash" label="Webhook secret hash" hint="The same value you set on the Flutterwave webhook page.">
                      <input id="k-flw-hash" className="ctl tnum" type="password" autoComplete="off" value={keys.flutterwave?.hash ?? ""} onChange={(e) => setKeys({ ...keys, flutterwave: { secret: keys.flutterwave?.secret ?? "", hash: e.target.value } })} />
                    </Field>
                  ) : null}
                  <div className="row">
                    <Btn kind="primary" disabled={busy || !keys[c.gateway]?.secret.trim()} onClick={async () => { const j = await send("/gateways/" + c.gateway + "/key", { secret: keys[c.gateway].secret, hash: keys[c.gateway]?.hash || null }, c.gateway + " key set from the dashboard", "PUT"); if (j) { setSaid(c.gateway + " key set \u2014 " + j.mode + " key ending " + j.last4); setKeys({ ...keys, [c.gateway]: { secret: "", hash: "" } }); } }}>{c.configured ? "Replace the key" : "Set the key"}</Btn>
                    {c.configured ? <Btn kind="ghost" disabled={busy} onClick={async () => { if (window.confirm("Clear the " + c.gateway + " key? The gateway turns off unless a service variable is set.") && await send("/gateways/" + c.gateway + "/clear-key", {}, c.gateway + " key cleared", "POST")) setSaid(c.gateway + " key cleared"); }}>Clear</Btn> : null}
                  </div>
                  </>
                  )}
                </div></div>
              ))}
            </div>
          </PBody>
        </Panel>
      ) : null}
      {may ? (
        <Panel title="Test the gateway" right="A small reference for a demo student, opened on the gateway">
          <PBody>
            <div className="grid grid--3">
              <Field id="tg-num" label="Student" hint="A demo student's matriculation number."><input id="tg-num" className="ctl tnum" value={test.number} onChange={(e) => setTest({ ...test, number: e.target.value })} /></Field>
              <Field id="tg-amt" label="Amount" hint="₦100 is enough."><input id="tg-amt" className="ctl tnum" value={test.amount} onChange={(e) => setTest({ ...test, amount: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
              <Field id="tg-gw" label="Gateway"><select id="tg-gw" className="ctl" value={test.gateway} onChange={(e) => setTest({ ...test, gateway: e.target.value })}>{d.gateways.filter((g) => g.gateway !== "paydirect").map((g) => <option key={g.gateway} value={g.gateway} disabled={!g.on}>{g.gateway}{g.on ? ` (${g.mode.toLowerCase()})` : " — not wired"}</option>)}</select></Field>
            </div>
            <div className="row">
              <Btn kind="primary" disabled={busy || !on.length || !test.number.trim()} onClick={async () => { const j = await send("/test-checkout", { number: test.number, amount: Number(test.amount) || 100, gateway: test.gateway }, `Gateway test checkout for ${test.number}`); if (j?.url) window.location.href = String(j.url); }}>Open a test checkout</Btn>
              <span className="sub2">Pay with the gateway&rsquo;s test card; the webhook lands in the log below, and the reference shows as settled. The purpose is &ldquo;Gateway test&rdquo;, which counts for nothing against the student&rsquo;s fees.</span>
            </div>
            <div className="grid grid--2">
              <Field id="tg-ref" label="Ask about a reference" hint="Any reference this portal generated."><input id="tg-ref" className="ctl tnum" value={ref} onChange={(e) => setRef(e.target.value)} placeholder="MOAUM-FEE-…" /></Field>
              <div className="row row--end" style={{ paddingBottom: "var(--s-4)" }}>
                <Btn kind="ghost" disabled={busy || !ref.trim()} onClick={async () => { const j = await send("/verify", { reference: ref }, `Verified ${ref} with the gateway`); if (j) setSaid(`${ref}: ${j.outcome}${j.said ? ` (${j.said})` : ""}`); }}>Verify with the gateway</Btn>
                <Btn kind="ghost" disabled={busy} onClick={async () => { if (await send("/sweep", {}, "Reconciliation sweep run by hand")) setSaid("The sweep ran; hanging payments were asked about"); }}>Run the sweep now</Btn>
              </div>
            </div>
          </PBody>
        </Panel>
      ) : null}
      <Panel title="Webhook and verification log" right="Every event the portal received, signature good or bad">
        {d.events.length ? (
          <DTable cols={["When|mid", "Gateway", "Event", "Reference", "Amount|num", "Signature|mid", "Result|num"]} rows={d.events.map((e) => [
            <span className="sub2 tnum" key="w">{when(e.received_at)}</span>,
            <span key="g">{DESK_LABEL[e.gateway] ?? e.gateway}<div className="sub2">{e.source.toLowerCase()}</div></span>,
            <span className="sub2" key="e">{e.event ?? "—"}{e.status ? ` · ${e.status}` : ""}</span>,
            <span className="tnum sub2" key="r">{e.reference ?? "—"}{e.gateway_ref ? <div className="sub2">{e.gateway_ref}</div> : null}</span>,
            <span className="tnum" key="a">{e.amount == null ? "—" : money(Number(e.amount))}</span>,
            e.signature_ok ? <Pil kind="ok" key="s">Valid</Pil> : <Pil kind="bad" key="s">Invalid</Pil>,
            <span key="o"><Pil kind={OUTCOME[e.outcome]?.[1] ?? "grey"}>{OUTCOME[e.outcome]?.[0] ?? e.outcome}</Pil>{e.resolved_at ? <div className="sub2">Resolved: {e.resolution} · {e.resolved_by_name ?? ""}</div> : EXCEPTIONS.includes(e.outcome) && may ? <div><Btn kind="ghost" disabled={busy} onClick={async () => { const why = window.prompt("How was it resolved? It goes on the record."); if (why && await send(`/events/${e.id}/resolve`, { resolution: why }, `Gateway event resolved: ${why}`)) setSaid("Resolved"); }}>Resolve</Btn></div> : null}</span>,
          ])} texts={d.events.map((e) => `${e.gateway} ${e.reference ?? ""} ${e.outcome}`)} />
        ) : <PBody><div className="sub2">No event has reached the portal yet. Open a test checkout above and pay with the gateway&rsquo;s test card.</div></PBody>}
      </Panel>
      <Note kind="info" title="A callback is a hint, not an instruction">The portal never credits a student because a gateway said so without keeping what it said. A forged callback is discarded at the signature and logged; a short payment is logged and left open; and on the student&rsquo;s &ldquo;check again&rdquo; the portal asks the gateway itself what the reference settled for.</Note>
    </>
  );
}
