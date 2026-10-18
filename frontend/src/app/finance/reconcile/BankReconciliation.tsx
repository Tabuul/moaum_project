"use client";

/** V557: the bank reconciliation statement of 1010 Bank — Fees collection or 1020 Bank — Disbursements for a month: the balance on
 *  the bank's statement, the items between it and the ledger (found from the statements matched above and on Refunds & Credits),
 *  the ledger's balance and what is left unexplained. The Bursary prepares it with the statement's closing balance, accounts for a
 *  line with a journal where it booked one, and another officer signs it; it is then kept as signed. */
import { useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

interface KindSum { kind: string; items: number; amount: number; effect: number }
interface Figures {
  account: string; account_name: string; period_from: string; period_to: string; items_from: string; statement_closing: number | null; ledger_balance: number;
  items_effect: number; adjusted_bank: number | null; difference: number | null; summary: KindSum[]; missing_days: number; missing: string | null; unposted: number; period_ended: boolean;
}
interface Item { kind: string; reference: string; day: string; description: string | null; amount: number; effect: number; line_id: string | null; journal_no: number | null }
interface Saved { id: string; state: "DRAFT" | "SIGNED"; statement_closing: number; difference: number; note: string | null; prepared_by_name: string | null; prepared_at: string; signed_by_name: string | null; signed_at: string | null; prepared_by_me: boolean }
interface Booked { id: string; line_no: number; label: string; day: string; reference: string | null; description: string | null; debit: number; credit: number; journal_no: number; journal_memo: string; booked_note: string | null }
interface Result { figures: Figures; items: Item[]; itemsMore: boolean; saved: Saved | null; booked: Booked[] }
interface Listed { id: string; account: string; period_from: string; period_to: string; difference: number; state: string; signed_by_name: string | null }

const ACCOUNTS: [string, string][] = [["1010", "1010 Bank — Fees collection"], ["1020", "1020 Bank — Disbursements"]];
const KIND: Record<string, string> = {
  RECEIPT_NOT_IN_BANK: "Receipts on the ledger, not yet in the bank",
  RECEIPT_OUTSIDE_BANK: "Receipts on the ledger through a channel that never passes the bank",
  LEDGER_DEBIT_NOT_IN_BANK: "Other money in on the ledger, not in the bank",
  LEDGER_CREDIT_NOT_IN_BANK: "Other money out on the ledger, not in the bank",
  PAYOUT_NOT_IN_BANK: "Payments on the ledger, not yet out of the bank",
  BANK_CREDIT_NOT_IN_LEDGER: "Money into the bank, not on the ledger",
  BANK_DEBIT_NOT_IN_LEDGER: "Money out of the bank, not on the ledger",
  AMOUNT_DIFFERENCE: "Amounts that differ between the bank and the ledger",
  NELFUND_NOT_CREDITED: "NELFUND remittances not yet credited to students",
  GATEWAY_CHARGES: "Gateway charges not yet on the ledger",
};
/** the line items the Bursary may account for with a journal it booked */
const BOOKABLE = ["BANK_CREDIT_NOT_IN_LEDGER", "BANK_DEBIT_NOT_IN_LEDGER", "AMOUNT_DIFFERENCE", "GATEWAY_CHARGES", "NELFUND_NOT_CREDITED"];
const day = (iso: string | null | undefined) => (iso ? new Date(`${iso.slice(0, 10)}T12:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const signed = (n: number) => `${n > 0 ? "+" : n < 0 ? "−" : ""}${money(Math.abs(n))}`;
const lastMonth = () => { const d = new Date(); d.setDate(1); d.setMonth(d.getMonth() - 1); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`; };
const bounds = (month: string) => {
  const [y, m] = month.split("-").map(Number);
  return { from: `${month}-01`, to: `${month}-${String(new Date(y, m, 0).getDate()).padStart(2, "0")}` };
};
const BASE = "/api/bff/api/v1/finance/bank-reconciliation";

export function BankReconciliation({ canPrepare }: { canPrepare: boolean }) {
  const [account, setAccount] = useState("1010");
  const [month, setMonth] = useState(lastMonth());
  const [closing, setClosing] = useState("");
  const [note, setNote] = useState("");
  const [kind, setKind] = useState("");
  const [result, setResult] = useState<Result | null>(null);
  const [list, setList] = useState<Listed[] | null>(null);
  const [booking, setBooking] = useState<Record<string, { journal: string; note: string }>>({});

  async function loadList() {
    const r = await fetch(`${BASE}/saved`, { cache: "no-store" }).catch(() => null);
    setList(r && r.ok ? ((await r.json()) as Listed[]) : []);
  }
  useEffect(() => {
    let live = true;
    fetch(`${BASE}/saved`, { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : []))
      .catch(() => [])
      .then((j: Listed[]) => { if (live) setList(j); });
    return () => { live = false; };
  }, []);

  async function load(acc = account, mon = month, close = closing) {
    const { from, to } = bounds(mon);
    const q = new URLSearchParams({ account: acc, from, to });
    if (close.trim()) q.set("closing", close.replace(/,/g, ""));
    const r = await fetch(`${BASE}?${q}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    const res = j as Result;
    setResult(res);
    if (res.saved) {
      if (!close.trim()) setClosing(String(Number(res.saved.statement_closing)));
      setNote(res.saved.note ?? "");
    }
  }

  async function post(path: string, body: unknown, why: string): Promise<Result | null> {
    const r = await fetch(`${BASE}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(body ?? {}) });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
    return j as Result;
  }

  async function prepare() {
    const { from, to } = bounds(month);
    const j = await post("", { account, from, to, closing: Number(closing.replace(/,/g, "")), note: note.trim() || null }, `Bank reconciliation of ${account} for ${month} prepared`);
    if (j) { setResult(j); notify(`The reconciliation of ${account} for ${month} is prepared; another officer signs it`); void loadList(); }
  }

  async function sign() {
    if (!result?.saved) return;
    const j = await post(`/${result.saved.id}/sign`, {}, `Bank reconciliation of ${account} for ${month} signed`);
    if (j) { setResult(j); notify(`The reconciliation of ${account} for ${month} is signed`); void loadList(); }
  }

  async function journal(lineId: string, journalNo: number | null, why: string) {
    const b = booking[lineId];
    const r = await fetch(`${BASE}/lines/${lineId}/journal`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) },
      body: JSON.stringify({ journalNo, note: journalNo == null ? null : b?.note?.trim() || null }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    notify(journalNo == null ? "The line is taken back from its journal" : `The line is accounted for with journal #${journalNo}`);
    setBooking({ ...booking, [lineId]: { journal: "", note: "" } });
    await load();
  }

  const f = result?.figures;
  const signedOff = result?.saved?.state === "SIGNED";
  const shown = (result?.items ?? []).filter((i) => !kind || i.kind === kind);
  const statementRows: [string, number | null, boolean?][] = f ? [
    [`Balance on the bank's statement at ${day(f.period_to)}`, f.statement_closing == null ? null : Number(f.statement_closing), true],
    ...f.summary.map((s): [string, number] => [`${KIND[s.kind] ?? s.kind} (${s.items})`, Number(s.effect)]),
    ["Adjusted balance of the bank", f.adjusted_bank == null ? null : Number(f.adjusted_bank), true],
    [`Balance on the ledger, ${f.account_name} (${f.account}), at ${day(f.period_to)}`, Number(f.ledger_balance), true],
    ["Difference left unexplained", f.difference == null ? null : Number(f.difference), true],
  ] : [];

  async function excel() {
    if (!f) return;
    const head = ["Part", "Day", "Reference", "Description", "Amount", "Effect on the bank's balance"];
    const rows = [
      ...statementRows.map(([label, v]) => [label, "", "", "", "", v == null ? "" : v]),
      ...(result?.items ?? []).map((i) => [KIND[i.kind] ?? i.kind, day(i.day), i.reference, i.description ?? "", Number(i.amount), Number(i.effect)]),
    ];
    downloadBlob(await brandedXlsx("Bank Reconciliation Statement", head, rows, { sub: `${f.account} ${f.account_name} · ${day(f.period_from)} to ${day(f.period_to)}`, serial: docSerial("BRS") }), `bank-reconciliation-${f.account}-${f.period_to.slice(0, 7)}.xlsx`);
  }
  function print() {
    if (!f) return;
    const s = result?.saved;
    brandedPrint("Bank Reconciliation Statement", `${f.account} ${f.account_name} · ${day(f.period_from)} to ${day(f.period_to)}`, ["", "Amount (₦)"],
      statementRows.map(([label, v]) => [label, v == null ? "—" : signed(v).replace("₦", "")]), docSerial("BRS"), {
        orientation: "portrait",
        meta: [["Prepared by", s?.prepared_by_name ? `${s.prepared_by_name}, ${day(s.prepared_at)}` : "Not prepared"], ["Signed by", s?.signed_by_name ? `${s.signed_by_name}, ${day(s.signed_at)}` : "Not signed"]],
        footnote: s?.note ? `Note: ${s.note}` : null,
      });
  }

  return (
    <Panel title="Bank reconciliation" right={f ? <span className="row row--tight"><Btn kind="ghost" size="sm" busyLabel="Preparing Excel..." onClick={() => excel()}>Excel</Btn><Btn kind="ghost" size="sm" onClick={() => print()}>Print</Btn></span> : undefined}>
      <PBody>
        <div className="sub2">The ledger&rsquo;s balance of a bank account at the end of a month beside the balance on the bank&rsquo;s statement, with the items between them: what the ledger holds and the bank does not show yet, and what the bank shows and the ledger does not hold. The items are found from the statements matched here and on Refunds &amp; Credits. The Bursary prepares it with the statement&rsquo;s closing balance; another officer signs it.</div>
        <div className="row mt-1" style={{ flexWrap: "wrap", gap: 8, alignItems: "flex-end" }}>
          <Field id="br-account" label="Account" style={{ width: 260 }}>
            <select id="br-account" className="ctl" value={account} onChange={(e) => { setAccount(e.target.value); setResult(null); setClosing(""); setNote(""); }}>
              {ACCOUNTS.map(([c, n]) => <option key={c} value={c}>{n}</option>)}
            </select>
          </Field>
          <Field id="br-month" label="Month" style={{ width: 170 }}><input id="br-month" type="month" className="ctl" value={month} onChange={(e) => { setMonth(e.target.value); setResult(null); setClosing(""); setNote(""); }} /></Field>
          <Field id="br-closing" label="Closing balance on the statement" hint="At the month's last day" style={{ width: 230 }}>
            <input id="br-closing" className="ctl tnum" inputMode="decimal" value={closing} disabled={signedOff} onChange={(e) => setClosing(e.target.value.replace(/[^0-9.,-]/g, ""))} />
          </Field>
          <Btn kind="ghost" disabled={!month} busyLabel="Working it out…" onClick={() => load()}>Work it out</Btn>
        </div>
      </PBody>
      {f && result ? (
        <>
          <PBody>
            {result.saved ? (
              <div className="row row--tight" style={{ flexWrap: "wrap" }}>
                <Pil kind={signedOff ? "ok" : "info"}>{signedOff ? "Signed" : "Prepared, not signed"}</Pil>
                <span className="sub2">{`Prepared by ${result.saved.prepared_by_name ?? "—"} on ${day(result.saved.prepared_at)}${signedOff ? ` · signed by ${result.saved.signed_by_name ?? "—"} on ${day(result.saved.signed_at)}` : ""}`}</span>
              </div>
            ) : <span className="sub2">Not prepared for this month yet.</span>}
          </PBody>
          {!signedOff && f.missing_days > 0 ? <Note kind="bad" title="The bank's statements do not cover the whole month">{`No statement of this account covers ${f.missing}. Upload it before the reconciliation is signed.`}</Note> : null}
          {!signedOff && Number(f.unposted) > 0 ? <Note kind="bad" title="Some of the month waits to be posted on the ledger">{`${f.unposted} transaction${Number(f.unposted) === 1 ? "" : "s"} of the month ${Number(f.unposted) === 1 ? "is" : "are"} not on the ledger yet. Post them on Accounting before it is signed.`}</Note> : null}
          {!signedOff && !f.period_ended ? <Note kind="info" title="The month has not ended">It is signed once the month has ended.</Note> : null}
          {f.items_from < f.period_from ? <PBody><div className="sub2">{`The items run from ${day(f.items_from)}, the start of this account's first reconciliation: what is still outstanding from earlier months is carried here.`}</div></PBody> : null}
          <Tiles items={[
            ["On the statement", f.statement_closing == null ? "—" : money(Number(f.statement_closing)), null, `At ${day(f.period_to)}`],
            ["On the ledger", money(Number(f.ledger_balance)), null, `${f.account} at ${day(f.period_to)}`],
            ["Items", String(result.items.length) + (result.itemsMore ? "+" : ""), null, `Net ${signed(Number(f.items_effect))} on the bank's balance`],
            ["Unexplained", f.difference == null ? "—" : money(Number(f.difference)), f.difference == null ? null : Number(f.difference) === 0 ? "var(--green-ink)" : "var(--red-ink)", "Ledger less the adjusted bank"],
          ]} />
          <DTable pageSize={0} cols={["", "Amount|num"]} rows={statementRows.map(([label, v, strong]) => [
            strong ? <b key="l">{label}</b> : <span key="l" style={{ paddingLeft: "var(--s-4)" }}>{label}</span>,
            v == null ? <span key="v" className="sub2">—</span> : strong ? <b key="v" className="tnum">{money(v)}</b> : <span key="v" className="tnum">{signed(v)}</span>,
          ])} />
          {result.items.length ? (
            <>
              <PBody>
                <div className="row" style={{ gap: 8, alignItems: "center", flexWrap: "wrap" }}>
                  <b>The items</b>
                  <select className="ctl" aria-label="Show the items of one kind" value={kind} onChange={(e) => setKind(e.target.value)} style={{ maxWidth: 360 }}>
                    <option value="">Every kind</option>
                    {f.summary.map((s) => <option key={s.kind} value={s.kind}>{`${KIND[s.kind] ?? s.kind} (${s.items})`}</option>)}
                  </select>
                </div>
              </PBody>
              <DTable cols={["Day|mid", "Item", "Kind", "Amount|num", "Effect|num", "|num"]} rows={shown.map((i) => {
                const b = i.line_id ? booking[i.line_id] : undefined;
                return [
                  <span key="d" className="tnum">{day(i.day)}</span>,
                  <Two key="r" a={<span className="tnum">{i.reference}</span>} b={`${i.description ?? ""}${i.journal_no ? ` · journal #${i.journal_no}` : ""}`} />,
                  <span key="k" className="sub2">{KIND[i.kind] ?? i.kind}</span>,
                  <span key="a" className="tnum">{money(Number(i.amount))}</span>,
                  <b key="e" className="tnum">{signed(Number(i.effect))}</b>,
                  <span key="x" className="row row--tight row--right" style={{ flexWrap: "wrap" }}>
                    {canPrepare && !signedOff && i.line_id && BOOKABLE.includes(i.kind) ? (
                      <>
                        <input className="ctl tnum" inputMode="numeric" aria-label={`Journal number for ${i.reference}`} placeholder="Journal no." value={b?.journal ?? ""}
                          onChange={(e) => setBooking({ ...booking, [i.line_id as string]: { journal: e.target.value.replace(/\D/g, ""), note: b?.note ?? "" } })} style={{ width: 110 }} />
                        <input className="ctl" aria-label={`What the journal records for ${i.reference}`} placeholder="What it records" value={b?.note ?? ""} maxLength={500}
                          onChange={(e) => setBooking({ ...booking, [i.line_id as string]: { journal: b?.journal ?? "", note: e.target.value } })} style={{ width: 180 }} />
                        <Btn kind="ghost" size="sm" disabled={!b?.journal || !b?.note?.trim()} busyLabel="Saving…" onClick={() => journal(i.line_id as string, Number(b?.journal), `Statement line ${i.reference} accounted for with journal #${b?.journal}`)}>On the ledger</Btn>
                      </>
                    ) : null}
                  </span>,
                ];
              })} texts={shown.map((i) => `${i.reference} ${i.description ?? ""} ${KIND[i.kind] ?? ""}`)} />
              {result.itemsMore ? <PBody><div className="sub2">The first 5,000 items are shown; the statement above counts them all.</div></PBody> : null}
            </>
          ) : <PBody><div className="sub2">No item stands between the bank&rsquo;s statement and the ledger.</div></PBody>}
          {result.booked.length ? (
            <>
              <PBody><b>Lines accounted for with a journal</b></PBody>
              <DTable pageSize={0} cols={["Day|mid", "Line", "Amount|num", "Journal", "|num"]} rows={result.booked.map((l) => [
                <span key="d" className="tnum">{day(l.day)}</span>,
                <Two key="l" a={l.reference || l.description || `line ${l.line_no}`} b={`${l.label}, line ${l.line_no}`} />,
                <span key="a" className="tnum">{money(Number(l.debit) || Number(l.credit))}</span>,
                <Two key="j" a={`#${l.journal_no} ${l.journal_memo}`} b={l.booked_note ?? ""} />,
                canPrepare && !signedOff ? <Btn key="x" kind="ghost" size="sm" busyLabel="Taking back…" onClick={() => journal(l.id, null, `Statement line ${l.line_no} of ${l.label} taken back from journal #${l.journal_no}`)}>Take back</Btn> : <span key="x" />,
              ])} />
            </>
          ) : null}
          {canPrepare && !signedOff ? (
            <PBody>
              <Field id="br-note" label="Note" hint="Required to sign while a difference is left: say what it is and what is being done about it">
                <textarea id="br-note" className="ctl" rows={2} maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} />
              </Field>
              <div className="row mt-1" style={{ gap: 8, flexWrap: "wrap", alignItems: "center" }}>
                <Btn kind={result.saved ? "ghost" : "primary"} disabled={!closing.trim()} busyLabel="Preparing…" onClick={() => prepare()}>{result.saved ? "Prepare again" : "Prepare"}</Btn>
                {result.saved ? (
                  result.saved.prepared_by_me
                    ? <span className="sub2">Another officer of the Bursary signs it.</span>
                    : <Btn kind="primary" busyLabel="Signing…" onClick={() => sign()}>Sign</Btn>
                ) : null}
              </div>
            </PBody>
          ) : result.saved?.note ? <PBody><div className="sub2">{`Note: ${result.saved.note}`}</div></PBody> : null}
        </>
      ) : null}
      {list?.length ? (
        <PBody>
          <div className="sub2">Reconciliations prepared:</div>
          <div className="row" style={{ flexWrap: "wrap", gap: 6, marginTop: 6 }}>
            {list.slice(0, 12).map((r) => (
              <Btn key={r.id} kind="ghost" size="sm" onClick={() => { const m = r.period_to.slice(0, 7); setAccount(r.account); setMonth(m); setClosing(""); void load(r.account, m, ""); }}>
                {`${r.account} · ${r.period_to.slice(0, 7)} · ${r.state === "SIGNED" ? "signed" : "prepared"}${Number(r.difference) ? ` · ${money(Math.abs(Number(r.difference)))} unexplained` : ""}`}
              </Btn>
            ))}
          </div>
        </PBody>
      ) : null}
    </Panel>
  );
}
