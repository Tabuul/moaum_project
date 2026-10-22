"use client";

/**
 * V631: the old portal's OUTSTANDING FEES payments, kept apart from school fees. One row a payment, with the student's school-fee
 * position on that session; the Students Account Officer (or the Bursar) ticks payments and verifies them against the records, in a
 * window that shows them, with the explicit confirmation; a Bursar officer other than the verifier credits the verified ones to the
 * students' wallets (one credit a payment, under a batch), or rejects, returns or reopens one with a reason. The server holds every
 * rule and works out every figure; nothing here is a balance.
 */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, day } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { StudentOpen } from "@/components/StudentModal";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { num } from "@/lib/legacy-wallet";
import { PAYMENT_HEADERS, PAYMENT_WORDS, naira, paymentRows, reconHref, type OutstandingPaymentFigures, type OutstandingPaymentRow, type PaymentStatus } from "@/lib/legacy-reconciliation";

const BASE = "/api/bff/api/v1/finance/legacy-reconciliation/outstanding-payments";
const n = (v: unknown) => Number(v ?? 0).toLocaleString("en-GB");
type Credited = { batch_ref: string | null; credited: number; amount: number | string; skipped: number; skipped_why: { student: string; number: string; reference: string; why: string }[] };

async function post<T>(path: string, body: unknown, reason: string): Promise<T | null> {
  const r = await fetch(`${BASE}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return null; }
  return j as T;
}

export function OutstandingPayments({ figures, rows, problem, filters, nav, refresh, faculties, departments, verifies, credits, me }: {
  figures: OutstandingPaymentFigures; rows: OutstandingPaymentRow[] | null; problem: Problem | null; filters: Record<string, string>;
  nav: (c: Record<string, string>) => void; refresh: () => void; faculties: [string, string][]; departments: { dept_code: string; department: string }[];
  verifies: boolean; credits: boolean; me: string | null;
}) {
  const [chosen, setChosen] = useState<Set<string>>(new Set());
  const [open, setOpen] = useState<OutstandingPaymentRow | null>(null);
  const [verifying, setVerifying] = useState(false);
  const [crediting, setCrediting] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const list = rows ?? [];
  const picked = list.filter((r) => chosen.has(r.payment_id));
  const toVerify = picked.filter((r) => r.status === "WAITING" || r.status === "RETURNED");
  const toCredit = picked.filter((r) => r.status === "VERIFIED");
  const selectable = (r: OutstandingPaymentRow) => (verifies && (r.status === "WAITING" || r.status === "RETURNED")) || (credits && r.status === "VERIFIED");
  const shownSelectable = list.filter(selectable);
  const allPicked = shownSelectable.length > 0 && shownSelectable.every((r) => chosen.has(r.payment_id));
  const statusWords = filters.status === "TO_VERIFY" ? "To verify (waiting or returned)" : filters.status ? PAYMENT_WORDS[filters.status as PaymentStatus]?.[0] ?? filters.status : "";
  const scopeWords = [filters.session || "Every session", statusWords, filters.fac ? faculties.find(([c]) => c === filters.fac)?.[1] ?? filters.fac : "",
    filters.dept ? departments.find((u) => u.dept_code === filters.dept)?.department ?? filters.dept : ""].filter(Boolean).join(" · ");
  const f = figures;

  async function exportRows(how: "excel" | "pdf") {
    const title = "Old-portal outstanding fees payments";
    const serial = docSerial("LOP");
    if (how === "excel") {
      setBusy("excel");
      try { downloadBlob(await brandedXlsx(title, PAYMENT_HEADERS, paymentRows(list), { sheetName: "Outstanding fees payments", serial, sub: scopeWords, meta: [["Filters", scopeWords], ["Rows", String(list.length)]] }), "legacy-outstanding-fees-payments.xlsx"); }
      finally { setBusy(null); }
    } else {
      brandedPrint(title, scopeWords, PAYMENT_HEADERS, paymentRows(list), serial, { meta: [["Filters", scopeWords]], generatedBy: me, orientation: "landscape" });
    }
  }

  return (
    <>
      <Tiles items={[
        ["Payments on file", n(f.payments), null, `${naira(f.amount)} · ${n(f.students)} students`, ""],
        ["To verify", n(f.waiting + f.returned), f.waiting + f.returned ? "var(--amber-ink)" : null, `${naira(num(f.waitingAmount) + num(f.returnedAmount))}${f.returned ? ` · ${n(f.returned)} returned` : ""}`, "TO_VERIFY"],
        ["Waiting for the Bursar", n(f.verified), f.verified ? "var(--amber-ink)" : null, `${naira(f.verifiedAmount)} verified`, "VERIFIED"],
        ["Credited to wallets", n(f.credited), "var(--green-ink)", `${naira(f.creditedAmount)} · ${naira(f.applied)} applied to fees`, "CREDITED"],
        ["Rejected", n(f.rejected), null, naira(f.rejectedAmount), "REJECTED"],
      ].map(([a, b, c, d, st]) => [a, b, c as string | null, d, reconHref({ ...filters, tab: "payments", status: st ?? "" })] as [string, string, string | null, string, string])} cls="grid--5" />

      <Panel title="Outstanding fees payments (old portal)" right={`${n(list.length)} listed`}>
        <PBody>
          <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
            <Field id="op-q" label="Search" style={{ flex: "2 1 220px" }}>
              <input id="op-q" className="ctl" type="search" defaultValue={filters.q ?? ""} placeholder="Name, matriculation number, reference, old payment number, batch"
                onKeyDown={(e) => { if (e.key === "Enter") nav({ q: (e.target as HTMLInputElement).value }); }} />
            </Field>
            <Field id="op-status" label="Status" style={{ flex: "0 1 220px" }}>
              <select id="op-status" className="ctl" value={filters.status ?? ""} onChange={(e) => nav({ status: e.target.value })}>
                <option value="">Any</option>
                <option value="TO_VERIFY">To verify (waiting or returned)</option>
                {(Object.keys(PAYMENT_WORDS) as PaymentStatus[]).map((k) => <option key={k} value={k}>{PAYMENT_WORDS[k][0]}</option>)}
              </select>
            </Field>
            <Field id="op-session" label="Session" style={{ flex: "0 1 170px" }}>
              <select id="op-session" className="ctl" value={filters.session ?? ""} onChange={(e) => nav({ session: e.target.value })}>
                <option value="">Every session</option>
                {f.sessions.map((x) => <option key={x.session} value={x.session}>{x.session} ({n(x.payments)})</option>)}
              </select>
            </Field>
            <Field id="op-fac" label="Faculty" style={{ flex: "1 1 180px" }}>
              <SearchSelect id="op-fac" value={filters.fac ?? ""} onChange={(v) => nav({ fac: v, dept: "" })} allLabel="Any faculty" options={faculties.map(([c, l]) => ({ value: c, label: l }))} />
            </Field>
            <Field id="op-dept" label="Department" style={{ flex: "1 1 200px" }}>
              <SearchSelect id="op-dept" value={filters.dept ?? ""} onChange={(v) => nav({ dept: v })} allLabel="Any department" options={departments.map((u) => ({ value: u.dept_code, label: u.department }))} />
            </Field>
            {filters.status || filters.q || filters.fac || filters.dept || filters.session ? <Btn kind="ghost" onClick={() => nav({ status: "", q: "", fac: "", dept: "", session: "" })}>Clear</Btn> : null}
          </div>
          <div className="row mt-2" style={{ flexWrap: "wrap", gap: "var(--s-3)" }}>
            {verifies || credits ? (
              <label className="row row--inline row--tight" style={{ gap: 6 }}>
                <input type="checkbox" className="pchk" checked={allPicked} disabled={!shownSelectable.length}
                  onChange={(e) => setChosen(e.target.checked ? new Set(shownSelectable.map((r) => r.payment_id)) : new Set())} />
                <span className="sub2">Select all you can act on ({n(shownSelectable.length)})</span>
              </label>
            ) : null}
            {verifies ? <Btn kind="primary" size="sm" disabled={!toVerify.length || !!busy} onClick={() => setVerifying(true)}>Verify selected ({toVerify.length})</Btn> : null}
            {credits ? <Btn kind="primary" size="sm" disabled={!toCredit.length || !!busy} onClick={() => setCrediting(true)}>Credit selected to the wallet ({toCredit.length})</Btn> : null}
            <Btn kind="ghost" size="sm" busy={busy === "excel"} busyLabel="Preparing…" disabled={!list.length} onClick={() => exportRows("excel")}>Download Excel</Btn>
            <Btn kind="ghost" size="sm" disabled={!list.length} onClick={() => exportRows("pdf")}>Download PDF</Btn>
          </div>
        </PBody>
        {problem ? <ProblemNotice problem={problem} /> : null}
        {list.length ? (
          <DTable pageSize={50}
            cols={[...(verifies || credits ? ["|mid"] : []), "Student", "Session", "Payment", "Amount|num", "Owed on the session|num", "Status", "Action"]}
            texts={list.map((r) => `${r.student} ${r.matric_no ?? ""} ${r.reference} ${r.old_reference ?? ""} ${r.batch_ref ?? ""} ${r.status}`)}
            rows={list.map((r) => [
              ...(verifies || credits ? [<input key="c" type="checkbox" className="pchk" aria-label={`Select ${r.student} ${r.reference}`} checked={chosen.has(r.payment_id)} disabled={!selectable(r)}
                onChange={(e) => setChosen((s) => { const t = new Set(s); if (e.target.checked) t.add(r.payment_id); else t.delete(r.payment_id); return t; })} />] : []),
              <span key="s"><b>{r.student}</b><div className="sub2 tnum">{r.matric_no ?? r.admission_no ?? "—"} · {r.programme ?? r.programme_code ?? ""}</div>
                {r.merged ? <Pil kind="bad">Merged record</Pil> : r.student_status === "DECEASED" ? <Pil kind="bad">Deceased</Pil> : null}</span>,
              <span key="ses" className="tnum">{r.session}<div className="sub2">{r.semester ? `Semester ${r.semester}` : "Whole session"}</div></span>,
              <span key="p" className="sub2"><span className="tnum">{r.old_reference ?? r.reference}</span><div>{[r.method, r.paid_at ? day(r.paid_at) : ""].filter(Boolean).join(" · ")}</div></span>,
              <span key="a" className="tnum b600">{naira(r.amount)}</span>,
              <span key="o" className={`tnum${num(r.owed) > 0 ? " ink-red" : " sub2"}`}>{naira(r.owed)}<div className="sub2">due {naira(r.due)}</div></span>,
              <span key="st"><Pil kind={PAYMENT_WORDS[r.status][1]}>{PAYMENT_WORDS[r.status][0]}</Pil>
                <div className="sub2">{r.status === "VERIFIED" ? `by ${r.verified_by ?? r.verified_office ?? ""} · ${day(r.verified_at)}` : r.status === "CREDITED" ? `${r.batch_ref ?? ""} · ${day(r.decided_at)}` : r.decided_at ? `${r.decided_by ?? ""} · ${day(r.decided_at)}` : ""}</div></span>,
              <span key="x" className="row row--inline row--tight row--right"><Btn kind="ghost" size="sm" onClick={() => setOpen(r)}>Open</Btn><StudentOpen id={r.student_id} label="Record" kind="ghost" /></span>,
            ])} />
        ) : <PBody><div className="sub2">{rows ? "No payment matches the filters." : "Reading…"}</div></PBody>}
        <PBody>
          <Note kind="info" title="What these payments are">
            The old portal took these payments as <b>OUTSTANDING FEES</b>. They came in with the old fees history and are kept as they were imported, apart from school
            fees: they do not count towards any session&rsquo;s fees. The Students Account Officer checks each one against the records and verifies it; a Bursar officer other
            than the one who verified it credits it to the student&rsquo;s wallet, once, as the student&rsquo;s own money. The student is told and applies it to the fees from the
            wallet page. <b>Owed on the session</b> is what the student still owes on that session&rsquo;s school fees today. On the ledger the credit is drawn from Opening
            balance / suspense, as every old-portal credit is.
          </Note>
        </PBody>
      </Panel>

      {f.batches.length ? (
        <Panel title="Credits to the wallet">
          <DTable pageSize={0} cols={["Batch", "Credited", "Payments|num", "Amount|num", "By"]}
            rows={f.batches.map((b) => [<span key="r" className="tnum">{b.ref}</span>, day(b.credited_at), n(b.payments), naira(b.amount), `${b.credited_by ?? ""} (${b.office ?? ""})`])} />
        </Panel>
      ) : null}

      {open ? <PaymentModal row={open} credits={credits} onClose={() => setOpen(null)} onChanged={() => { setOpen(null); refresh(); }} /> : null}
      {verifying ? <VerifyModal rows={toVerify} busy={busy === "verify"} onClose={() => setVerifying(false)} onConfirm={async (note) => {
        setBusy("verify");
        try {
          const r = await post<{ verified: number; asked: number }>("/verify", { ids: toVerify.map((x) => x.payment_id), note, confirmed: true }, `Old-portal outstanding fees payments verified: ${toVerify.length}`);
          if (r) { notify(`${n(r.verified)} of ${n(r.asked)} verified and sent to the Bursar to credit`); setChosen(new Set()); setVerifying(false); refresh(); }
        } finally { setBusy(null); }
      }} /> : null}
      {crediting ? <CreditModal rows={toCredit} onClose={() => setCrediting(false)} onDone={() => { setCrediting(false); setChosen(new Set()); refresh(); }} /> : null}
    </>
  );
}

/* ── the verification, confirmed in a window that shows the payments ── */
function VerifyModal({ rows, busy, onClose, onConfirm }: { rows: OutstandingPaymentRow[]; busy: boolean; onClose: () => void; onConfirm: (note: string) => void }) {
  const [note, setNote] = useState("");
  const [confirmed, setConfirmed] = useState(false);
  const total = rows.reduce((a, r) => a + num(r.amount), 0);
  return (
    <Modal wide title={`Verify ${rows.length} outstanding fees payment${rows.length === 1 ? "" : "s"}`} sub={`${naira(total)} to send to the Bursar`} onClose={onClose}
      foot={<><Btn kind="primary" busy={busy} busyLabel="Verifying…" disabled={busy || !confirmed} onClick={() => onConfirm(note)}>Verify &amp; send to the Bursar</Btn><Btn kind="ghost" disabled={busy} onClick={onClose}>Cancel</Btn></>}>
      <DTable pageSize={0} cols={["Student", "Session", "Payment", "Amount|num", "Owed on the session|num"]}
        rows={rows.map((r) => [<span key="s"><b>{r.student}</b><div className="sub2 tnum">{r.matric_no ?? r.admission_no ?? ""}</div></span>,
          <span key="ses" className="tnum">{r.session}{r.semester ? ` · S${r.semester}` : ""}</span>, <span key="p" className="tnum sub2">{r.old_reference ?? r.reference}</span>,
          <span key="a" className="tnum b600">{naira(r.amount)}</span>, <span key="o" className="tnum">{naira(r.owed)}</span>])} />
      <Field id="op-vnote" label="Remarks" hint="What the payments were checked against; the Bursar reads it" full><input id="op-vnote" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      <label className="row row--inline row--tight" style={{ alignItems: "flex-start", gap: 8 }}>
        <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} />
        <span>I confirm that each payment has been checked against the available records and that the amount is correct.</span>
      </label>
      <Note kind="bad" title="Nothing is credited yet">Once verified, these payments wait for a Bursar officer other than you to credit them to the students&rsquo; wallets, or to return them to you.</Note>
    </Modal>
  );
}

/* ── the credit, by a Bursar officer other than the verifier ── */
function CreditModal({ rows, onClose, onDone }: { rows: OutstandingPaymentRow[]; onClose: () => void; onDone: () => void }) {
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<Credited | null>(null);
  const total = rows.reduce((a, r) => a + num(r.amount), 0);
  return (
    <Modal wide title={`Credit ${rows.length} verified payment${rows.length === 1 ? "" : "s"} to the wallet`} sub={naira(total)} onClose={result ? onDone : onClose}
      foot={result ? <Btn kind="primary" onClick={onDone}>Close</Btn> : <>
        <Btn kind="ghost" onClick={onClose}>Cancel</Btn>
        <Btn kind="primary" busy={busy} busyLabel="Crediting the wallets…" disabled={busy} onClick={async () => {
          setBusy(true);
          try {
            const r = await post<Credited>("/credit", { ids: rows.map((x) => x.payment_id), note }, `Old-portal outstanding fees payments credited to the wallet: ${rows.length}`);
            if (r) { setResult(r); notify(`${n(r.credited)} credited (${naira(r.amount)})${r.batch_ref ? ` under ${r.batch_ref}` : ""}${r.skipped ? `, ${n(r.skipped)} skipped` : ""}`); }
          } finally { setBusy(false); }
        }}>Credit to the wallets</Btn></>}>
      {result ? (
        <>
          {result.credited ? <Note kind="ok" title={`${n(result.credited)} credited under ${result.batch_ref}`}>{naira(result.amount)} credited as the students&rsquo; own money (source LEGACY_OUTSTANDING); each student is told and applies it to the fees from the wallet page.</Note>
            : <Note kind="bad" title="Nothing was credited">Every payment was skipped, for the reason given against it.</Note>}
          {result.skipped_why.length ? <DTable pageSize={0} cols={["Student", "Number", "Payment", "Why skipped"]}
            rows={result.skipped_why.map((s, i) => [s.student || "—", <span key={`n${i}`} className="tnum">{s.number || ""}</span>, <span key={`r${i}`} className="tnum sub2">{s.reference || ""}</span>, s.why])} /> : null}
        </>
      ) : (
        <>
          <Note kind="info" title="One credit a payment, once">Each payment was verified by another officer; one you verified yourself is skipped and said. Each is credited for its own amount to the
            student&rsquo;s wallet and drawn from Opening balance / suspense on the ledger.</Note>
          <DTable pageSize={0} cols={["Student", "Session", "Amount|num", "Verified by"]}
            rows={rows.map((r) => [`${r.student} · ${r.matric_no ?? ""}`, <span key="s" className="tnum">{r.session}{r.semester ? ` · S${r.semester}` : ""}</span>,
              <span key="a" className="tnum">{naira(r.amount)}</span>, `${r.verified_by ?? ""} (${r.verified_office ?? ""}) · ${day(r.verified_at)}`])} />
          <Field id="op-cnote" label="Note" full><input id="op-cnote" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </>
      )}
    </Modal>
  );
}

/* ── one payment: the record in full and the Bursar's decision ── */
function PaymentModal({ row, credits, onClose, onChanged }: { row: OutstandingPaymentRow; credits: boolean; onClose: () => void; onChanged: () => void }) {
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  async function decide(action: "REJECT" | "RETURN" | "REOPEN") {
    setBusy(action);
    try {
      const r = await post<OutstandingPaymentRow>(`/${row.payment_id}/decide`, { action, reason }, `Outstanding fees payment ${row.reference} ${action.toLowerCase()}: ${row.matric_no ?? row.student}`);
      if (r) { notify(action === "REJECT" ? `${row.reference} rejected; nothing was credited.` : action === "RETURN" ? `${row.reference} returned to the officer.` : `${row.reference} reopened for the officer to verify again.`); onChanged(); }
    } finally { setBusy(null); }
  }
  const canReject = credits && ["WAITING", "RETURNED", "VERIFIED"].includes(row.status);
  const canReturn = credits && row.status === "VERIFIED";
  const canReopen = credits && row.status === "REJECTED";
  const reasonOk = reason.trim().length >= 10;
  return (
    <Modal wide title={`${row.student} · ${row.session}`} sub={`${row.matric_no ?? row.admission_no ?? ""} · ${row.programme ?? ""}`} onClose={onClose}
      foot={<>
        <Btn kind="ghost" onClick={onClose}>Close</Btn>
        {canReopen ? <Btn kind="secondary" busy={busy === "REOPEN"} busyLabel="Reopening…" disabled={!!busy || !reasonOk} onClick={() => decide("REOPEN")}>Reopen</Btn> : null}
        {canReturn ? <Btn kind="ghost" busy={busy === "RETURN"} busyLabel="Returning…" disabled={!!busy || !reasonOk} onClick={() => decide("RETURN")}>Return to the officer</Btn> : null}
        {canReject ? <Btn kind="ghost" busy={busy === "REJECT"} busyLabel="Rejecting…" disabled={!!busy || !reasonOk} onClick={() => decide("REJECT")}>Reject</Btn> : null}
      </>}>
      <div className="row" style={{ gap: "var(--s-3)", flexWrap: "wrap", marginBottom: "var(--s-3)" }}>
        <Pil kind={PAYMENT_WORDS[row.status][1]}>{PAYMENT_WORDS[row.status][0]}</Pil>
        <span className="sub2">{PAYMENT_WORDS[row.status][2]}</span>
      </div>
      <div className="eyebrow">The payment</div>
      <KvGrid cls="grid--3" pairs={[["Purpose on the old portal", row.purpose], ["Amount", naira(row.amount)], ["Paid on", row.paid_at ? day(row.paid_at) : "—"],
        ["Reference", row.reference], ["Old payment number", row.old_reference ?? "—"], ["Method", row.method ?? "—"],
        ["Session", row.session], ["Semester", row.semester ? String(row.semester) : "Whole session"], ["Imported as", row.note ?? "—"]]} />
      <div className="eyebrow" style={{ marginTop: "var(--s-3)" }}>The student&rsquo;s school fees on {row.session}</div>
      <KvGrid cls="grid--3" pairs={[["Fees due", naira(row.due)], ["Paid as school fees", naira(row.paid)], ["Owed today", naira(row.owed)]]} />
      <div className="eyebrow" style={{ marginTop: "var(--s-3)" }}>Where it stands</div>
      <KvGrid cls="grid--3" pairs={[["Verified", row.verified_at ? `${row.verified_by ?? ""} (${row.verified_office ?? ""}) · ${day(row.verified_at)}${row.verify_note ? ` · ${row.verify_note}` : ""}` : "—"],
        ["Bursar", row.decided_at ? `${row.decided_by ?? ""} (${row.decided_office ?? ""}) · ${day(row.decided_at)}` : "—"], ["Note", row.decision_note ?? "—"],
        ["On the wallet", row.status === "CREDITED" ? `${naira(row.credited_amount)} · ${row.batch_ref ?? ""}` : "Not credited"]]} />
      {row.merged || row.student_status === "DECEASED" ? <Note kind="bad" title="Not credited to this record">{row.merged ? "This student record was merged into another: nothing is credited to it." : "The student is recorded as deceased: nothing is credited."}</Note> : null}
      {canReject || canReturn || canReopen ? (
        <Field id="op-reason" label={canReopen ? "Reason to reopen" : canReturn ? "Reason (to reject or return to the officer)" : "Reason to reject"} hint="Ten characters or more; the officer reads it" full>
          <input id="op-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
      ) : null}
    </Modal>
  );
}
