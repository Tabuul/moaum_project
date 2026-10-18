"use client";

/** V533: the banks refunds are paid into (finance.bank) — the Bursary switches the account-number check on or off for a bank, sets
 *  a bank aside, renames one or adds one; the others read it. The check (the CBN's NUBAN check digit) is for a commercial,
 *  non-interest or merchant bank with a three-digit code only. */
import { useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";

interface BankRow { code: string; name: string; aliases: string; kind: string; nuban_check: boolean; active: boolean; /** V545: the accounts paid into, how many pass the check digit */ paid_accounts?: number | null; passing?: number | null }

/** V545: the evidence for a bank's check — the accounts refunds and withdrawals were paid into, and how many pass its check digit */
const evidence = (b: BankRow) => {
  const n = Number(b.paid_accounts ?? 0);
  if (!n) return "No account paid yet";
  if (b.passing == null) return `${n} paid`;
  return Number(b.passing) === n ? `${n} paid · all pass` : `${n} paid · ${n - Number(b.passing)} fail`;
};

const KIND: Record<string, string> = { COMMERCIAL: "Commercial", NON_INTEREST: "Non-interest", MERCHANT: "Merchant", MICROFINANCE: "Microfinance", PAYMENT_SERVICE: "Payment service" };

export function BanksPanel({ may, onChanged }: { may: boolean; onChanged: () => void }) {
  const [open, setOpen] = useState(false);
  const [rows, setRows] = useState<BankRow[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [nb, setNb] = useState({ code: "", name: "", kind: "COMMERCIAL", aliases: "", check: false });

  useEffect(() => {
    if (!open || rows) return;
    let live = true;
    fetch("/api/bff/api/v1/finance/refunds/banks", { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : []))
      .then((j: BankRow[]) => { if (live) setRows(j); })
      .catch(() => { if (live) setRows([]); });
    return () => { live = false; };
  }, [open, rows]);

  async function save(body: Record<string, unknown>, said: string) {
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/finance/refunds/banks", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(said) }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return false; }
      setRows(j as BankRow[]);
      notify(said);
      onChanged();
      return true;
    } finally {
      setBusy(false);
    }
  }

  // the NUBAN check digit is the banks' own: a commercial, non-interest or merchant bank with a three-digit code
  const checkable = (code: string, kind: string) => /^\d{3}$/.test(code) && ["COMMERCIAL", "NON_INTEREST", "MERCHANT"].includes(kind);
  return (
    <Panel title="Banks refunds are paid into" right={<Btn kind="ghost" size="sm" onClick={() => setOpen(!open)}>{open ? "Hide" : "Show the banks"}</Btn>}>
      {!open ? (
        <PBody><div className="sub2">An account number is checked against its bank as it is given (the Central Bank&rsquo;s check digit) wherever the bank is checked; a payment service bank, whose numbers are often phone numbers, is not.</div></PBody>
      ) : rows === null ? <PBody><div className="sub2">Looking…</div></PBody> : (
        <>
          <DTable pageSize={0} cols={["Bank", "Code|mid", "Kind", "Accounts paid into", "Number checked|mid", "Listed|mid"]} rows={rows.map((b) => [
            <span key="n"><b>{b.name}</b>{b.aliases ? <div className="sub2">also {b.aliases}</div> : null}</span>,
            <span key="c" className="tnum">{b.code}</span>,
            <span key="k" className="sub2">{KIND[b.kind] ?? b.kind}</span>,
            <span key="ev" className={`sub2${b.passing != null && Number(b.passing) < Number(b.paid_accounts ?? 0) ? " ink-red" : ""}`}>{evidence(b)}</span>,
            may && checkable(b.code, b.kind)
              ? <input key="chk" type="checkbox" className="chk" aria-label={`Check account numbers at ${b.name}`} checked={b.nuban_check} disabled={busy}
                  onChange={(e) => void save({ code: b.code, name: b.name, nubanCheck: e.target.checked }, `${b.name}: account numbers ${e.target.checked ? "checked" : "not checked"}`)} />
              : <Pil key="chk" kind={b.nuban_check ? "ok" : "grey"}>{b.nuban_check ? "Checked" : "Not checked"}</Pil>,
            may
              ? <input key="act" type="checkbox" className="chk" aria-label={`${b.name} on the list`} checked={b.active} disabled={busy}
                  onChange={(e) => void save({ code: b.code, name: b.name, active: e.target.checked }, `${b.name} ${e.target.checked ? "listed" : "set aside"}`)} />
              : <Pil key="act" kind={b.active ? "ok" : "grey"}>{b.active ? "Listed" : "Set aside"}</Pil>,
          ])} texts={rows.map((b) => `${b.name} ${b.code} ${b.aliases}`)} />
          {may ? (
            <PBody>
              <div className="row" style={{ flexWrap: "wrap", gap: 8, alignItems: "flex-end" }}>
                <Field id="bk-code" label="Code" style={{ width: 110 }}><input id="bk-code" className="ctl tnum" value={nb.code} maxLength={8} onChange={(e) => setNb({ ...nb, code: e.target.value.toUpperCase().replace(/[^0-9A-Z]/g, "") })} autoComplete="off" /></Field>
                <Field id="bk-name" label="Bank" style={{ width: 220 }}><input id="bk-name" className="ctl" value={nb.name} onChange={(e) => setNb({ ...nb, name: e.target.value })} autoComplete="off" /></Field>
                <Field id="bk-kind" label="Kind" style={{ width: 170 }}>
                  <select id="bk-kind" className="ctl" value={nb.kind} onChange={(e) => setNb({ ...nb, kind: e.target.value })}>
                    {Object.entries(KIND).map(([k, w]) => <option key={k} value={k}>{w}</option>)}
                  </select>
                </Field>
                <Field id="bk-aliases" label="Other names" hint="Comma-separated" style={{ width: 220 }}><input id="bk-aliases" className="ctl" value={nb.aliases} onChange={(e) => setNb({ ...nb, aliases: e.target.value })} autoComplete="off" /></Field>
                <label className="row row--inline row--tight" style={{ paddingBottom: 8 }}><input type="checkbox" className="chk" checked={nb.check && checkable(nb.code, nb.kind)} disabled={!checkable(nb.code, nb.kind)} onChange={(e) => setNb({ ...nb, check: e.target.checked })} /> Check its numbers</label>
                <Btn kind="primary" size="sm" disabled={busy || nb.code.length < 3 || !nb.name.trim()} onClick={async () => {
                  const ok = await save({ code: nb.code, name: nb.name.trim(), kind: nb.kind, aliases: nb.aliases.split(",").map((x) => x.trim()).filter(Boolean), nubanCheck: nb.check && checkable(nb.code, nb.kind), active: true }, `${nb.name.trim()} added to the banks`);
                  if (ok) setNb({ code: "", name: "", kind: "COMMERCIAL", aliases: "", check: false });
                }}>Add the bank</Btn>
              </div>
            </PBody>
          ) : null}
        </>
      )}
    </Panel>
  );
}
