"use client";

/**
 * A new payment correction (V649), or one returned for correction changed and sent again. Four steps:
 *   1. the payment — found on the server by its reference, receipt or old-portal number, or the student's matriculation, JAMB,
 *      admission or application number or name, narrowed by session and status; only a verified payment that may be corrected is
 *      chosen;
 *   2. where it belongs — the purpose (the University's catalogue: the ones the finance engine keeps an account of may be chosen,
 *      the others say how they are paid), the session (the calendar's, each with the student's own level in it and whether school
 *      fees are stated), the semester of that session; the faculty, department and programme are the student's, never typed;
 *   3. the financial calculation, the server's: the destination's fee, what is already paid towards it, the amount reallocated and
 *      the balance to pay or the surplus, and the obligation the payment leaves;
 *   4. what was wrong, the reason, the evidence, then the preview with the confirmation, and SUBMIT FOR APPROVAL.
 */
import { useMemo, useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { Field, Modal, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notifyProblem } from "@/components/proto/Toast";
import { formatDocDateTime } from "@/lib/document/institution";
import {
  OUTCOME_WORDS, REASON_CODES, REASON_WORDS, evidenceRefusal, periodSemesters, periodWords, reasonOk, refusalParts,
  type Destination, type FoundPayment, type Period, type ReallocCheck, type ReallocDetail, type ReasonCode,
} from "@/lib/payment-reallocations";
import { fileAsDataUrl, reallocGet, reallocPost } from "./realloc-call";

/** the calculation as the server made it: the obligation met, and the one left */
export function Calculation({ check }: { check: ReallocCheck }) {
  const d = check.destination;
  const s = check.source;
  if (!d) return null;
  const [kind, word] = d.outcome ? OUTCOME_WORDS[d.outcome] : ["grey" as const, "No account kept"];
  return (
    <div className="grid grid--2">
      <div className="card" style={{ padding: 12, minWidth: 0 }}>
        <div className="eyebrow">The obligation it meets</div>
        <b>{d.label ?? d.code}</b> <Pil kind={kind}>{word}</Pil>
        <div className="sub2">{d.purpose} · {periodWords(d.session, d.semester, d.level)}</div>
        <table className="tbl tbl--data" style={{ marginTop: 8 }}>
          <tbody>
            <tr><td>Destination fee</td><td className="num tnum">{d.fee == null ? "—" : money(Number(d.fee))}</td></tr>
            <tr><td>Already paid towards it</td><td className="num tnum">{d.paidBefore == null ? "—" : money(Number(d.paidBefore))}</td></tr>
            <tr><td>Amount reallocated</td><td className="num tnum">{money(Number(d.applied))}</td></tr>
            <tr><td>Total paid after</td><td className="num tnum">{d.paidAfter == null ? "—" : money(Number(d.paidAfter))}</td></tr>
            {d.surplus != null && Number(d.surplus) > 0
              ? <tr><td><b>Surplus</b></td><td className="num tnum"><b>{money(Number(d.surplus))}</b></td></tr>
              : <tr><td><b>Balance to pay</b></td><td className="num tnum"><b>{d.balance == null ? "—" : money(Number(d.balance))}</b></td></tr>}
          </tbody>
        </table>
      </div>
      {s ? (
        <div className="card" style={{ padding: 12, minWidth: 0 }}>
          <div className="eyebrow">The obligation it leaves</div>
          <b>{s.label ?? s.code}</b>
          <div className="sub2">{s.purpose} · {periodWords(s.session, s.semester, s.level)}</div>
          {s.account ? (
            <table className="tbl tbl--data" style={{ marginTop: 8 }}>
              <tbody>
                <tr><td>Fee</td><td className="num tnum">{money(Number(s.account.fee))}</td></tr>
                <tr><td>Paid now</td><td className="num tnum">{money(Number(s.account.paid))}</td></tr>
                <tr><td>Paid after</td><td className="num tnum"><b>{s.paidAfter == null ? "—" : money(Number(s.paidAfter))}</b></td></tr>
              </tbody>
            </table>
          ) : <div className="sub2" style={{ marginTop: 8 }}>The finance engine keeps no account of this purpose; nothing is owed on it.</div>}
        </div>
      ) : null}
    </div>
  );
}

export function NewReallocation({ destinations, onClose, onDone, returned, returnedBase, returnedPeriods }: {
  destinations: Destination[]; onClose: () => void; onDone: (d: ReallocDetail) => void;
  /** a correction returned for correction: its payment and what it asked, to change and send again, with the payment and its
   *  sessions as the server reads them now */
  returned?: ReallocDetail; returnedBase?: ReallocCheck; returnedPeriods?: Period[];
}) {
  const r0 = returned?.reallocation;
  const [pq, setPq] = useState("");
  const [pses, setPses] = useState("");
  const [payments, setPayments] = useState<FoundPayment[] | null>(null);
  const [payment, setPayment] = useState<{ id: string; reference: string } | null>(r0 ? { id: r0.payment_id, reference: r0.reference } : null);
  const [base, setBase] = useState<ReallocCheck | null>(returnedBase ?? null);
  const [periods, setPeriods] = useState<Period[]>(returnedPeriods ?? []);
  const [mode, setMode] = useState<"PURPOSE" | "PERIOD">("PURPOSE");
  const [purpose, setPurpose] = useState(r0?.to_purpose_code ?? "SCHOOL_FEES");
  const [session, setSession] = useState(r0?.to_session ?? "");
  const [semester, setSemester] = useState<string>(r0?.to_semester ? String(r0.to_semester) : "");
  const [check, setCheck] = useState<ReallocCheck | null>(null);
  const [reasonCode, setReasonCode] = useState<ReasonCode | "">(r0?.reason_code ?? "");
  const [reason, setReason] = useState(r0?.reason ?? "");
  const [evidence, setEvidence] = useState("");
  const [files, setFiles] = useState<File[]>([]);
  const [previewing, setPreviewing] = useState(false);
  const [confirmed, setConfirmed] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [stage, setStage] = useState<"" | "search" | "load" | "calc" | "submit">("");

  async function findPayments() {
    setStage("search"); setErr(null); setPayment(null); setBase(null); setCheck(null);
    const qs = new URLSearchParams({ q: pq.trim() });
    if (/^\d{4}\/\d{4}$/.test(pses.trim())) qs.set("session", pses.trim());
    const r = await reallocGet<FoundPayment[]>(`/payments?${qs.toString()}`);
    setStage("");
    if (!r.ok) { setErr(r.problem); return; }
    setPayments(r.data);
  }

  // the chosen payment as the server reads it, and the sessions it may move to
  async function choose(p: FoundPayment) {
    setPayment({ id: p.id, reference: p.reference }); setCheck(null); setErr(null); setStage("load");
    const [b, ps] = await Promise.all([reallocGet<ReallocCheck>(`/check?payment=${p.id}`), reallocGet<Period[]>(`/periods?payment=${p.id}`)]);
    setStage("");
    if (!b.ok) { setErr(b.problem); return; }
    setBase(b.data);
    setPeriods(ps.ok ? ps.data : []);
    setSession(b.data.payment?.session ?? "");
  }

  // a period correction keeps the payment's own purpose
  function pick(m: "PURPOSE" | "PERIOD") {
    setMode(m);
    setCheck(null);
    if (m === "PERIOD" && base?.source?.code) setPurpose(base.source.code);
  }

  const period = periods.find((p) => p.session === session);
  const semesters = periodSemesters(period);
  const chosen = destinations.find((d) => d.code === purpose);

  async function calculate() {
    if (!payment || !session || !purpose) return;
    setStage("calc"); setErr(null); setPreviewing(false); setConfirmed(false);
    const qs = new URLSearchParams({ payment: payment.id, purpose, session });
    if (purpose === "SCHOOL_FEES" && semester) qs.set("semester", semester);
    const r = await reallocGet<ReallocCheck>(`/check?${qs.toString()}`);
    setStage("");
    if (!r.ok) { setErr(r.problem); return; }
    setCheck(r.data);
  }

  const fileProblem = files.map((f) => evidenceRefusal(f)).find(Boolean) ?? null;
  const ready = !!check?.ok && !!reasonCode && reasonOk(reason) && !fileProblem;
  const stale = useMemo(() => !!check && (check.destination?.code !== purpose || check.destination?.session !== session
    || (purpose === "SCHOOL_FEES" && String(check.destination?.semester ?? "") !== semester)), [check, purpose, session, semester]);

  async function submit() {
    if (!payment || !check?.ok) return;
    setStage("submit"); setErr(null);
    try {
      const body = { purpose, session, semester: purpose === "SCHOOL_FEES" && semester ? Number(semester) : null, reasonCode, reason: reason.trim(),
        evidence: evidence.trim() || null, confirmed };
      const made = r0
        ? await reallocPost<ReallocDetail>(`/${r0.id}/resubmit`, body, `Payment correction ${r0.realloc_ref} changed and sent again: ${reason.trim()}`)
        : await reallocPost<ReallocDetail>("", { payment: payment.id, ...body }, `Payment correction of ${payment.reference} initiated: ${reason.trim()}`);
      if (!made.ok) { setErr(made.problem); notifyProblem(made.problem); return; }
      let last = made.data;
      for (const f of files) {
        const up = await reallocPost<ReallocDetail>(`/${made.data.reallocation.id}/evidence`, { filename: f.name, dataUrl: await fileAsDataUrl(f) }, `Evidence for ${made.data.reallocation.realloc_ref}`);
        if (!up.ok) { notifyProblem(up.problem, `${f.name} was not attached`); continue; }
        last = up.data;
      }
      onDone(last);
    } finally {
      setStage("");
    }
  }

  const pay = base?.payment;
  const st = base?.student;
  const src = base?.source;

  return (
    <Modal wide title={r0 ? `Change and send again — ${r0.realloc_ref}` : "Payment reallocation & correction"}
      sub="The whole payment moves to the obligation it was meant for, once a Bursar officer other than you approves it" onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" />
        {!previewing
          ? <Btn kind="secondary" size="md" disabled={!ready || stale} onClick={() => { setPreviewing(true); setConfirmed(false); }}>Preview correction</Btn>
          : <Btn kind="primary" size="md" disabled={!ready || stale || !confirmed} busy={stage === "submit"} busyLabel="Submitting..." onClick={submit}>Submit for approval</Btn>}</>}>
      {err ? <ProblemNotice problem={err} /> : null}
      {r0?.returned_note ? <Note kind="info" title={`Returned by ${r0.returned_name ?? "the Bursar"}`}>{r0.returned_note}</Note> : null}

      {!r0 ? (
        <Field id="ra-pq" label="1. The payment" hint="A payment reference, receipt or old-portal number, or the student's matriculation, JAMB, admission or application number or name">
          <div className="row" style={{ flexWrap: "wrap" }}>
            <input id="ra-pq" className="ctl" value={pq} autoComplete="off" onChange={(e) => setPq(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter" && pq.trim().length >= 3) { e.preventDefault(); void findPayments(); } }} placeholder="e.g. MOAU/AD/ACC/26/10001" />
            <input aria-label="Session (optional)" className="ctl tnum" style={{ maxWidth: 130 }} value={pses} autoComplete="off" onChange={(e) => setPses(e.target.value)} placeholder="Session" />
            <Btn kind="ghost" disabled={pq.trim().length < 3} busy={stage === "search"} busyLabel="Searching..." onClick={findPayments}>Search</Btn>
          </div>
        </Field>
      ) : null}
      {payments && !payment ? (
        payments.length ? (
          <table className="tbl tbl--data">
            <thead><tr><th>Reference</th><th>Student</th><th className="num">Amount</th><th>Purpose · session</th><th>Confirmed</th><th /></tr></thead>
            <tbody>
              {payments.map((p) => (
                <tr key={p.id}>
                  <td className="tnum">{p.reference}{p.receipt_no ? <div className="sub2">receipt {p.receipt_no}</div> : null}</td>
                  <td>{p.matric_no ?? p.admission_no ?? ""}<div className="sub2">{p.name}</div></td>
                  <td className="num tnum">{money(Number(p.amount))}</td>
                  <td>{p.purpose}<div className="sub2">{p.session}{p.channel ? ` · ${p.channel}` : ""}</div></td>
                  <td className="sub2">{p.confirmed_at ? formatDocDateTime(p.confirmed_at) : "Not confirmed"}</td>
                  <td className="num">
                    {p.eligible ? <Btn kind="secondary" busyLabel="Loading..." onClick={() => choose(p)}>Choose</Btn>
                      : <span className="sub2" title={p.refusals.map((x) => refusalParts(x).words).join(" ")}>{refusalParts(p.refusals[0] ?? "").words}</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : <Note kind="info" title="No payment matches">Search by the payment reference, the receipt, or the student&apos;s number.</Note>
      ) : null}

      {payment && stage === "load" ? <div className="sub2">Loading the payment...</div> : null}
      {pay && st && src ? (
        <>
          <div className="row row--inline" style={{ marginTop: 8 }}>
            <b>Original payment</b><span className="grow" />
            {!r0 ? <Btn kind="ghost" onClick={() => { setPayment(null); setBase(null); setCheck(null); }}>Choose another payment</Btn> : null}
          </div>
          <table className="tbl tbl--data">
            <tbody>
              <tr><td>Student</td><td>{st.name} · <span className="tnum">{st.matricNo ?? st.admissionNo ?? ""}</span>{st.jambRegNo ? <span className="sub2 tnum"> · JAMB {st.jambRegNo}</span> : null}</td></tr>
              <tr><td>Programme</td><td>{[st.programme, st.department, st.faculty].filter(Boolean).join(" · ")}{st.programmeType ? <span className="sub2"> · {st.programmeType}</span> : null}{st.studyMode ? <span className="sub2"> · {st.studyMode}</span> : null}</td></tr>
              <tr><td>Payment</td><td className="tnum">{pay.reference}{pay.legacy ? <> <Pil kind="grey">Old portal{pay.legacyPayref ? ` ${pay.legacyPayref}` : ""}</Pil></> : null}</td></tr>
              <tr><td>Purpose</td><td>{pay.purpose} <span className="sub2">({src.label ?? src.code})</span></td></tr>
              <tr><td>Period</td><td>{periodWords(src.session, src.semester, src.level)}</td></tr>
              <tr><td>Amount paid</td><td className="tnum"><b>{money(Number(pay.amount))}</b> — the whole payment moves</td></tr>
              <tr><td>Channel · receipt</td><td>{pay.channel ?? "—"}{pay.receiptNo ? ` · ${pay.receiptNo}` : ""}</td></tr>
              <tr><td>Confirmed</td><td>{formatDocDateTime(pay.confirmedAt)} (unchanged by the correction)</td></tr>
            </tbody>
          </table>
          {!base?.ok && base.refusals.length ? (
            <Note kind="bad" title="This payment cannot be corrected">{base.refusals.map((x) => <div key={x}>{refusalParts(x).words}</div>)}</Note>
          ) : null}

          <div className="eyebrow" style={{ marginTop: 12 }}>2. Correct the payment to</div>
          <div className="row" style={{ gap: 8, marginBottom: 6 }}>
            <Btn kind={mode === "PURPOSE" ? "secondary" : "ghost"} onClick={() => pick("PURPOSE")}>Change payment purpose</Btn>
            <Btn kind={mode === "PERIOD" ? "secondary" : "ghost"} onClick={() => pick("PERIOD")}>Correct academic period</Btn>
          </div>
          <div className="row" style={{ gap: 10, flexWrap: "wrap", alignItems: "flex-end" }}>
            <Field id="ra-purpose" label="Purpose">
              <select id="ra-purpose" className="ctl" value={purpose} disabled={mode === "PERIOD"} onChange={(e) => { setPurpose(e.target.value); setCheck(null); }}>
                {destinations.map((d) => <option key={d.code} value={d.code} disabled={!d.supported}>{d.label}{d.supported ? "" : " — paid through its own request"}</option>)}
              </select>
            </Field>
            <Field id="ra-session" label="Session" hint="With the student's level in it">
              <select id="ra-session" className="ctl" value={session} onChange={(e) => { setSession(e.target.value); setSemester(""); setCheck(null); }}>
                <option value="">Choose</option>
                {periods.map((p) => <option key={p.session} value={p.session}>{p.session}{p.level ? ` · ${p.level} Level` : ""}{p.fees_stated === false && purpose === "SCHOOL_FEES" ? " · no fees stated" : ""}</option>)}
              </select>
            </Field>
            {purpose === "SCHOOL_FEES" ? (
              <Field id="ra-sem" label="Semester">
                <select id="ra-sem" className="ctl" value={semester} onChange={(e) => { setSemester(e.target.value); setCheck(null); }}>
                  <option value="">Whole session</option>
                  {semesters.map((n) => <option key={n} value={String(n)}>{n === 1 ? "First semester" : n === 2 ? "Second semester" : `Semester ${n}`}</option>)}
                </select>
              </Field>
            ) : null}
            <Field id="ra-level" label="Level" hint="The student's, for the session"><input id="ra-level" className="ctl tnum" value={period?.level ? `${period.level} Level` : "—"} readOnly /></Field>
            <Btn kind="secondary" disabled={!session || !purpose || !chosen?.supported} busy={stage === "calc"} busyLabel="Calculating..." onClick={calculate}>Calculate</Btn>
          </div>
          <div className="sub2" style={{ marginTop: 4 }}>{chosen?.how}. Faculty, department and programme are the student&apos;s: {[st.faculty, st.department, st.programme].filter(Boolean).join(" · ")}.</div>

          {check ? (
            <>
              <div className="eyebrow" style={{ marginTop: 12 }}>3. Financial calculation</div>
              {stale ? <Note kind="info" title="The destination changed">Calculate again before you go on.</Note> : null}
              {!check.ok ? <Note kind="bad" title="The payment cannot be moved there">{check.refusals.map((x) => <div key={x}>{refusalParts(x).words}</div>)}</Note> : null}
              <Calculation check={check} />
              {check.ok && check.destination?.outcome === "OVERPAID" ? (
                <Note kind="info" title="The payment is more than the obligation">
                  The surplus of {money(Number(check.destination.surplus))} is not absorbed: after the correction it is an overpayment for the Bursary to carry forward or refund on Refunds &amp; Credits.
                </Note>
              ) : null}
              {check.ok ? (
                <>
                  <div className="eyebrow" style={{ marginTop: 12 }}>4. Reason</div>
                  <Field id="ra-rc" label="What was wrong" required>
                    <select id="ra-rc" className="ctl" value={reasonCode} onChange={(e) => setReasonCode(e.target.value as ReasonCode)}>
                      <option value="">Choose</option>
                      {REASON_CODES.map((c) => <option key={c} value={c}>{REASON_WORDS[c]}</option>)}
                    </select>
                  </Field>
                  <Field id="ra-reason" label="Explanation" required hint="Twenty characters or more; “wrong” or “correction” is not a reason">
                    <textarea id="ra-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)}
                      placeholder="e.g. The student selected Inter-Departmental Transfer instead of School Fees; the teller and the student's letter confirm it" />
                  </Field>
                  <Field id="ra-evidence" label="Evidence" hint="What shows it: the student's request, a Bursary memo, the teller or bank line">
                    <input id="ra-evidence" className="ctl" value={evidence} autoComplete="off" onChange={(e) => setEvidence(e.target.value)} />
                  </Field>
                  <Field id="ra-files" label="Supporting documents" hint="Optional: PDF, JPEG or PNG, up to 5 MB each" error={fileProblem ?? undefined}>
                    <input id="ra-files" type="file" multiple accept="application/pdf,image/jpeg,image/png" onChange={(e) => setFiles(Array.from(e.target.files ?? []))} />
                  </Field>
                </>
              ) : null}
            </>
          ) : null}

          {previewing && check?.ok && check.destination ? (
            <div className="card" style={{ padding: 12, marginTop: 12 }}>
              <b>Payment correction preview</b>
              <table className="tbl tbl--data" style={{ marginTop: 8 }}>
                <thead><tr><th /><th>Original</th><th>Destination</th></tr></thead>
                <tbody>
                  <tr><td>Purpose</td><td>{pay.purpose}</td><td>{check.destination.purpose}</td></tr>
                  <tr><td>Session</td><td>{src.session}</td><td>{check.destination.session}</td></tr>
                  <tr><td>Semester</td><td>{periodWords("", src.semester).replace(/^, /, "") || "—"}</td><td>{periodWords("", check.destination.semester).replace(/^, /, "") || "—"}</td></tr>
                  <tr><td>Level</td><td className="tnum">{src.level ?? "—"}</td><td className="tnum">{check.destination.level ?? "—"}</td></tr>
                  <tr><td>Amount</td><td className="tnum">{money(Number(pay.amount))}</td><td className="tnum">Fee {check.destination.fee == null ? "—" : money(Number(check.destination.fee))}</td></tr>
                </tbody>
              </table>
              <table className="tbl tbl--data" style={{ marginTop: 8 }}>
                <tbody>
                  <tr><td>Amount reallocated</td><td className="num tnum">{money(Number(check.destination.applied))}</td></tr>
                  <tr><td>{Number(check.destination.surplus ?? 0) > 0 ? "Surplus" : "Balance remaining"}</td><td className="num tnum"><b>{money(Number(Number(check.destination.surplus ?? 0) > 0 ? check.destination.surplus : check.destination.balance ?? 0))}</b></td></tr>
                  <tr><td>Revenue impact</td><td className="num">No new cash receipt — the ledger moves the income between accounts</td></tr>
                  <tr><td>Payment status</td><td className="num">Verified, unchanged</td></tr>
                  <tr><td>Entitlement</td><td className="num">Pending until a Bursar officer approves and the correction is executed</td></tr>
                </tbody>
              </table>
              <label className="row row--inline" style={{ gap: 8, alignItems: "flex-start", marginTop: 8 }}>
                <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} />
                <span>I have checked this payment and confirm it belongs to {check.destination.purpose} ({check.destination.session}).</span>
              </label>
            </div>
          ) : null}
        </>
      ) : null}
    </Modal>
  );
}
