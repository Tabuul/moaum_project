"use client";

/** bRefunds — proto/part…: refunds and credits, maker–checker controlled. The officer who
 *  raises a refund cannot approve it; the database refuses the second click. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { JupebClaims } from "./JupebClaims";
import { OldFeesOverpaid } from "../legacy-fees/OldFeesOverpaid";
import { BankAccountFields, useBanks } from "@/components/finance/BankAccountFields";
import { type BankAccountValue, EMPTY_ACCOUNT, accountDigits, accountProblem, bankToSend, valueFromAccount } from "@/lib/banks";
import { BanksPanel } from "./BanksPanel";

export interface Refund {
  id: string; reference: string; student_id: string | null; payer: string; reason: string; amount: number;
  bank_name: string | null; account_name: string | null; account_last4: string | null; state: string;
  proposed_at: string; approved_at: string | null; rejected_why: string | null; paid_at: string | null;
  number: string | null; proposed_by_name: string | null; approved_by_name: string | null; proposed_by_me: boolean;
  source_reference: string | null;
  /** V528: the account the student gave for a refund of overpaid fees (full number, for the desk that pays), and whether it is one */
  account_number?: string | null; account_given_at?: string | null; from_overpayment?: boolean;
  /** V533: where the account came from, and whether its name shares a word with the person's */
  bank_code?: string | null; account_source?: "STUDENT" | "DESK" | "JUPEB" | null; account_name_matches?: boolean | null;
  /** V534: the evidence of the payment, and how many other refunds carry the same transfer reference */
  paid_reference?: string | null; paid_on?: string | null; paid_reference_others?: number | null;
}

/** today in Lagos, as the date field holds it */
const lagosToday = () => new Date().toLocaleDateString("en-CA", { timeZone: "Africa/Lagos" });

const SOURCE_WORD: Record<string, string> = { STUDENT: "given by the student", DESK: "recorded at the desk", JUPEB: "from the JUPEB claim" };
const day = (iso: string) => new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });

/** V528, V533: where a refund is paid — the full account on record, where it came from and when; or, before V533, the last four
 *  digits recorded when it was raised */
function payInto(r: Refund): { text: string; sub: string | null } | null {
  if (r.account_number) return { text: `${r.bank_name ?? ""} · ${r.account_number}`, sub: `${r.account_name ?? ""}${r.account_source ? ` · ${SOURCE_WORD[r.account_source] ?? ""}` : ""}${r.account_given_at ? ` ${day(r.account_given_at)}` : ""}` };
  if (r.account_last4) return { text: `${r.bank_name ?? "Bank"} · ending ${r.account_last4}`, sub: `${r.account_name ?? ""} · the full number not yet recorded` };
  return null;
}

/** V533: a refund is paid only into a full account on record (the database refuses PAID without one) */
const awaitsAccount = (r: Refund) => !r.account_number;

/** V533: whether the account part of the form was begun (then it must be whole) */
const accountStarted = (v: BankAccountValue) => !!(v.bankCode || v.otherBank.trim() || v.accountName.trim() || v.accountNumber.trim());

interface Txn { kind: string; amount: number; confirmed_at: string | null; channel: string | null; receipt_no: string | null; payer: string | null; number: string | null; student_id: string | null; purpose: string | null }

const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  PROPOSED: ["warn", "Awaiting approval"], APPROVED: ["info", "Approved, to pay"], PAID: ["ok", "Paid"], REJECTED: ["grey", "Rejected"],
};

export function Refunds({ refunds, actingOffice, initialRefund }: { refunds: Refund[]; actingOffice: string | null; initialRefund?: string | null }) {
  const router = useRouter();
  const may = ["bursar", "super"].includes(actingOffice ?? "");
  const [add, setAdd] = useState(!!(initialRefund && may));
  const [f, setF] = useState({ payer: "", reason: "", amount: "" });
  // V533: the full account, checked against the bank — optional when raising, recorded later otherwise
  const banks = useBanks("/finance/refunds/banks");
  const [acct, setAcct] = useState<BankAccountValue>(EMPTY_ACCOUNT);
  const [accountFor, setAccountFor] = useState<Refund | null>(null);
  const [acct2, setAcct2] = useState<BankAccountValue | null>(null);
  // V534: a refund marked paid with the bank transfer reference and the date the money left
  const [payFor, setPayFor] = useState<Refund | null>(null);
  const [pay, setPay] = useState({ reference: "", paidOn: "" });
  const [source, setSource] = useState(initialRefund && may ? initialRefund.toUpperCase() : "");
  const [student, setStudent] = useState<string | null>(null);
  const [txn, setTxn] = useState<Txn | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  function openModal(fromReference?: string) {
    setF({ payer: "", reason: "", amount: "" });
    setAcct(EMPTY_ACCOUNT);
    setSource(fromReference ?? "");
    setStudent(null);
    setTxn(null);
    setErr(null);
    setAdd(true);
    if (fromReference) void fetchTxn(fromReference);
  }

  async function fetchTxn(ref: string) {
    const r = ref.trim();
    if (!r) return;
    setBusy(true);
    setErr(null);
    try {
      const res = await fetch(`/api/bff/api/v1/finance/refunds/transaction?reference=${encodeURIComponent(r)}`);
      const j = await res.json().catch(() => null);
      if (!res.ok) { setErr(j ?? { status: res.status, title: res.statusText }); notifyProblem(j ?? { status: res.status, title: res.statusText }); setTxn(null); return; }
      const t = j as Txn;
      setTxn(t);
      setStudent(t.student_id ?? null);
      setSource(r.toUpperCase());
      setF((prev) => ({ ...prev, payer: t.payer ?? prev.payer, amount: t.amount != null ? String(t.amount) : prev.amount, reason: prev.reason || `Refund against ${r.toUpperCase()}${t.purpose ? ` — ${t.purpose}` : ""}` }));
    } finally {
      setBusy(false);
    }
  }

  const open = refunds.filter((r) => r.state === "PROPOSED").length;
  const toPay = refunds.filter((r) => r.state === "APPROVED").length;

  // launched from a transaction on the ledger: the modal opens pre-filled (above),
  // and this fetches that transaction to fill in the payer and amount
  useEffect(() => {
    if (!initialRefund || !may) return;
    let live = true;
    (async () => {
      const res = await fetch(`/api/bff/api/v1/finance/refunds/transaction?reference=${encodeURIComponent(initialRefund)}`);
      const j = await res.json().catch(() => null);
      if (!live) return;
      if (!res.ok) { setErr(j ?? { status: res.status, title: res.statusText }); notifyProblem(j ?? { status: res.status, title: res.statusText }); return; }
      const t = j as Txn;
      setTxn(t);
      setStudent(t.student_id ?? null);
      setF((prev) => ({ ...prev, payer: t.payer ?? prev.payer, amount: t.amount != null ? String(t.amount) : prev.amount, reason: prev.reason || `Refund against ${initialRefund.toUpperCase()}${t.purpose ? ` — ${t.purpose}` : ""}` }));
    })();
    return () => { live = false; };
  }, [initialRefund, may]);

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/finance/refunds${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="Maker and checker are always different people">
        The officer who raises a refund cannot approve it. It is paid only after a second officer approves, and only into a full account on record: the one recorded at the desk, the one a student gives for overpaid school fees on their fees page, or a JUPEB candidate&rsquo;s. An account the desk records on an approved refund goes back for approval.
      </Note>

      {said ? <Note kind="ok" title={said}>It waits for a second officer to approve it before any money leaves the University.</Note> : null}
      <JupebClaims may={may} onChanged={() => router.refresh()} />
      {/* V519: overpaid school fees carried into the next session or refunded — a refund raised there joins the requests below */}
      <OldFeesOverpaid may={may} onChanged={() => router.refresh()} />
      {err ? <ProblemNotice problem={err} /> : null}

      <Tiles items={[
        ["Awaiting approval", String(open), open ? "var(--red-ink)" : null, "A second officer must agree"],
        ["Approved, to pay", String(toPay), toPay ? "var(--chrome)" : null, "Ready to disburse"],
        ["Paid", String(refunds.filter((r) => r.state === "PAID").length), "var(--green-ink)", "On the record"],
        ["All", String(refunds.length), null, "Newest 300"],
      ]} />

      <Panel title="Refund requests" right={may ? undefined : "You are reading this queue"}>
        {refunds.length ? (
          <DTable cols={["Reference", "Payer", "Reason", "Amount|num", "Pay into", "Stage", "Action|num"]} rows={refunds.map((r) => [
            <span key="r"><span className="tnum">{r.reference}</span>{r.source_reference ? <div className="sub2">against <span className="tnum">{r.source_reference}</span></div> : null}</span>,
            <Two key="p" a={r.payer} b={r.number ?? ""} />,
            <span className="sub2" key="rs">{r.reason}</span>,
            <b className="tnum" key="a">{money(Number(r.amount))}</b>,
            (() => { const p = payInto(r); return p ? <span key="pi"><Two a={<span className="tnum">{p.text}</span>} b={p.sub ?? ""} />{r.account_name_matches === false ? <div><Pil kind="warn" title="The name on the account shares no word with the person's">Name differs</Pil></div> : null}</span>
              : r.state !== "PAID" && r.state !== "REJECTED" ? <span key="pi" className="sub2">{r.from_overpayment ? "Waiting for the student\u2019s bank details" : "No account recorded"}</span>
              : <span key="pi" className="sub2">—</span>; })(),
            <span key="s"><Pil kind={STATE[r.state]?.[0] ?? "grey"}>{STATE[r.state]?.[1] ?? r.state}</Pil>{r.proposed_by_name ? <div className="sub2">Raised by {r.proposed_by_me ? "you" : r.proposed_by_name}</div> : null}{r.rejected_why ? <div className="sub2">{r.rejected_why}</div> : null}
              {r.state === "PAID" && r.paid_on ? <div className="sub2">{`On ${day(`${r.paid_on}T12:00:00`)}${r.paid_reference ? ` · ref ${r.paid_reference}` : ""}`}</div> : null}
              {r.state === "PAID" && Number(r.paid_reference_others) > 0 ? <div><Pil kind="warn" title="Another refund was recorded paid with the same bank transfer reference">Same reference on {r.paid_reference_others} other refund{Number(r.paid_reference_others) === 1 ? "" : "s"}</Pil></div> : null}</span>,
            <span key="ac" className="row row--inline row--tight">
              {may && r.state === "PROPOSED" && !r.proposed_by_me ? <Btn kind="go" disabled={busy} onClick={() => void send(`/${r.id}/approve`, {}, `Approve refund ${r.reference}`).then((j) => { if (j) setSaid(`${r.reference} approved`); })}>Approve</Btn> : null}
              {may && r.state === "PROPOSED" && r.proposed_by_me ? <Btn kind="ghost" disabled>Awaiting another approver</Btn> : null}
              {may && r.state === "PROPOSED" ? <Btn kind="ghost" disabled={busy} onClick={() => { const w = window.prompt("Why is this refund rejected? The reason is recorded."); if (w) void send(`/${r.id}/reject`, { why: w }, `Reject refund ${r.reference}`); }}>Reject</Btn> : null}
              {may && (r.state === "PROPOSED" || r.state === "APPROVED") ? <Btn kind="ghost" disabled={busy} onClick={() => { setErr(null); setAcct2(null); setAccountFor(r); }}>{r.account_number ? "Change the account" : "Record the account"}</Btn> : null}
              {may && r.state === "APPROVED" && awaitsAccount(r) ? <Btn kind="ghost" disabled>Waiting for the account</Btn> : null}
              {may && r.state === "APPROVED" && !awaitsAccount(r) ? <Btn kind="primary" disabled={busy} onClick={() => { setErr(null); setPay({ reference: "", paidOn: lagosToday() }); setPayFor(r); }}>Mark paid</Btn> : null}
              {!may || (r.state !== "PROPOSED" && r.state !== "APPROVED") ? <span className="sub2">{r.paid_at ? "Disbursed" : r.approved_by_name ? `Approved by ${r.approved_by_name}` : ""}</span> : null}
            </span>,
          ])} texts={refunds.map((r) => `${r.reference} ${r.payer} ${r.reason} ${r.account_number ?? ""}`)} />
        ) : <PBody><div className="sub2">No refund has been raised.</div></PBody>}
      </Panel>

      {may ? (
        <div><Btn kind="primary" size="md" onClick={() => openModal()}>+ Raise a refund</Btn></div>
      ) : null}

      {add ? (
        <Modal title="Raise a refund" sub="It goes to a second officer to approve" onClose={() => setAdd(false)}
          foot={<><Btn kind="ghost" onClick={() => setAdd(false)}>Cancel</Btn><span className="grow" />
            <Btn kind="primary" disabled={busy || !f.payer.trim() || !f.reason.trim() || !(Number(f.amount) > 0) || (accountStarted(acct) && accountProblem(acct, banks) !== null)} onClick={async () => { const withAccount = accountProblem(acct, banks) === null; const j = await send("", { student, payer: f.payer, reason: f.reason, amount: Number(f.amount), bank: withAccount ? bankToSend(acct) : null, accountName: withAccount ? acct.accountName.trim() : null, accountNumber: withAccount ? accountDigits(acct.accountNumber) : null, source: source.trim() || null }, `Raise refund for ${f.payer}`); if (j) { setSaid(`Refund ${j.reference} raised for ${f.payer}`); setAdd(false); } }}>Raise it</Btn></>}>
          {err ? <ProblemNotice problem={err} /> : null}
          <Field id="rf-src" label="From a payment reference" hint="Optional; fills and checks the payer and amount.">
            <div className="row">
              <input id="rf-src" className="ctl tnum" value={source} onChange={(e) => setSource(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); void fetchTxn(source); } }} placeholder="e.g. a receipt or reference" autoComplete="off" />
              <Btn kind="ghost" disabled={busy || !source.trim()} onClick={() => void fetchTxn(source)}>Fetch</Btn>
            </div>
          </Field>
          {txn ? (
            <Note kind={txn.confirmed_at ? "ok" : "bad"} title={txn.confirmed_at ? `Confirmed payment of ${money(Number(txn.amount))}` : "Not a confirmed payment"}>
              {txn.payer ?? "Payer not on record"}{txn.number ? ` · ${txn.number}` : ""}{txn.purpose ? ` · ${txn.purpose}` : ""}{txn.receipt_no ? ` · receipt ${txn.receipt_no}` : ""}. A refund cannot exceed what was paid on this transaction.
            </Note>
          ) : null}
          <Field id="rf-payer" label="Paid to" hint="The student or sponsor the money is owed to"><input id="rf-payer" className="ctl" value={f.payer} onChange={(e) => setF({ ...f, payer: e.target.value })} autoComplete="off" /></Field>
          <div className="grid grid--2">
            <Field id="rf-reason" label="Reason"><input id="rf-reason" className="ctl" value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} placeholder="Duplicate payment — timeout retry" autoComplete="off" /></Field>
            <Field id="rf-amount" label="Amount (₦)"><input id="rf-amount" className="ctl tnum" value={f.amount} inputMode="decimal" onChange={(e) => setF({ ...f, amount: e.target.value })} /></Field>
          </div>
          <Field id="rf-acct-bank" label="The account it is paid into" hint={<>Optional now: it can be recorded later, and the refund is not paid until it is. A refund of overpaid school fees takes the student&rsquo;s own.</>}>
            <BankAccountFields id="rf-acct" value={acct} onChange={setAcct} banks={banks} holderName={f.payer} />
          </Field>
        </Modal>
      ) : null}

      {accountFor ? (() => {
        const v = acct2 ?? valueFromAccount(accountFor.bank_name, accountFor.account_name, banks);
        const backForApproval = accountFor.state === "APPROVED";
        return (
          <Modal title={accountFor.account_number ? "Change the account" : "Record the account"} sub={`${accountFor.reference} · ${accountFor.payer} · ${money(Number(accountFor.amount))}`} onClose={() => setAccountFor(null)}
            foot={<><Btn kind="ghost" onClick={() => setAccountFor(null)}>Cancel</Btn><span className="grow" />
              <Btn kind="primary" disabled={busy || accountProblem(v, banks) !== null} onClick={async () => {
                const j = await send(`/${accountFor.id}/account`, { bank: bankToSend(v), accountName: v.accountName.trim(), accountNumber: accountDigits(v.accountNumber) }, `Account of refund ${accountFor.reference} recorded at the desk`);
                if (j) { setSaid(j.state === "PROPOSED" && backForApproval ? `${accountFor.reference} goes back for approval with the new account` : `Account of ${accountFor.reference} recorded`); setAccountFor(null); }
              }}>Save the account</Btn></>}>
            {err ? <ProblemNotice problem={err} /> : null}
            {backForApproval ? <Note kind="info" title="This refund is already approved">The account you record goes back for approval by another officer, unless it only completes the account that was approved (the same bank and last four digits{accountFor.account_last4 ? `, ending ${accountFor.account_last4}` : ""}).</Note> : null}
            {accountFor.account_source === "STUDENT" ? <Note kind="info" title="The student gave this account">Change it only on the student&rsquo;s word; the change is on the record with your name.</Note> : null}
            <BankAccountFields id="rf-acct2" value={v} onChange={setAcct2} banks={banks} holderName={accountFor.payer} />
          </Modal>
        );
      })() : null}

      {payFor ? (() => {
        const today = lagosToday();
        const approvedOn = payFor.approved_at ? new Date(payFor.approved_at).toLocaleDateString("en-CA", { timeZone: "Africa/Lagos" }) : undefined;
        const ref = pay.reference.trim();
        const refOk = ref.length >= 4 && ref.length <= 60 && /^[A-Za-z0-9][A-Za-z0-9/._: -]*$/.test(ref);
        const dateOk = /^\d{4}-\d{2}-\d{2}$/.test(pay.paidOn) && pay.paidOn <= today && (!approvedOn || pay.paidOn >= approvedOn);
        return (
          <Modal title="Record the payment" sub={`${payFor.reference} · ${payFor.payer} · ${money(Number(payFor.amount))}`} onClose={() => setPayFor(null)}
            foot={<><Btn kind="ghost" onClick={() => setPayFor(null)}>Cancel</Btn><span className="grow" />
              <Btn kind="primary" disabled={busy || !refOk || !dateOk} onClick={async () => {
                const j = await send(`/${payFor.id}/pay`, { reference: ref, paidOn: pay.paidOn }, `Refund ${payFor.reference} paid, transfer reference ${ref}`);
                if (j) { setSaid(`${payFor.reference} recorded paid`); setPayFor(null); }
              }}>Record it paid</Btn></>}>
            {err ? <ProblemNotice problem={err} /> : null}
            <Note kind="info" title="Record this once the money has left">
              Paid into {payFor.bank_name ?? "the bank"} · {payFor.account_number ?? `ending ${payFor.account_last4 ?? ""}`} · {payFor.account_name ?? ""}. The transfer reference is on the bank&rsquo;s confirmation; Internal Audit matches it to the bank statement{payFor.from_overpayment ? ", and the student is told it" : ""}.
            </Note>
            <div className="grid grid--2">
              <Field id="rf-paid-ref" label="Bank transfer reference" required error={ref && !refOk ? "4 to 60 letters and digits, as on the bank's confirmation" : undefined}>
                <input id="rf-paid-ref" className="ctl tnum" maxLength={60} value={pay.reference} onChange={(e) => setPay({ ...pay, reference: e.target.value })} autoComplete="off" />
              </Field>
              <Field id="rf-paid-on" label="Date the money left" required error={pay.paidOn && !dateOk ? `From the approval${approvedOn ? ` (${day(`${approvedOn}T12:00:00`)})` : ""} to today` : undefined}>
                <input id="rf-paid-on" type="date" className="ctl" min={approvedOn} max={today} value={pay.paidOn} onChange={(e) => setPay({ ...pay, paidOn: e.target.value })} />
              </Field>
            </div>
          </Modal>
        );
      })() : null}

      {/* V533: the banks refunds are paid into, and whether a number at each is checked */}
      <BanksPanel may={may} onChanged={() => router.refresh()} />
    </>
  );
}
