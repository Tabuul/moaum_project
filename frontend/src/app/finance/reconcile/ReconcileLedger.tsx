"use client";

/** The transaction-by-transaction reconciliation of confirmed payments against the
 *  bank (V068). The audit directorate and the Bursary validate each transaction:
 *  matched to the bank, or a discrepancy with a note. Readers see the state; only
 *  reconcilers can record a check. Nothing here moves money. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { when } from "@/lib/bursary";
import { money } from "@/lib/format";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Row {
  reference: string; confirmed_at: string; payer: string | null; number: string | null; purpose: string | null;
  amount: number; channel: string | null; receipt_no: string | null; session: string | null;
  result: string | null; bank_reference: string | null; note: string | null; checked_at: string | null; checked_by_name: string | null;
}

function today() { return new Date().toISOString().slice(0, 10); }
function daysAgo(n: number) { const d = new Date(); d.setDate(d.getDate() - n); return d.toISOString().slice(0, 10); }

export function ReconcileLedger({ canCheck }: { canCheck: boolean }) {
  const [from, setFrom] = useState(daysAgo(30));
  const [to, setTo] = useState(today());
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [nonce, setNonce] = useState(0);

  useEffect(() => {
    let live = true;
    (async () => {
      setLoading(true);
      const r = await fetch(`/api/bff/api/v1/finance/reconciliation?from=${from}&to=${to}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!live) return;
      if (r.ok && j) { setRows((j.rows ?? []) as Row[]); setProblem(null); }
      else setProblem(j ?? { status: r.status, title: r.statusText });
      setLoading(false);
    })();
    return () => { live = false; };
  }, [from, to, nonce]);

  async function check(reference: string, result: "MATCHED" | "DISCREPANCY", bankReference: string | null, note: string | null) {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/finance/reconciliation/${encodeURIComponent(reference)}/check`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Reconcile ${reference}: ${result.toLowerCase()}`) },
        body: JSON.stringify({ result, bankReference, note }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setSaid(`${reference} recorded as ${result === "MATCHED" ? "matched to the bank" : "a discrepancy"}`);
      setNonce((n) => n + 1);
    } finally {
      setBusy(false);
    }
  }

  const matched = rows.filter((r) => r.result === "MATCHED").length;
  const discrepancies = rows.filter((r) => r.result === "DISCREPANCY").length;
  const unchecked = rows.filter((r) => !r.result).length;
  const total = rows.reduce((n, r) => n + Number(r.amount), 0);

  return (
    <>
      <Tiles items={[
        ["Confirmed in the window", money(total), null, `${rows.length} transaction${rows.length === 1 ? "" : "s"}`],
        ["Matched to the bank", String(matched), matched ? "var(--green-ink)" : null, "Validated against the statement"],
        ["Discrepancies", String(discrepancies), discrepancies ? "var(--red-ink)" : null, "Do not agree with the bank"],
        ["Not yet checked", String(unchecked), unchecked ? "var(--chrome)" : null, "Awaiting reconciliation"],
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}
      <Panel title="Confirmed payments to reconcile" right={canCheck ? "Check each against the bank statement" : "You are reading this reconciliation"}>
        <PBody>
          <div className="grid grid--3">
            <Field id="rc-from" label="From"><input id="rc-from" className="ctl" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
            <Field id="rc-to" label="To"><input id="rc-to" className="ctl" type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
          </div>
        </PBody>
        {loading ? <PBody><div className="sub2">Reading the ledger…</div></PBody> : rows.length ? (
          <DTable
            cols={canCheck ? ["Reference", "When|mid", "Payer", "Amount|num", "Bank / status", "Action|num"] : ["Reference", "When|mid", "Payer", "Amount|num", "Bank / status"]}
            rows={rows.map((r) => [
              <span key="r"><span className="tnum sub2">{r.reference}</span><div className="sub2">{r.purpose}</div></span>,
              <span className="sub2 tnum" key="w">{when(r.confirmed_at)}</span>,
              <Two key="p" a={r.payer ?? "—"} b={r.number ?? ""} />,
              <b className="tnum" key="a">{money(Number(r.amount))}</b>,
              <span key="s">
                {r.result === "MATCHED" ? <Pil kind="ok">Matched</Pil> : r.result === "DISCREPANCY" ? <Pil kind="bad">Discrepancy</Pil> : <Pil kind="grey">Not checked</Pil>}
                {r.bank_reference ? <div className="sub2 tnum">Bank {r.bank_reference}</div> : null}
                {r.note ? <div className="sub2">{r.note}</div> : null}
                {r.checked_by_name ? <div className="sub2">{r.result === "MATCHED" ? "Reconciled" : "Flagged"} by {r.checked_by_name}</div> : null}
              </span>,
              ...(canCheck ? [
                <span key="ac" style={{ display: "inline-flex", gap: 6, flexWrap: "wrap", justifyContent: "flex-end" }}>
                  <Btn kind="go" disabled={busy} onClick={() => { const b = window.prompt(`Bank reference for ${r.reference}? (optional — the credit or narration on the statement)`) ?? ""; void check(r.reference, "MATCHED", b.trim() || null, null); }}>{r.result === "MATCHED" ? "Re-confirm" : "Matched"}</Btn>
                  <Btn kind="ghost" disabled={busy} onClick={() => { const n = window.prompt(`What does not agree for ${r.reference}? The note is recorded.`); if (n && n.trim()) { const b = window.prompt("Bank reference, if any (optional)") ?? ""; void check(r.reference, "DISCREPANCY", b.trim() || null, n.trim()); } }}>Flag</Btn>
                </span>,
              ] : []),
            ])}
            texts={rows.map((r) => `${r.reference} ${r.payer ?? ""} ${r.number ?? ""} ${r.purpose ?? ""} ${r.result ?? "unchecked"}`)}
          />
        ) : <PBody><div className="sub2">No confirmed payment between {from} and {to}.</div></PBody>}
      </Panel>
      <Note kind="info" title="Reconciliation validates the ledger against the bank; it does not move money">
        A transaction the portal marks confirmed was confirmed by a gateway callback or by the Bursary against a bank record. This step is the independent check that the money actually landed in the University&rsquo;s account. A discrepancy - a settled callback with no matching credit, or an amount that differs - is flagged with a note for the Bursary to resolve. Both the audit directorate and the Bursary may reconcile.
      </Note>
    </>
  );
}
