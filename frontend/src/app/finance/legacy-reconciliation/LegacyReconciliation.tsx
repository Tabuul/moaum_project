"use client";

/**
 * Legacy financial reconciliation (V625). The old portal's outstanding fees of a session, student by student, as the reconciliation
 * classifies them — what the student owes (a liability, never wallet money) and what the student paid above the fees stated (a credit
 * the University holds); the e-wallet top-ups (the V583 desk's figures, with the desk itself a click away); the wallet credit
 * requests: the Students Account Officer confirms an overpayment against the records (the amount never above the excess, a different
 * amount with its reason, the evidence, the explicit confirmation) and sends it to the Bursar; a Bursar officer other than the
 * initiator approves (the wallet credited once by the server), rejects or returns it; the history; the reports, S/N first. The
 * server holds every rule and works out every figure; nothing here is a balance.
 */
import { useEffect, useState } from "react";
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
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
import { DECISION_WORDS, OUTSTANDING_HEADERS, REQUEST_HEADERS, REQUEST_WORDS, STATE_WORDS, TABS, naira, outstandingRows, reconHref, requestRows,
  type CreditRequestRow, type OutstandingRow, type OutstandingState, type ReconFigures, type RequestStatus, type StudentPicture, type Tab } from "@/lib/legacy-reconciliation";

const BASE = "/api/bff/api/v1/finance/legacy-reconciliation";
const n = (v: unknown) => Number(v ?? 0).toLocaleString("en-GB");
type Unit = { faculty_code: string; faculty: string; dept_code: string; department: string };

async function post<T>(path: string, body: unknown, reason: string): Promise<T | null> {
  const r = await fetch(`${BASE}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem(j ? (j as unknown as Parameters<typeof notifyProblem>[0]) : { status: r.status, title: r.statusText }); return null; }
  return j as T;
}

export function LegacyReconciliation({ figures, sessions, filters, outstanding, outstandingProblem, requests, requestsProblem, structure, actingOffice, me }: {
  figures: ReconFigures; sessions: string[]; filters: Record<string, string>; outstanding: OutstandingRow[] | null; outstandingProblem: Problem | null;
  requests: CreditRequestRow[] | null; requestsProblem: Problem | null; structure: Unit[]; actingOffice: string | null; me: string | null;
}) {
  const go = useQueryNav();
  const tab = (filters.tab || "overview") as Tab;
  const nav = (c: Record<string, string>) => go(reconHref({ ...filters, ...c }));
  const initiates = ["bursar", "studentaccounts", "super"].includes(actingOffice ?? "");
  const decides = ["bursar", "super"].includes(actingOffice ?? "");
  const session = filters.session || figures.session;
  const [openStudent, setOpenStudent] = useState<OutstandingRow | null>(null);
  const [openRequest, setOpenRequest] = useState<CreditRequestRow | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const faculties = Array.from(new Map(structure.map((u) => [u.faculty_code, u.faculty])).entries());
  const departments = structure.filter((u) => !filters.fac || u.faculty_code === filters.fac);
  const o = figures.outstanding, q = figures.requests, w = figures.wallet;
  const scopeWords = [session, filters.state ? STATE_WORDS[filters.state as OutstandingState]?.[0] : "", filters.status ? REQUEST_WORDS[filters.status as RequestStatus]?.[0] : "",
    filters.fac ? faculties.find(([c]) => c === filters.fac)?.[1] ?? filters.fac : "", filters.dept ? departments.find((u) => u.dept_code === filters.dept)?.department ?? filters.dept : ""]
    .filter(Boolean).join(" · ");
  const historyRows = (requests ?? []).filter((r) => ["CREDITED", "REJECTED", "WITHDRAWN"].includes(r.status));
  const queueRows = (requests ?? []).filter((r) => ["PENDING_BURSAR_APPROVAL", "RETURNED_FOR_CORRECTION"].includes(r.status));
  const shownRequests = tab === "history" ? historyRows : filters.status ? (requests ?? []) : queueRows;

  const tabs = (
    <div className="row row--tight" style={{ flexWrap: "wrap", marginBottom: "var(--s-3)" }} role="tablist" aria-label="Legacy financial reconciliation">
      {TABS.map((t) => <Btn key={t.id} kind={tab === t.id ? "primary" : "ghost"} size="sm" onClick={() => nav({ tab: t.id, state: "", status: "", q: "" })}>{t.label}</Btn>)}
    </div>
  );
  const sessionPick = (
    <Field id="lr-session" label="Legacy session" style={{ flex: "0 1 170px" }}>
      <select id="lr-session" className="ctl" value={session} onChange={(e) => nav({ session: e.target.value })}>
        {!sessions.includes(session) ? <option value={session}>{session}</option> : null}
        {sessions.map((x) => <option key={x} value={x}>{x}</option>)}
      </select>
    </Field>
  );

  async function exportRows(kind: "outstanding" | "requests", how: "excel" | "pdf") {
    const isO = kind === "outstanding";
    const title = isO ? "Legacy outstanding fees report" : tab === "history" ? "Legacy reconciliation history" : "Legacy wallet credit requests";
    const headers = isO ? OUTSTANDING_HEADERS : REQUEST_HEADERS;
    const rows = isO ? outstandingRows(outstanding ?? []) : requestRows(shownRequests);
    const serial = docSerial(isO ? "LOR" : "LWR");
    if (how === "excel") {
      setBusy("excel");
      try { downloadBlob(await brandedXlsx(title, headers, rows, { sheetName: isO ? "Outstanding fees" : "Credit requests", serial, sub: scopeWords, meta: [["Filters", scopeWords], ["Rows", String(rows.length)]] }), `${isO ? "legacy-outstanding-fees" : "legacy-credit-requests"}.xlsx`); }
      finally { setBusy(null); }
    } else {
      brandedPrint(title, scopeWords, headers, rows, serial, { meta: [["Filters", scopeWords]], generatedBy: me, orientation: "landscape" });
    }
  }

  return (
    <>
      {tabs}
      {tab === "overview" ? (
        <>
          <Note kind="info" title="What this desk does">
            A legacy <b>outstanding fee</b> is what the student still owes the University for a session on the old portal&rsquo;s records: it stays a liability and is never
            wallet money. A <b>credit</b> is what the student paid above the fees stated: the Students Account Officer confirms it against the records and sends a request,
            a Bursar officer other than the one who confirmed it approves, and only then is the student&rsquo;s wallet credited &mdash; once &mdash; on the wallet that exists.
            The old portal&rsquo;s <b>e-wallet top-ups</b> follow the same two-officer road on the Old E-Wallet Balances desk: only the unused balance, verified, is posted.
          </Note>
          <div className="eyebrow">Student liabilities · {session}</div>
          <Tiles items={[
            ["Students who owe", n(o.owes), o.owes ? "var(--red-ink)" : null, `${naira(o.owesAmount)} outstanding to the University`, reconHref({ ...filters, tab: "outstanding", state: "OWES" })],
            ["Settled", n(o.settled), null, "Paid what the fee setup states", reconHref({ ...filters, tab: "outstanding", state: "SETTLED" })],
            ["No fee stated", n(o.noFee), o.noFee ? "var(--amber-ink)" : null, "The Bursary states the session's fees first", reconHref({ ...filters, tab: "outstanding", state: "NO_FEE_STATED" })],
            ["Students with old payments", n(o.students), null, `on ${session}`, reconHref({ ...filters, tab: "outstanding" })],
          ]} />
          <div className="eyebrow">Student credits · {session}</div>
          <Tiles items={[
            ["Credits held", n(o.credit), o.credit ? "var(--amber-ink)" : null, `${naira(o.creditAmount)} paid above the fees stated · not yet decided`, reconHref({ ...filters, tab: "outstanding", state: "CREDIT" })],
            ["Decided", n(o.decided), null, `${n(o.carried)} carried · ${n(o.refunded)} refunded · ${n(o.toWallet)} to the wallet`, reconHref({ ...filters, tab: "outstanding", state: "CREDIT_DECIDED" })],
            ["Pending Bursar approval", n(q.pending), q.pending ? "var(--amber-ink)" : null, `${naira(q.pendingAmount)} requested · ${n(q.adjusted)} with the amount adjusted`, reconHref({ ...filters, tab: "requests", status: "PENDING_BURSAR_APPROVAL" })],
            ["Returned for correction", n(q.returned), q.returned ? "var(--red-ink)" : null, naira(q.returnedAmount), reconHref({ ...filters, tab: "requests", status: "RETURNED_FOR_CORRECTION" })],
            ["Credited to wallets", n(q.credited), "var(--green-ink)", `${naira(q.creditedAmount)} credited · ${naira(figures.overpaidCredited.applied)} applied to fees`, reconHref({ ...filters, tab: "history", status: "CREDITED" })],
            ["Rejected", n(q.rejected), null, `${naira(q.rejectedAmount)} · ${n(q.withdrawn)} withdrawn`, reconHref({ ...filters, tab: "history", status: "REJECTED" })],
          ]} />
          <div className="eyebrow">Old e-wallet top-ups</div>
          <Tiles items={[
            ["To verify", n(w.computed), w.computed ? "var(--amber-ink)" : null, `${naira(w.computedAmount)} computed from the imported payments`, "/finance/legacy-wallet?status=COMPUTED"],
            ["Pending Bursar posting", n(w.verified), w.verified ? "var(--amber-ink)" : null, `${naira(w.verifiedAmount)} verified`, "/finance/legacy-wallet?status=VERIFIED"],
            ["Returned for correction", n(w.returned), w.returned ? "var(--red-ink)" : null, naira(w.returnedAmount), "/finance/legacy-wallet?status=RETURNED"],
            ["Posted to wallets", n(w.posted), "var(--green-ink)", `${naira(w.postedAmount)} credited · ${naira(w.applied)} applied to fees`, "/finance/legacy-wallet?status=POSTED"],
            ["Requires review", n(w.review), w.review ? "var(--red-ink)" : null, "Paid from the old wallet beyond the top-ups on file", "/finance/legacy-wallet?status=REQUIRES_REVIEW"],
            ["Rejected or frozen", n(w.rejected + w.frozen), null, `${n(w.noBalance)} with nothing left`, "/finance/legacy-wallet?status=REJECTED"],
          ]} />
          {decides && queueRows.length ? (
            <Panel title="Wallet credit approvals waiting on the Bursar" right={`${n(queueRows.length)} request${queueRows.length === 1 ? "" : "s"}`}>
              <RequestsTable rows={queueRows.slice(0, 10)} onOpen={setOpenRequest} />
              {queueRows.length > 10 ? <PBody><Link className="lnk" href={reconHref({ ...filters, tab: "requests" })}>All {n(queueRows.length)} requests</Link></PBody> : null}
            </Panel>
          ) : null}
        </>
      ) : null}

      {tab === "outstanding" ? (
        <Panel title={`Outstanding fees reconciliation · ${session}`} right={`${n(outstanding?.length ?? 0)} listed`}>
          <PBody>
            <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
              {sessionPick}
              <Field id="lr-q" label="Search" style={{ flex: "2 1 220px" }}>
                <input id="lr-q" className="ctl" type="search" defaultValue={filters.q ?? ""} placeholder="Name, matriculation, JAMB or application number, reference"
                  onKeyDown={(e) => { if (e.key === "Enter") nav({ q: (e.target as HTMLInputElement).value }); }} />
              </Field>
              <Field id="lr-state" label="Classification" style={{ flex: "0 1 230px" }}>
                <select id="lr-state" className="ctl" value={filters.state ?? ""} onChange={(e) => nav({ state: e.target.value })}>
                  <option value="">Any</option>
                  {(Object.keys(STATE_WORDS) as OutstandingState[]).map((k) => <option key={k} value={k}>{STATE_WORDS[k][0]}</option>)}
                </select>
              </Field>
              <Field id="lr-fac" label="Faculty" style={{ flex: "1 1 180px" }}>
                <SearchSelect id="lr-fac" value={filters.fac ?? ""} onChange={(v) => nav({ fac: v, dept: "" })} allLabel="Any faculty" options={faculties.map(([c, l]) => ({ value: c, label: l }))} />
              </Field>
              <Field id="lr-dept" label="Department" style={{ flex: "1 1 200px" }}>
                <SearchSelect id="lr-dept" value={filters.dept ?? ""} onChange={(v) => nav({ dept: v })} allLabel="Any department" options={departments.map((u) => ({ value: u.dept_code, label: u.department }))} />
              </Field>
              {filters.state || filters.q || filters.fac || filters.dept ? <Btn kind="ghost" onClick={() => nav({ state: "", q: "", fac: "", dept: "" })}>Clear</Btn> : null}
            </div>
            <div className="row mt-2" style={{ flexWrap: "wrap", gap: "var(--s-3)" }}>
              <Btn kind="ghost" size="sm" busy={busy === "excel"} busyLabel="Preparing…" disabled={!outstanding?.length} onClick={() => exportRows("outstanding", "excel")}>Download Excel</Btn>
              <Btn kind="ghost" size="sm" disabled={!outstanding?.length} onClick={() => exportRows("outstanding", "pdf")}>Download PDF</Btn>
            </div>
          </PBody>
          {outstandingProblem ? <ProblemNotice problem={outstandingProblem} /> : null}
          {outstanding?.length ? (
            <DTable pageSize={50} cols={["Student", "Fees due|num", "Paid|num", "Student owes|num", "Credit held|num", "Classification", "Decision · request", "Action"]}
              texts={outstanding.map((r) => `${r.name} ${r.matric_no ?? ""} ${r.jamb_reg_no ?? ""} ${r.admission_no ?? ""} ${r.request_ref ?? ""} ${r.state}`)}
              rows={outstanding.map((r) => [
                <span key="s"><b>{r.name}</b><div className="sub2 tnum">{r.matric_no ?? r.admission_no ?? "—"} · {r.programme ?? r.programme_code ?? ""}{r.level ? ` · ${r.level} Level` : ""}</div></span>,
                <span key="d" className="tnum">{naira(r.due)}</span>,
                <span key="p" className="tnum">{naira(r.paid)}<div className="sub2">{r.old_payments} old-portal payment{r.old_payments === 1 ? "" : "s"}{r.doubles ? ` · ${r.doubles} double${r.doubles === 1 ? "" : "s"}` : ""}</div></span>,
                <span key="o" className={`tnum${num(r.owed) > 0 ? " ink-red b600" : " sub2"}`}>{naira(r.owed)}</span>,
                <span key="c" className={`tnum${num(r.excess) > 0 ? " b600" : " sub2"}`}>{naira(r.excess)}</span>,
                <span key="st"><Pil kind={STATE_WORDS[r.state][1]}>{STATE_WORDS[r.state][0]}</Pil></span>,
                <span key="x" className="sub2">{r.decision ? DECISION_WORDS[r.decision] ?? r.decision : ""}{r.request_ref ? <div className="tnum">{r.request_ref} · {REQUEST_WORDS[r.request_status!]?.[0] ?? r.request_status}</div> : null}{!r.decision && !r.request_ref ? "—" : null}</span>,
                <span key="a" className="row row--inline row--tight row--right">
                  <Btn kind={r.state === "CREDIT" && initiates && !r.request_ref ? "primary" : "ghost"} size="sm" onClick={() => setOpenStudent(r)}>{r.state === "CREDIT" && initiates && !r.request_ref ? "Confirm" : "View"}</Btn>
                  <StudentOpen id={r.student_id} label="Record" kind="ghost" />
                </span>,
              ])} />
          ) : <PBody><div className="sub2">{outstanding ? "No student matches the filters." : "Reading…"}</div></PBody>}
          <PBody>
            <Note kind="info" title="How a row is classified">
              Fees due are what the fee setup states for the student&rsquo;s programme and level in the session; paid is every confirmed school-fees payment of the session, the
              old portal&rsquo;s included. <b>Student owes</b> is a liability of the student: it stays outstanding on the student&rsquo;s account and is never credited to a wallet.
              <b> Credit held</b> is what was paid above the fees stated: it reaches the wallet only through a request the Bursar approves, or is carried into the next session or
              refunded on the Old Fees History desk. A double on the old portal&rsquo;s records is withdrawn there first; a payment credited to the wrong student is moved by a
              School Fees Payment Swap, never paid twice.
            </Note>
          </PBody>
        </Panel>
      ) : null}

      {tab === "wallet" ? (
        <Panel title="E-wallet top-up reconciliation" right={<Link className="lnk" href="/finance/legacy-wallet">Open the Old E-Wallet Balances desk</Link>}>
          <PBody>
            <Tiles items={[
              ["Students with old top-ups", n(w.students), null, "One row a student: top-ups less the fees paid from the old wallet", "/finance/legacy-wallet"],
              ["To verify", n(w.computed), w.computed ? "var(--amber-ink)" : null, naira(w.computedAmount), "/finance/legacy-wallet?status=COMPUTED"],
              ["Pending Bursar posting", n(w.verified), w.verified ? "var(--amber-ink)" : null, naira(w.verifiedAmount), "/finance/legacy-wallet?status=VERIFIED"],
              ["Returned for correction", n(w.returned), w.returned ? "var(--red-ink)" : null, naira(w.returnedAmount), "/finance/legacy-wallet?status=RETURNED"],
              ["Posted to wallets", n(w.posted), "var(--green-ink)", `${naira(w.postedAmount)} · ${naira(w.applied)} applied to fees`, "/finance/legacy-wallet?status=POSTED"],
              ["Requires review", n(w.review), w.review ? "var(--red-ink)" : null, "Nothing is posted until the old portal's statement is entered", "/finance/legacy-wallet?status=REQUIRES_REVIEW"],
              ["Rejected", n(w.rejected), null, `${n(w.frozen)} frozen`, "/finance/legacy-wallet?status=REJECTED"],
              ["No balance", n(w.noBalance), null, "Fully used on the old portal: nothing to credit", "/finance/legacy-wallet?status=NO_BALANCE"],
            ]} />
            <Note kind="info" title="Only the verified unused balance becomes wallet credit">
              A top-up the old portal already spent is not credited again: the balance is top-ups less what was paid from the old wallet, or the old portal&rsquo;s own statement
              where the Bursary holds it. The Students Account Officer verifies it against the records; a Bursar officer other than the verifier posts it (or returns it for
              correction with a reason); one credit a student, ever. The desk lists each student with the legacy wallet reference, the top-up dates, the original amount, what was
              used, the balance and the status, and prints the report.
            </Note>
          </PBody>
        </Panel>
      ) : null}

      {tab === "requests" || tab === "history" ? (
        <Panel title={tab === "history" ? "Legacy reconciliation history" : decides ? "Legacy wallet credit approval" : "Wallet credit requests"} right={`${n(shownRequests.length)} listed`}>
          <PBody>
            <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
              <Field id="lr-rq" label="Search" style={{ flex: "2 1 220px" }}>
                <input id="lr-rq" className="ctl" type="search" defaultValue={filters.q ?? ""} placeholder="Request, name, matriculation or JAMB number"
                  onKeyDown={(e) => { if (e.key === "Enter") nav({ q: (e.target as HTMLInputElement).value }); }} />
              </Field>
              <Field id="lr-status" label="Status" style={{ flex: "0 1 230px" }}>
                <select id="lr-status" className="ctl" value={filters.status ?? ""} onChange={(e) => nav({ status: e.target.value })}>
                  <option value="">{tab === "history" ? "Credited, rejected, withdrawn" : "Waiting or returned"}</option>
                  {(Object.keys(REQUEST_WORDS) as RequestStatus[]).map((k) => <option key={k} value={k}>{REQUEST_WORDS[k][0]}</option>)}
                </select>
              </Field>
              <Field id="lr-rsession" label="Legacy session" style={{ flex: "0 1 170px" }}>
                <select id="lr-rsession" className="ctl" value={filters.session ?? ""} onChange={(e) => nav({ session: e.target.value })}>
                  <option value="">Any session</option>
                  {sessions.map((x) => <option key={x} value={x}>{x}</option>)}
                </select>
              </Field>
              <Field id="lr-rfac" label="Faculty" style={{ flex: "1 1 180px" }}>
                <SearchSelect id="lr-rfac" value={filters.fac ?? ""} onChange={(v) => nav({ fac: v, dept: "" })} allLabel="Any faculty" options={faculties.map(([c, l]) => ({ value: c, label: l }))} />
              </Field>
              {filters.status || filters.q || filters.fac || filters.dept || filters.session ? <Btn kind="ghost" onClick={() => nav({ status: "", q: "", fac: "", dept: "", session: "" })}>Clear</Btn> : null}
            </div>
            <div className="row mt-2" style={{ flexWrap: "wrap", gap: "var(--s-3)" }}>
              <Btn kind="ghost" size="sm" busy={busy === "excel"} busyLabel="Preparing…" disabled={!shownRequests.length} onClick={() => exportRows("requests", "excel")}>Download Excel</Btn>
              <Btn kind="ghost" size="sm" disabled={!shownRequests.length} onClick={() => exportRows("requests", "pdf")}>Download PDF</Btn>
              {tab === "history" ? <Link className="lnk" href="/finance/legacy-wallet">Old e-wallet postings</Link> : null}
            </div>
          </PBody>
          {requestsProblem ? <ProblemNotice problem={requestsProblem} /> : null}
          {shownRequests.length ? <RequestsTable rows={shownRequests} onOpen={setOpenRequest} /> : <PBody><div className="sub2">{requests ? "Nothing here." : "Reading…"}</div></PBody>}
        </Panel>
      ) : null}

      {openStudent ? <StudentModal row={openStudent} initiates={initiates} session={session} onClose={() => setOpenStudent(null)}
        onChanged={() => { setOpenStudent(null); go(reconHref(filters)); }} /> : null}
      {openRequest ? <RequestModal row={openRequest} initiates={initiates} decides={decides} onClose={() => setOpenRequest(null)}
        onChanged={() => { setOpenRequest(null); go(reconHref(filters)); }} /> : null}
    </>
  );
}

function RequestsTable({ rows, onOpen }: { rows: CreditRequestRow[]; onOpen: (r: CreditRequestRow) => void }) {
  return (
    <DTable pageSize={50} cols={["Request", "Student", "Legacy session", "Original (excess)|num", "Confirmed|num", "Account officer", "Status", "Bursar", "Action"]}
      texts={rows.map((r) => `${r.ref} ${r.student} ${r.matric_no ?? ""} ${r.jamb_reg_no ?? ""} ${r.status}`)}
      rows={rows.map((r) => [
        <span key="r" className="tnum b600">{r.ref}<div className="sub2">Overpaid school fees</div></span>,
        <span key="s"><b>{r.student}</b><div className="sub2 tnum">{r.matric_no ?? r.admission_no ?? "—"} · {r.programme ?? ""}</div></span>,
        <span key="ses" className="tnum">{r.session}</span>,
        <span key="l" className="tnum">{naira(r.legacy_amount)}</span>,
        <span key="c" className="tnum b600">{naira(r.confirmed_amount)}{r.adjusted ? <div><Pil kind="warn">Amount adjusted</Pil></div> : null}</span>,
        <span key="o" className="sub2">{r.initiated_by ?? r.initiated_office}<div className="tnum">{day(r.initiated_at)}{r.resubmissions ? ` · resubmitted ${day(r.resubmitted_at)}` : ""}</div></span>,
        <span key="st"><Pil kind={REQUEST_WORDS[r.status][1]}>{REQUEST_WORDS[r.status][0]}</Pil></span>,
        <span key="b" className="sub2">{r.decided_at ? <>{r.decided_by ?? ""}<div className="tnum">{day(r.decided_at)}</div></> : r.withdrawn_at ? `withdrawn by ${r.withdrawn_by ?? ""}` : "—"}</span>,
        <span key="a" className="row row--inline row--tight row--right"><Btn kind="ghost" size="sm" onClick={() => onOpen(r)}>Open</Btn><StudentOpen id={r.student_id} label="Record" kind="ghost" /></span>,
      ])} />
  );
}

/* ── one student: the legacy record in full, and the officer's confirmation ── */
function StudentModal({ row, initiates, session, onClose, onChanged }: { row: OutstandingRow; initiates: boolean; session: string; onClose: () => void; onChanged: () => void }) {
  const [pic, setPic] = useState<StudentPicture | null>(null);
  const [form, setForm] = useState({ amount: String(num(row.excess)), reason: "", evidence: "", adjust: "", confirmed: false });
  const [busy, setBusy] = useState(false);
  const [confirming, setConfirming] = useState(false);
  useEffect(() => {
    let on = true;
    (async () => {
      const r = await fetch(`${BASE}/students/${row.student_id}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (on) setPic(r.ok && j ? (j as StudentPicture) : null);
    })();
    return () => { on = false; };
  }, [row.student_id]);
  const excess = num(row.excess);
  const amount = Number(form.amount);
  const amountOk = Number.isFinite(amount) && amount >= 1 && amount <= excess;
  const adjusted = amountOk && amount !== excess;
  const canConfirm = row.state === "CREDIT" && initiates && !row.request_ref;
  const ready = canConfirm && amountOk && form.reason.trim().length >= 10 && form.evidence.trim().length >= 3 && (!adjusted || form.adjust.trim().length >= 10) && form.confirmed;
  async function submit() {
    setBusy(true);
    try {
      const r = await post<CreditRequestRow>("/requests", { student: row.student_id, session, amount, reason: form.reason, evidence: form.evidence, adjustmentReason: adjusted ? form.adjust : null, confirmed: form.confirmed },
        `Legacy credit request for ${row.matric_no ?? row.name}: ${naira(amount)} overpaid on ${session}`);
      if (r) { notify(`${r.ref} submitted to the Bursar: ${naira(r.confirmed_amount)} for ${row.name}. The wallet is not credited until the Bursar approves.`); onChanged(); }
    } finally { setBusy(false); setConfirming(false); }
  }
  return (
    <Modal wide title={row.name} sub={`${row.matric_no ?? row.admission_no ?? ""} · ${row.programme ?? ""} · ${session}`} onClose={onClose}
      foot={<>
        <Btn kind="ghost" onClick={onClose}>Close</Btn>
        {canConfirm ? <Btn kind="primary" disabled={!ready || busy} onClick={() => setConfirming(true)}>Confirm &amp; initiate wallet credit</Btn> : null}
      </>}>
      <div className="row" style={{ gap: "var(--s-3)", flexWrap: "wrap", marginBottom: "var(--s-3)" }}>
        <Pil kind={STATE_WORDS[row.state][1]}>{STATE_WORDS[row.state][0]}</Pil>
        <span className="sub2">{STATE_WORDS[row.state][2]}</span>
      </div>
      <div className="eyebrow">Student</div>
      <KvGrid cls="grid--3" pairs={[["Name", row.name], ["Matric number", row.matric_no ?? "—"], ["JAMB number", row.jamb_reg_no ?? "—"], ["Application number", row.admission_no ?? "—"],
        ["Faculty", row.faculty ?? row.faculty_code ?? "—"], ["Department", row.department ?? row.dept_code ?? "—"], ["Programme", row.programme ?? row.programme_code ?? "—"],
        ["Level in the session", row.level ? `${row.level} Level` : "—"], ["Current wallet balance", pic ? naira(pic.walletBalance) : "…"]]} />
      <div className="eyebrow" style={{ marginTop: "var(--s-3)" }}>Legacy financial record · {session}</div>
      <KvGrid cls="grid--3" pairs={[["Record type", "Outstanding fees (old portal)"], ["Legacy session", session], ["Source", "Old Fees History import"],
        ["Fees due (fee setup)", naira(row.due)], ["Paid, every confirmed payment", naira(row.paid)], ["Paid on the old portal", `${naira(num(row.paid_old_s1) + num(row.paid_old_s2) + num(row.paid_old_session))} (${row.old_payments})`],
        ["Student owes", naira(row.owed)], ["Credit held (paid above the fees)", naira(row.excess)], ["Doubles on the old records", row.doubles ? `${row.doubles} — withdraw them on Old Fees History first` : "None"],
        ["Legacy status", STATE_WORDS[row.state][0]], ["Decision", row.decision ? DECISION_WORDS[row.decision] ?? row.decision : "—"],
        ["Wallet credit", row.request_ref ? `${row.request_ref} · ${REQUEST_WORDS[row.request_status!]?.[0] ?? row.request_status}` : "Not yet requested"]]} />
      <div className="eyebrow" style={{ marginTop: "var(--s-3)" }}>Old-portal payments behind the figures</div>
      {pic ? (pic.payments.filter((p) => p.session === session).length ? <DTable pageSize={0} cols={["Date", "Purpose", "Channel", "Amount|num", "Reference", "Old reference"]}
        rows={pic.payments.filter((p) => p.session === session).map((p) => [day(p.confirmed_at), p.purpose, p.channel, <span key="a" className="tnum">{naira(p.amount)}</span>,
          <span key="r" className="tnum sub2">{p.reference}</span>, <span key="l" className="tnum sub2">{p.legacy_payref ?? "—"}</span>])} />
        : <div className="sub2">None on file for this session.</div>) : <div className="sub2">Reading…</div>}
      {pic && pic.sessions.length > 1 ? (
        <>
          <div className="eyebrow" style={{ marginTop: "var(--s-3)" }}>Every session with school-fees payments</div>
          <DTable pageSize={0} cols={["Session", "Due|num", "Paid|num", "Owes|num", "Credit|num", "Decision"]}
            rows={pic.sessions.map((x) => [<span key="s" className="tnum">{x.session}</span>, <span key="d" className="tnum">{naira(x.due)}</span>, <span key="p" className="tnum">{naira(x.paid)}</span>,
              <span key="o" className={`tnum${num(x.owed) > 0 ? " ink-red" : ""}`}>{naira(x.owed)}</span>, <span key="e" className="tnum">{naira(x.excess)}</span>,
              <span key="x" className="sub2">{x.decision ? `${DECISION_WORDS[x.decision] ?? x.decision} · ${x.decision_reference ?? ""}` : "—"}</span>])} />
        </>
      ) : null}
      {pic?.requests.length ? (
        <>
          <div className="eyebrow" style={{ marginTop: "var(--s-3)" }}>Wallet credit requests</div>
          <DTable pageSize={0} cols={["Request", "Session", "Confirmed|num", "Status", "Officer", "Bursar"]}
            rows={pic.requests.map((r) => [<span key="r" className="tnum">{r.ref}</span>, r.session, <span key="c" className="tnum">{naira(r.confirmed_amount)}</span>,
              <Pil key="s" kind={REQUEST_WORDS[r.status][1]}>{REQUEST_WORDS[r.status][0]}</Pil>, `${r.initiated_by ?? ""} · ${day(r.initiated_at)}`, r.decided_at ? `${r.decided_by ?? ""} · ${day(r.decided_at)}` : "—"])} />
        </>
      ) : null}
      {row.state === "OWES" ? (
        <Note kind="bad" title="Student owes the University">
          This record is an outstanding fee payable by the student: {naira(row.owed)} stays on the student&rsquo;s account as a liability. It is never credited to the wallet.
        </Note>
      ) : null}
      {canConfirm ? (
        <>
          <div className="eyebrow" style={{ marginTop: "var(--s-3)" }}>Confirm the legacy record</div>
          <KvGrid cls="grid--4" pairs={[["Original amount", naira(row.excess)], ["Already used", "—"], ["Eligible amount", naira(row.excess)], ["Amount to credit", amountOk ? naira(amount) : "—"]]} />
          <div className="grid grid--2">
            <Field id="lc-amount" label="Confirmed amount" hint={`Up to ${naira(row.excess)}, the excess the records show`} required>
              <input id="lc-amount" className="ctl tnum" inputMode="decimal" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} /></Field>
            <Field id="lc-evidence" label="Supporting evidence or reference" hint="The old portal's statement, the receipt, the export row" required>
              <input id="lc-evidence" className="ctl" value={form.evidence} onChange={(e) => setForm({ ...form, evidence: e.target.value })} /></Field>
          </div>
          {adjusted ? (
            <Field id="lc-adjust" label="Reason for the difference" hint="The amount differs from the excess the records show; the request is marked AMOUNT ADJUSTED for the Bursar" required full>
              <input id="lc-adjust" className="ctl" value={form.adjust} onChange={(e) => setForm({ ...form, adjust: e.target.value })} /></Field>
          ) : null}
          <Field id="lc-reason" label="Confirmation reason or remarks" hint="Ten characters or more; the Bursar reads it" required full>
            <input id="lc-reason" className="ctl" value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} /></Field>
          <label className="row row--inline row--tight" style={{ alignItems: "flex-start", gap: 8 }}>
            <input type="checkbox" checked={form.confirmed} onChange={(e) => setForm({ ...form, confirmed: e.target.checked })} />
            <span>I confirm that the legacy record and amount have been reviewed against the available records and that the amount entered is correct.</span>
          </label>
        </>
      ) : null}
      {confirming ? (
        <Modal title="Confirm legacy financial record" sub={`${row.name} · ${session}`} onClose={() => setConfirming(false)}
          foot={<><Btn kind="primary" busy={busy} busyLabel="Submitting for Bursar approval…" disabled={busy} onClick={submit}>Confirm &amp; submit</Btn><Btn kind="ghost" disabled={busy} onClick={() => setConfirming(false)}>Cancel</Btn></>}>
          <KvGrid cls="grid--2" pairs={[["Student", row.name], ["Legacy type", "Outstanding fees: credit held (overpaid school fees)"], ["Legacy amount", naira(row.excess)], ["Eligible", naira(row.excess)],
            ["Amount to credit", naira(amount)], ["Adjusted", adjusted ? `Yes: ${form.adjust}` : "No"], ["Evidence", form.evidence], ["Reason", form.reason]]} />
          <Note kind="bad" title="Nothing is credited yet">
            Once submitted, this record goes to the Bursar for approval. The student&rsquo;s wallet will NOT be credited until a Bursar officer other than you approves it.
          </Note>
        </Modal>
      ) : null}
    </Modal>
  );
}

/* ── one request: the Bursar's decision, or the officer's correction ── */
function RequestModal({ row, initiates, decides, onClose, onChanged }: { row: CreditRequestRow; initiates: boolean; decides: boolean; onClose: () => void; onChanged: () => void }) {
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [approving, setApproving] = useState(false);
  const [fix, setFix] = useState({ amount: String(num(row.confirmed_amount)), reason: row.reason, evidence: row.evidence, adjust: row.adjustment_reason ?? "", confirmed: false });
  const pending = row.status === "PENDING_BURSAR_APPROVAL";
  const returned = row.status === "RETURNED_FOR_CORRECTION";
  const excess = num(row.legacy_amount);
  const fixAmount = Number(fix.amount);
  const fixOk = Number.isFinite(fixAmount) && fixAmount >= 1 && fixAmount <= excess && fix.reason.trim().length >= 10 && fix.evidence.trim().length >= 3 && (fixAmount === excess || fix.adjust.trim().length >= 10) && fix.confirmed;
  async function decide(action: "APPROVE" | "REJECT" | "RETURN") {
    setBusy(action);
    try {
      const r = await post<CreditRequestRow>(`/requests/${row.id}/decide`, { action, note }, `Legacy credit ${row.ref} ${action.toLowerCase()}: ${row.matric_no ?? row.student}`);
      if (r) {
        notify(action === "APPROVE" ? `${naira(r.confirmed_amount)} has been credited to ${row.student}'s wallet (${r.wallet_reference ?? r.ref}).` : action === "REJECT" ? `${r.ref} rejected; no financial change was made.` : `${r.ref} returned to the officer for correction.`);
        onChanged();
      }
    } finally { setBusy(null); setApproving(false); }
  }
  async function resubmit() {
    setBusy("resubmit");
    try {
      const r = await post<CreditRequestRow>(`/requests/${row.id}/resubmit`, { amount: fixAmount, reason: fix.reason, evidence: fix.evidence, adjustmentReason: fixAmount === excess ? null : fix.adjust, confirmed: fix.confirmed },
        `Legacy credit ${row.ref} resubmitted: ${naira(fixAmount)}`);
      if (r) { notify(`${r.ref} resubmitted to the Bursar.`); onChanged(); }
    } finally { setBusy(null); }
  }
  async function withdraw() {
    setBusy("withdraw");
    try {
      const r = await post<CreditRequestRow>(`/requests/${row.id}/withdraw`, { reason: note }, `Legacy credit ${row.ref} withdrawn`);
      if (r) { notify(`${r.ref} withdrawn.`); onChanged(); }
    } finally { setBusy(null); }
  }
  return (
    <Modal wide title={`${row.ref} · ${row.student}`} sub={`${row.matric_no ?? row.admission_no ?? ""} · ${row.programme ?? ""}`} onClose={onClose}
      foot={<>
        <Btn kind="ghost" onClick={onClose}>Close</Btn>
        {initiates && (pending || returned) ? <Btn kind="ghost" busy={busy === "withdraw"} busyLabel="Withdrawing…" disabled={!!busy || note.trim().length < 10} onClick={withdraw}>Withdraw</Btn> : null}
        {decides && pending ? <Btn kind="ghost" busy={busy === "RETURN"} busyLabel="Returning…" disabled={!!busy || note.trim().length < 10} onClick={() => decide("RETURN")}>Return for correction</Btn> : null}
        {decides && pending ? <Btn kind="ghost" busy={busy === "REJECT"} busyLabel="Rejecting…" disabled={!!busy || note.trim().length < 10} onClick={() => decide("REJECT")}>Reject</Btn> : null}
        {decides && pending ? <Btn kind="primary" disabled={!!busy} onClick={() => setApproving(true)}>Approve &amp; credit wallet</Btn> : null}
        {initiates && returned ? <Btn kind="primary" busy={busy === "resubmit"} busyLabel="Resubmitting…" disabled={!!busy || !fixOk} onClick={resubmit}>Resubmit to the Bursar</Btn> : null}
      </>}>
      <div className="row" style={{ gap: "var(--s-3)", flexWrap: "wrap", marginBottom: "var(--s-3)" }}>
        <Pil kind={REQUEST_WORDS[row.status][1]}>{REQUEST_WORDS[row.status][0]}</Pil>
        {row.adjusted ? <Pil kind="warn">Amount adjusted</Pil> : null}
      </div>
      <div className="eyebrow">Legacy wallet credit approval</div>
      <KvGrid cls="grid--3" pairs={[["Student", row.student], ["Matric", row.matric_no ?? row.admission_no ?? "—"], ["Record type", "Overpaid school fees (old portal)"],
        ["Legacy reference", row.session], ["Fees due", naira(row.due)], ["Paid", naira(row.paid)],
        ["Original amount (excess)", naira(row.legacy_amount)], ["Previously used", "—"], ["Eligible amount", naira(row.legacy_amount)],
        ["Student Account Officer", `${row.initiated_by ?? ""} (${row.initiated_office})`], ["Confirmation date", `${day(row.initiated_at)}${row.resubmissions ? ` · resubmitted ${day(row.resubmitted_at)} (${row.resubmissions})` : ""}`], ["Requested wallet credit", naira(row.confirmed_amount)],
        ["Officer remarks", row.reason], ["Evidence", row.evidence], ["Reason for the adjusted amount", row.adjustment_reason ?? "—"],
        ["Bursar", row.decided_at ? `${row.decided_by ?? ""} (${row.decided_office ?? ""}) · ${day(row.decided_at)}` : "—"], ["Decision note", row.decision_note ?? row.withdraw_reason ?? "—"],
        ["Wallet", row.wallet_reference ? `${row.wallet_reference} · ${day(row.credited_at)} · balance after ${naira(row.balance_after)}` : "Not yet credited"]]} />
      {decides && pending ? <Field id="lr-note" label="Decision note (required to reject or return)" full><input id="lr-note" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} /></Field> : null}
      {initiates && !decides && (pending || returned) ? <Field id="lr-wnote" label="Reason to withdraw" full><input id="lr-wnote" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} /></Field> : null}
      {initiates && returned ? (
        <>
          <div className="eyebrow" style={{ marginTop: "var(--s-3)" }}>Correct and resubmit</div>
          <div className="grid grid--2">
            <Field id="lf-amount" label="Confirmed amount" hint={`Up to ${naira(row.legacy_amount)}`} required><input id="lf-amount" className="ctl tnum" inputMode="decimal" value={fix.amount} onChange={(e) => setFix({ ...fix, amount: e.target.value })} /></Field>
            <Field id="lf-evidence" label="Supporting evidence or reference" required><input id="lf-evidence" className="ctl" value={fix.evidence} onChange={(e) => setFix({ ...fix, evidence: e.target.value })} /></Field>
          </div>
          {Number.isFinite(fixAmount) && fixAmount !== excess ? <Field id="lf-adjust" label="Reason for the difference" required full><input id="lf-adjust" className="ctl" value={fix.adjust} onChange={(e) => setFix({ ...fix, adjust: e.target.value })} /></Field> : null}
          <Field id="lf-reason" label="Confirmation reason or remarks" required full><input id="lf-reason" className="ctl" value={fix.reason} onChange={(e) => setFix({ ...fix, reason: e.target.value })} /></Field>
          <label className="row row--inline row--tight" style={{ alignItems: "flex-start", gap: 8 }}>
            <input type="checkbox" checked={fix.confirmed} onChange={(e) => setFix({ ...fix, confirmed: e.target.checked })} />
            <span>I confirm that the legacy record and amount have been reviewed against the available records and that the amount entered is correct.</span>
          </label>
        </>
      ) : null}
      {approving ? (
        <Modal title="Approve wallet credit" sub={row.ref} onClose={() => setApproving(false)}
          foot={<><Btn kind="primary" busy={busy === "APPROVE"} busyLabel="Processing wallet credit…" disabled={!!busy} onClick={() => decide("APPROVE")}>Approve &amp; credit wallet</Btn><Btn kind="ghost" disabled={!!busy} onClick={() => setApproving(false)}>Cancel</Btn></>}>
          <KvGrid cls="grid--2" pairs={[["Student", row.student], ["Amount", naira(row.confirmed_amount)], ["Legacy reference", row.session], ["Account officer", row.initiated_by ?? row.initiated_office]]} />
          <Note kind="info" title="After approval">The approved amount will be credited to the student&rsquo;s wallet, once, as the student&rsquo;s own money; the student is told. If anything fails, no financial change is made.</Note>
        </Modal>
      ) : null}
    </Modal>
  );
}
