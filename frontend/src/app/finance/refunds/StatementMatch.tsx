"use client";

/** V545: the disbursement account's bank statement matched to what was paid out — the Bursary or Internal Audit uploads the bank's
 *  CSV or Excel file; each debit is matched by the transfer reference and the amount to a paid refund or wallet withdrawal (or to
 *  every payment sharing that reference); what does not match, and what was paid out but is not on the statement, is listed. */
import { useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { csvRows, xlsxRows } from "@/lib/xlsx";
import { type StatementRead, readStatement } from "@/lib/bank-statement";

interface Line { line_no: number; value_date: string | null; description: string | null; reference: string | null; debit: number; credit: number; status: string; matched_reference: string | null; expected_amount: number | null; matched_payouts: number }
interface Missing { kind: string; reference: string; payee: string; number: string | null; bank_name: string | null; account_number: string | null; amount: number; paid_on: string; transfer_reference: string | null }
interface Result { id: string; label: string; file_name: string | null; period_from: string | null; period_to: string | null; lines: Line[]; missing: Missing[] }
interface Past { id: string; label: string; period_from: string | null; period_to: string | null; lines: number; uploaded_at: string; uploaded_by_name: string | null; matched: number; amount_differs: number; unmatched: number }

const STATUS: Record<string, ["ok" | "warn" | "bad" | "grey", string]> = { MATCHED: ["ok", "Matched"], AMOUNT_DIFFERS: ["warn", "Amount differs"], UNMATCHED: ["bad", "No payout"], CREDIT: ["grey", "Money in"] };
const day = (iso: string | null) => (iso ? new Date(`${iso}T12:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

export function StatementMatch() {
  const [label, setLabel] = useState("");
  const [file, setFile] = useState<string | null>(null);
  const [read, setRead] = useState<StatementRead | null>(null);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<Result | null>(null);
  const [past, setPast] = useState<Past[] | null>(null);

  async function loadPast() {
    const r = await fetch("/api/bff/api/v1/finance/refunds/bank-statements", { cache: "no-store" }).catch(() => null);
    setPast(r && r.ok ? ((await r.json()) as Past[]) : []);
  }
  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/finance/refunds/bank-statements", { cache: "no-store" })
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

  async function upload() {
    if (!read?.lines.length) return;
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/finance/refunds/bank-statements", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Bank statement ${label} matched to what was paid out`) },
        body: JSON.stringify({ label: label.trim(), fileName: file, rows: read.lines }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setResult(j as Result);
      notify(`${label} matched`);
      void loadPast();
    } finally {
      setBusy(false);
    }
  }

  async function open(id: string) {
    const r = await fetch(`/api/bff/api/v1/finance/refunds/bank-statements/${id}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    setResult(j as Result);
  }

  const counts = (st: string) => (result?.lines ?? []).filter((l) => l.status === st).length;
  const odd = (result?.lines ?? []).filter((l) => l.status === "UNMATCHED" || l.status === "AMOUNT_DIFFERS");
  async function excel() {
    if (!result) return;
    const head = ["Line", "Date", "Reference", "Description", "Debit", "Credit", "Result", "Transfer reference matched", "Payout amount", "Payouts"];
    const rows = result.lines.map((l) => [l.line_no, day(l.value_date), l.reference ?? "", l.description ?? "", Number(l.debit) || "", Number(l.credit) || "",
      STATUS[l.status]?.[1] ?? l.status, l.matched_reference ?? "", l.expected_amount == null ? "" : Number(l.expected_amount), l.matched_payouts || ""]);
    const missing = result.missing.map((m, i) => [`M${i + 1}`, day(m.paid_on), m.transfer_reference ?? "", `${m.reference} · ${m.payee} · ${m.bank_name ?? ""} ${m.account_number ?? ""}`, Number(m.amount), "", "Paid out, not on the statement", "", "", ""]);
    downloadBlob(await brandedXlsx("Bank Statement Matched to Payouts", head, [...rows, ...missing], { sub: `${result.label} · ${day(result.period_from)} to ${day(result.period_to)}`, serial: docSerial("BSM") }), `statement-match-${result.period_from ?? "lines"}.xlsx`);
  }

  return (
    <Panel title="Bank statement" right={result ? <Btn kind="ghost" size="sm" busyLabel="Preparing Excel..." onClick={() => excel()}>Excel</Btn> : undefined}>
      <PBody>
        <div className="sub2">Upload the disbursement account&rsquo;s statement (the bank&rsquo;s CSV or Excel file). Each debit is matched to a paid refund or wallet withdrawal by the bank transfer reference in its reference or narration and by the amount; what does not match, and what was paid out but is not on the statement, is listed.</div>
        <div className="row mt-1" style={{ flexWrap: "wrap", gap: 8, alignItems: "flex-end" }}>
          <Field id="bs-file" label="Statement file" style={{ width: 280 }}><input id="bs-file" type="file" className="ctl" accept=".csv,.xlsx" onChange={(e) => void choose(e.target.files?.[0] ?? null)} /></Field>
          <Field id="bs-label" label="Name" hint="The account and the period" style={{ width: 280 }}><input id="bs-label" className="ctl" maxLength={200} value={label} onChange={(e) => setLabel(e.target.value)} /></Field>
          <Btn kind="primary" disabled={busy || !read?.lines.length || !label.trim()} onClick={() => void upload()}>{busy ? "Matching…" : "Match the statement"}</Btn>
        </div>
        {read ? (read.problem
          ? <Note kind="bad" title="The file could not be read as a statement">{read.problem}</Note>
          : <div className="sub2 mt-1">{read.lines.length} line{read.lines.length === 1 ? "" : "s"} read ({read.lines.filter((l) => l.debit).length} debits){read.skipped ? `, ${read.skipped} without a date or amount left out` : ""}, from the columns {Object.entries(read.columns).filter(([, i]) => i >= 0).map(([k, i]) => `${k}: “${read.header[i]}”`).join(", ")}.</div>) : null}
      </PBody>
      {result ? (
        <>
          <PBody><b>{result.label}</b> <span className="sub2">Lines dated {day(result.period_from)} to {day(result.period_to)}</span></PBody>
          <Tiles items={[
            ["Matched", String(counts("MATCHED")), "var(--green-ink)", "Debits matched to a payout"],
            ["Amount differs", String(counts("AMOUNT_DIFFERS")), counts("AMOUNT_DIFFERS") ? "var(--amber-ink)" : null, "The reference, another amount"],
            ["No payout", String(counts("UNMATCHED")), counts("UNMATCHED") ? "var(--red-ink)" : null, "Debits the portal did not pay out"],
            ["Not on the statement", String(result.missing.length), result.missing.length ? "var(--red-ink)" : null, "Paid out in the period"],
          ]} />
          {odd.length ? (
            <DTable pageSize={0} cols={["Line|num", "Date|mid", "On the statement", "Debit|num", "Result", "Payout"]} rows={odd.map((l) => [
              <span key="n" className="tnum">{l.line_no}</span>,
              <span key="d" className="tnum">{day(l.value_date)}</span>,
              <Two key="t" a={<span className="tnum">{l.reference || "—"}</span>} b={l.description ?? ""} />,
              <b key="m" className="tnum">{money(Number(l.debit))}</b>,
              <Pil key="s" kind={STATUS[l.status]?.[0] ?? "grey"}>{STATUS[l.status]?.[1] ?? l.status}</Pil>,
              <span key="p" className="sub2">{l.matched_reference ? `${l.matched_reference} · ${money(Number(l.expected_amount))}` : "—"}</span>,
            ])} texts={odd.map((l) => `${l.reference ?? ""} ${l.description ?? ""}`)} />
          ) : <PBody><div className="sub2">Every debit on the statement matched a payout.</div></PBody>}
          {result.missing.length ? (
            <>
              <PBody><b>Paid out in the period, not on the statement</b></PBody>
              <DTable pageSize={0} cols={["Paid on|mid", "Payment", "Paid into", "Amount|num", "Transfer reference"]} rows={result.missing.map((m) => [
                <span key="d" className="tnum">{day(m.paid_on)}</span>,
                <Two key="p" a={<span className="tnum">{m.reference}</span>} b={m.payee} />,
                <span key="a" className="tnum">{`${m.bank_name ?? ""} · ${m.account_number ?? "—"}`}</span>,
                <b key="m" className="tnum">{money(Number(m.amount))}</b>,
                <span key="t" className="tnum">{m.transfer_reference ?? "—"}</span>,
              ])} texts={result.missing.map((m) => `${m.reference} ${m.payee} ${m.transfer_reference ?? ""}`)} />
            </>
          ) : null}
        </>
      ) : null}
      {past?.length ? (
        <PBody>
          <div className="sub2">Statements matched before:</div>
          <div className="row" style={{ flexWrap: "wrap", gap: 6, marginTop: 6 }}>
            {past.slice(0, 10).map((p) => (
              <Btn key={p.id} kind="ghost" size="sm" onClick={() => void open(p.id)}>{`${p.label} · ${p.matched}/${p.lines}${Number(p.unmatched) + Number(p.amount_differs) ? ` · ${Number(p.unmatched) + Number(p.amount_differs)} to look at` : ""}`}</Btn>
            ))}
          </div>
        </PBody>
      ) : null}
    </Panel>
  );
}
