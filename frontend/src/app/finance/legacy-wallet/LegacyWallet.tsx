"use client";

/**
 * The old portal's e-wallet reconciled (V583). The figures: top-ups and wallet-paid fees as the old-fees export brought them, the
 * balances computed, verified, posted, applied to fees and left, the records under review. The rows: one a student who topped up
 * the old wallet, with how the balance was arrived at and the officer's steps — verify (Students Account Officer or Bursar), post
 * to the wallet (a Bursar officer other than the verifier), enter the old portal's own statement for a student, reject, freeze,
 * reopen. The report, S/N first. The server holds every rule and works out every figure; nothing here is a balance.
 */
import { useEffect, useState } from "react";
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
import { REASON_WORDS, REPORT_HEADERS, STATUS_WORDS, balanceWords, legacyWalletHref, num, reportRows, type LegacyWalletFigures, type LegacyWalletRow, type LegacyWalletStatus } from "@/lib/legacy-wallet";

const BASE = "/api/bff/api/v1/finance/legacy-wallet";
const naira = (v: unknown) => `₦${num(v).toLocaleString("en-GB", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const n = (v: unknown) => Number(v ?? 0).toLocaleString("en-GB");

async function post<T>(path: string, body: unknown, reason: string): Promise<T | null> {
  const r = await fetch(`${BASE}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return null; }
  return j as T;
}

type Unit = { faculty_code: string; faculty: string; dept_code: string; department: string };

export function LegacyWallet({ figures, rows, rowsProblem, structure, filters, actingOffice, generatedBy }: {
  figures: LegacyWalletFigures; rows: LegacyWalletRow[]; rowsProblem: Problem | null; structure: Unit[]; filters: Record<string, string>;
  actingOffice: string | null; generatedBy: string | null;
}) {
  const go = useQueryNav();
  const nav = (c: Record<string, string>) => go(legacyWalletHref({ ...filters, ...c }));
  const verifies = ["bursar", "studentaccounts", "super"].includes(actingOffice ?? "");
  const posts = ["bursar", "super"].includes(actingOffice ?? "");
  const [chosen, setChosen] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState<string | null>(null);
  const [open, setOpen] = useState<LegacyWalletRow | null>(null);
  const [posting, setPosting] = useState(false);
  // V625: the verification is confirmed in a window that shows the figures, never by one click
  const [verifying, setVerifying] = useState(false);
  const faculties = Array.from(new Map(structure.map((u) => [u.faculty_code, u.faculty])).entries());
  const departments = structure.filter((u) => !filters.fac || u.faculty_code === filters.fac);
  const title = "Legacy wallet report";
  const scopeWords = [filters.status ? STATUS_WORDS[filters.status as LegacyWalletStatus]?.[0] : "", filters.fac ? faculties.find(([c]) => c === filters.fac)?.[1] ?? filters.fac : "",
    filters.dept ? departments.find((u) => u.dept_code === filters.dept)?.department ?? filters.dept : ""].filter(Boolean).join(" · ") || "Every student";
  const selectable = rows.filter((r) => chosen.has(r.id));
  const toVerify = selectable.filter((r) => ["COMPUTED", "RETURNED"].includes(r.status) && num(r.available) > 0);
  const toPost = selectable.filter((r) => r.status === "VERIFIED");

  async function compute() {
    setBusy("compute");
    try {
      const r = await post<{ students: number; with_balance: number; review: number; no_balance: number; posted: number; available: number }>("/compute", {}, "Old e-wallet reconciliation run");
      if (r) { notify(`${n(r.students)} students read: ${n(r.with_balance)} with a balance (${naira(r.available)}), ${n(r.review)} to review, ${n(r.no_balance)} with nothing left`); go(legacyWalletHref(filters)); }
    } finally { setBusy(null); }
  }
  async function verify(note: string) {
    setBusy("verify");
    try {
      const r = await post<{ verified: number; asked: number }>("/verify", { ids: toVerify.map((x) => x.id), note }, `Old e-wallet balances verified: ${toVerify.length}`);
      if (r) { notify(`${n(r.verified)} of ${n(r.asked)} verified and sent to the Bursar for posting`); setChosen(new Set()); setVerifying(false); go(legacyWalletHref(filters)); }
    } finally { setBusy(null); }
  }

  return (
    <>
      <Tiles items={[
        ["Students with old top-ups", n(figures.students), null, `${n(figures.topupCount)} top-ups · ${naira(figures.topups)}`, legacyWalletHref({ ...filters, status: "" })],
        ["Paid from the old wallet", naira(figures.used), null, `${n(figures.orphanStudents)} other students paid ${naira(figures.orphanAmount)} with no top-up on file`],
        ["To verify", n(figures.computed), figures.computed ? "var(--amber-ink)" : null, `${naira(figures.computedAmount)} computed`, legacyWalletHref({ ...filters, status: "COMPUTED" })],
        ["To post", n(figures.verified), figures.verified ? "var(--amber-ink)" : null, `${naira(figures.verifiedAmount)} verified`, legacyWalletHref({ ...filters, status: "VERIFIED" })],
        ["Posted to the wallet", n(figures.posted), "var(--green-ink)", `${naira(figures.postedAmount)} credited · ${naira(figures.applied)} applied to fees · ${naira(figures.remaining)} still on the wallet`, legacyWalletHref({ ...filters, status: "POSTED" })],
        ["Returned for correction", n(figures.returned ?? 0), figures.returned ? "var(--red-ink)" : null, `${naira(figures.returnedAmount ?? 0)} to correct and verify again`, legacyWalletHref({ ...filters, status: "RETURNED" })],
        ["Requires review", n(figures.review), figures.review ? "var(--red-ink)" : null, `${naira(figures.reviewUsed)} paid beyond the top-ups on file · ${n(figures.differs)} statements differ · ${n(figures.changed)} changed since`, legacyWalletHref({ ...filters, status: "REQUIRES_REVIEW" })],
        ["No balance", n(figures.noBalance), null, `${n(figures.rejected)} rejected · ${n(figures.frozen)} frozen`, legacyWalletHref({ ...filters, status: "NO_BALANCE" })],
        ["Last reconciliation", figures.lastComputed ? day(figures.lastComputed) : "Not yet", null, figures.lastComputed ? new Date(figures.lastComputed).toLocaleTimeString("en-GB") : "Run it to read the imported payments"],
      ]} cls="grid--4" />

      <Panel title="Old e-wallet balances" right={`${n(rows.length)} listed`}>
        <PBody>
          <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
            <Field id="lw-q" label="Search" style={{ flex: "2 1 220px" }}>
              <input id="lw-q" className="ctl" type="search" defaultValue={filters.q ?? ""} placeholder="Name, matriculation, JAMB number, batch or old reference"
                onKeyDown={(e) => { if (e.key === "Enter") nav({ q: (e.target as HTMLInputElement).value }); }} />
            </Field>
            <Field id="lw-status" label="Status" style={{ flex: "0 1 190px" }}>
              <select id="lw-status" className="ctl" value={filters.status ?? ""} onChange={(e) => nav({ status: e.target.value })}>
                <option value="">Any</option>
                {(Object.keys(STATUS_WORDS) as LegacyWalletStatus[]).map((k) => <option key={k} value={k}>{STATUS_WORDS[k][0]}</option>)}
              </select>
            </Field>
            <Field id="lw-fac" label="Faculty" style={{ flex: "1 1 180px" }}>
              <SearchSelect id="lw-fac" value={filters.fac ?? ""} onChange={(v) => nav({ fac: v, dept: "" })} allLabel="Any faculty" options={faculties.map(([c, l]) => ({ value: c, label: l }))} />
            </Field>
            <Field id="lw-dept" label="Department" style={{ flex: "1 1 200px" }}>
              <SearchSelect id="lw-dept" value={filters.dept ?? ""} onChange={(v) => nav({ dept: v })} allLabel="Any department" options={departments.map((u) => ({ value: u.dept_code, label: u.department }))} />
            </Field>
            {Object.keys(filters).length ? <Btn kind="ghost" onClick={() => go(legacyWalletHref({}))}>Clear</Btn> : null}
            <span className="grow" />
            {verifies ? <Btn kind="secondary" busy={busy === "compute"} busyLabel="Reconciling…" disabled={!!busy} onClick={compute} title="Read the imported old-portal payments again: every student's top-ups and wallet-paid fees">Run the reconciliation</Btn> : null}
          </div>
          <div className="row mt-2" style={{ flexWrap: "wrap", gap: "var(--s-3)" }}>
            {verifies ? <Btn kind="primary" size="sm" disabled={!toVerify.length || !!busy} onClick={() => setVerifying(true)}>Verify selected ({toVerify.length})</Btn> : null}
            {posts ? <Btn kind="primary" size="sm" disabled={!toPost.length || !!busy} onClick={() => setPosting(true)}>Post selected to the wallet ({toPost.length})</Btn> : null}
            <Btn kind="ghost" size="sm" busy={busy === "excel"} busyLabel="Preparing…" disabled={!rows.length} onClick={async () => {
              setBusy("excel");
              try { downloadBlob(await brandedXlsx(title, REPORT_HEADERS, reportRows(rows), { sheetName: "Legacy wallet", serial: docSerial("LWR"), sub: scopeWords, meta: [["Filters", scopeWords], ["Rows", String(rows.length)]] }), "legacy-wallet-report.xlsx"); }
              finally { setBusy(null); }
            }}>Download Excel</Btn>
            <Btn kind="ghost" size="sm" disabled={!rows.length} onClick={() => brandedPrint(title, scopeWords, REPORT_HEADERS, reportRows(rows), docSerial("LWR"), { meta: [["Filters", scopeWords]], generatedBy, orientation: "landscape" })}>Download PDF</Btn>
          </div>
        </PBody>
        {rowsProblem ? <ProblemNotice problem={rowsProblem} /> : null}
        {rows.length ? (
          <DTable pageSize={50} cols={[...(verifies ? ["|mid"] : []), "Student", "Top-ups|num", "Paid from it|num", "Balance|num", "How", "Status", "On the wallet", "Action"]}
            texts={rows.map((r) => `${r.student} ${r.matric_no ?? ""} ${r.jamb_reg_no ?? ""} ${r.batch_ref ?? ""} ${r.status}`)}
            rows={rows.map((r) => [
              ...(verifies ? [<input key="c" type="checkbox" className="pchk" aria-label={`Select ${r.student}`} checked={chosen.has(r.id)} disabled={!["COMPUTED", "VERIFIED", "RETURNED"].includes(r.status)}
                onChange={(e) => setChosen((s) => { const t = new Set(s); if (e.target.checked) t.add(r.id); else t.delete(r.id); return t; })} />] : []),
              <span key="s"><b>{r.student}</b><div className="sub2 tnum">{r.matric_no ?? r.jamb_reg_no ?? "—"} · {r.programme ?? ""}</div></span>,
              <span key="t" className="tnum">{naira(r.topups)}<div className="sub2">{r.topup_count} · last {day(r.last_topup_at)}</div></span>,
              <span key="u" className="tnum">{naira(r.used)}<div className="sub2">{r.used_count} payment{r.used_count === 1 ? "" : "s"}</div></span>,
              <span key="a" className={`tnum b600${num(r.available) > 0 ? "" : " sub2"}`}>{naira(r.available)}</span>,
              <span key="h" className="sub2">{r.stated_balance != null ? `Old portal statement (${r.stated_source})` : "Top-ups − paid"}{r.reason_code ? <div className="ink-red">{REASON_WORDS[r.reason_code] ?? r.reason_code}</div> : null}</span>,
              <span key="st"><Pil kind={STATUS_WORDS[r.status][1]}>{STATUS_WORDS[r.status][0]}</Pil>
                <div className="sub2">{r.status === "VERIFIED" ? `by ${r.verified_by ?? r.verified_office} · ${day(r.verified_at)}` : r.status === "POSTED" ? `${r.batch_ref} · ${day(r.posted_at)}` : r.decided_at ? `${r.decided_by ?? ""} · ${day(r.decided_at)}` : ""}</div></span>,
              <span key="w" className="tnum sub2">{r.status === "POSTED" ? `${naira(r.applied)} applied · ${naira(r.remaining)} left` : "—"}</span>,
              <span key="x" className="row row--inline row--tight row--right"><Btn kind="ghost" size="sm" onClick={() => setOpen(r)}>Open</Btn><StudentOpen id={r.student_id} label="Record" kind="ghost" /></span>,
            ])} />
        ) : <PBody><div className="sub2">{figures.lastComputed ? "No student matches the filters." : "Run the reconciliation to read the imported old-portal payments."}</div></PBody>}
        <PBody>
          <Note kind="info" title="How a balance is read">
            A top-up is a payment the old-fees export brought with the purpose <b>E-WALLET TOP-UP</b>; a fee paid from the old wallet is one whose method reads <b>E-Wallet</b>.
            Top-ups less what was paid from the wallet is the balance — computed, never trusted: one officer verifies it, another Bursar officer posts it to the wallet as the
            student&rsquo;s own money, once. Where a student paid from the old wallet more than the top-ups on file, the old wallet held money the export does not show, and nothing
            is posted until the old portal&rsquo;s own statement for the student is entered. On the ledger the credit is drawn from Opening balance / suspense (3900), as every
            old-portal credit is; the Bursary settles it from Accounting &rarr; Wallet opening.
          </Note>
        </PBody>
      </Panel>

      {figures.batches.length ? (
        <Panel title="Postings">
          <DTable pageSize={0} cols={["Batch", "Posted", "Students|num", "Amount|num", "Skipped|num", "By"]}
            rows={figures.batches.map((b) => [<span key="r" className="tnum">{b.ref}</span>, day(b.posted_at), n(b.students), naira(b.amount), n(b.skipped), `${b.posted_by ?? ""} (${b.office ?? ""})`])} />
        </Panel>
      ) : null}

      {open ? <RowModal row={open} verifies={verifies} posts={posts} onClose={() => setOpen(null)} onChanged={() => { setOpen(null); go(legacyWalletHref(filters)); }} /> : null}
      {posting ? <PostModal rows={toPost} onClose={() => setPosting(false)} onDone={() => { setPosting(false); setChosen(new Set()); go(legacyWalletHref({ ...filters, status: "POSTED" })); }} /> : null}
      {verifying ? <VerifyModal rows={toVerify} busy={busy === "verify"} onClose={() => setVerifying(false)} onConfirm={verify} /> : null}
    </>
  );
}

/* ── one student: the payments behind the figures, the old portal's statement, the decision ── */

function RowModal({ row, verifies, posts, onClose, onChanged }: { row: LegacyWalletRow; verifies: boolean; posts: boolean; onClose: () => void; onChanged: () => void }) {
  const [stmt, setStmt] = useState({ topups: "", used: "", refunds: "", reversed: "", balance: "", source: "", note: "" });
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [detail, setDetail] = useState<{ payments: Record<string, unknown>[]; wallet: Record<string, unknown>[] } | null>(null);
  const live = !["POSTED", "REJECTED", "FROZEN"].includes(row.status);
  // the payments behind the figures, read when the window opens
  useEffect(() => {
    let on = true;
    (async () => {
      const r = await fetch(`${BASE}/students/${row.student_id}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (on) setDetail(r.ok && j ? j : { payments: [], wallet: [] });
    })();
    return () => { on = false; };
  }, [row.student_id]);
  async function statement() {
    setBusy("stmt");
    try {
      const r = await post(`/students/${row.student_id}/statement`, { topups: stmt.topups || null, used: stmt.used || null, refunds: stmt.refunds || null, reversed: stmt.reversed || null,
        balance: stmt.balance, source: stmt.source, note: stmt.note }, `Old portal wallet statement entered for ${row.matric_no ?? row.student}`);
      if (r) { notify("Statement entered: the balance now rests on it; verify it afresh"); onChanged(); }
    } finally { setBusy(null); }
  }
  async function decide(action: "REJECT" | "FREEZE" | "REOPEN" | "RETURN") {
    setBusy(action);
    try {
      const r = await post(`/${row.id}/decide`, { action, reason }, `Old e-wallet ${action.toLowerCase()}: ${row.matric_no ?? row.student}`);
      if (r) { notify(`${action === "REJECT" ? "Rejected" : action === "FREEZE" ? "Frozen" : action === "RETURN" ? "Returned to the officer for correction" : "Reopened"}`); onChanged(); }
    } finally { setBusy(null); }
  }
  return (
    <Modal wide title={row.student} sub={`${row.matric_no ?? row.jamb_reg_no ?? ""} · ${row.programme ?? ""}`} onClose={onClose}
      foot={<>
        <Btn kind="ghost" onClick={onClose}>Close</Btn>
        {posts && row.status === "VERIFIED" ? <Btn kind="ghost" busy={busy === "RETURN"} busyLabel="Returning…" disabled={!!busy || reason.trim().length < 10} onClick={() => decide("RETURN")}>Return for correction</Btn> : null}
        {posts && live ? <Btn kind="ghost" busy={busy === "FREEZE"} busyLabel="Freezing…" disabled={!!busy || reason.trim().length < 10} onClick={() => decide("FREEZE")}>Freeze</Btn> : null}
        {posts && live ? <Btn kind="ghost" busy={busy === "REJECT"} busyLabel="Rejecting…" disabled={!!busy || reason.trim().length < 10} onClick={() => decide("REJECT")}>Reject</Btn> : null}
        {posts && ["REJECTED", "FROZEN"].includes(row.status) ? <Btn kind="primary" busy={busy === "REOPEN"} busyLabel="Reopening…" disabled={!!busy || reason.trim().length < 10} onClick={() => decide("REOPEN")}>Reopen</Btn> : null}
      </>}>
      <div className="row" style={{ gap: "var(--s-3)", flexWrap: "wrap", marginBottom: "var(--s-3)" }}>
        <Pil kind={STATUS_WORDS[row.status][1]}>{STATUS_WORDS[row.status][0]}</Pil>
        {row.reason_code ? <Pil kind="bad">{REASON_WORDS[row.reason_code] ?? row.reason_code}</Pil> : null}
        <span className="sub2">{balanceWords(row)}</span>
      </div>
      <KvGrid cls="grid--3" pairs={[["Top-ups on file", `${naira(row.topups)} (${row.topup_count})`], ["Paid from the old wallet", `${naira(row.used)} (${row.used_count})`], ["Balance", naira(row.available)],
        ["Last top-up", row.last_topup_at ? `${day(row.last_topup_at)} · ${row.last_topup_ref ?? ""}` : "—"], ["Session", row.session ?? "—"],
        ["Verified", row.verified_at ? `${row.verified_by ?? ""} (${row.verified_office}) · ${day(row.verified_at)}${row.verify_note ? ` · ${row.verify_note}` : ""}` : "—"],
        ["Posted", row.posted_at ? `${row.posted_by ?? ""} (${row.posted_office}) · ${day(row.posted_at)} · ${row.batch_ref}` : "—"],
        ["On the wallet", row.status === "POSTED" ? `${row.wallet_reference} · ${naira(row.applied)} applied · ${naira(row.refunded)} refunded · ${naira(row.remaining)} left` : "—"],
        ["Decision", row.decided_at ? `${row.decided_by ?? ""} · ${day(row.decided_at)} · ${row.decision_note ?? ""}` : "—"]]} />
      {row.reason ? <Note kind="info" title="Finding">{row.reason}</Note> : null}
      <div className="eyebrow" style={{ marginTop: "var(--s-3)" }}>The old portal&rsquo;s payments behind the figures</div>
      {detail ? (detail.payments.length ? <DTable pageSize={0} cols={["Date", "Purpose", "Method", "Amount|num", "Reference"]}
        rows={detail.payments.map((p) => [day(String(p.confirmed_at)), <span key="p">{String(p.purpose)}{p.topup ? <> <Pil kind="ok">Top-up</Pil></> : null}</span>, String(p.method ?? "—"),
          <span key="a" className="tnum">{naira(p.amount)}</span>, <span key="r" className="tnum sub2">{String(p.reference)}</span>])} />
        : <div className="sub2">None on file.</div>) : <div className="sub2">Reading…</div>}
      {row.stated_balance != null ? (
        <Note kind="info" title={`The old portal's statement, entered by ${row.stated_by ?? ""} on ${day(row.stated_at)} (${row.stated_source})`}>
          Top-ups {naira(row.stated_topups)}, used {naira(row.stated_used)}, refunds {naira(row.stated_refunds)}, reversed {naira(row.stated_reversed)}, balance <b>{naira(row.stated_balance)}</b>.{row.stated_note ? ` ${row.stated_note}` : ""}
        </Note>
      ) : null}
      {verifies && live ? (
        <>
          <div className="eyebrow" style={{ marginTop: "var(--s-3)" }}>Enter the old portal&rsquo;s own statement (it governs the balance)</div>
          <div className="grid grid--3">
            <Field id="st-t" label="Top-ups"><input id="st-t" className="ctl" inputMode="decimal" value={stmt.topups} onChange={(e) => setStmt({ ...stmt, topups: e.target.value })} /></Field>
            <Field id="st-u" label="Used"><input id="st-u" className="ctl" inputMode="decimal" value={stmt.used} onChange={(e) => setStmt({ ...stmt, used: e.target.value })} /></Field>
            <Field id="st-b" label="Balance the old portal states" required><input id="st-b" className="ctl" inputMode="decimal" value={stmt.balance} onChange={(e) => setStmt({ ...stmt, balance: e.target.value })} /></Field>
            <Field id="st-r" label="Refunds"><input id="st-r" className="ctl" inputMode="decimal" value={stmt.refunds} onChange={(e) => setStmt({ ...stmt, refunds: e.target.value })} /></Field>
            <Field id="st-v" label="Reversed"><input id="st-v" className="ctl" inputMode="decimal" value={stmt.reversed} onChange={(e) => setStmt({ ...stmt, reversed: e.target.value })} /></Field>
            <Field id="st-s" label="Read from" hint="The old portal's wallet page, its export, a printout" required><input id="st-s" className="ctl" value={stmt.source} onChange={(e) => setStmt({ ...stmt, source: e.target.value })} /></Field>
          </div>
          <Field id="st-n" label="Note" full><input id="st-n" className="ctl" value={stmt.note} onChange={(e) => setStmt({ ...stmt, note: e.target.value })} /></Field>
          <Btn kind="secondary" size="sm" busy={busy === "stmt"} busyLabel="Saving the statement…" disabled={!!busy || !stmt.balance || stmt.source.trim().length < 3} onClick={statement}>Enter the statement</Btn>
        </>
      ) : null}
      {posts ? <Field id="lw-reason" label="Reason (to reject, freeze, return for correction or reopen)" full><input id="lw-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} /></Field> : null}
    </Modal>
  );
}

/* ── V625: the verification confirmed — the figures in front of the officer, the explicit confirmation, the remarks ── */
function VerifyModal({ rows, busy, onClose, onConfirm }: { rows: LegacyWalletRow[]; busy: boolean; onClose: () => void; onConfirm: (note: string) => void }) {
  const [note, setNote] = useState("");
  const [confirmed, setConfirmed] = useState(false);
  const total = rows.reduce((a, r) => a + num(r.available), 0);
  return (
    <Modal wide title={`Confirm ${rows.length} old e-wallet balance${rows.length === 1 ? "" : "s"}`} sub={`${naira(total)} to send to the Bursar for posting`} onClose={onClose}
      foot={<><Btn kind="primary" busy={busy} busyLabel="Confirming…" disabled={busy || !confirmed} onClick={() => onConfirm(note)}>Confirm &amp; send to the Bursar</Btn><Btn kind="ghost" disabled={busy} onClick={onClose}>Cancel</Btn></>}>
      <DTable pageSize={0} cols={["Student", "Original top-ups|num", "Already used|num", "Eligible balance|num", "Amount to credit|num", "How"]}
        rows={rows.map((r) => [<span key="s"><b>{r.student}</b><div className="sub2 tnum">{r.matric_no ?? r.jamb_reg_no ?? ""}</div></span>,
          <span key="t" className="tnum">{naira(r.stated_balance != null ? r.stated_topups : r.topups)}</span>, <span key="u" className="tnum">{naira(r.stated_balance != null ? r.stated_used : r.used)}</span>,
          <span key="e" className="tnum">{naira(r.available)}</span>, <span key="a" className="tnum b600">{naira(r.available)}</span>,
          <span key="h" className="sub2">{r.stated_balance != null ? `The old portal's statement (${r.stated_source})` : "Top-ups less what was paid from the old wallet"}</span>])} />
      <Field id="lv-note" label="Confirmation remarks" hint="What the balances were checked against; the Bursar reads it" full><input id="lv-note" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      <label className="row row--inline row--tight" style={{ alignItems: "flex-start", gap: 8 }}>
        <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} />
        <span>I confirm that each legacy record and amount has been reviewed against the available records and that the amount to credit is correct.</span>
      </label>
      <Note kind="bad" title="Nothing is credited yet">Once confirmed, these balances wait for a Bursar officer other than you to post them to the students&rsquo; wallets, or to return them for correction.</Note>
    </Modal>
  );
}

/* ── the posting, by a Bursar officer other than the verifier ── */

function PostModal({ rows, onClose, onDone }: { rows: LegacyWalletRow[]; onClose: () => void; onDone: () => void }) {
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<{ batch_ref: string; posted: number; amount: number; skipped: number; skipped_why: { student: string; number: string; why: string }[] } | null>(null);
  const total = rows.reduce((a, r) => a + num(r.available), 0);
  return (
    <Modal wide title={`Post ${rows.length} verified balance${rows.length === 1 ? "" : "s"} to the wallet`} sub={naira(total)} onClose={onClose}
      foot={result ? <Btn kind="primary" onClick={onDone}>Close</Btn> : <>
        <Btn kind="ghost" onClick={onClose}>Cancel</Btn>
        <Btn kind="primary" busy={busy} busyLabel="Posting to the wallets…" disabled={busy} onClick={async () => {
          setBusy(true);
          try {
            const r = await post<{ batch_ref: string; posted: number; amount: number; skipped: number; skipped_why: { student: string; number: string; why: string }[] }>("/post", { ids: rows.map((x) => x.id), note },
              `Old e-wallet balances posted: ${rows.length}`);
            if (r) { setResult(r); notify(`${n(r.posted)} posted (${naira(r.amount)}) under ${r.batch_ref}${r.skipped ? `, ${n(r.skipped)} skipped` : ""}`); }
          } finally { setBusy(false); }
        }}>Post to the wallets</Btn></>}>
      {result ? (
        <>
          <Note kind="ok" title={`${n(result.posted)} posted under ${result.batch_ref}`}>{naira(result.amount)} credited as the students&rsquo; own money (source LEGACY_WALLET); each student is told and applies it to their fees from the wallet page.</Note>
          {result.skipped_why.length ? <DTable pageSize={0} cols={["Student", "Number", "Why skipped"]} rows={result.skipped_why.map((s) => [s.student, <span key="n" className="tnum">{s.number}</span>, s.why])} /> : null}
        </>
      ) : (
        <>
          <Note kind="info" title="One credit a student, once">Each balance was verified by another officer; a balance you verified yourself is skipped and said. The credit is dated the student&rsquo;s last top-up and drawn from Opening balance / suspense on the ledger.</Note>
          <DTable pageSize={0} cols={["Student", "Balance|num", "Verified by"]} rows={rows.map((r) => [`${r.student} · ${r.matric_no ?? ""}`, <span key="a" className="tnum">{naira(r.available)}</span>, `${r.verified_by ?? ""} (${r.verified_office})`])} />
          <Field id="pm-note" label="Note" full><input id="pm-note" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </>
      )}
    </Modal>
  );
}
