"use client";
/** V766 · Transfer application payments — the Bursary reconciles the inter-university transfer application fee: each reference drawn,
 *  paid (with its channel and receipt), waiting or expired, the totals the API sums over the filters, and the payments owed back (a second
 *  payment for an application already settled, D19: the refund desk pays it; once it has given it back the payment reads Refunded and
 *  leaves the list owed back). The Bursar confirms a payment by hand against the bank's
 *  record, as the JUPEB fees desk does (a bank credit for a reference confirmed by hand is never posted: V766 round 7); the whole list is
 *  exported as CSV. The application fee itself is not refunded on a decline or a
 *  withdrawal. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { downloadBlob } from "@/lib/exportbrand";
import { sessionSlug, toCsv } from "@/lib/report";
import {
  FEE_PUBLISHERS, PAGE_SIZE, PAYMENT_HEAD, PAYMENT_STATES, PAYMENT_WORDS, dayWords, naira, num, officeWords, paymentLine, refundWords, type IutPaymentRow, type IutPayments,
} from "@/lib/transfer-application";
import { FEES, call } from "@/app/transfer/call";

export interface PaymentFilters { session: string | null; state: string | null; q: string; page: number }

const PATH = "/finance/transfer-application-payments";

function href(f: PaymentFilters): string {
  const p = new URLSearchParams();
  if (f.session) p.set("session", f.session);
  if (f.state) p.set("state", f.state);
  if (f.q.trim()) p.set("q", f.q.trim());
  if (f.page) p.set("page", String(f.page));
  return `${PATH}${p.size ? `?${p}` : ""}`;
}

export function TransferApplicationPayments({ data, filters, sessions, office }: { data: IutPayments; filters: PaymentFilters; sessions: string[]; office: string | null }) {
  const go = useQueryNav();
  const router = useRouter();
  const [q, setQ] = useState(filters.q);
  const [busy, setBusy] = useState(false);
  const [confirming, setConfirming] = useState<IutPaymentRow | null>(null);
  const [note, setNote] = useState("");
  const noteOk = note.trim().length >= 5 && note.trim().length <= 600;
  const t = data.totals ?? {};
  const drawn = num(t.drawn);
  const pages = Math.max(1, Math.ceil(drawn / PAGE_SIZE));
  const mayConfirm = FEE_PUBLISHERS.includes(office ?? "");
  const scope = [filters.session ?? "Every session", filters.state ? PAYMENT_WORDS[filters.state]?.[0] : null, filters.q.trim() ? `“${filters.q.trim()}”` : null].filter(Boolean).join(" · ");

  async function exportCsv() {
    setBusy(true);
    try {
      const rows: IutPaymentRow[] = [];
      for (let p = 0; p < 200; p++) {
        const qs = new URLSearchParams({ ...(filters.session ? { session: filters.session } : {}), ...(filters.state ? { state: filters.state } : {}),
          ...(filters.q.trim() ? { q: filters.q.trim() } : {}), page: String(p), size: "500" });
        const r = await call<IutPayments>("GET", `${FEES}/payments?${qs}`);
        if (!r.ok) { notifyProblem(r.problem); return; }
        rows.push(...r.data.rows);
        if (r.data.rows.length < 500) break;
      }
      downloadBlob(new Blob([toCsv(PAYMENT_HEAD, rows.map(paymentLine))], { type: "text/csv;charset=utf-8" }),
        `transfer-application-payments-${filters.session ? sessionSlug(filters.session) : "all"}.csv`);
    } finally {
      setBusy(false);
    }
  }
  async function confirm() {
    // the bank's record is required (5 to 600 characters), as the API holds it
    if (!confirming || !noteOk) return;
    const r = await call<string>("POST", `${FEES}/payments/${encodeURIComponent(confirming.reference)}/confirm`, { note: note.trim() },
      `Transfer application fee confirmed by hand: ${confirming.reference}: ${note.trim()}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    notify(`${confirming.reference}: confirmed`);
    setConfirming(null);
    setNote("");
    router.refresh();
  }

  return (
    <>
      <Tiles cls="grid--5" items={[
        ["References drawn", drawn.toLocaleString("en-NG"), null, scope],
        ["Paid", num(t.paid).toLocaleString("en-NG"), "var(--green-ink)", `${naira(t.paidAmount)} received`],
        ["Waiting", num(t.pending).toLocaleString("en-NG"), null, "Drawn, not yet paid"],
        ["Expired", num(t.expired).toLocaleString("en-NG"), null, "A new reference is free"],
        ["Owed back", num(t.owedBack).toLocaleString("en-NG"), num(t.owedBack) ? "var(--red-ink)" : null,
          `${naira(t.owedBackAmount)} for the refund desk${num(t.refundedAmount) > 0 ? `; ${naira(t.refundedAmount)} given back` : ""}`],
      ]} />
      <Panel title="Filters">
        <PBody>
          <form className="row row--inline row--tight" style={{ flexWrap: "wrap", alignItems: "flex-end" }} onSubmit={(e) => { e.preventDefault(); go(href({ ...filters, q, page: 0 })); }}>
            <Field id="ip-session" label="Session">
              <select id="ip-session" className="ctl" value={filters.session ?? ""} onChange={(e) => go(href({ ...filters, session: e.target.value || null, page: 0 }))}>
                <option value="">Every session</option>
                {sessions.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
            </Field>
            <Field id="ip-state" label="Payment">
              <select id="ip-state" className="ctl" value={filters.state ?? ""} onChange={(e) => go(href({ ...filters, state: e.target.value || null, page: 0 }))}>
                <option value="">Every reference</option>
                {PAYMENT_STATES.map((s) => <option key={s} value={s}>{PAYMENT_WORDS[s][0]}</option>)}
              </select>
            </Field>
            <Field id="ip-q" label="Search" hint="Reference, receipt, application or JAMB number, name">
              <input id="ip-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} style={{ minWidth: 240 }} />
            </Field>
            <Btn kind="primary" type="submit">Search</Btn>
          </form>
        </PBody>
      </Panel>
      <Panel title={`${drawn.toLocaleString("en-NG")} reference${drawn === 1 ? "" : "s"}`} right={
        <span className="row row--inline row--tight">
          <span className="sub2">page {filters.page + 1} of {pages}</span>
          <Btn kind="ghost" size="sm" disabled={filters.page === 0} onClick={() => go(href({ ...filters, page: filters.page - 1 }))}>Previous</Btn>
          <Btn kind="ghost" size="sm" disabled={filters.page + 1 >= pages} onClick={() => go(href({ ...filters, page: filters.page + 1 }))}>Next</Btn>
          <Btn kind="secondary" size="sm" disabled={busy || !drawn} busy={busy} busyLabel="Preparing CSV…" onClick={() => exportCsv()}>CSV</Btn>
        </span>}>
        {data.rows.length ? (
          <DTable cols={["S/N|num", "Reference", "Applicant", "Programme", "Amount|num", "Payment", "Receipt", "Application", "|num"]} rows={data.rows.map((r, i) => {
            const [w, pill] = PAYMENT_WORDS[r.state] ?? [r.state, "grey"];
            return [
              <span key="n" className="tnum sub2">{filters.page * PAGE_SIZE + i + 1}</span>,
              <span key="r"><span className="tnum t-xs">{r.reference}</span><div className="sub2">drawn {dayWords(r.generatedAt) || "—"}</div></span>,
              <span key="a"><b>{r.name ?? "—"}</b><div className="sub2 tnum">{[r.applicationNo, r.jambRegNo].filter(Boolean).join(" · ")}</div></span>,
              <span key="p">{r.programmeName ?? r.programme ?? "—"}</span>,
              <span key="m" className="tnum">{naira(r.amount)}</span>,
              <span key="s"><Pil kind={pill}>{w}</Pil>{r.owedBack ? <div><Pil kind="bad">Owed back</Pil></div> : null}
                {refundWords(r) ? <div><Pil kind={r.owedBack ? "warn" : "grey"}>{r.owedBack ? "Part refunded" : "Refunded"}</Pil> <span className="sub2">{refundWords(r)}</span></div> : null}
                {r.confirmedAt ? <div className="sub2">{dayWords(r.confirmedAt)}{r.channel ? ` · ${r.channel}` : ""}</div> : r.state === "PENDING" && r.expiresAt ? <div className="sub2">until {dayWords(r.expiresAt)}</div> : null}</span>,
              <span key="c" className="tnum">{r.receiptNo ?? "—"}</span>,
              <span key="ap" className="sub2">{r.applicationState ? officeWords(r.applicationState)[0] : "—"}</span>,
              mayConfirm && r.state !== "PAID" ? <Btn key="x" kind="ghost" size="sm" onClick={() => { setConfirming(r); setNote(""); }}>Confirm by hand</Btn> : <span key="x" />,
            ];
          })} texts={data.rows.map((r) => `${r.reference} ${r.receiptNo ?? ""} ${r.applicationNo ?? ""} ${r.jambRegNo ?? ""} ${r.name ?? ""}`)} />
        ) : <PBody><Note kind="info" title="No reference matches">No transfer application fee reference for the filters chosen.</Note></PBody>}
      </Panel>
      {confirming ? (
        <Modal title={`Confirm ${confirming.reference} by hand`} sub={`${confirming.name ?? ""} · ${naira(confirming.amount)}`} onClose={() => setConfirming(null)}
          foot={<><Btn kind="ghost" onClick={() => setConfirming(null)}>Cancel</Btn><span className="grow" /><Btn kind="go" disabled={!noteOk} title={noteOk ? undefined : "Give the bank's record first: five characters or more"} onClick={() => confirm()}>Confirm the payment</Btn></>}>
          <div className="sub2 mb-1">Only against the bank&rsquo;s record of the money received: a receipt is issued and the applicant told. A reference for an application already
            settled is confirmed as owed back. Once you confirm it by hand, a bank credit for this reference is never posted by the portal: the Bursary checks the
            bank&rsquo;s record and rejects the proposal, and refunds only money received twice.</div>
          <Field id="ip-note" label="The bank's record" required hint="The bank, the teller or transfer number as the bank's record shows it, and the date: 5 to 600 characters">
            <input id="ip-note" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} maxLength={600} required />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}
