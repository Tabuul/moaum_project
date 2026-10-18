"use client";

/** V552: the collections account's bank statement matched to what the portal received — the Bursary or Internal Audit uploads the
 *  bank's CSV or Excel file; each credit is matched by the portal reference in its reference or narration to a payment the portal
 *  confirmed (same amount, or another), a reference the portal issued and never confirmed (the student paid and may still be
 *  blocked: sent to the bank credits for two officers to post), or a NELFUND remittance; a gateway's one credit for a day is marked
 *  that day's settlement; what the portal confirmed in the period and the bank does not show is listed. */
import { useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { csvRows, xlsxRows } from "@/lib/xlsx";
import { type StatementRead, readStatement } from "@/lib/bank-statement";

interface Line {
  id: string; line_no: number; value_date: string | null; description: string | null; reference: string | null; debit: number; credit: number; status: string;
  matched_kind: string | null; matched_reference: string | null; expected_amount: number | null; matched_payouts: number; settlement_channel: string | null; settlement_day: string | null;
  bank_credit_id: string | null; bank_credit_state: string | null; payer: string | null; number: string | null; confirmed_now: boolean | null;
}
interface Day { channel: string; day: string; payments: number; total: number }
interface NotReceived { reference: string; channel: string; day: string; amount: number; purpose: string | null; payer: string | null; number: string | null }
interface Result { id: string; label: string; period_from: string | null; period_to: string | null; lines: Line[]; unmatchedDays: Day[]; notReceived: NotReceived[]; notReceivedMore: boolean }
interface Past { id: string; label: string; lines: number; matched: number; amount_differs: number; not_confirmed: number; unmatched: number }

const STATUS: Record<string, ["ok" | "warn" | "bad" | "grey" | "info", string]> = {
  MATCHED: ["ok", "Matched"], SETTLEMENT: ["ok", "Day's settlement"], AMOUNT_DIFFERS: ["warn", "Amount differs"], DUPLICATE: ["warn", "Paid twice"],
  RECEIVED_NOT_CONFIRMED: ["bad", "Received, not confirmed"], UNMATCHED: ["bad", "Not found"], DEBIT: ["grey", "Money out"],
};
const day = (iso: string | null) => (iso ? new Date(`${iso}T12:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const ATTENTION = ["RECEIVED_NOT_CONFIRMED", "AMOUNT_DIFFERS", "DUPLICATE", "UNMATCHED"];
const BASE = "/api/bff/api/v1/finance/collections";

export function CollectionsStatement({ canCheck, canPropose }: { canCheck: boolean; canPropose: boolean }) {
  const [label, setLabel] = useState("");
  const [file, setFile] = useState<string | null>(null);
  const [read, setRead] = useState<StatementRead | null>(null);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<Result | null>(null);
  const [past, setPast] = useState<Past[] | null>(null);
  /** the channel and day chosen for each unmatched credit, "channel|day" */
  const [settleAs, setSettleAs] = useState<Record<string, string>>({});

  async function loadPast() {
    const r = await fetch(`${BASE}/statements`, { cache: "no-store" }).catch(() => null);
    setPast(r && r.ok ? ((await r.json()) as Past[]) : []);
  }
  useEffect(() => {
    let live = true;
    fetch(`${BASE}/statements`, { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : []))
      .catch(() => [])
      .then((j: Past[]) => { if (live) setPast(j); });
    return () => { live = false; };
  }, []);

  async function choose(f: File | null) {
    setResult(null);
    if (!f) { setRead(null); setFile(null); return; }
    setFile(f.name);
    if (!label) setLabel(f.name.replace(/\.[^.]+$/, ""));
    const rows = /\.csv$/i.test(f.name) ? csvRows(await f.text()) : await xlsxRows(await f.arrayBuffer());
    setRead(readStatement(rows));
  }

  async function post(path: string, body: unknown, why: string): Promise<(Result & Record<string, unknown>) | null> {
    const r = await fetch(`${BASE}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(body ?? {}) });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
    setResult(j as Result);
    return j;
  }

  async function upload() {
    if (!read?.lines.length) return;
    setBusy(true);
    try {
      if (await post("/statements", { label: label.trim(), fileName: file, rows: read.lines }, `Collections statement ${label} matched to what was received`)) {
        notify(`${label} matched`);
        void loadPast();
      }
    } finally {
      setBusy(false);
    }
  }

  async function open(id: string) {
    const r = await fetch(`${BASE}/statements/${id}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    setResult(j as Result);
  }

  async function settle(l: Line) {
    const [channel, d] = (settleAs[l.id] ?? "").split("|");
    if (!channel || !d) return;
    const j = await post(`/lines/${l.id}/settle`, { channel, day: d }, `Collections line ${l.line_no} marked the settlement of ${channel} on ${d}`);
    if (j) {
      const s = j.settled as { payments: number; total: number; difference: number };
      notify(`Line ${l.line_no}: ${s.payments} ${channel} payment${s.payments === 1 ? "" : "s"} of ${day(d)} settled · ${Number(s.difference) >= 0 ? `${money(Number(s.difference))} charges` : `${money(-Number(s.difference))} more than the payments`}`);
      void loadPast();
    }
  }

  async function toBankCredit(l: Line) {
    if (await post(`/lines/${l.id}/bank-credit`, {}, `Collections line ${l.line_no} for ${l.matched_reference}, never confirmed, sent to the bank credits`)) {
      notify(`Line ${l.line_no} proposed against ${l.matched_reference}: another officer approves it on the exceptions desk`);
      void loadPast();
    }
  }

  const count = (...st: string[]) => (result?.lines ?? []).filter((l) => st.includes(l.status)).length;
  const attention = (result?.lines ?? []).filter((l) => ATTENTION.includes(l.status));
  const settlements = (result?.lines ?? []).filter((l) => l.status === "SETTLEMENT");
  const notReceivedTotal = (result?.notReceived ?? []).reduce((n, x) => n + Number(x.amount), 0);

  async function excel() {
    if (!result) return;
    const head = ["Line", "Date", "Reference", "Description", "Credit", "Debit", "Result", "Portal reference / remittance", "Payer", "Portal amount", "Settled day"];
    const rows = result.lines.map((l) => [l.line_no, day(l.value_date), l.reference ?? "", l.description ?? "", Number(l.credit) || "", Number(l.debit) || "",
      STATUS[l.status]?.[1] ?? l.status, l.matched_reference ?? (l.settlement_channel ?? ""), l.payer ? `${l.payer}${l.number ? ` (${l.number})` : ""}` : "",
      l.expected_amount == null ? "" : Number(l.expected_amount), l.settlement_day ? `${l.settlement_channel} · ${day(l.settlement_day)} · ${l.matched_payouts} payments` : ""]);
    const missing = result.notReceived.map((n, i) => [`C${i + 1}`, day(n.day), n.reference, n.purpose ?? "", "", "", "Confirmed, not in the bank", n.channel, n.payer ? `${n.payer}${n.number ? ` (${n.number})` : ""}` : "", Number(n.amount), ""]);
    downloadBlob(await brandedXlsx("Collections Statement Matched to Receipts", head, [...rows, ...missing], { sub: `${result.label} · ${day(result.period_from)} to ${day(result.period_to)}`, serial: docSerial("CSM") }), `collections-match-${result.period_from ?? "lines"}.xlsx`);
  }

  return (
    <Panel title="Collections statement" right={result ? <Btn kind="ghost" size="sm" busyLabel="Preparing Excel..." onClick={() => excel()}>Excel</Btn> : undefined}>
      <PBody>
        <div className="sub2">Upload the fees collection account&rsquo;s statement (the bank&rsquo;s CSV or Excel file). Each credit is matched by the portal reference in its reference or narration: to a payment the portal confirmed, to a reference it issued and never confirmed (the student paid and may still be blocked), or to a NELFUND remittance. A gateway&rsquo;s one credit for a day is marked that day&rsquo;s settlement. What the portal confirmed in the period and the bank does not show is listed.</div>
        {canCheck ? (
          <div className="row mt-1" style={{ flexWrap: "wrap", gap: 8, alignItems: "flex-end" }}>
            <Field id="cs-file" label="Statement file" style={{ width: 280 }}><input id="cs-file" type="file" className="ctl" accept=".csv,.xlsx" onChange={(e) => void choose(e.target.files?.[0] ?? null)} /></Field>
            <Field id="cs-label" label="Name" hint="The account and the period" style={{ width: 280 }}><input id="cs-label" className="ctl" maxLength={200} value={label} onChange={(e) => setLabel(e.target.value)} /></Field>
            <Btn kind="primary" disabled={busy || !read?.lines.length || !label.trim()} onClick={() => void upload()}>{busy ? "Matching…" : "Match the statement"}</Btn>
          </div>
        ) : null}
        {read ? (read.problem
          ? <Note kind="bad" title="The file could not be read as a statement">{read.problem}</Note>
          : <div className="sub2 mt-1">{read.lines.length} line{read.lines.length === 1 ? "" : "s"} read ({read.lines.filter((l) => l.credit).length} credits){read.skipped ? `, ${read.skipped} without a date or amount left out` : ""}, from the columns {Object.entries(read.columns).filter(([, i]) => i >= 0).map(([k, i]) => `${k}: “${read.header[i]}”`).join(", ")}.</div>) : null}
      </PBody>
      {result ? (
        <>
          <PBody><b>{result.label}</b> <span className="sub2">Lines dated {day(result.period_from)} to {day(result.period_to)}</span></PBody>
          <Tiles items={[
            ["Matched", String(count("MATCHED", "SETTLEMENT")), "var(--green-ink)", "Credits found on the portal"],
            ["Received, not confirmed", String(count("RECEIVED_NOT_CONFIRMED")), count("RECEIVED_NOT_CONFIRMED") ? "var(--red-ink)" : null, "The student paid; the portal never confirmed"],
            ["Amount differs", String(count("AMOUNT_DIFFERS", "DUPLICATE")), count("AMOUNT_DIFFERS", "DUPLICATE") ? "var(--amber-ink)" : null, "Another amount, or paid twice"],
            ["Not in the bank", `${result.notReceived.length}${result.notReceivedMore ? "+" : ""}`, result.notReceived.length ? "var(--red-ink)" : null, `Confirmed in the period · ${money(notReceivedTotal)}`],
          ]} />
          {attention.length ? (
            <DTable pageSize={0} cols={["Line|num", "Date|mid", "On the statement", "Credit|num", "Result", "On the portal", "|num"]} rows={attention.map((l) => {
              const options = result.unmatchedDays.slice().sort((a, b) => Math.abs(Number(a.total) - Number(l.credit)) - Math.abs(Number(b.total) - Number(l.credit)));
              return [
                <span key="n" className="tnum">{l.line_no}</span>,
                <span key="d" className="tnum">{day(l.value_date)}</span>,
                <Two key="t" a={<span className="tnum">{l.reference || "—"}</span>} b={l.description ?? ""} />,
                <b key="m" className="tnum">{money(Number(l.credit))}</b>,
                <Pil key="s" kind={STATUS[l.status]?.[0] ?? "grey"}>{STATUS[l.status]?.[1] ?? l.status}</Pil>,
                <span key="p">{l.matched_reference
                  ? <Two a={<span className="tnum">{`${l.matched_reference} · ${money(Number(l.expected_amount))}`}</span>} b={l.payer ? `${l.payer}${l.number ? ` · ${l.number}` : ""}` : l.matched_kind === "NELFUND" ? "NELFUND remittance" : ""} />
                  : <span className="sub2">No portal reference in the line</span>}</span>,
                <span key="a" className="row row--tight row--right" style={{ flexWrap: "wrap" }}>
                  {l.status === "RECEIVED_NOT_CONFIRMED" ? (
                    l.confirmed_now ? <Pil kind="ok">Confirmed since</Pil>
                      : l.bank_credit_id ? <LinkBtn kind="ghost" href="/finance/exceptions">{l.bank_credit_state === "PROPOSED" ? "Awaiting a second officer" : "On the bank credits"}</LinkBtn>
                      : canPropose ? <Btn kind="primary" size="sm" busyLabel="Proposing…" onClick={() => toBankCredit(l)}>Propose against the reference</Btn>
                      : <span className="sub2">The Bursary proposes it</span>
                  ) : l.status === "UNMATCHED" && canCheck && options.length ? (
                    <>
                      <select className="ctl" aria-label={`Settlement for line ${l.line_no}`} value={settleAs[l.id] ?? ""} onChange={(e) => setSettleAs({ ...settleAs, [l.id]: e.target.value })} style={{ maxWidth: 280 }}>
                        <option value="">A gateway&rsquo;s day it settles…</option>
                        {options.map((o) => <option key={`${o.channel}|${o.day}`} value={`${o.channel}|${o.day}`}>{`${o.channel} · ${day(o.day)} · ${o.payments} for ${money(Number(o.total))}`}</option>)}
                      </select>
                      <Btn kind="ghost" size="sm" disabled={!settleAs[l.id]} busyLabel="Settling…" onClick={() => settle(l)}>Settles that day</Btn>
                    </>
                  ) : null}
                </span>,
              ];
            })} texts={attention.map((l) => `${l.reference ?? ""} ${l.description ?? ""} ${l.matched_reference ?? ""} ${l.payer ?? ""}`)} />
          ) : <PBody><div className="sub2">Every credit on the statement was found on the portal.</div></PBody>}
          {settlements.length ? (
            <PBody>
              <div className="sub2">Days settled by one credit: {settlements.map((l) => `line ${l.line_no}, ${l.settlement_channel} on ${day(l.settlement_day)} (${l.matched_payouts} payments, ${money(Number(l.expected_amount))}; credited ${money(Number(l.credit))})`).join("; ")}.</div>
            </PBody>
          ) : null}
          {result.unmatchedDays.length ? (
            <>
              <PBody><b>Confirmed on the portal, not in the bank — by channel and day</b></PBody>
              <DTable pageSize={0} cols={["Day|mid", "Channel", "Payments|num", "Total|num"]} rows={result.unmatchedDays.map((d) => [
                <span key="d" className="tnum">{day(d.day)}</span>, <span key="c">{d.channel}</span>, <span key="n" className="tnum">{d.payments}</span>, <b key="t" className="tnum">{money(Number(d.total))}</b>,
              ])} />
              <DTable cols={["Day|mid", "Payment", "Payer", "Channel", "Amount|num"]} rows={result.notReceived.map((n) => [
                <span key="d" className="tnum">{day(n.day)}</span>,
                <Two key="r" a={<span className="tnum">{n.reference}</span>} b={n.purpose ?? ""} />,
                <Two key="p" a={n.payer ?? "—"} b={n.number ?? ""} />,
                <span key="c" className="sub2">{n.channel}</span>,
                <b key="a" className="tnum">{money(Number(n.amount))}</b>,
              ])} texts={result.notReceived.map((n) => `${n.reference} ${n.payer ?? ""} ${n.number ?? ""} ${n.channel}`)} />
              {result.notReceivedMore ? <PBody><div className="sub2">The first 500 are shown one by one; the days above count them all.</div></PBody> : null}
            </>
          ) : null}
        </>
      ) : null}
      {past?.length ? (
        <PBody>
          <div className="sub2">Statements matched before:</div>
          <div className="row" style={{ flexWrap: "wrap", gap: 6, marginTop: 6 }}>
            {past.slice(0, 10).map((p) => {
              const look = Number(p.unmatched) + Number(p.amount_differs) + Number(p.not_confirmed);
              return <Btn key={p.id} kind="ghost" size="sm" onClick={() => void open(p.id)}>{`${p.label} · ${p.matched}/${p.lines}${look ? ` · ${look} to look at` : ""}`}</Btn>;
            })}
          </div>
        </PBody>
      ) : null}
    </Panel>
  );
}
