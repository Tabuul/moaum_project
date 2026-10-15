"use client";

/**
 * Pay on Quickteller (V299) on the Bursary's screen: the address the University
 * gives Interswitch (Oct 2026: one address for both messages, as Interswitch asks;
 * or each message to its own), the billers (their Quickteller page, whether the
 * portal sends payers there, whether the amount rides in the link), Quickteller's
 * recent reference checks, and the collections report import — the way back for
 * any payment whose notification did not arrive. V383: the test references the
 * Bursary issues for Interswitch's testers.
 */
import { useState, type ReactNode } from "react";
import { DTable } from "@/components/proto/DTable";
import { Field, day, money } from "@/components/proto/blocks";
import { Btn, KvGrid, Note, PBody, Panel, Pil } from "@/components/proto/ui";
import { OUTCOME, when, type PaydirectBiller, type PaydirectDesk } from "@/lib/bursary";
import { collectionRows, gridToText, interswitchLink, quicktellerLink } from "@/lib/quickteller";
import { xlsxRows } from "@/lib/xlsx";
import { InterswitchTestReferences, TEST_REFERENCES_ANCHOR } from "./InterswitchTestReferences";

/** where the collections report is imported — the hanging list sends a PayDirect payment Interswitch did not report here */
export const COLLECTIONS_REPORT_ANCHOR = "collections-report";

type Send = (path: string, body: unknown, reason: string, method?: string) => Promise<Record<string, unknown> | null>;
type Edit = { code: string; name: string; link: string; active: boolean; redirect: boolean; withAmount: boolean };

const COLLEGE: Record<string, string> = { MAIN: "Every department", CHS: "College of Health Sciences" };
const EXAMPLE = { MAIN: "MOAUM-FEE-CSC21001-0042", CHS: "MOAUM-FEE-MBBS21001-0007" } as Record<string, string>;

function editOf(b: PaydirectBiller): Edit {
  return { code: b.biller_code, name: b.name, link: b.pay_link ?? "", active: b.active, redirect: b.redirect, withAmount: b.with_amount };
}

/** Oct 2026: Interswitch's certification, step by step, each read off what the portal has — and what to tell their team next */
function Certification({ q }: { q: PaydirectDesk }) {
  const c = q.certification;
  if (!c) return null;
  const refs = q.testReferences ?? [];
  const open = refs.filter((t) => t.state === "OPEN");
  const asked = refs.filter((t) => Number(t.checks ?? 0) > 0);
  const discarded = Number(c.discarded_since ?? 0);
  const steps: [boolean, string, ReactNode][] = [
    [!!q.notificationKey || !!q.credentialsPair, "The notification address Interswitch has",
      q.notificationKey ? "The keyed address is set: it is the only thing their team configures."
        : q.credentialsPair ? "A username and password are set; Interswitch must send them in each notification — or use the keyed address, which needs nothing of theirs."
        : "Generate the keyed address on Payment gateways and give it to Interswitch as the notification URL."],
    [open.length > 0 || asked.length > 0, "A test reference for their team to use",
      open.length ? `${open.length} open below: give one to the certification team as the reference to validate and pay. Their own references are refused as unknown.`
        : <>Issue one <a href={`#${TEST_REFERENCES_ANCHOR}`}>below</a> and give it to the certification team; their own references are refused as unknown.</>],
    [asked.length > 0 || !!c.validation_at, "Interswitch asked the portal about a reference (customer validation)",
      c.validation_at ? `Last asked ${when(c.validation_at)}; answered ${OUTCOME[c.validation_outcome ?? ""]?.[0] ?? c.validation_outcome ?? ""}.`
        : "Not yet. It shows here the moment their team posts a validation."],
    [!!c.believed_at, "A payment notification was believed",
      c.believed_at ? `${when(c.believed_at)}: ${OUTCOME[c.believed_outcome ?? ""]?.[0] ?? c.believed_outcome ?? ""}${c.believed_outcome === "UNKNOWN_REFERENCE" ? " (their own reference; ask them to pay the test reference)" : ""}.`
        : discarded ? `${discarded} notification${discarded === 1 ? " was" : "s were"} discarded (last ${when(c.discarded_at)}): they were posted to an address without the key. Give their team the keyed address and ask for a resend.`
        : "Not yet."],
    [!!c.reversal_at, "A reversal was believed",
      c.reversal_at ? `${when(c.reversal_at)} on ${c.reversal_reference ?? "—"}; left for the Bursary, as every reversal is.` : "Not yet. Their reversal test shows here."],
  ];
  const done = steps.filter((s) => s[0]).length;
  return (
    <div>
      <div className="row row--between"><div className="b700">Interswitch certification</div><Pil kind={done === steps.length ? "ok" : "info"}>{done} of {steps.length}</Pil></div>
      <ol className="sub2" style={{ paddingLeft: 20, margin: "6px 0 0" }}>
        {steps.map(([ok, title, what], i) => (
          <li key={i} style={{ marginBottom: 6 }}><Pil kind={ok ? "ok" : "grey"}>{ok ? "Done" : "Pending"}</Pil> <b>{title}</b><div>{what}</div></li>
        ))}
      </ol>
    </div>
  );
}

export function PayOnQuickteller({ q, may, busy, send, say }: { q: PaydirectDesk; may: boolean; busy: boolean; send: Send; say: (s: string) => void }) {
  const [edit, setEdit] = useState<Record<string, Edit>>({});
  const [text, setText] = useState("");
  const [file, setFile] = useState<{ name: string; problem: string | null } | null>(null);
  const rows = collectionRows(text);
  const total = rows.reduce((n, r) => n + (Number(r.amount) || 0), 0);

  /** Interswitch's report as downloaded — .xlsx or .csv — read into the box, so what is imported is what is seen */
  async function readReport(f: File) {
    setFile({ name: f.name, problem: null });
    try {
      if (/\.xlsx$/i.test(f.name)) setText(gridToText(await xlsxRows(await f.arrayBuffer())));
      else if (/\.(csv|txt|tsv)$/i.test(f.name)) setText(await f.text());
      else setFile({ name: f.name, problem: "Choose the report as .xlsx or .csv. An older .xls file: open it and save it as .xlsx first." });
    } catch (e) {
      setFile({ name: f.name, problem: `The file could not be read: ${(e as Error).message}` });
    }
  }
  const validateAt = q.apiBase + q.validatePath;
  const notifyAt = q.apiBase + q.notifyPath;
  const singleAt = q.apiBase + (q.singlePath ?? "/api/v1/payments/paydirect/interswitch");
  // Oct 2026: with a key generated on Payment gateways, the address to give is the keyed one — shown once when generated
  const keyedAt = q.apiBase + (q.keyedPath ?? "/api/v1/payments/paydirect/interswitch/<key>");
  const on = q.billers.filter((b) => b.active && b.redirect && b.pay_link);

  function copy(s: string) {
    void navigator.clipboard?.writeText(s).then(() => say("Copied: " + s), () => say(s));
  }

  return (
    <Panel title="Pay on Quickteller" right={on.length ? <Pil kind="ok">Sending payers to {on.map((b) => COLLEGE[b.scope] ?? b.scope).join(" and ")}</Pil> : <Pil kind="grey">Not switched on</Pil>}>
      <PBody>
        <Note kind="info" title="Interswitch's arrangement: the portal's own reference, filled in on the University's Quickteller page">
          The biller&rsquo;s page opens with the reference in <b>cid</b>. Quickteller checks the reference with the portal and reports each payment; it is confirmed once, for the amount owed. College of Health Sciences payers use the College&rsquo;s biller while it is in use.
        </Note>
        <KvGrid cls="grid--2" pairs={[
          ["1 · Give Interswitch this one address", <span key="a">
            <span className="blk"><b className="tnum">{singleAt}</b> <Btn kind="ghost" onClick={() => copy(singleAt)}>Copy</Btn></span>
            <span className="blk sub2">Where Interswitch configures only the address, give the keyed one: <b className="tnum">{keyedAt}</b>{q.notificationKey ? " — a key is set; the address was shown once when it was generated on Payment gateways." : " — generate the key on Payment gateways; the address is shown once."}</span>
            <span className="sub2 blk mt-2">It takes both the customer validation (the reference check) and the payment notification &mdash; the single URL Interswitch asks for. Each message says which it is, and is answered as such. Opened in a browser, it says it is reachable.</span>
            <span className="sub2 blk mt-2">{"Should Interswitch take them separately: customer validation "}<span className="tnum">{validateAt}</span>{", payment notification "}<span className="tnum">{notifyAt}</span>.</span>
          </span>],
          ["2 · Agree the notification's service username and password", q.credentials
            ? <span key="c"><Pil kind="ok">Set</Pil> <span className="sub2">A notification that does not carry them is kept and not believed.</span></span>
            : <span key="c"><Pil kind="bad">Not set</Pil> <span className="sub2">No notification is believed until the Directorate of ICT sets them under &ldquo;Configure the keys&rdquo; &mdash; payments then wait for the collections import below.</span></span>],
          ["3 · Switch the biller on", "Tick “Send payers here” for the University’s biller (and the College’s, when its biller is ready) and save. Test with a small payment before announcing it."],
          ["Payments that do not come back", "Paste Interswitch’s collections report below: each reference is matched and confirmed; a short payment is kept open for the Bursary."],
        ]} />

        <DTable cols={["Payers|mid", "Biller", "Code|mid", "Quickteller page", "In use|mid", "Sends payers|mid", "Amount in link|mid"]} rows={q.billers.map((b) => [
          <Pil kind={b.scope === "CHS" ? "info" : "grey"} key="s">{COLLEGE[b.scope] ?? b.scope}</Pil>,
          <span key="n">{b.name}</span>,
          <span className="tnum" key="c">{b.biller_code}</span>,
          b.pay_link ? <a className="sub2" href={b.pay_link} target="_blank" rel="noopener noreferrer" key="l">{b.pay_link}</a> : <span className="sub2" key="l">—</span>,
          b.active ? <Pil kind="ok" key="a">In use</Pil> : <Pil kind="grey" key="a">Not in use</Pil>,
          b.redirect ? <Pil kind="ok" key="r">On</Pil> : <Pil kind="grey" key="r">Off</Pil>,
          <span className="sub2" key="w">{b.with_amount ? "Yes" : "No — reference only"}</span>,
        ])} />

        {may ? (
          <div className="grid grid--2 mt-3">
            {q.billers.map((b) => {
              const e = edit[b.scope] ?? editOf(b);
              const set = (patch: Partial<Edit>) => setEdit({ ...edit, [b.scope]: { ...e, ...patch } });
              const link = interswitchLink(e.link);
              const badLink = e.link.trim() !== "" && !link;
              const example = link ? quicktellerLink(link, EXAMPLE[b.scope] ?? "MOAUM-FEE-EXAMPLE-0001", 51000, e.withAmount) : null;
              return (
                <div className="card" key={b.scope}><div className="card__body">
                  <div className="row"><b>{COLLEGE[b.scope] ?? b.scope}</b>{b.updated_at ? <span className="sub2">Saved {day(b.updated_at)}</span> : null}</div>
                  <div className="grid grid--2">
                    <Field id={`qt-code-${b.scope}`} label="Biller code"><input id={`qt-code-${b.scope}`} className="ctl tnum" value={e.code} onChange={(ev) => set({ code: ev.target.value })} /></Field>
                    <Field id={`qt-name-${b.scope}`} label="Name"><input id={`qt-name-${b.scope}`} className="ctl" value={e.name} onChange={(ev) => set({ name: ev.target.value })} /></Field>
                  </div>
                  <Field id={`qt-link-${b.scope}`} label="Quickteller page" hint="The biller's own page, such as https://quickteller.com/bsum — the portal adds the reference and the amount." error={badLink ? "Only an Interswitch page: https, a quickteller.com address, and nothing after the path." : undefined}>
                    <input id={`qt-link-${b.scope}`} className="ctl" value={e.link} onChange={(ev) => set({ link: ev.target.value })} placeholder="https://quickteller.com/bsum" />
                  </Field>
                  <label className="sub2 row"><input type="checkbox" checked={e.active} onChange={(ev) => set({ active: ev.target.checked, redirect: ev.target.checked && e.redirect })} /> In use{b.scope === "CHS" ? " — when not, the College's payers pay the University's biller" : ""}</label>
                  <label className="sub2 row"><input type="checkbox" checked={e.redirect} disabled={!e.active || !link} onChange={(ev) => set({ redirect: ev.target.checked })} /> Send payers here (Pay on Quickteller)</label>
                  <label className="sub2 row"><input type="checkbox" checked={e.withAmount} onChange={(ev) => set({ withAmount: ev.target.checked })} /> Carry the amount in the link</label>
                  {example ? <div className="sub2 mt-2">A payer is sent to <span className="tnum">{example}</span></div> : null}
                  <div className="row mt-2">
                    <Btn kind="primary" disabled={busy || !e.code.trim() || !e.name.trim() || badLink} onClick={async () => {
                      const j = await send(`/paydirect/billers/${b.scope}`, { code: e.code.trim(), name: e.name.trim(), link: link ?? null, active: e.active, redirect: e.redirect, withAmount: e.withAmount },
                        `Quickteller biller ${b.scope} saved${e.redirect ? " — payers sent to it" : ""}`, "PUT");
                      if (j) { const rest = { ...edit }; delete rest[b.scope]; setEdit(rest); say(`${COLLEGE[b.scope] ?? b.scope}: saved${e.redirect ? "; Pay on Quickteller is on" : ""}`); }
                    }}>Save</Btn>
                    {edit[b.scope] ? <Btn kind="ghost" disabled={busy} onClick={() => { const rest = { ...edit }; delete rest[b.scope]; setEdit(rest); }}>Undo</Btn> : null}
                  </div>
                </div></div>
              );
            })}
          </div>
        ) : null}
      </PBody>

      <PBody>
        <Certification q={q} />
      </PBody>

      <PBody>
        <div id={TEST_REFERENCES_ANCHOR}><InterswitchTestReferences refs={q.testReferences ?? []} may={may} busy={busy} send={send} say={say} /></div>
      </PBody>

      <PBody>
        <div className="b700">Quickteller&rsquo;s reference checks</div>
        {q.validations.length ? (
          <DTable cols={["When|mid", "Reference", "Answer|mid", "Amount|num", "Why"]} rows={q.validations.map((v) => [
            <span className="sub2 tnum" key="w">{when(v.received_at)}</span>,
            <span className="tnum" key="r">{v.reference ?? "—"}{v.merchant_reference ? <div className="sub2">merchant {v.merchant_reference}</div> : null}</span>,
            <Pil kind={OUTCOME[v.outcome]?.[1] ?? "grey"} key="o">{OUTCOME[v.outcome]?.[0] ?? v.outcome}</Pil>,
            <span className="tnum" key="a">{v.amount == null ? "—" : money(Number(v.amount))}</span>,
            <span className="sub2" key="y">{v.why ?? ""}</span>,
          ])} texts={q.validations.map((v) => `${v.reference ?? ""} ${v.outcome}`)} />
        ) : <div className="sub2">No reference check has reached the portal yet.</div>}
      </PBody>

      {may ? (
        // the hanging list's PayDirect rows link here: the way back for a payment Interswitch did not report
        <div id={COLLECTIONS_REPORT_ANCHOR}><PBody>
          <Field id="qt-report-file" label="Import the collections report" hint="Interswitch's collections report as downloaded (.xlsx or .csv), or its rows pasted below: Customer Reference, Amount, Payment Log Id, Payment Date, Channel, Customer Name. Title lines above the header are passed over.">
            <input id="qt-report-file" className="ctl" type="file" accept=".xlsx,.csv,.txt,.tsv" onChange={(ev) => { const f = ev.target.files?.[0]; if (f) void readReport(f); ev.target.value = ""; }} />
          </Field>
          {file ? <div className="sub2 mb-1">{file.problem ? <b>{file.problem}</b> : `Read from ${file.name}.`}</div> : null}
          <Field id="qt-report" label="The rows">
            <textarea id="qt-report" className="ctl tnum" rows={5} value={text} onChange={(ev) => { setText(ev.target.value); setFile(null); }} />
          </Field>
          {rows.length ? (
            <div className="mb-2">
              <div className="sub2 mb-1">{`${rows.length} row${rows.length === 1 ? "" : "s"} read, ${money(total)} in all — each is matched to its reference when imported${rows.length > 8 ? "; the first 8 shown" : ""}.`}</div>
              <DTable noPrint pageSize={0} cols={["Reference", "Amount|num", "Payment Log Id", "Paid", "Channel", "Payer"]} rows={rows.slice(0, 8).map((r, i) => [
                <span key={"p" + i} className="tnum">{r.prn}</span>, <span key={"a" + i} className="tnum">{r.amount ? money(Number(r.amount)) : "—"}</span>,
                <span key={"r" + i} className="tnum sub2">{r.rrn || "—"}</span>, <span key={"d" + i} className="sub2">{r.paidAt || "—"}</span>,
                <span key={"c" + i} className="sub2">{r.channel || "—"}</span>, <span key={"n" + i} className="sub2">{r.payer || "—"}</span>,
              ])} />
            </div>
          ) : null}
          <div className="row">
            <Btn kind="primary" disabled={busy || !rows.length} onClick={async () => {
              const j = await send("/paydirect/import", { rows }, `Quickteller collections report imported: ${rows.length} row${rows.length === 1 ? "" : "s"}`);
              if (j) { say(`Imported ${j.imported}: ${j.matched} confirmed, ${j.short_paid} short and kept open, ${j.unmatched} not the portal's, ${j.duplicate} already imported`); setText(""); setFile(null); }
            }}>{rows.length ? `Import and match ${rows.length} row${rows.length === 1 ? "" : "s"}` : "Import and match"}</Btn>
            {text.trim() && !rows.length ? <span className="sub2">No row with a reference was read: the report needs a Customer Reference column (or the reference first on each line).</span> : null}
          </div>
        </PBody></div>
      ) : null}
      {q.collections.length ? (
        <DTable cols={["Imported|mid", "Reference", "Amount|num", "Channel", "State|mid", "Note"]} rows={q.collections.slice(0, 100).map((c) => [
          <span className="sub2 tnum" key="i">{day(c.imported_at)}</span>,
          <span className="tnum" key="p">{c.prn}{c.rrn ? <div className="sub2">{c.rrn}</div> : null}</span>,
          <span className="tnum" key="a">{c.amount == null ? "—" : money(Number(c.amount))}</span>,
          <span className="sub2" key="c">{c.channel ?? "—"}</span>,
          <Pil kind={c.state === "MATCHED" ? "ok" : c.state === "DUPLICATE" ? "grey" : "bad"} key="s">{c.state === "MATCHED" ? "Confirmed" : c.state === "SHORT_PAID" ? "Short — open" : c.state === "DUPLICATE" ? "Already imported" : "Not the portal's"}</Pil>,
          <span className="sub2" key="w">{c.state === "MATCHED" ? `Confirmed ${c.reference ?? ""}` : (c.why ?? "")}</span>,
        ])} texts={q.collections.slice(0, 100).map((c) => `${c.prn} ${c.state} ${c.payer ?? ""}`)} />
      ) : null}
    </Panel>
  );
}
