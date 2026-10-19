"use client";

/** V570: Interswitch's settlement report — uploaded from its CSV or Excel file and matched row by row to the portal; each day tied to
 *  the collections statement's credit of its net, Interswitch's fees booked against 5250 Bank charges in the same press; a tie
 *  taken back; a row Interswitch settled for a reference the portal never confirmed proposed to the bank credits. */
import { useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { csvRows, xlsxRows } from "@/lib/xlsx";
import { readSettlement, type SettlementRead } from "@/lib/settlement-file";

interface FileRow { id: string; label: string; file_name: string | null; rows: number; gross: number; fees: number; net: number; first_day: string | null; last_day: string | null;
  uploaded_at: string; uploaded_by_name: string | null; days?: number; tied_days?: number; not_confirmed?: number }
interface Day { settled_on: string; payments: number; gross: number; fees: number; net: number; line_id: string | null; tied_at: string | null; statement: string | null;
  line_no: number | null; value_date: string | null; tied_by_name: string | null; journal_no: number | null }
interface Candidate { settled_on: string; line_id: string; statement: string; line_no: number; value_date: string | null; credit: number; description: string | null }
interface Item { id: string; row_no: number; settled_on: string; paid_on: string | null; reference: string | null; txn_ref: string | null; log_id: string | null; channel: string | null;
  payer: string | null; amount: number; fee: number; net: number; state: string; matched_reference: string | null; matched_by: string | null; expected: number | null;
  bank_credit_id: string | null; bank_credit_state: string | null; portal_payer: string | null; number: string | null }
interface Detail { file: FileRow; days: Day[]; candidates: Candidate[]; counts: { state: string; rows: number; amount: number }[]; items: Item[]; tied?: number }

const STATE: Record<string, ["ok" | "warn" | "bad" | "grey" | "info", string, string]> = {
  MATCHED: ["ok", "Matched", "A payment the portal confirmed, for its amount"],
  AMOUNT_DIFFERS: ["warn", "Amount differs", "Settled for another amount than the portal confirmed"],
  NOT_CONFIRMED: ["bad", "Not confirmed", "Interswitch settled it; the portal never confirmed the reference: the payer paid and may still be blocked"],
  UNKNOWN: ["bad", "Not the portal's", "No reference, transaction reference or Payment Log Id the portal knows"],
  DUPLICATE: ["warn", "Settled before", "In this report twice, or in a report uploaded before"],
  REVERSAL: ["grey", "Reversal", "A negative row: money taken back"],
};
const day = (iso: string | null) => (iso ? new Date(`${iso}T12:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const BASE = "/api/bff/api/v1/finance/settlements";

export function SettlementFile({ canUpload, canTie }: { canUpload: boolean; canTie: boolean }) {
  const [label, setLabel] = useState("");
  const [file, setFile] = useState<string | null>(null);
  const [grid, setGrid] = useState<string[][] | null>(null);
  const [settledDay, setSettledDay] = useState("");
  const [busy, setBusy] = useState(false);
  const [detail, setDetail] = useState<Detail | null>(null);
  const [files, setFiles] = useState<FileRow[] | null>(null);
  const [choice, setChoice] = useState<Record<string, string>>({});
  const [show, setShow] = useState<string>("ATTENTION");
  const read: SettlementRead | null = grid ? readSettlement(grid, settledDay) : null;

  async function loadFiles() {
    const r = await fetch(BASE, { cache: "no-store" }).catch(() => null);
    setFiles(r && r.ok ? ((await r.json()) as FileRow[]) : []);
  }
  useEffect(() => {
    let live = true;
    fetch(BASE, { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : []))
      .catch(() => [])
      .then((j: FileRow[]) => { if (live) setFiles(j); });
    return () => { live = false; };
  }, []);

  async function choose(f: File | null) {
    setDetail(null);
    if (!f) { setGrid(null); setFile(null); return; }
    setFile(f.name);
    if (!label) setLabel(f.name.replace(/\.[^.]+$/, ""));
    setGrid(/\.csv$/i.test(f.name) ? csvRows(await f.text()) : await xlsxRows(await f.arrayBuffer()));
  }

  async function send(path: string, body: unknown, why: string): Promise<Detail | null> {
    const r = await fetch(`${BASE}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(body ?? {}) });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
    return j as Detail;
  }

  async function upload() {
    if (!read?.rows.length || read.needsDay) return;
    setBusy(true);
    try {
      const d = await send("", { label: label.trim(), fileName: file, rows: read.rows }, `Interswitch settlement report ${label} matched`);
      if (d) { setDetail(d); notify(`${label}: ${d.file.rows} row${Number(d.file.rows) === 1 ? "" : "s"} matched`); void loadFiles(); }
    } finally {
      setBusy(false);
    }
  }

  async function open(id: string) {
    const r = await fetch(`${BASE}/${id}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    setDetail(j as Detail);
  }

  async function act(path: string, body: unknown, why: string, said: (d: Detail) => string) {
    if (!detail) return;
    const d = await send(`/${detail.file.id}${path}`, body, why);
    if (d) { setDetail(d); notify(said(d)); void loadFiles(); }
  }

  async function toBankCredit(i: Item) {
    if (!detail) return;
    const r = await fetch(`${BASE}/items/${i.id}/bank-credit`, { method: "POST", headers: { "Content-Type": "application/json",
      "X-Reason": reasonHeader(`Settlement row ${i.row_no} for ${i.matched_reference}, never confirmed, sent to the bank credits`) }, body: "{}" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    notify(`Row ${i.row_no} proposed against ${i.matched_reference}: another officer approves it on the exceptions desk`);
    await open(detail.file.id);
  }

  async function excel() {
    if (!detail) return;
    const head = ["Row", "Settled", "Paid", "Reference", "Transaction reference", "Payment Log Id", "Payer", "Amount", "Fee", "Paid over", "Result", "Portal reference", "Portal amount"];
    const rows = detail.items.map((i) => [i.row_no, day(i.settled_on), day(i.paid_on), i.reference ?? "", i.txn_ref ?? "", i.log_id ?? "", i.portal_payer ?? i.payer ?? "",
      Number(i.amount), Number(i.fee), Number(i.net), STATE[i.state]?.[1] ?? i.state, i.matched_reference ?? "", i.expected == null ? "" : Number(i.expected)]);
    downloadBlob(await brandedXlsx("Interswitch Settlement Matched", head, rows, { sub: `${detail.file.label} · ${day(detail.file.first_day)} to ${day(detail.file.last_day)}`, serial: docSerial("ISM") }),
      `settlement-${detail.file.first_day ?? "rows"}.xlsx`);
  }

  const counted = (st: string) => Number(detail?.counts.find((c) => c.state === st)?.rows ?? 0);
  const shown = (detail?.items ?? []).filter((i) => show === "ALL" || (show === "ATTENTION" ? ["NOT_CONFIRMED", "UNKNOWN", "AMOUNT_DIFFERS", "DUPLICATE"].includes(i.state) : i.state === show));
  const ties = detail ? detail.days.filter((d) => !d.line_id && detail.candidates.filter((c) => c.settled_on === d.settled_on).length === 1).length : 0;

  return (
    <Panel title="Interswitch settlement report" right={detail ? <Btn kind="ghost" size="sm" busyLabel="Preparing Excel..." onClick={() => excel()}>Excel</Btn> : undefined}>
      <PBody>
        <div className="sub2">Upload Interswitch&rsquo;s per-transaction settlement report (CSV or Excel). Each row is matched to the portal by its customer reference, WebPAY&rsquo;s transaction reference or the Payment Log Id. Each day settled is then tied to the collections statement&rsquo;s credit of exactly its net: the day&rsquo;s payments count as in the bank, and Interswitch&rsquo;s fees are booked to 5250 Bank charges in the same press.</div>
        {canUpload ? (
          <div className="row mt-1" style={{ flexWrap: "wrap", gap: 8, alignItems: "flex-end" }}>
            <Field id="sf-file" label="Settlement report" style={{ width: 280 }}><input id="sf-file" type="file" className="ctl" accept=".csv,.xlsx" onChange={(e) => void choose(e.target.files?.[0] ?? null)} /></Field>
            <Field id="sf-label" label="Name" hint="The gateway and the period" style={{ width: 260 }}><input id="sf-label" className="ctl" maxLength={200} value={label} onChange={(e) => setLabel(e.target.value)} /></Field>
            {read?.needsDay ? <Field id="sf-day" label="Settled on" required hint="The report names no settlement date" style={{ width: 180 }}>
              <input id="sf-day" type="date" className="ctl" value={settledDay} onChange={(e) => setSettledDay(e.target.value)} /></Field> : null}
            <Btn kind="primary" disabled={busy || !read?.rows.length || read.needsDay || !label.trim()} onClick={() => void upload()}>{busy ? "Matching…" : "Match the report"}</Btn>
          </div>
        ) : null}
        {read ? (read.problem && !read.rows.length
          ? <Note kind="bad" title="The file could not be read as a settlement report">{read.problem}</Note>
          : <div className="sub2 mt-1">{read.rows.length} row{read.rows.length === 1 ? "" : "s"} read{read.skipped ? `, ${read.skipped} without an amount left out` : ""}, from the columns {Object.entries(read.columns).filter(([, i]) => i >= 0).map(([k, i]) => `${k}: “${read.header[i]}”`).join(", ")}.{read.needsDay ? " Give the day it was settled." : ""}</div>) : null}
      </PBody>
      {detail ? (
        <>
          <PBody><b>{detail.file.label}</b> <span className="sub2">Settled {day(detail.file.first_day)} to {day(detail.file.last_day)} · {money(Number(detail.file.gross))} less {money(Number(detail.file.fees))} fees, {money(Number(detail.file.net))} paid over</span></PBody>
          <Tiles items={[
            ["Matched", String(counted("MATCHED")), "var(--green-ink)", "Payments the portal confirmed"],
            ["Not confirmed", String(counted("NOT_CONFIRMED")), counted("NOT_CONFIRMED") ? "var(--red-ink)" : null, "Settled by Interswitch, never confirmed: propose each to the bank credits"],
            ["Not the portal's", String(counted("UNKNOWN")), counted("UNKNOWN") ? "var(--red-ink)" : null, "A reference the portal did not issue"],
            ["Differs or twice", String(counted("AMOUNT_DIFFERS") + counted("DUPLICATE")), counted("AMOUNT_DIFFERS") + counted("DUPLICATE") ? "var(--amber-ink)" : null, "Another amount, or settled before"],
          ]} />
          <PBody>
            <div className="row" style={{ justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 8 }}>
              <b>Days settled · {detail.days.filter((d) => d.line_id).length} of {detail.days.length} tied</b>
              {canTie && ties ? <Btn kind="primary" size="sm" busyLabel="Tying…" onClick={() => act("/tie-all", {}, `Settlement days of ${detail.file.label} tied to their credits`,
                (d) => `${d.tied ?? 0} day${d.tied === 1 ? "" : "s"} tied; the charges booked to 5250`)}>{`Tie ${ties} day${ties === 1 ? "" : "s"} with one credit`}</Btn> : null}
            </div>
          </PBody>
          <DTable pageSize={0} cols={["Settled|mid", "Payments|num", "Settled amount|num", "Fees|num", "Paid over|num", "The bank's credit", "|num"]} rows={detail.days.map((d) => {
            const options = detail.candidates.filter((c) => c.settled_on === d.settled_on);
            return [
              <span key="d" className="tnum">{day(d.settled_on)}</span>,
              <span key="n" className="tnum">{d.payments}</span>,
              <span key="g" className="tnum">{money(Number(d.gross))}</span>,
              <span key="f" className="tnum">{money(Number(d.fees))}</span>,
              <b key="t" className="tnum">{money(Number(d.net))}</b>,
              <span key="l">{d.line_id
                ? <Two a={<span><Pil kind="ok">Tied</Pil> {d.statement}, line {d.line_no}{d.value_date ? ` · ${day(d.value_date)}` : ""}</span>}
                    b={`${d.journal_no ? `Fees journal #${d.journal_no}` : "No fees"}${d.tied_by_name ? ` · ${d.tied_by_name}` : ""}`} />
                : options.length ? (canTie ? (
                    <select className="ctl" aria-label={`The credit of ${day(d.settled_on)}`} value={choice[d.settled_on] ?? options[0].line_id} onChange={(e) => setChoice({ ...choice, [d.settled_on]: e.target.value })} style={{ maxWidth: 300 }}>
                      {options.map((o) => <option key={o.line_id} value={o.line_id}>{`${o.statement}, line ${o.line_no} · ${day(o.value_date)} · ${money(Number(o.credit))}`}</option>)}
                    </select>) : <span className="sub2">{options.length} credit{options.length === 1 ? "" : "s"} of that amount</span>)
                : <span className="sub2">No credit of {money(Number(d.net))} on a collections statement within a week after</span>}</span>,
              <span key="a">{!canTie ? null : d.line_id
                ? <Btn kind="ghost" size="sm" busyLabel="Taking back…" onClick={() => act(`/days/${d.settled_on}/untie`, {}, `Settlement of ${d.settled_on} taken back`, () => `${day(d.settled_on)} taken back; its fees journal reversed`)}>Take back</Btn>
                : options.length ? <Btn kind="primary" size="sm" busyLabel="Tying…" onClick={() => act(`/days/${d.settled_on}/tie`, { lineId: choice[d.settled_on] ?? options[0].line_id },
                    `Settlement of ${d.settled_on} tied to its credit`, () => `${day(d.settled_on)} tied; ${money(Number(d.fees))} fees booked to 5250`)}>Tie</Btn> : null}</span>,
            ];
          })} />
          <PBody>
            <div className="row" style={{ alignItems: "center", gap: 8, flexWrap: "wrap" }}>
              <b>Rows</b>
              <select className="ctl" aria-label="Which rows" value={show} onChange={(e) => setShow(e.target.value)} style={{ maxWidth: 260 }}>
                <option value="ATTENTION">To look at</option>
                <option value="ALL">Every row</option>
                {Object.entries(STATE).map(([k, v]) => <option key={k} value={k}>{v[1]}</option>)}
              </select>
              {detail.items.length < Number(detail.file.rows) ? <span className="sub2">The first {detail.items.length} of {detail.file.rows}, those to look at first; Excel has these.</span> : null}
            </div>
          </PBody>
          {shown.length ? (
            <DTable cols={["Row|num", "Settled|mid", "On the report", "Amount|num", "Result", "On the portal", "|num"]} rows={shown.map((i) => [
              <span key="n" className="tnum">{i.row_no}</span>,
              <span key="d" className="tnum">{day(i.settled_on)}</span>,
              <Two key="r" a={<span className="tnum">{i.reference ?? i.txn_ref ?? "—"}</span>} b={[i.log_id ? `Log ${i.log_id}` : null, i.payer, i.channel].filter(Boolean).join(" · ")} />,
              <span key="a" className="tnum">{money(Number(i.amount))}<div className="sub2">fee {money(Number(i.fee))}</div></span>,
              <span key="s"><Pil kind={STATE[i.state]?.[0] ?? "grey"}>{STATE[i.state]?.[1] ?? i.state}</Pil><div className="sub2">{STATE[i.state]?.[2]}</div></span>,
              <span key="p">{i.matched_reference
                ? <Two a={<span className="tnum">{`${i.matched_reference}${i.expected != null ? ` · ${money(Number(i.expected))}` : ""}`}</span>} b={[i.portal_payer, i.number].filter(Boolean).join(" · ")} />
                : <span className="sub2">—</span>}</span>,
              <span key="x">{i.state !== "NOT_CONFIRMED" ? null
                : i.bank_credit_id ? <LinkBtn kind="ghost" href="/finance/exceptions">{i.bank_credit_state === "PROPOSED" ? "Awaiting a second officer" : "On the bank credits"}</LinkBtn>
                : canTie ? <Btn kind="primary" size="sm" busyLabel="Proposing…" onClick={() => toBankCredit(i)}>Propose against the reference</Btn>
                : <span className="sub2">The Bursary proposes it</span>}</span>,
            ])} texts={shown.map((i) => `${i.reference ?? ""} ${i.txn_ref ?? ""} ${i.log_id ?? ""} ${i.payer ?? ""} ${i.matched_reference ?? ""} ${i.portal_payer ?? ""}`)} />
          ) : <PBody><div className="sub2">No row of that kind.</div></PBody>}
        </>
      ) : null}
      {files?.length ? (
        <PBody>
          <div className="sub2">Reports matched before:</div>
          <div className="row" style={{ flexWrap: "wrap", gap: 6, marginTop: 6 }}>
            {files.slice(0, 10).map((f) => (
              <Btn key={f.id} kind="ghost" size="sm" onClick={() => void open(f.id)}>{`${f.label} · ${f.tied_days ?? 0}/${f.days ?? 0} days tied${Number(f.not_confirmed) ? ` · ${f.not_confirmed} not confirmed` : ""}`}</Btn>
            ))}
          </div>
        </PBody>
      ) : null}
    </Panel>
  );
}
