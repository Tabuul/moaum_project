"use client";

/** tGateways — proto/part18.html: the gateways wired, a secret never read back, the webhook log, a test checkout (V037). */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { OUTCOME, when, type GatewayConfig, type PaymentsDesk, type PaydirectDesk } from "@/lib/bursary";
import { parseRows } from "@/lib/wallet";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, day, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export function Gateways({ d, config, paydirect, paid, actingOffice }: { d: PaymentsDesk; config: GatewayConfig[]; paydirect: PaydirectDesk | null; paid: string | null; actingOffice: string | null }) {
  const router = useRouter();
  // the Bursary monitors, tests and verifies; only the Directorate of ICT and the Super
  // Administrator set or clear a gateway key — the key setup is off the Bursar's desk
  const may = ["bursar", "ict", "admin", "super"].includes(actingOffice ?? "");
  const mayConfigure = ["ict", "admin", "super"].includes(actingOffice ?? "");
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const [test, setTest] = useState({ number: "MOAUM/MTC/24/9903", amount: "100", gateway: d.gateways.find((g) => g.on)?.gateway ?? "paystack" });
  const [ref, setRef] = useState("");
  const [keys, setKeys] = useState<Record<string, { secret: string; hash: string }>>({ paystack: { secret: "", hash: "" }, flutterwave: { secret: "", hash: "" } });
  // Quickteller Business is not one string but a set: the whole set is stored as one JSON secret
  const [qt, setQt] = useState({ clientId: "", clientSecret: "", merchantCode: "", payItemId: "", sandbox: true });
  // Quickteller PayDirect: the query-API credentials (optional; the report import needs none)
  const [pdKey, setPdKey] = useState({ clientId: "", clientSecret: "", sandbox: true });
  const [pdText, setPdText] = useState("");
  const [pdEdit, setPdEdit] = useState<Record<string, { code: string; name: string; link: string }>>({});
  const on = d.gateways.filter((g) => g.on);
  const t = d.tiles;
  const apiBase = d.portalUrl.replace("moaum-portal", "moaum-api");

  async function send(path: string, body: unknown, reason: string, method: string = "POST"): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/payments${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return null; }
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
        ["Gateways live", String(on.length), on.length ? "var(--green-ink)" : "var(--red-ink)", on.length ? on.map((g) => `${g.gateway} · ${g.mode.toLowerCase()}`).join(", ") : "Set a secret to wire one"],
        ["Events today", String(t.today), null, `${money(Number(t.settled_today))} settled today`],
        ["Settled, all time", String(t.settled), "var(--green-ink)", "Posted from a gateway's word, verified"],
        ["Exceptions open", String(t.exceptions), Number(t.exceptions) ? "var(--red-ink)" : null, `${t.bad_signatures} bad signature${Number(t.bad_signatures) === 1 ? "" : "s"} discarded`],
      ]} />
      <Panel title="Configured gateways" right="Test or live is read from the key's own prefix">
        <DTable cols={["Gateway", "Mode|mid", "Channels", "Webhook address", "Status|num"]} rows={d.gateways.map((g) => [
          <strong key="g" style={{ textTransform: "capitalize" }}>{g.gateway}</strong>,
          g.on ? <Pil kind={g.mode === "LIVE" ? "ok" : "info"} key="m">{g.mode === "LIVE" ? "Live" : "Test"}</Pil> : <Pil kind="grey" key="m">Off</Pil>,
          <span className="sub2" key="c">{g.channels}</span>,
          <span className="tnum sub2" key="w">{apiBase}{g.webhook}</span>,
          g.on ? (g.gateway === "flutterwave" && !g.hash ? <Pil kind="bad" key="s">Secret set, hash missing — webhooks refused</Pil> : <Pil kind="ok" key="s">Wired</Pil>) : <Pil kind="grey" key="s">Not wired</Pil>,
        ])} />
        <PBody>
          <KvGrid cls="grid--2" pairs={[
            ["Paystack", "Settings → API Keys & Webhooks: set the webhook URL above; the secret key signs every event (x-paystack-signature). Test keys start sk_test_."],
            ["Flutterwave", "Settings → Webhooks: set the URL above and a secret hash; put the same hash in MOAUM_FLUTTERWAVE_HASH. Test keys start FLWSECK_TEST."],
            ["Return address", `${d.portalUrl}/student/fees?paid=… — the student's browser comes back here; the money is confirmed by the webhook or by verification, never by the browser.`],
            ["The reconciler", "Every ten minutes the portal asks the gateway about every checkout opened in the last three days with nothing confirmed behind it, and posts what the gateway answers."],
          ]} />
        </PBody>
      </Panel>
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
                    <b style={{ textTransform: "capitalize" }}>{c.gateway}</b>
                    {c.configured ? <Pil kind={c.mode === "LIVE" ? "ok" : "info"}>{c.mode === "LIVE" ? "Live key set" : "Test key set"}</Pil> : <Pil kind="grey">No dashboard key</Pil>}
                    {c.configured ? <span className="sub2 tnum">ends {c.last4}</span> : null}
                  </div>
                  {c.configured ? <div className="sub2">Set {c.set_at ? when(c.set_at) : ""}{c.set_by_name ? " by " + c.set_by_name : ""}{c.gateway === "flutterwave" ? (c.has_hash ? " \u00b7 hash set" : " \u00b7 no hash yet") : ""}</div> : null}
                  {c.gateway === "quickteller" ? (
                    <>
                      <div className="sub2">Quickteller Business (Interswitch): the four things from your merchant profile at business.quickteller.com. They are stored together, encrypted, and shown never.</div>
                      <Field id="qt-cid" label="Client ID" hint="From your Interswitch/Quickteller developer profile."><input id="qt-cid" className="ctl tnum" autoComplete="off" value={qt.clientId} onChange={(e) => setQt({ ...qt, clientId: e.target.value })} placeholder="IKIA\u2026" /></Field>
                      <Field id="qt-cs" label="Client secret" hint="Pasted once; it is never displayed after this."><input id="qt-cs" className="ctl tnum" type="password" autoComplete="off" value={qt.clientSecret} onChange={(e) => setQt({ ...qt, clientSecret: e.target.value })} /></Field>
                      <Field id="qt-mc" label="Merchant code" hint="Your Quickteller merchant code."><input id="qt-mc" className="ctl tnum" autoComplete="off" value={qt.merchantCode} onChange={(e) => setQt({ ...qt, merchantCode: e.target.value })} placeholder="MX\u2026" /></Field>
                      <Field id="qt-pi" label="Pay item ID" hint="The payable/pay-item configured on the merchant profile."><input id="qt-pi" className="ctl tnum" autoComplete="off" value={qt.payItemId} onChange={(e) => setQt({ ...qt, payItemId: e.target.value })} placeholder="Default_Payable_MX\u2026" /></Field>
                      <label className="sub2 row"><input type="checkbox" checked={qt.sandbox} onChange={(e) => setQt({ ...qt, sandbox: e.target.checked })} /> Sandbox (test) &mdash; uncheck for the live Interswitch endpoints</label>
                      <div className="row">
                        <Btn kind="primary" disabled={busy || !qt.clientId.trim() || !qt.clientSecret.trim() || !qt.merchantCode.trim() || !qt.payItemId.trim()} onClick={async () => { const j = await send("/gateways/quickteller/key", { secret: JSON.stringify({ clientId: qt.clientId.trim(), clientSecret: qt.clientSecret.trim(), merchantCode: qt.merchantCode.trim(), payItemId: qt.payItemId.trim(), sandbox: qt.sandbox }), hash: null }, "Quickteller configuration set from the dashboard", "PUT"); if (j) { setSaid("Quickteller configured \u2014 " + j.mode + " \u00b7 merchant ending " + j.last4); setQt({ clientId: "", clientSecret: "", merchantCode: "", payItemId: "", sandbox: true }); } }}>{c.configured ? "Replace the configuration" : "Set the configuration"}</Btn>
                        {c.configured ? <Btn kind="ghost" disabled={busy} onClick={async () => { if (window.confirm("Clear the Quickteller configuration? The gateway turns off unless a service variable is set.") && await send("/gateways/quickteller/clear-key", {}, "Quickteller configuration cleared", "POST")) setSaid("Quickteller configuration cleared"); }}>Clear</Btn> : null}
                      </div>
                    </>
                  ) : c.gateway === "paydirect" ? (
                    <>
                      <div className="sub2">Quickteller PayDirect query API (optional): the client id and secret Interswitch issues for the Transaction Query API. The collections import needs none of this — set it only to poll payments automatically.</div>
                      <Field id="pd-cid" label="Client ID"><input id="pd-cid" className="ctl tnum" autoComplete="off" value={pdKey.clientId} onChange={(e) => setPdKey({ ...pdKey, clientId: e.target.value })} /></Field>
                      <Field id="pd-cs" label="Client secret" hint="Pasted once; never displayed after this."><input id="pd-cs" className="ctl tnum" type="password" autoComplete="off" value={pdKey.clientSecret} onChange={(e) => setPdKey({ ...pdKey, clientSecret: e.target.value })} /></Field>
                      <label className="sub2 row"><input type="checkbox" checked={pdKey.sandbox} onChange={(e) => setPdKey({ ...pdKey, sandbox: e.target.checked })} /> Sandbox (test)</label>
                      <div className="row">
                        <Btn kind="primary" disabled={busy || !pdKey.clientId.trim() || !pdKey.clientSecret.trim()} onClick={async () => { const j = await send("/gateways/paydirect/key", { secret: JSON.stringify({ clientId: pdKey.clientId.trim(), clientSecret: pdKey.clientSecret.trim(), sandbox: pdKey.sandbox }), hash: null }, "PayDirect query credentials set from the dashboard", "PUT"); if (j) { setSaid("PayDirect query API configured — " + j.mode); setPdKey({ clientId: "", clientSecret: "", sandbox: true }); } }}>{c.configured ? "Replace the credentials" : "Set the credentials"}</Btn>
                        {c.configured ? <Btn kind="ghost" disabled={busy} onClick={async () => { if (window.confirm("Clear the PayDirect query credentials? The report import still works.") && await send("/gateways/paydirect/clear-key", {}, "PayDirect query credentials cleared", "POST")) setSaid("PayDirect query credentials cleared"); }}>Clear</Btn> : null}
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
      {may && paydirect ? (
        <Panel title="Quickteller PayDirect" right="Billers routed by College, and the collections report">
          <PBody>
            <Note kind="info" title="A student pays a PRN; the payment comes back by import or by query">
              Each College pays its own biller — Health Sciences the CHS biller, every other department the main one — and the student cannot choose. The student&rsquo;s reference is the PRN they enter on Quickteller, an ATM, USSD or at a bank. Import the day&rsquo;s collections report here to confirm those payments; when the query credentials above are set, the ten-minute sweep also polls Interswitch.
            </Note>
            <DTable cols={["College|mid", "Biller", "Code|mid", "Pay link", "Active|mid"]} rows={paydirect.billers.map((b) => [
              <Pil kind={b.scope === "CHS" ? "info" : "grey"} key="s">{b.scope === "CHS" ? "Health Sciences" : "All departments"}</Pil>,
              <span key="n">{b.name}</span>,
              <span className="tnum" key="c">{b.biller_code}</span>,
              b.pay_link ? <a className="sub2" href={b.pay_link} target="_blank" rel="noreferrer" key="l">{b.pay_link}</a> : <span className="sub2" key="l">—</span>,
              b.active ? <Pil kind="ok" key="a">Active</Pil> : <Pil kind="grey" key="a">Off</Pil>,
            ])} />
            <div className="mt-3">
              {paydirect.billers.map((b) => {
                const ed = pdEdit[b.scope] ?? { code: b.biller_code, name: b.name, link: b.pay_link ?? "" };
                const set = (k: "code" | "name" | "link", v: string) => setPdEdit({ ...pdEdit, [b.scope]: { ...ed, [k]: v } });
                return (
                  <div key={b.scope} className="row row--end mb-2">
                    <span className="sub2" style={{ minWidth: 120 }}>{b.scope === "CHS" ? "Health Sciences" : "All departments"}</span>
                    <input className="ctl tnum" style={{ width: 130 }} placeholder="Biller code" value={ed.code} onChange={(e) => set("code", e.target.value)} />
                    <input className="ctl" style={{ width: 220 }} placeholder="Name" value={ed.name} onChange={(e) => set("name", e.target.value)} />
                    <input className="ctl" style={{ width: 240 }} placeholder="Pay link" value={ed.link} onChange={(e) => set("link", e.target.value)} />
                    <Btn kind="ghost" disabled={busy || !ed.code.trim() || !ed.name.trim()} onClick={async () => { if (await send(`/paydirect/billers/${b.scope}`, { code: ed.code.trim(), name: ed.name.trim(), link: ed.link.trim() || null, active: true }, `PayDirect biller ${b.scope} updated`, "PUT")) setSaid(`${b.scope} biller saved`); }}>Save</Btn>
                  </div>
                );
              })}
            </div>
            <Field id="pd-rows" label="Import the collections report" hint="Paste rows: PRN, amount, settlement reference (RRN) — with or without a header. One payment per line.">
              <textarea id="pd-rows" className="ctl tnum" rows={5} value={pdText} onChange={(e) => setPdText(e.target.value)} />
            </Field>
            <div><Btn kind="primary" disabled={busy || !pdText.trim()} onClick={async () => { const rows = parseRows(pdText, ["prn", "amount", "rrn", "paidat", "channel", "payer"]).map((r) => ({ prn: r.prn, amount: r.amount, rrn: r.rrn, paidAt: r.paidat, channel: r.channel, payer: r.payer })); const j = await send("/paydirect/import", { rows }, "PayDirect collections report imported"); if (j) { setSaid(`Imported ${j.imported}: ${j.matched} matched, ${j.unmatched} unmatched, ${j.duplicate} already seen`); setPdText(""); } }}>Import and match</Btn></div>
            {paydirect.collections.length ? (
              <div className="mt-3">
                <DTable cols={["Imported|mid", "PRN", "Amount|num", "Channel", "State|mid", "Note"]} rows={paydirect.collections.slice(0, 50).map((c2) => [
                  <span className="sub2 tnum" key="i">{c2.imported_at ? day(c2.imported_at) : ""}</span>,
                  <span className="tnum" key="p">{c2.prn}{c2.rrn ? <div className="sub2">{c2.rrn}</div> : null}</span>,
                  <span className="tnum" key="a">{c2.amount === null ? "—" : money(Number(c2.amount))}</span>,
                  <span className="sub2" key="c">{c2.channel ?? "—"}</span>,
                  <Pil kind={c2.state === "MATCHED" ? "ok" : c2.state === "DUPLICATE" ? "grey" : "bad"} key="s">{c2.state.toLowerCase()}</Pil>,
                  <span className="sub2" key="w">{c2.state === "MATCHED" ? `Confirmed ${c2.reference ?? ""}` : (c2.why ?? "")}</span>,
                ])} texts={paydirect.collections.slice(0, 50).map((c2) => `${c2.prn} ${c2.state}`)} />
              </div>
            ) : null}
          </PBody>
        </Panel>
      ) : null}
      {may ? (
        <Panel title="Test the gateway" right="A small reference for a demo student, opened on the gateway">
          <PBody>
            <div className="grid grid--3">
              <Field id="tg-num" label="Student" hint="A demo student's matriculation number."><input id="tg-num" className="ctl tnum" value={test.number} onChange={(e) => setTest({ ...test, number: e.target.value })} /></Field>
              <Field id="tg-amt" label="Amount" hint="₦100 is enough."><input id="tg-amt" className="ctl tnum" value={test.amount} onChange={(e) => setTest({ ...test, amount: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
              <Field id="tg-gw" label="Gateway"><select id="tg-gw" className="ctl" value={test.gateway} onChange={(e) => setTest({ ...test, gateway: e.target.value })}>{d.gateways.map((g) => <option key={g.gateway} value={g.gateway} disabled={!g.on}>{g.gateway}{g.on ? ` (${g.mode.toLowerCase()})` : " — not wired"}</option>)}</select></Field>
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
            <span key="g" style={{ textTransform: "capitalize" }}>{e.gateway}<div className="sub2">{e.source.toLowerCase()}</div></span>,
            <span className="sub2" key="e">{e.event ?? "—"}{e.status ? ` · ${e.status}` : ""}</span>,
            <span className="tnum sub2" key="r">{e.reference ?? "—"}{e.gateway_ref ? <div className="sub2">{e.gateway_ref}</div> : null}</span>,
            <span className="tnum" key="a">{e.amount === null ? "—" : money(Number(e.amount))}</span>,
            e.signature_ok ? <Pil kind="ok" key="s">Valid</Pil> : <Pil kind="bad" key="s">Invalid</Pil>,
            <span key="o"><Pil kind={OUTCOME[e.outcome]?.[1] ?? "grey"}>{OUTCOME[e.outcome]?.[0] ?? e.outcome}</Pil>{e.resolved_at ? <div className="sub2">Resolved: {e.resolution} · {e.resolved_by_name ?? ""}</div> : ["UNKNOWN_REFERENCE", "SHORT_PAID", "BAD_SIGNATURE", "GATEWAY_ERROR"].includes(e.outcome) && may ? <div><Btn kind="ghost" disabled={busy} onClick={async () => { const why = window.prompt("How was it resolved? It goes on the record."); if (why && await send(`/events/${e.id}/resolve`, { resolution: why }, `Gateway event resolved: ${why}`)) setSaid("Resolved"); }}>Resolve</Btn></div> : null}</span>,
          ])} texts={d.events.map((e) => `${e.gateway} ${e.reference ?? ""} ${e.outcome}`)} />
        ) : <PBody><div className="sub2">No event has reached the portal yet. Open a test checkout above and pay with the gateway&rsquo;s test card.</div></PBody>}
      </Panel>
      <Note kind="info" title="A callback is a hint, not an instruction">The portal never credits a student because a gateway said so without keeping what it said. A forged callback is discarded at the signature and logged; a short payment is logged and left open; and on the student&rsquo;s &ldquo;check again&rdquo; the portal asks the gateway itself what the reference settled for.</Note>
    </>
  );
}
