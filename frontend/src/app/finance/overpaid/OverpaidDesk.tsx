"use client";

/**
 * V781: Overpaid school fees — every student paid above their charge in a session, by cause, with what holds the student back said beside
 * the student. The Students Account Officer or a Bursary officer asks for a wallet credit (one student, some, or a whole paid-twice
 * cause); a different Bursary officer approves, returns or rejects it, many at once. A refund keeps its own two-person rule on
 * Refunds & Credits. A row that is not an exact repeated payment is decided one student at a time, with the officer's confirmation that
 * the fee setup and the payments were checked. The list is the server's kept list, its state read live; every figure and every rule is
 * the server's. The approval credits the wallet and pays no fees: the student applies the money on the Wallet page, or asks for a refund.
 */
import { useEffect, useState, type ReactNode } from "react";
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tabs, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, day } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { StudentOpen } from "@/components/StudentModal";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import type { CreditRequestRow } from "@/lib/legacy-reconciliation";
import {
  CAUSES, CAUSE_WORDS, OVERPAID_DESK_HEADERS, STATES, STATE_WORDS, SUGGESTED_WORDS, actBody, addUp, asOf, causeWord, count, creditRows, holdRemedy, holdWord, isPaidTwice,
  levelWords, levelsDiffer, naira, num, overpaidExcelRow, overpaidHref, overpaidMay, paymentKindWord, readyRows, refundDone, requestDone, rowsQuery, selectable, selectionFor,
  whyNot, type ActTotals, type CreditBatch, type OverpaidCause, type OverpaidDeskRow, type OverpaidFigures, type OverpaidRows, type RefundAnswer, type RequestAnswer,
} from "@/lib/overpaid";
import { ActResult, ApproveModal, postOverpaid, runDecide } from "@/components/finance/OverpaidApprove";

const BASE = "/api/bff/api/v1/finance/overpaid";
const PAGE = 200;

type Tab = "students" | "approvals" | "returned";
/** what the last act did, said at the top of the desk until it is dismissed */
type Acted = { act: "request" | "refund" | "approve" | "reject" | "return"; totals: ActTotals } | { words: string };

export function OverpaidDesk({ figures, rows, rowsProblem, filters, actingOffice }: {
  figures: OverpaidFigures; rows: OverpaidRows | null; rowsProblem: Problem | null; filters: Record<string, string>; actingOffice: string | null;
}) {
  const go = useQueryNav();
  const may = overpaidMay(actingOffice);
  const tab = (filters.tab || "students") as Tab;
  const session = figures.session;
  const q = figures.requests;
  const [acted, setActed] = useState<Acted | null>(null);
  const [stamp, setStamp] = useState(0);
  const [working, setWorking] = useState(false);
  const here = (c: Record<string, string> = {}) => ({ ...filters, session, ...c });
  const nav = (c: Record<string, string>) => go(overpaidHref(here({ ...("page" in c ? {} : { page: "" }), ...c })));
  const reread = () => { setStamp((x) => x + 1); go(overpaidHref(here())); };
  const sessions = figures.sessions?.includes(session) ? figures.sessions : [session, ...(figures.sessions ?? [])];

  async function refresh() {
    if (working) return;
    setWorking(true);
    try {
      const r = await postOverpaid<OverpaidFigures>("/refresh", { session }, `Overpaid school fees of ${session} worked out again`);
      if (r) { notify(`The list for ${session} is worked out again: ${num(r.students).toLocaleString("en-GB")} students paid above their charge.`); reread(); }
    } finally {
      setWorking(false);
    }
  }

  const causeTiles = CAUSES.map((c): [ReactNode, ReactNode, string | null, ReactNode, string] => {
    const x = figures.causes.find((y) => y.cause === c);
    return [`${CAUSE_WORDS[c]}${filters.cause === c ? " (shown)" : ""}`, num(x?.students).toLocaleString("en-GB"), null,
      `${naira(x?.excess)} above the charge · ${num(x?.undecided).toLocaleString("en-GB")} not decided · ${num(x?.ready).toLocaleString("en-GB")} ready · ${num(x?.held).toLocaleString("en-GB")} held`,
      overpaidHref(here({ tab: "students", cause: filters.cause === c ? "" : c, page: "" }))];
  });

  return (
    <>
      <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
        <Field id="od-session" label="Session" style={{ flex: "0 1 170px" }}>
          <select id="od-session" className="ctl" value={session} onChange={(e) => go(overpaidHref({ session: e.target.value, tab: filters.tab }))}>
            {sessions.map((x) => <option key={x} value={x}>{x}</option>)}
          </select>
        </Field>
        <div className="sub2 grow">
          {figures.computed ? `Figures as of ${asOf(figures.refreshedAt) || "—"} · ${num(figures.students).toLocaleString("en-GB")} students paid ${naira(figures.excess)} above their charge`
            : `Not yet worked out for ${session}`}
        </div>
        {may.refresh ? <Btn kind="ghost" disabled={working} onClick={refresh}>{working ? "Working it out…" : "Refresh"}</Btn> : null}
        <LinkBtn kind="ghost" href="/finance/refunds">Refunds &amp; Credits</LinkBtn>
      </div>

      {!figures.computed ? (
        may.refresh ? (
          <Note kind="info" title={`Not yet worked out for ${session}`} action={<Btn kind="primary" disabled={working} onClick={refresh}>{working ? "Working it out…" : "Refresh"}</Btn>}>
            The list of students paid above their charge is worked out for a session when you press Refresh, and again every ten minutes while payments come in. It can take up to a minute.
          </Note>
        ) : (
          <Note kind="info" title={`Not yet worked out for ${session}`}>The Bursary or the Students Account Officer opens it.</Note>
        )
      ) : (
        <>
          {acted ? ("words" in acted
            ? <Note kind="ok" title={acted.words} action={<Btn kind="ghost" size="sm" onClick={() => setActed(null)}>Dismiss</Btn>} />
            : <ActResult act={acted.act} totals={acted.totals} onClose={() => setActed(null)} />) : null}
          {num(figures.overDecided.students) > 0 ? (
            <Note kind="info" title={`${count(figures.overDecided.students, "student")} decided above the excess`}
              action={<LinkBtn kind="ghost" href={overpaidHref(here({ tab: "students", state: "OVER_DECIDED", page: "" }))}>Show them</LinkBtn>}>
              {count(figures.overDecided.students, "student was", "students were")} decided for {naira(figures.overDecided.amount)} more than is now paid above their charge, because the charge rose after the decision.
              What their wallets still hold of it is kept back from refunds; nothing here decides them again.
            </Note>
          ) : null}
          <Tiles cls="grid--5" items={causeTiles} />
          <Tabs look="line" label="Overpaid school fees" value={tab} onChange={(id) => nav({ tab: id === "students" ? "" : id })}
            items={[{ id: "students", label: "Students", count: num(figures.students).toLocaleString("en-GB") },
              { id: "approvals", label: "Approvals", count: num(q.pending).toLocaleString("en-GB") },
              { id: "returned", label: "Returned", count: num(q.returned).toLocaleString("en-GB") }]} />
          {tab === "students" ? (
            <StudentsTab key={rowsQuery(here())} session={session} figures={figures} data={rows} problem={rowsProblem} filters={here()} nav={nav} may={may} setActed={setActed} reread={reread} />
          ) : null}
          {tab === "approvals" ? <ApprovalsTab session={session} figures={figures} may={may} stamp={stamp} setActed={setActed} reread={reread} /> : null}
          {tab === "returned" ? <ReturnedTab session={session} may={may} stamp={stamp} setActed={setActed} reread={reread} /> : null}
        </>
      )}
    </>
  );
}

/* ── the students tab ── */

function StudentsTab({ session, figures, data, problem, filters, nav, may, setActed, reread }: {
  session: string; figures: OverpaidFigures; data: OverpaidRows | null; problem: Problem | null; filters: Record<string, string>; nav: (c: Record<string, string>) => void;
  may: ReturnType<typeof overpaidMay>; setActed: (a: Acted | null) => void; reread: () => void;
}) {
  const [sel, setSel] = useState<Record<string, boolean>>({});
  const [openPay, setOpenPay] = useState<Record<string, boolean>>({});
  const [acting, setActing] = useState<"credit" | "refund" | null>(null);
  const list = data?.rows ?? [];
  const chosen = list.filter((r) => sel[r.student_id]);
  const total = num(data?.total);
  const size = num(data?.size) || 100;
  const page = num(data?.page);
  const departments = (data?.departments ?? []).filter((d) => !filters.faculty || d.faculty === filters.faculty);
  const cause = filters.cause as OverpaidCause | undefined;
  // the cause as a whole is every ready student of it in every faculty and department, whether or not they are on this page: it is offered
  // only while the cause is the one thing narrowing the list (a page change or a filter clears the ticks, and must not turn a few students
  // into a whole cause)
  const onlyCause = !filters.state && !filters.held && !filters.bulk && !filters.faculty && !filters.department && !filters.q;
  const allCause = !chosen.length && onlyCause && cause && isPaidTwice(cause) ? cause : null;
  const narrowed = !chosen.length && !onlyCause && cause && isPaidTwice(cause);
  const allReady = allCause ? figures.causes.find((c) => c.cause === allCause) : undefined;
  const credit = selectionFor("credit", chosen);
  const refund = selectionFor("refund", chosen);
  const filtered = !!(filters.cause || filters.state || filters.held || filters.bulk || filters.faculty || filters.department || filters.q);
  const act = { credit: may.credit, refund: may.refund };

  const toggle = (r: OverpaidDeskRow) => setSel((s) => ({ ...s, [r.student_id]: !s[r.student_id] }));
  const tickReady = () => { const next: Record<string, boolean> = {}; for (const r of readyRows(list)) next[r.student_id] = true; setSel(next); };
  async function excel() {
    const r = await fetch(`${BASE}/rows?${rowsQuery(filters, 100, true)}`, { cache: "no-store" }).catch(() => null);
    const j = r ? ((await r.json().catch(() => null)) as OverpaidRows | null) : null;
    if (!r || !r.ok || !j) { notifyProblem((j ?? { status: r?.status ?? 0, title: r?.statusText || "The portal could not be reached" }) as unknown as Problem); return; }
    const scope = [session, filters.cause ? causeWord(filters.cause) : "", filters.state ? STATE_WORDS[filters.state as keyof typeof STATE_WORDS]?.[0] ?? "" : ""].filter(Boolean).join(" · ");
    downloadBlob(await brandedXlsx(`Overpaid school fees, ${session}`, OVERPAID_DESK_HEADERS, j.rows.map(overpaidExcelRow),
      { sheetName: "Overpaid", serial: docSerial("OPD"), sub: scope, meta: [["Filters", scope], ["Rows", String(j.rows.length)]] }), `overpaid-school-fees-${session.replace("/", "-")}.xlsx`);
  }

  return (
    <Panel title={`Students paid above their charge · ${session}`} right={`${total.toLocaleString("en-GB")} listed`}>
      <PBody>
        <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
          <Field id="od-q" label="Search" style={{ flex: "2 1 220px" }}>
            <input id="od-q" className="ctl" type="search" defaultValue={filters.q ?? ""} placeholder="Name or number"
              onKeyDown={(e) => { if (e.key === "Enter") nav({ q: (e.target as HTMLInputElement).value }); }} />
          </Field>
          <Field id="od-cause" label="Cause" style={{ flex: "0 1 230px" }}>
            <select id="od-cause" className="ctl" value={filters.cause ?? ""} onChange={(e) => nav({ cause: e.target.value })}>
              <option value="">Any cause</option>
              {CAUSES.map((c) => <option key={c} value={c}>{CAUSE_WORDS[c]}</option>)}
            </select>
          </Field>
          <Field id="od-state" label="State" style={{ flex: "0 1 230px" }}>
            <select id="od-state" className="ctl" value={filters.state ?? ""} onChange={(e) => nav({ state: e.target.value })}>
              <option value="">Any state</option>
              {STATES.map((s) => <option key={s} value={s}>{STATE_WORDS[s][0]}</option>)}
            </select>
          </Field>
          <Field id="od-held" label="Held" style={{ flex: "0 1 150px" }}>
            <select id="od-held" className="ctl" value={filters.held ?? ""} onChange={(e) => nav({ held: e.target.value })}>
              <option value="">Held or not</option><option value="true">Held only</option><option value="false">Not held</option>
            </select>
          </Field>
          <Field id="od-bulk" label="Repeated payment" style={{ flex: "0 1 190px" }}>
            <select id="od-bulk" className="ctl" value={filters.bulk ?? ""} onChange={(e) => nav({ bulk: e.target.value })}>
              <option value="">Exact repeat or not</option><option value="true">Exact repeat</option><option value="false">Not an exact repeat</option>
            </select>
          </Field>
          <Field id="od-fac" label="Faculty" style={{ flex: "1 1 180px" }}>
            <SearchSelect id="od-fac" value={filters.faculty ?? ""} onChange={(v) => nav({ faculty: v, department: "" })} allLabel="Any faculty"
              options={(data?.faculties ?? []).map((f) => ({ value: f.code, label: f.name }))} />
          </Field>
          <Field id="od-dept" label="Department" style={{ flex: "1 1 180px" }}>
            <SearchSelect id="od-dept" value={filters.department ?? ""} onChange={(v) => nav({ department: v })} allLabel="Any department"
              options={departments.map((d) => ({ value: d.code, label: d.name }))} />
          </Field>
          {filtered ? <Btn kind="ghost" onClick={() => nav({ cause: "", state: "", held: "", bulk: "", faculty: "", department: "", q: "" })}>Clear</Btn> : null}
        </div>
        <div className="row mt-2" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "center" }}>
          {act.credit || act.refund ? <Btn kind="ghost" size="sm" disabled={!readyRows(list).length} onClick={tickReady}>Select all ready on this page</Btn> : null}
          {chosen.length ? <Btn kind="ghost" size="sm" onClick={() => setSel({})}>Clear the selection</Btn> : null}
          {chosen.length ? <span className="sub2">{count(chosen.length, "student")} ticked · {naira(chosen.reduce((a, r) => a + num(r.remaining), 0))} not yet decided</span> : null}
          <span className="grow" />
          {act.credit ? (
            <Btn kind="primary" disabled={chosen.length ? credit.count === 0 : !allCause}
              title={chosen.length ? (credit.count === 0 ? "Refund-only students are refunded, never credited to a wallet" : undefined) : allCause ? undefined : narrowed ? "Tick students, or clear the other filters to credit every ready student of the cause" : "Tick students, or show one paid-twice cause to credit every ready student of it"}
              onClick={() => setActing("credit")}>
              {chosen.length ? `Credit ${credit.count} to the wallet` : allCause ? `Credit all ready: ${CAUSE_WORDS[allCause]}` : "Credit to wallet"}
            </Btn>
          ) : null}
          {act.refund ? (
            <Btn kind="ghost" disabled={chosen.length ? refund.count === 0 : !allCause}
              title={chosen.length || allCause ? undefined : narrowed ? "Tick students, or clear the other filters to refund every ready student of the cause" : "Tick students, or show one paid-twice cause to refund every ready student of it"}
              onClick={() => setActing("refund")}>
              {chosen.length ? `Refund ${refund.count}` : allCause ? `Refund all ready: ${CAUSE_WORDS[allCause]}` : "Refund"}
            </Btn>
          ) : null}
          <Btn kind="ghost" disabled={!total} onClick={excel}>Excel</Btn>
        </div>
        {!act.credit && !act.refund ? <div className="sub2 mt-2">Your office reads this list; the Bursary and the Students Account Officer decide.</div> : null}
      </PBody>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {data && list.length ? (
        <DTable pageSize={0} cols={["|mid", "Student", "Programme · level", "Charged|num", "Paid|num", "Excess|num", "Cause", "Payments", "Held for", "State"]}
          rows={list.map((r) => {
            const why = whyNot(r, act);
            const cannotJoin = !why && !selectable(r, chosen);
            const title = why ?? (cannotJoin ? "A row that is not an exact repeated payment is decided alone: untick the others first." : undefined);
            const lastDecision = r.decisions?.[0];
            return [
              <input key="c" type="checkbox" aria-label={`Tick ${r.name}`} checked={!!sel[r.student_id]} disabled={!!why || cannotJoin} title={title} onChange={() => toggle(r)} />,
              <span key="s"><Two a={r.name} b={<span className="tnum">{r.number ?? "—"}</span>} /><StudentOpen id={r.student_id} label="Record" kind="link" /></span>,
              <span key="p"><span className="sub2">{r.programme_code ?? ""}</span><div style={levelsDiffer(r) ? { color: "var(--amber-ink)" } : undefined}>{levelWords(r)}</div></span>,
              <span key="d" className="tnum">{naira(r.due)}</span>,
              <span key="a" className="tnum">{naira(r.paid)}</span>,
              <span key="x"><b className="tnum">{naira(r.excess)}</b>
                {num(r.decided) > 0 ? <div className="sub2">{naira(r.decided)} decided</div> : null}
                {num(r.refunded_by_hand) > 0 ? <div className="sub2">{naira(r.refunded_by_hand)} refunded on Refunds &amp; Credits</div> : null}</span>,
              <span key="k">{r.cause ? <Pil kind={isPaidTwice(r.cause) ? "info" : "grey"}>{CAUSE_WORDS[r.cause] ?? r.cause}</Pil> : <span className="sub2">—</span>}
                {r.repeat_amount != null && num(r.repeat_amount) > 0 ? <div className="sub2">repeat of {naira(r.repeat_amount)}</div> : null}
                {r.cause && isPaidTwice(r.cause) && !r.bulk ? <div className="sub2">not an exact repeat</div> : null}
                {r.suggested ? <div className="sub2">{SUGGESTED_WORDS[r.suggested] ?? r.suggested}</div> : null}</span>,
              <span key="y">
                <button type="button" className="lnk" style={{ background: "none", border: "none", padding: 0, cursor: "pointer", font: "inherit" }} aria-expanded={!!openPay[r.student_id]}
                  onClick={() => setOpenPay((o) => ({ ...o, [r.student_id]: !o[r.student_id] }))}>{num(r.n_payments)} {num(r.n_payments) === 1 ? "payment" : "payments"}</button>
                {openPay[r.student_id] ? (
                  <ul style={{ margin: "4px 0 0", paddingLeft: 16 }}>
                    {(r.payments ?? []).map((p, i) => <li key={i} className="sub2">{naira(p.amount)} · {p.channel || "—"} · {p.on ? day(p.on) : "—"} · {paymentKindWord(p.kind)}</li>)}
                  </ul>
                ) : null}
              </span>,
              <span key="h">{(r.holds ?? []).length ? (r.holds ?? []).map((h) => <div key={h}><Pil kind="warn" title={holdRemedy(h)}>{holdWord(h)}</Pil></div>) : <span className="sub2">—</span>}</span>,
              <span key="t"><Pil kind={STATE_WORDS[r.state]?.[1] ?? "grey"}>{STATE_WORDS[r.state]?.[0] ?? r.state}</Pil>
                {r.state === "OVER_DECIDED" ? <div className="sub2">{naira(r.over_decided)} to recover</div> : null}
                {r.request ? <div className="sub2"><span className="tnum">{r.request.ref}</span>{r.request.by ? ` · by ${r.request.mine ? "you" : r.request.by}` : ""}</div> : null}
                {r.request?.skip ? <div className="sub2">{r.request.skip}</div> : null}
                {!r.request && lastDecision?.reference ? <div className="sub2 tnum">{lastDecision.reference}</div> : null}</span>,
            ];
          })} />
      ) : <PBody><div className="sub2">{data ? (filtered ? "No student matches these filters." : `No student is paid above the charge for ${session}.`) : problem ? "" : "Reading…"}</div></PBody>}
      {data && total > size ? (
        <PBody>
          <div className="row row--tight" style={{ alignItems: "center" }}>
            <Btn kind="ghost" size="sm" disabled={page <= 0} onClick={() => nav({ page: page - 1 > 0 ? String(page - 1) : "" })}>Previous</Btn>
            <span className="sub2">{(page * size + 1).toLocaleString("en-GB")}–{Math.min(total, (page + 1) * size).toLocaleString("en-GB")} of {total.toLocaleString("en-GB")}</span>
            <Btn kind="ghost" size="sm" disabled={(page + 1) * size >= total} onClick={() => nav({ page: String(page + 1) })}>Next</Btn>
          </div>
        </PBody>
      ) : null}
      {acting ? (
        <ActModal kind={acting} session={session} chosen={chosen} cause={allCause} ready={allReady} onClose={() => setActing(null)}
          onDone={(a) => { setActing(null); setSel({}); if (a) setActed(a); reread(); }} />
      ) : null}
    </Panel>
  );
}

/** asking for a wallet credit, or raising a refund, for the students ticked or for a paid-twice cause as a whole: the reason, the
 *  officer's confirmation that the payments were looked at and — for one student who is not an exact repeated payment — that the fee
 *  setup was checked. A request or a refund runs call after call until nothing is left; one request is one batch. */
function ActModal({ kind, session, chosen, cause, ready, onClose, onDone }: {
  kind: "credit" | "refund"; session: string; chosen: OverpaidDeskRow[]; cause: OverpaidCause | null; ready?: { ready: number; readyAmount: number };
  onClose: () => void; onDone: (a: Acted | null) => void;
}) {
  const [reason, setReason] = useState("");
  const [looked, setLooked] = useState(false);
  const [setup, setSetup] = useState(false);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<string | null>(null);
  const sel = chosen.length ? selectionFor(kind, chosen) : null;
  const whole = !sel && cause;
  const n = sel ? sel.count : num(ready?.ready);
  const amount = sel ? sel.amount : num(ready?.readyAmount);
  const needsTick = !!sel?.needsTick;
  const ok = reason.trim().length >= 10 && looked && (!needsTick || setup) && (sel ? sel.count > 0 : !!whole);

  async function run() {
    setBusy(true);
    const calls: (RequestAnswer | RefundAnswer)[] = [];
    try {
      let batch: string | null = null;
      for (let i = 0; i < 200; i++) {
        const body = actBody({ session, students: sel?.ids, cause: whole ? cause : null, reason, feeSetupChecked: needsTick && setup, batch: kind === "credit" ? batch : null, limit: kind === "credit" ? 1000 : 2000 });
        const a = await postOverpaid<RequestAnswer & RefundAnswer>(kind === "credit" ? "/credits/request" : "/refund", body,
          kind === "credit" ? `Overpaid school fees of ${session}: wallet credit requested: ${reason.trim()}` : `Overpaid school fees of ${session}: refund raised: ${reason.trim()}`);
        if (!a) break;
        calls.push(a);
        batch = batch ?? (a as RequestAnswer).batch ?? null;
        const t = addUp(calls);
        setProgress(kind === "credit" ? `${count(t.requested, "student")} requested${num(a.remaining) > 0 ? `, ${num(a.remaining).toLocaleString("en-GB")} to go` : ""}…`
          : `${count(t.refunds, "refund")} raised${num(a.remaining) > 0 ? `, ${num(a.remaining).toLocaleString("en-GB")} to go` : ""}…`);
        if (kind === "credit" ? requestDone(a as RequestAnswer) : refundDone(a as RefundAnswer)) break;
      }
      onDone(calls.length ? { act: kind === "credit" ? "request" : "refund", totals: addUp(calls) } : null);
    } finally { setBusy(false); setProgress(null); }
  }

  return (
    <Modal title={kind === "credit" ? `Credit ${count(n, "student")} to the wallet` : `Raise ${count(n, "refund")}`}
      sub={`${session}${whole ? ` · every ready student: ${CAUSE_WORDS[cause]}, in every faculty and department` : ""}`} onClose={() => { if (!busy) onClose(); }}
      foot={<><Btn kind="primary" busy={busy} busyLabel={progress ?? "Working…"} disabled={busy || !ok} onClick={run}>{kind === "credit" ? "Request the credit" : "Raise the refund"}</Btn>
        <Btn kind="ghost" disabled={busy} onClick={onClose}>Cancel</Btn></>}>
      <p>
        <b>{whole ? `Up to ${count(n, "student")}` : count(n, "student")}</b> · <b>{whole ? "up to " : ""}{naira(amount)}</b> not yet decided.{" "}
        {kind === "credit" ? "Nothing is credited now: another Bursary officer approves." : "A refund is raised for each on Refunds & Credits; another officer approves it, and it is paid with the transfer reference and date."}
      </p>
      {sel?.leftOut.length ? (
        <Note kind="info" title={`${count(sel.leftOut.length, "student")} left out`}>
          {sel.leftOut.length === 1 ? "This student is" : "These students are"} graduated, withdrawn or no longer students of the University: the excess is refunded, never credited to a wallet. Raise a refund for {sel.leftOut.length === 1 ? "them" : "each"} instead:
          {" "}{sel.leftOut.slice(0, 5).map((r) => r.name).join("; ")}{sel.leftOut.length > 5 ? `; and ${sel.leftOut.length - 5} more` : ""}.
        </Note>
      ) : null}
      {whole && kind === "credit" ? <div className="sub2 mb-2">Students who are refund-only are left out and named afterwards.</div> : null}
      <Field id="oa-reason" label="Why" required hint="At least ten characters; kept with each request">
        <textarea id="oa-reason" className="ctl" rows={2} maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)}
          placeholder={kind === "credit" ? "e.g. paid twice on the portal; the repeated payment is on the bank's statement" : "e.g. paid twice; the student asked for the money back"} />
      </Field>
      <label className="row row--inline row--tight" style={{ alignItems: "flex-start", gap: 8 }}>
        <input type="checkbox" checked={looked} onChange={(e) => setLooked(e.target.checked)} />
        <span>I have looked at the payments behind these students&rsquo; excess.</span>
      </label>
      {needsTick ? (
        <label className="row row--inline row--tight mt-2" style={{ alignItems: "flex-start", gap: 8 }}>
          <input type="checkbox" checked={setup} onChange={(e) => setSetup(e.target.checked)} />
          <span>The fee setup for this student&rsquo;s programme and level, and the payments, were checked.</span>
        </label>
      ) : null}
    </Modal>
  );
}

/* ── the requests made on this desk: the approvals tab and the returned tab ── */

type Maybe = ReturnType<typeof overpaidMay>;

/** one page of the requests made on the desk (GET /credits); null, the problem shown, when the server refused it */
async function readCredits(session: string, status: string, batch: string | null, page: number): Promise<CreditRequestRow[] | null> {
  const qs = new URLSearchParams({ session, status, page: String(page), size: String(PAGE) });
  if (batch) qs.set("batch", batch);
  const r = await fetch(`${BASE}/credits?${qs.toString()}`, { cache: "no-store" }).catch(() => null);
  const j = r ? await r.json().catch(() => null) : null;
  if (!r || !r.ok) { notifyProblem((j ?? { status: r?.status ?? 0, title: r?.statusText || "The portal could not be reached" }) as Problem); return null; }
  return creditRows(j);
}

function NoteModal({ title, label, hint, confirm, onClose, onConfirm }: { title: string; label: string; hint: string; confirm: string; onClose: () => void; onConfirm: (note: string) => Promise<void> }) {
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  return (
    <Modal title={title} onClose={() => { if (!busy) onClose(); }}
      foot={<><Btn kind="primary" busy={busy} disabled={busy || note.trim().length < 10} onClick={async () => { setBusy(true); try { await onConfirm(note.trim()); } finally { setBusy(false); } }}>{confirm}</Btn>
        <Btn kind="ghost" disabled={busy} onClick={onClose}>Cancel</Btn></>}>
      <Field id="on-note" label={label} required hint={hint}>
        <textarea id="on-note" className="ctl" rows={2} maxLength={500} value={note} onChange={(e) => setNote(e.target.value)} />
      </Field>
    </Modal>
  );
}

function ApprovalsTab({ session, figures, may, stamp, setActed, reread }: { session: string; figures: OverpaidFigures; may: Maybe; stamp: number; setActed: (a: Acted | null) => void; reread: () => void }) {
  const batches = (figures.requests.batches ?? []).filter((b) => num(b.pending) > 0);
  const [openBatch, setOpenBatch] = useState<string | null>(null);
  const [approving, setApproving] = useState<CreditBatch | null>(null);
  const [noting, setNoting] = useState<{ b: CreditBatch; act: "RETURN" | "REJECT" } | null>(null);
  const [withdrawing, setWithdrawing] = useState<CreditBatch | null>(null);
  const q = figures.requests;
  const mayWithdraw = (b: CreditBatch) => may.credit && (b.mine || may.decide);

  return (
    <Panel title={`Wallet credits waiting for approval · ${session}`} right={`${num(q.pending).toLocaleString("en-GB")} waiting · ${naira(q.pendingAmount)}`}>
      {batches.length ? (
        <DTable pageSize={0} cols={["Batch", "Cause", "Requested by", "Students|num", "Amount|num", "Action"]}
          rows={batches.map((b) => [
            <span key="b"><b className="tnum">{b.batch}</b>{num(b.skipped) > 0 ? <div className="sub2">{num(b.skipped).toLocaleString("en-GB")} left by an earlier approval</div> : null}</span>,
            <span key="c">{causeWord(b.cause)}</span>,
            <span key="r">{b.mine ? "You" : b.requestedBy || "An officer"}<div className="sub2">{asOf(b.requestedAt)}</div></span>,
            <span key="n" className="tnum">{num(b.pending).toLocaleString("en-GB")}{num(b.returned) > 0 ? <div className="sub2">{num(b.returned)} returned</div> : null}</span>,
            <span key="a" className="tnum">{naira(b.amount)}</span>,
            <span key="x" className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
              <Btn kind="ghost" size="sm" onClick={() => setOpenBatch(openBatch === b.batch ? null : b.batch)}>{openBatch === b.batch ? "Close" : "Open"}</Btn>
              {may.decide && !b.mine ? <Btn kind="primary" size="sm" onClick={() => setApproving(b)}>Approve</Btn> : null}
              {may.decide && !b.mine ? <Btn kind="ghost" size="sm" onClick={() => setNoting({ b, act: "RETURN" })}>Return</Btn> : null}
              {may.decide && !b.mine ? <Btn kind="ghost" size="sm" onClick={() => setNoting({ b, act: "REJECT" })}>Reject</Btn> : null}
              {b.mine ? <span className="sub2">Another Bursary officer approves this</span> : null}
              {mayWithdraw(b) ? <Btn kind="ghost" size="sm" onClick={() => setWithdrawing(b)}>Withdraw</Btn> : null}
            </span>,
          ])} />
      ) : (
        <PBody><div className="sub2">No wallet credit request is waiting. A request is made from the Students tab; a different Bursary officer approves it.</div></PBody>
      )}
      {q.single > 0 ? <PBody><div className="sub2">{count(q.single, "single request")} wait on Legacy Financial Reconciliation, where each is decided. <a className="lnk" href="/finance/legacy-reconciliation?tab=requests">Open them</a></div></PBody> : null}
      {openBatch ? (
        <RequestsList key={`${openBatch}#${stamp}`} session={session} status="PENDING_BURSAR_APPROVAL" batch={openBatch} may={may} setActed={setActed} reread={reread} />
      ) : null}
      {approving ? (
        <ApproveModal title={`Approve ${approving.batch}`} sub={`${session}${approving.requestedBy ? ` · requested by ${approving.requestedBy}` : ""}`} count={num(approving.pending)} amount={num(approving.amount)}
          upTo={num(approving.returned) > 0} target={{ batch: approving.batch }} onClose={() => setApproving(null)}
          onDone={(t) => { setApproving(null); if (t) setActed({ act: "approve", totals: t }); reread(); }} />
      ) : null}
      {noting ? (
        <NoteModal title={`${noting.act === "RETURN" ? "Return" : "Reject"} ${noting.b.batch}`} label="Note" confirm={noting.act === "RETURN" ? "Return for correction" : "Reject"}
          hint={noting.act === "RETURN" ? "At least ten characters; the requester reads it. No student is told." : "At least ten characters. No student is told."} onClose={() => setNoting(null)}
          onConfirm={async (note) => {
            const t = await runDecide({ batch: noting.b.batch }, noting.act, note, `Overpaid school fees: batch ${noting.b.batch} ${noting.act === "RETURN" ? "returned" : "rejected"}: ${note}`);
            setNoting(null);
            if (t) setActed({ act: noting.act === "RETURN" ? "return" : "reject", totals: t });
            reread();
          }} />
      ) : null}
      {withdrawing ? (
        <NoteModal title={`Withdraw ${withdrawing.batch}`} label="Why" confirm="Withdraw" hint="At least ten characters; kept with each request" onClose={() => setWithdrawing(null)}
          onConfirm={async (reason) => {
            const r = await postOverpaid<{ withdrawn: number }>("/credits/withdraw", { batch: withdrawing.batch, reason }, `Overpaid school fees: batch ${withdrawing.batch} withdrawn: ${reason}`);
            setWithdrawing(null);
            if (r) setActed({ words: `${count(r.withdrawn, "request")} withdrawn from ${withdrawing.batch}.` });
            reread();
          }} />
      ) : null}
    </Panel>
  );
}

function ReturnedTab({ session, may, stamp, setActed, reread }: { session: string; may: Maybe; stamp: number; setActed: (a: Acted | null) => void; reread: () => void }) {
  return (
    <Panel title={`Wallet credits returned for correction · ${session}`} right="Withdraw each, then request the student again">
      <PBody>
        <div className="sub2">The Bursar returned these with a note. Nothing is resubmitted here: the officer who requested them withdraws each and requests the student again from the Students tab once what the note names is put right.</div>
      </PBody>
      <RequestsList key={`returned#${stamp}`} session={session} status="RETURNED_FOR_CORRECTION" batch={null} may={may} setActed={setActed} reread={reread} />
    </Panel>
  );
}

/** the requests of one batch (or every returned request), read page by page from GET /credits; the ones ticked are approved, returned,
 *  rejected or withdrawn. A request made by the officer reading is never decided by the same officer. */
function RequestsList({ session, status, batch, may, setActed, reread }: {
  session: string; status: "PENDING_BURSAR_APPROVAL" | "RETURNED_FOR_CORRECTION"; batch: string | null; may: Maybe; setActed: (a: Acted | null) => void; reread: () => void;
}) {
  const [rows, setRows] = useState<CreditRequestRow[] | null>(null);
  const [page, setPage] = useState(0);
  const [more, setMore] = useState(false);
  const [sel, setSel] = useState<Record<string, boolean>>({});
  const [approving, setApproving] = useState(false);
  const [noting, setNoting] = useState<"RETURN" | "REJECT" | "WITHDRAW" | null>(null);
  const [loading, setLoading] = useState(false);
  const pending = status === "PENDING_BURSAR_APPROVAL";

  useEffect(() => {
    let live = true;
    void readCredits(session, status, batch, 0).then((got) => { if (live && got) { setRows(got); setPage(0); setMore(got.length >= PAGE); } });
    return () => { live = false; };
  }, [session, status, batch]);
  async function next() {
    setLoading(true);
    const got = await readCredits(session, status, batch, page + 1);
    setLoading(false);
    if (got) { setRows((old) => [...(old ?? []), ...got]); setPage(page + 1); setMore(got.length >= PAGE); }
  }

  const list = rows ?? [];
  const chosen = list.filter((r) => sel[r.id]);
  const decidable = (r: CreditRequestRow) => pending && may.decide && !r.mine;
  const withdrawable = (r: CreditRequestRow) => may.credit && (r.mine || may.decide);
  const ids = (f: (r: CreditRequestRow) => boolean) => chosen.filter(f).map((r) => r.id);
  const toDecide = ids(decidable);
  const toWithdraw = ids(withdrawable);
  const decideAmount = chosen.filter(decidable).reduce((a, r) => a + num(r.confirmed_amount), 0);

  return (
    <>
      <PBody>
        <div className="row row--tight" style={{ flexWrap: "wrap", alignItems: "center" }}>
          <span className="sub2 grow">{batch ? `${batch} · ` : ""}{rows ? `${count(list.length, "request")}${more ? " read so far" : ""}` : "Reading…"}{chosen.length ? ` · ${chosen.length} ticked` : ""}</span>
          {toDecide.length ? <Btn kind="primary" size="sm" onClick={() => setApproving(true)}>Approve {toDecide.length}</Btn> : null}
          {toDecide.length ? <Btn kind="ghost" size="sm" onClick={() => setNoting("RETURN")}>Return {toDecide.length}</Btn> : null}
          {toDecide.length ? <Btn kind="ghost" size="sm" onClick={() => setNoting("REJECT")}>Reject {toDecide.length}</Btn> : null}
          {toWithdraw.length ? <Btn kind="ghost" size="sm" onClick={() => setNoting("WITHDRAW")}>Withdraw {toWithdraw.length}</Btn> : null}
        </div>
      </PBody>
      {rows && !list.length ? <PBody><div className="sub2">{pending ? "Nothing is waiting in this batch." : "No request is returned for correction."}</div></PBody> : null}
      {list.length ? (
        <DTable pageSize={50} cols={["|mid", "Request", "Student", "Amount|num", "Evidence", pending ? "Requested by" : "Bursar's note"]}
          texts={list.map((r) => `${r.ref} ${r.student} ${r.matric_no ?? ""} ${r.admission_no ?? ""}`)}
          rows={list.map((r) => {
            const can = decidable(r) || withdrawable(r);
            return [
              <input key="c" type="checkbox" aria-label={`Tick ${r.ref}`} checked={!!sel[r.id]} disabled={!can}
                title={can ? undefined : r.mine && pending ? "Your own request: another Bursary officer decides it" : "Your office does not act on this request"}
                onChange={() => setSel((s) => ({ ...s, [r.id]: !s[r.id] }))} />,
              <span key="r"><b className="tnum">{r.ref}</b>{r.request_batch ? <div className="sub2 tnum">{r.request_batch}</div> : null}</span>,
              <span key="s"><Two a={r.student} b={<span className="tnum">{r.matric_no ?? r.admission_no ?? "—"}</span>} />{r.cause ? <div className="sub2">{causeWord(r.cause)}</div> : null}</span>,
              <b key="a" className="tnum">{naira(r.confirmed_amount)}</b>,
              <span key="e" className="sub2">{r.evidence}{r.last_skip_why ? <div style={{ color: "var(--amber-ink)" }}>{r.last_skip_why}</div> : null}</span>,
              pending ? <span key="b" className="sub2">{r.mine ? "You" : r.initiated_by ?? r.initiated_office}<div className="tnum">{day(r.initiated_at)}</div></span>
                : <span key="b" className="sub2">{r.decision_note ?? "—"}<div>{r.decided_by ?? ""}{r.decided_at ? ` · ${day(r.decided_at)}` : ""}</div></span>,
            ];
          })} />
      ) : null}
      {more ? <PBody><Btn kind="ghost" size="sm" disabled={loading} onClick={next}>{loading ? "Reading…" : "Read the next page"}</Btn></PBody> : null}
      {approving ? (
        <ApproveModal title={`Approve ${toDecide.length} wallet credits`} sub={session} count={toDecide.length} amount={decideAmount} target={{ ids: toDecide }} onClose={() => setApproving(false)}
          onDone={(t) => { setApproving(false); setSel({}); if (t) setActed({ act: "approve", totals: t }); reread(); }} />
      ) : null}
      {noting ? (
        <NoteModal title={`${noting === "RETURN" ? "Return" : noting === "REJECT" ? "Reject" : "Withdraw"} ${noting === "WITHDRAW" ? toWithdraw.length : toDecide.length} request${(noting === "WITHDRAW" ? toWithdraw.length : toDecide.length) === 1 ? "" : "s"}`}
          label={noting === "WITHDRAW" ? "Why" : "Note"} confirm={noting === "RETURN" ? "Return for correction" : noting === "REJECT" ? "Reject" : "Withdraw"}
          hint={noting === "WITHDRAW" ? "At least ten characters; kept with each request" : "At least ten characters. No student is told."} onClose={() => setNoting(null)}
          onConfirm={async (note) => {
            if (noting === "WITHDRAW") {
              const r = await postOverpaid<{ withdrawn: number }>("/credits/withdraw", { ids: toWithdraw, reason: note }, `Overpaid school fees: ${toWithdraw.length} requests withdrawn: ${note}`);
              if (r) setActed({ words: `${count(r.withdrawn, "request")} withdrawn.` });
            } else {
              const t = await runDecide({ ids: toDecide }, noting, note, `Overpaid school fees: ${toDecide.length} requests ${noting === "RETURN" ? "returned" : "rejected"}: ${note}`);
              if (t) setActed({ act: noting === "RETURN" ? "return" : "reject", totals: t });
            }
            setNoting(null); setSel({}); reread();
          }} />
      ) : null}
    </>
  );
}
