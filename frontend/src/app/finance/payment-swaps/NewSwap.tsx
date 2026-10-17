"use client";

/**
 * A new school fees payment swap (V527), in four steps: the payment (found by its reference, receipt, old-portal number, or the
 * credited student's number or name — only a verified school-fees payment may be chosen), the student it belongs to (found by
 * matriculation, JAMB, admission or application number, or name), both accounts side by side as the server reads them, then the
 * reason, the evidence and the officer's confirmation. Sent, it waits for a Bursar officer other than the one who sent it.
 */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { Field, Modal, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notifyProblem } from "@/components/proto/Toast";
import { formatDocDateTime } from "@/lib/document/institution";
import { clearsWord, evidenceRefusal, reasonOk, refusalParts, studentLine, type FoundPayment, type FoundStudent, type SwapAccount, type SwapCheck, type SwapDetail, type SwapProfile } from "@/lib/payment-swaps";
import { fileAsDataUrl, swapGet, swapPost } from "./swap-call";

function Account({ title, profile, account, after }: { title: string; profile?: SwapProfile; account?: SwapAccount; after?: number | null }) {
  if (!profile || !account) return null;
  return (
    <div className="card" style={{ padding: 12, minWidth: 0 }}>
      <div className="eyebrow">{title}</div>
      <b>{profile.name}</b>
      <div className="sub2 tnum">{profile.matric_no ?? profile.admission_no ?? "No matriculation number"}{profile.jamb_reg_no ? ` · JAMB ${profile.jamb_reg_no}` : ""}</div>
      <div className="sub2">{[profile.programme, profile.department, profile.faculty].filter(Boolean).join(" · ")}</div>
      <div className="sub2">{profile.current_level ? `${profile.current_level} level · ` : ""}{profile.status ?? ""}{profile.merged ? " · merged record" : ""}</div>
      <table className="tbl tbl--data" style={{ marginTop: 8 }}>
        <tbody>
          <tr><td>School fees due</td><td className="num tnum">{money(Number(account.due))}</td></tr>
          <tr><td>Paid</td><td className="num tnum">{money(Number(account.paid))}</td></tr>
          <tr><td>Balance</td><td className="num tnum"><b>{money(Number(account.balance))}</b></td></tr>
          {after != null ? <tr><td>Paid after the swap</td><td className="num tnum"><b>{money(after)}</b></td></tr> : null}
          <tr><td>Clears registration</td><td className="num"><Pil kind={account.clearsRegistration ? "ok" : account.clearsRegistration == null ? "grey" : "warn"}>{clearsWord(account.clearsRegistration)}</Pil></td></tr>
          <tr><td>Clears examination</td><td className="num"><Pil kind={account.clearsExamination ? "ok" : account.clearsExamination == null ? "grey" : "warn"}>{clearsWord(account.clearsExamination)}</Pil></td></tr>
        </tbody>
      </table>
    </div>
  );
}

export function SwapAccounts({ check }: { check: SwapCheck }) {
  const amount = Number(check.payment?.amount ?? 0);
  return (
    <div className="grid grid--2">
      <Account title="Credited to (wrong student)" profile={check.fromProfile} account={check.fromAccount} after={check.fromAccount ? Number(check.fromAccount.paid) - amount : null} />
      <Account title="Belongs to (correct student)" profile={check.toProfile} account={check.toAccount} after={check.toAccount ? Number(check.toAccount.paid) + amount : null} />
    </div>
  );
}

export function NewSwap({ onClose, onDone }: { onClose: () => void; onDone: (d: SwapDetail) => void }) {
  const [pq, setPq] = useState("");
  const [payments, setPayments] = useState<FoundPayment[] | null>(null);
  const [payment, setPayment] = useState<FoundPayment | null>(null);
  const [sq, setSq] = useState("");
  const [students, setStudents] = useState<FoundStudent[] | null>(null);
  const [check, setCheck] = useState<SwapCheck | null>(null);
  const [reason, setReason] = useState("");
  const [evidence, setEvidence] = useState("");
  const [files, setFiles] = useState<File[]>([]);
  const [confirmed, setConfirmed] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [stage, setStage] = useState<"" | "payments" | "students" | "check" | "submit">("");

  async function findPayments() {
    setStage("payments"); setErr(null); setPayment(null); setCheck(null); setStudents(null);
    const r = await swapGet<FoundPayment[]>(`/payments?q=${encodeURIComponent(pq.trim())}`);
    setStage("");
    if (!r.ok) { setErr(r.problem); return; }
    setPayments(r.data);
  }

  async function findStudents() {
    setStage("students"); setErr(null); setCheck(null);
    const r = await swapGet<FoundStudent[]>(`/students?q=${encodeURIComponent(sq.trim())}`);
    setStage("");
    if (!r.ok) { setErr(r.problem); return; }
    setStudents(r.data);
  }

  async function prepare(to: FoundStudent) {
    if (!payment) return;
    setStage("check"); setErr(null);
    const r = await swapGet<SwapCheck>(`/check?payment=${payment.id}&to=${to.id}`);
    setStage("");
    if (!r.ok) { setErr(r.problem); return; }
    setCheck(r.data);
    setConfirmed(false);
  }

  const fileProblem = files.map((f) => evidenceRefusal(f)).find(Boolean) ?? null;

  async function submit() {
    if (!payment || !check?.to) return;
    setStage("submit"); setErr(null);
    try {
      const made = await swapPost<SwapDetail>("", { payment: payment.id, to: check.to.id, reason: reason.trim(), evidence: evidence.trim() || null, confirmed },
        `Payment swap of ${payment.reference} initiated: ${reason.trim()}`);
      if (!made.ok) { setErr(made.problem); notifyProblem(made.problem); return; }
      let last = made.data;
      for (const f of files) {
        const up = await swapPost<SwapDetail>(`/${made.data.swap.id}/evidence`, { filename: f.name, dataUrl: await fileAsDataUrl(f) }, `Evidence for ${made.data.swap.swap_ref}`);
        if (!up.ok) { notifyProblem(up.problem, `${f.name} was not attached`); continue; }
        last = up.data;
      }
      onDone(last);
    } finally {
      setStage("");
    }
  }

  const ready = !!check?.ok && reasonOk(reason) && confirmed && !fileProblem;

  return (
    <Modal wide title="New school fees payment swap" sub="The whole payment moves to the student it belongs to, once a Bursar officer other than you approves it" onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" />
        <Btn kind="primary" size="md" disabled={!ready} busy={stage === "submit"} busyLabel="Submitting for Review..." onClick={submit}>Submit for review</Btn></>}>
      {err ? <ProblemNotice problem={err} /> : null}

      <Field id="sw-pq" label="1. The payment" hint="A payment reference, receipt or old-portal number, or the credited student's matriculation or JAMB number or name">
        <div className="row">
          <input id="sw-pq" className="ctl" value={pq} autoComplete="off" onChange={(e) => setPq(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter" && pq.trim().length >= 3) { e.preventDefault(); void findPayments(); } }} placeholder="e.g. MOAU/AD/BUS/25/12939" />
          <Btn kind="ghost" disabled={pq.trim().length < 3} busy={stage === "payments"} busyLabel="Searching..." onClick={findPayments}>Search</Btn>
        </div>
      </Field>
      {payments && !payment ? (
        payments.length ? (
          <table className="tbl tbl--data">
            <thead><tr><th>Reference</th><th>Credited to</th><th className="num">Amount</th><th>Session</th><th>Confirmed</th><th /></tr></thead>
            <tbody>
              {payments.map((p) => (
                <tr key={p.id}>
                  <td className="tnum">{p.reference}{p.receipt_no ? <div className="sub2">receipt {p.receipt_no}</div> : null}<div className="sub2">{p.purpose}{p.channel ? ` · ${p.channel}` : ""}</div></td>
                  <td>{studentLine(p)}</td>
                  <td className="num tnum">{money(Number(p.amount))}</td>
                  <td>{p.session}</td>
                  <td className="sub2">{p.confirmed_at ? formatDocDateTime(p.confirmed_at) : "Not confirmed"}</td>
                  <td className="num">
                    {p.eligible ? <Btn kind="secondary" onClick={() => { setPayment(p); setStudents(null); setCheck(null); }}>Choose</Btn>
                      : <span className="sub2" title={p.refusals.map((x) => refusalParts(x).words).join(" ")}>{refusalParts(p.refusals[0] ?? "").words}</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : <Note kind="info" title="No school-fees payment matches">Search by the payment reference, the receipt, or the credited student&apos;s number.</Note>
      ) : null}
      {payment ? (
        <Note kind="ok" title={`${payment.reference} · ${money(Number(payment.amount))} · ${payment.session}`}
          action={<Btn kind="ghost" onClick={() => { setPayment(null); setCheck(null); setStudents(null); }}>Change</Btn>}>
          {payment.purpose}, credited to {studentLine(payment)}{payment.confirmed_at ? `, confirmed ${formatDocDateTime(payment.confirmed_at)}` : ""}. The whole payment is swapped, never part of it.
        </Note>
      ) : null}

      {payment ? (
        <Field id="sw-sq" label="2. The student it belongs to" hint="Matriculation, JAMB, admission or application number, or name — chosen from the register, never typed in">
          <div className="row">
            <input id="sw-sq" className="ctl" value={sq} autoComplete="off" onChange={(e) => setSq(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter" && sq.trim().length >= 3) { e.preventDefault(); void findStudents(); } }} placeholder="e.g. MOAU/SC/MCB/24/75807" />
            <Btn kind="ghost" disabled={sq.trim().length < 3} busy={stage === "students"} busyLabel="Searching..." onClick={findStudents}>Search</Btn>
          </div>
        </Field>
      ) : null}
      {payment && students && !check ? (
        students.length ? (
          <table className="tbl tbl--data">
            <thead><tr><th>Student</th><th>Programme</th><th>Level</th><th>Status</th><th /></tr></thead>
            <tbody>
              {students.map((s) => (
                <tr key={s.id}>
                  <td>{studentLine(s)}{s.jamb_reg_no ? <div className="sub2 tnum">JAMB {s.jamb_reg_no}</div> : null}</td>
                  <td className="sub2">{s.programme ?? ""}</td>
                  <td className="tnum">{s.current_level ?? ""}</td>
                  <td className="sub2">{s.status ?? ""}{s.merged ? " · merged record" : ""}</td>
                  <td className="num">
                    {s.id === payment.student_id ? <span className="sub2">Already credited</span>
                      : <Btn kind="secondary" busy={stage === "check"} busyLabel="Preparing Swap..." onClick={() => prepare(s)}>Choose</Btn>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : <Note kind="info" title="No student matches">Search by the student&apos;s own matriculation or JAMB number.</Note>
      ) : null}

      {check ? (
        <>
          <div className="row row--inline" style={{ marginTop: 8 }}>
            <b>3. Both accounts for {check.payment?.session}</b><span className="grow" />
            <Btn kind="ghost" onClick={() => { setCheck(null); }}>Choose another student</Btn>
          </div>
          {check.ok ? null : (
            <Note kind="bad" title="This payment cannot be swapped to this student">
              {check.refusals.map((r) => <div key={r}>{refusalParts(r).words}</div>)}
            </Note>
          )}
          <SwapAccounts check={check} />
          {check.ok && check.toAccount && check.payment && Number(check.toAccount.paid) + Number(check.payment.amount) > Number(check.toAccount.due) ? (
            <Note kind="info" title="The student it belongs to will have paid more than this session's fees">
              After the swap {studentLine(check.toProfile)} will have paid {money(Number(check.toAccount.paid) + Number(check.payment.amount) - Number(check.toAccount.due))} more
              than is due for {check.payment.session}. The swap is still the whole payment; the excess is an overpayment for the Bursary to carry forward or refund.
            </Note>
          ) : null}
          {check.ok ? (
            <>
              <Field id="sw-reason" label="4. Reason" required hint="Why the payment belongs to the other student — twenty characters or more; “wrong” or “fix” is not a reason">
                <textarea id="sw-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)}
                  placeholder="e.g. The parent paid on the wrong matriculation number; the teller and the student's admission letter confirm it is MOAU/SC/MCB/24/75807's" />
              </Field>
              <Field id="sw-evidence" label="Evidence" hint="What shows whose payment it is: a teller, a bank statement line, a parent's letter, the receipt numbers">
                <input id="sw-evidence" className="ctl" value={evidence} autoComplete="off" onChange={(e) => setEvidence(e.target.value)} />
              </Field>
              <Field id="sw-files" label="Attach files" hint="Optional: PDF, JPEG or PNG, up to 5 MB each" error={fileProblem ?? undefined}>
                <input id="sw-files" type="file" multiple accept="application/pdf,image/jpeg,image/png" onChange={(e) => setFiles(Array.from(e.target.files ?? []))} />
              </Field>
              <label className="row row--inline" style={{ gap: 8, alignItems: "flex-start" }}>
                <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} />
                <span>I have verified that this payment belongs to the target student, {studentLine(check.toProfile)}.</span>
              </label>
            </>
          ) : null}
        </>
      ) : null}
    </Modal>
  );
}
