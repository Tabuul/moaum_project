"use client";
/** V752 · SIWES fee payments — the Bursary reconciles the SIWES registration fee with the verified transactions: every confirmed
 *  payment of the session (the portal's, with its gateway and the gateway's reference, and the old portal's SIWES payment that counts
 *  for its session), filtered by faculty, department, programme and where it was paid, totalled, paged on the server, and the whole list
 *  as a branded Excel workbook or a printed list. Never a school fee, never the GST fee. A payment that does not settle the student's fee
 *  (a second payment for a session already paid) is marked as the credit it is held as, or as given back; the totals (the API's, the
 *  same on the tiles and in the exports) give what settles fees, what is held settling nothing and what was refunded, apart. An old-portal
 *  payment that waits on the Bursary's bank check (V561) says which wait, under the pill of the database's code (K31: the record the bank
 *  never received apart from the one it did receive), on screen and in the exports; a payment given back waits on nothing (K35). The
 *  credits are listed below for the Bursar: refunded with a note, or reopened when settled in error (and then settling the fee where
 *  nothing else does, K33); a credit is applied by moving its payment on the payment correction desk, which records it here (as the
 *  Summer's, V751). */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import {
  FEE_PUBLISHERS, PAYMENT_HEAD, SIWES_DESK_READERS, SOURCES, SOURCE_WORD, creditActions, creditBankCheck, dateWord, naira, num, paymentBankCheck, paymentLine, paymentStanding,
  paymentTotals, reopenedWords, scopeWords, settledWords, siwesQuery, sourceWord, unitOptions, type Opt, type SiwesCredit, type SiwesFilters, type SiwesPaymentPage, type SiwesPaymentRow,
  type UnitTree,
} from "@/lib/siwes";

const SIZE = 50;

/** the SIWES credits of the session: a payment for a session already paid, held for the Bursar — refunded with a note of ten characters
 *  or more, or reopened (with a reason) when settled by hand in error. What is offered is what the database said passes (canRefund,
 *  canReopen); a credit the database settled itself says how (settledKind) and offers nothing, and one whose payment now settles the
 *  fee says so; one held for the Bursary's bank check (K15, K20, V561: a possible bank double charge, a withdrawal waiting, another
 *  record of its day found never received) says why, in the database's words under the pill of the database's code for that wait (K31),
 *  and where the check is recorded — the one that settles the fee meanwhile too; a refusal that comes all the same is shown as it comes */
function Credits({ credits, session, problem: readProblem, mayAct, office }: { credits: SiwesCredit[]; session: string | null; problem: Problem | null; mayAct: boolean; office: string | null }) {
  const router = useRouter();
  const [acting, setActing] = useState<{ id: string; kind: "REFUND" | "REOPEN" } | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  async function send() {
    if (!acting) return;
    setBusy(true);
    setProblem(null);
    try {
      const refund = acting.kind === "REFUND";
      const r = await fetch(`/api/bff/api/v1/finance/siwes/credits/${encodeURIComponent(acting.id)}/${refund ? "settle" : "reopen"}`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(refund ? "SIWES credit refunded" : "SIWES credit reopened") },
        body: JSON.stringify(refund ? { state: "REFUNDED", note: note.trim() } : { reason: note.trim() }),
      });
      if (!r.ok) {
        const j = await r.json().catch(() => null);
        const p = j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText };
        setProblem(p);
        notifyProblem(p);
        return;
      }
      // K33: a reopened credit may settle the fee at once (nothing else settling it): say what it became, from the database's answer
      notify(refund ? "Recorded as refunded" : reopenedWords(await r.json().catch(() => null)));
      setActing(null);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }
  if (readProblem) return <ProblemNotice problem={readProblem} />;
  if (!credits.length) return null;
  return (
    <Panel title="Unapplied SIWES payments" right={`${credits.filter((x) => x.state === "OPEN").length} open`}>
      <PBody><div className="sub2">A SIWES payment confirmed for a session the student had already paid — a reference paid at the bank after the card, or after the
        old portal&rsquo;s payment. It never settles the fee twice: the money is held here until the Bursar refunds it. A credit is the whole of its payment, so it is
        applied by moving the payment on the payment correction desk, which records it here. A credit settled here in error can be reopened; where by then no
        other payment settles the student&rsquo;s fee (the one that did was given back or moved), the reopened credit settles it. A credit the
        portal settled itself (its payment moved, the fee settled by it, or a refund on the refund desk) says so and is not changed here.
        An old-portal payment that may be a bank double charge (another of the same student, day and amount under another payment number) is neither
        refunded nor moved until the Bursary has recorded the bank&rsquo;s answer on Old Fees History (possible double charges); where the bank found a
        payment of that day never received, every SIWES payment of the day waits until that one is withdrawn (Payments not received), and a credit on
        the payment never received is not listed here meanwhile: it settles nothing, so the payment the bank did receive settles the fee in its place.</div></PBody>
      <DTable cols={["Number", "Name", "Session", "Amount|num", "Reference", "Received", "State", "|mid"]} rows={credits.map((x) => {
        const can = creditActions(x);
        const held = creditBankCheck(x, office);
        return [
          <span key="n" className="tnum">{x.matricNo ?? "—"}</span>,
          <span key="nm">{x.name || "—"}</span>,
          <span key="s" className="tnum">{x.session ?? session ?? "—"}</span>,
          <span key="a" className="tnum">{naira(x.amount)}</span>,
          <span key="r"><span className="tnum t-xs">{x.reference}</span>{x.reason ? <span className="blk sub2">{x.reason}</span> : null}
            {/* K15, K20, K31: held for the bank check, in the database's words, under the pill of the database's code for the wait */}
            {held ? <span className="blk"><Pil kind={held.pill[1]}>{held.pill[0]}</Pil> <span className="sub2">{held.words}</span></span> : null}</span>,
          <span key="d" className="sub2">{dateWord(x.paidAt)}</span>,
          <span key="st"><Pil kind={x.state === "OPEN" ? "warn" : "ok"}>{x.state}</Pil>
            {x.settledNote ? <span className="blk sub2">{x.settledNote}</span> : null}
            {/* K19: how it was settled, as the database recorded it — never read from the note */}
            {settledWords(x) ? <span className="blk sub2">{settledWords(x)}</span> : null}
          </span>,
          // its payment now settles the student's fee: nothing to refund or reopen (K20: one held for the bank check meanwhile says so too)
          can.settlesNow ? (
            <span key="x"><Pil kind="ok">Settles the fee now</Pil>
              {held?.page ? <span className="blk"><LinkBtn kind="ghost" size="sm" href={held.page.href}>{held.page.label}</LinkBtn></span> : null}</span>
          )
            // K15: no Refund until the bank check finds it received; the check and the withdrawals are recorded on Old Fees History
            : held ? (held.page ? <LinkBtn key="x" kind="ghost" size="sm" href={held.page.href}>{held.page.label}</LinkBtn> : <span key="x" className="sub2">Waits for the bank check</span>)
            : mayAct && (can.refund || can.reopen) ? (
              <span key="x" className="row row--inline row--tight">
                {can.refund ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { setActing({ id: x.id, kind: "REFUND" }); setNote(""); setProblem(null); }}>Refund</Btn> : null}
                {/* V751's precedent: a credit settled by hand in error is reopened, with a reason */}
                {can.reopen ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { setActing({ id: x.id, kind: "REOPEN" }); setNote(""); setProblem(null); }}>Reopen</Btn> : null}
              </span>
            ) : <span key="x" />,
        ];
      })} />
      {acting ? (
        <PBody>
          <div className="row" style={{ flexWrap: "wrap", alignItems: "flex-end", gap: "var(--s-2)" }}>
            <Field id="sw-cn" label={acting.kind === "REFUND" ? "How it was refunded" : "Why it is reopened"}
              hint={acting.kind === "REFUND" ? "At least 10 characters: the voucher, the reference or the desk that paid it back." : "At least 10 characters, kept on the audit trail."}>
              <input id="sw-cn" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} />
            </Field>
            <Btn kind="primary" size="md" busy={busy} busyLabel="Recording…" disabled={busy || note.trim().length < 10} onClick={() => void send()}>
              {acting.kind === "REFUND" ? "Record the refund" : "Reopen it"}
            </Btn>
            <Btn kind="ghost" size="md" disabled={busy} onClick={() => setActing(null)}>Cancel</Btn>
          </div>
        </PBody>
      ) : null}
      {problem ? <PBody><ProblemNotice problem={problem} /></PBody> : null}
    </Panel>
  );
}

export function SiwesPayments({ data, page, filters, sessions, structure, credits = [], creditsProblem = null, actingOffice = null }: {
  data: SiwesPaymentPage; page: number; filters: SiwesFilters; sessions: string[]; structure: UnitTree;
  credits?: SiwesCredit[]; creditsProblem?: Problem | null; actingOffice?: string | null;
}) {
  const go = useQueryNav();
  const [busy, setBusy] = useState(false);
  const opts = unitOptions(structure, filters);
  const scope = scopeWords(filters, opts, [filters.source ? `Paid on the ${sourceWord(filters.source).toLowerCase()}` : null]);
  const size = data.size ?? SIZE;
  const at = data.page ?? page;
  const pages = Math.max(1, Math.ceil(data.total / Math.max(1, size)));
  // the totals of every payment the filters select, as the API sums them: the tiles and the exports read the same figures
  const totals = paymentTotals(data);
  const href = (patch: SiwesFilters & { page?: number }) => {
    const n: SiwesFilters & { page?: number } = { ...filters, ...patch };
    if ("faculty" in patch) { delete n.department; delete n.programme; }
    if ("department" in patch) delete n.programme;
    if (!("page" in patch)) delete n.page;
    return `/finance/siwes-payments?${siwesQuery(n)}`;
  };
  const sel = (id: string, label: string, k: keyof SiwesFilters, options: Opt[], all: string) => (
    <Field id={id} label={label}>
      <select id={id} className="ctl" value={filters[k] ?? ""} onChange={(e) => go(href({ [k]: e.target.value || undefined }))}>
        <option value="">{all}</option>
        {options.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
      </select>
    </Field>
  );

  /** every payment the filters select, and the first answer (its totals are the API's, over all of them) */
  async function allRows(): Promise<{ rows: SiwesPaymentRow[]; first: SiwesPaymentPage | null }> {
    const out: SiwesPaymentRow[] = [];
    let first: SiwesPaymentPage | null = null;
    for (let p = 0; p * 500 < data.total && p < 200; p++) {
      const r = await fetch(`/api/bff/api/v1/finance/siwes/payments?${siwesQuery(filters, { page: p, size: 500 })}`, { cache: "no-store" });
      if (!r.ok) throw (await r.json().catch(() => ({ status: r.status, title: r.statusText })));
      const j = (await r.json()) as SiwesPaymentPage;
      first ??= j;
      out.push(...j.rows);
      if (j.rows.length < 500) break;
    }
    return { rows: out, first };
  }
  async function exportAs(kind: "xlsx" | "pdf") {
    setBusy(true);
    try {
      const { rows, first } = await allRows();
      const body = rows.map(paymentLine);
      // the API's totals, as the tiles show them; summed from the rows exported only when the answer carries none
      const t = paymentTotals(first ?? { ...data, rows }, rows);
      const title = "SIWES Registration Fee Payments";
      const meta: [string, string][] = [["Payments", String(rows.length)], ["Amount", naira(t.amount)], ["Settling the fee", naira(t.settling)],
        ["Held, settling nothing", naira(t.credits)], ["Refunded", naira(t.refunded)]];
      if (kind === "xlsx") downloadBlob(await brandedXlsx(title, PAYMENT_HEAD, body, { sheetName: "SIWES payments", serial: docSerial("SIW"), sub: scope, meta }), `siwes-fee-payments-${(filters.session ?? "").replace("/", "-")}.xlsx`);
      else brandedPrint(title, scope, PAYMENT_HEAD, body, docSerial("SIW"), { meta });
    } catch (e) {
      notifyProblem((e as { status?: number }).status ? (e as Problem) : { status: 500, title: "The export could not be built" });
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Tiles cls="grid--5" items={[
        ["Payments", num(data.total).toLocaleString("en-NG"), null, `${naira(data.amount)} received for the filters chosen`],
        ["Settling the fee", naira(totals.settling), "var(--green-ink)", totals.fromRows ? "Of the payments on this page" : "One payment a student and session"],
        ["Held, settling nothing", naira(totals.credits), totals.credits ? "var(--red-ink)" : null, totals.fromRows ? "Of the payments on this page" : "Credits open or applied, and old-portal duplicates"],
        ["Refunded", naira(totals.refunded), null, totals.fromRows ? "Of the payments on this page" : "Given back on the refund desk, or a credit recorded refunded"],
        ["Session", filters.session ?? "—", null, scope],
      ]} />
      {/* the desk's figures are linked only for an office that reads the desk (the auditors read the payments alone) */}
      <Panel title="Filters" right={SIWES_DESK_READERS.includes(actingOffice ?? "")
        ? <LinkBtn kind="ghost" size="sm" href={`/siwes/registration?${siwesQuery({ session: filters.session }, { tab: "stats" })}`}>SIWES registration figures</LinkBtn> : undefined}>
        <PBody>
          <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
            <Field id="sp-session" label="Session">
              <select id="sp-session" className="ctl" value={filters.session ?? ""} onChange={(e) => go(`/finance/siwes-payments?${siwesQuery({ session: e.target.value })}`)}>
                {filters.session && !sessions.includes(filters.session) ? <option value={filters.session}>{filters.session}</option> : null}
                {sessions.map((x) => <option key={x} value={x}>{x}</option>)}
              </select>
            </Field>
            {sel("sp-fac", "Faculty", "faculty", opts.faculties, "All faculties")}
            {sel("sp-dept", "Department", "department", opts.departments, "All departments")}
            {sel("sp-prog", "Programme", "programme", opts.programmes, "All programmes")}
            {sel("sp-src", "Paid on", "source", SOURCES.map((x) => [x, SOURCE_WORD[x]] as Opt), "The portal and the old portal")}
          </div>
        </PBody>
      </Panel>
      <Panel title={`${num(data.total).toLocaleString("en-NG")} payment${data.total === 1 ? "" : "s"} · ${naira(data.amount)}`} right={
        <span className="row row--inline row--tight">
          <span className="sub2">page {at + 1} of {pages}</span>
          <Btn kind="ghost" size="sm" disabled={at === 0} onClick={() => go(href({ page: at - 1 }))}>Previous</Btn>
          <Btn kind="ghost" size="sm" disabled={at + 1 >= pages} onClick={() => go(href({ page: at + 1 }))}>Next</Btn>
          <Btn kind="secondary" size="sm" disabled={busy || !data.total} onClick={() => void exportAs("xlsx")}>Excel</Btn>
          <Btn kind="ghost" size="sm" disabled={busy || !data.total} onClick={() => void exportAs("pdf")}>Print</Btn>
        </span>}>
        {data.rows.length ? (
          <DTable cols={["S/N|num", "Student", "Programme", "Amount|num", "Gateway", "Receipt", "Confirmed", "Paid on|mid"]} rows={data.rows.map((r, i) => {
            const standing = paymentStanding(r);
            const held = paymentBankCheck(r, actingOffice);
            return [
            <span key="n" className="tnum sub2">{at * size + i + 1}</span>,
            <span key="s"><b>{r.name}</b><div className="sub2 tnum">{r.matricNo ?? "—"}</div></span>,
            <span key="p">{r.programme ?? "—"}<div className="sub2">{[r.department, r.faculty].filter(Boolean).join(" · ")}</div></span>,
            // a payment that does not settle the fee says what it is held as
            <span key="a"><span className="tnum">{naira(r.amount)}</span>{standing && r.settles !== true ? <div><Pil kind={standing[1]}>{standing[0]}</Pil></div> : null}
              {num(r.refunded) > 0 ? <div className="sub2 tnum">{naira(r.refunded)} refunded</div> : null}</span>,
            <span key="g"><span className="tnum t-xs">{r.reference}</span><div className="sub2 tnum">{[r.gateway, r.gatewayReference].filter(Boolean).join(" · ") || "—"}</div>
              {/* K31: waiting on the bank check, under the pill of the database's code — never "never received" on the record the bank received */}
              {held ? <div><Pil kind={held.pill[1]}>{held.pill[0]}</Pil>{held.words ? <span className="blk sub2">{held.words}</span> : null}
                {held.page ? <span className="blk"><LinkBtn kind="ghost" size="sm" href={held.page.href}>{held.page.label}</LinkBtn></span> : null}</div> : null}</span>,
            <span key="r" className="tnum">{r.receiptNo ?? "—"}</span>,
            <span key="c" className="tnum sub2">{dateWord(r.confirmedAt)}</span>,
            <Pil key="o" kind={r.source === "OLD_PORTAL" ? "grey" : "ok"}>{sourceWord(r.source).toUpperCase() || "—"}</Pil>,
            ];
          })} />
        ) : <PBody><Note kind="info" title="No SIWES payment matches">No confirmed SIWES registration fee for the filters chosen.</Note></PBody>}
      </Panel>
      <Credits credits={credits} session={filters.session ?? null} problem={creditsProblem} mayAct={FEE_PUBLISHERS.includes(actingOffice ?? "")} office={actingOffice} />
    </>
  );
}
