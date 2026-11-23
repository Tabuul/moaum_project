"use client";

/**
 * V781: overpaid school fees on the Bursar's and the Students Account Officer's dashboards, and the approval of wallet credits both the
 * dashboard and the Overpaid school fees desk use. The panel reads the kept list's figures (GET /finance/overpaid/figures — never a
 * session's whole read), by cause, with what is held, what waits for the officer, what is credited and refunded; a Bursary officer
 * other than the one who requested a batch approves it here, call after call of one pass until nothing is left. The server holds every
 * rule and works out every figure. Nothing is credited to fees by an approval: the wallet is credited, the student told, and the student
 * applies it on the Wallet page or asks there for a refund.
 */
import { useEffect, useRef, useState, type ReactNode } from "react";
import Link from "next/link";
import { notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import {
  APPROVE_WORDS, CAUSES, CAUSE_WORDS, actWords, addUp, asOf, batchWords, commonestHolds, count, decideDone, naira, num, overDecidedWords, overpaidHref, skipTitle,
  type ActTotals, type CreditBatch, type DecideAnswer, type OverpaidFigures, type SkipWhy,
} from "@/lib/overpaid";

const BASE = "/api/bff/api/v1/finance/overpaid";

/** a POST to the Overpaid desk's API with the reason the audit trail keeps; null (the problem shown) when the server refused it */
export async function postOverpaid<T>(path: string, body: unknown, reason: string): Promise<T | null> {
  const r = await fetch(`${BASE}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) }).catch(() => null);
  const j = r ? await r.json().catch(() => null) : null;
  if (!r || !r.ok) {
    notifyProblem((j ?? { status: r?.status ?? 0, title: r?.statusText || "The portal could not be reached" }) as Problem);
    return null;
  }
  return j as T;
}

/** one pass of an approval, a return or a rejection of a batch or of the requests named: call after call, the first answer's `since`
 *  passed back, until nothing is left or a call tried nothing. What a call left is marked and not tried again in the pass, so the
 *  loop ends. The totals of the calls made — also when a later call was refused (its problem is shown). */
export async function runDecide(target: { batch?: string | null; ids?: readonly string[] }, action: "APPROVE" | "REJECT" | "RETURN", note: string, reason: string,
  onProgress?: (words: string) => void): Promise<ActTotals | null> {
  const calls: DecideAnswer[] = [];
  let since: string | undefined;
  for (let i = 0; i < 500; i++) {
    const body: Record<string, unknown> = { action, limit: 200 };
    if (target.batch) body.batch = target.batch; else body.ids = [...(target.ids ?? [])];
    if (note.trim()) body.note = note.trim();
    if (since) body.since = since;
    const a = await postOverpaid<DecideAnswer>("/credits/decide", body, reason);
    if (!a) break;
    calls.push(a);
    since = a.since ?? since;
    const t = addUp(calls);
    onProgress?.(`${t.credited + t.rejected + t.returned ? count(t.credited + t.rejected + t.returned, "request") : "Nothing"} decided${num(a.remaining) > 0 ? `, ${num(a.remaining).toLocaleString("en-GB")} to go` : ""}…`);
    if (decideDone(a)) break;
  }
  return calls.length ? addUp(calls) : null;
}

/** what an act did, with the first sentences the server left students with */
export function ActResult({ act, totals, onClose }: { act: Parameters<typeof actWords>[0]; totals: ActTotals; onClose?: () => void }) {
  const w = actWords(act, totals);
  const why: SkipWhy[] = totals.skippedWhy;
  return (
    <Note kind={w.tone === "ok" ? "ok" : w.tone === "bad" ? "bad" : "info"} title={w.title} action={onClose ? <Btn kind="ghost" size="sm" onClick={onClose}>Dismiss</Btn> : null}>
      {w.text}
      {why.length ? (
        <ul style={{ margin: "6px 0 0", paddingLeft: 18 }}>
          {why.slice(0, 5).map((s, i) => <li key={`${s.id ?? s.student_id ?? i}`}><b>{skipTitle(s.code)}</b>{s.name || s.number ? ` · ${s.name ?? s.number}` : ""}: {s.why}</li>)}
          {why.length > 5 ? <li>and {why.length - 5} more: the desk lists each beside its request.</li> : null}
        </ul>
      ) : null}
    </Note>
  );
}

/** the confirmation before a batch or some requests are approved: how many and how much, what an approval does and does not do */
export function ApproveModal({ title, sub, count: n, amount, upTo, target, onClose, onDone }: {
  title: string; sub?: ReactNode; count: number; amount: number; upTo?: boolean; target: { batch?: string | null; ids?: readonly string[] };
  onClose: () => void; onDone: (t: ActTotals | null) => void;
}) {
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<string | null>(null);
  async function go() {
    setBusy(true);
    try {
      const t = await runDecide(target, "APPROVE", note, `Overpaid school fees: ${target.batch ? `batch ${target.batch}` : `${n} requests`} approved`, setProgress);
      onDone(t);
    } finally { setBusy(false); setProgress(null); }
  }
  return (
    <Modal title={title} sub={sub} onClose={() => { if (!busy) onClose(); }}
      foot={<><Btn kind="primary" busy={busy} busyLabel={progress ?? "Approving…"} disabled={busy} onClick={go}>Approve</Btn><Btn kind="ghost" disabled={busy} onClick={onClose}>Cancel</Btn></>}>
      <p><b>{count(n, "student")}</b> · {upTo ? "up to " : ""}<b>{naira(amount)}</b></p>
      <p>{APPROVE_WORDS}</p>
      <Field id="oa-note" label="Note" hint="Optional; kept with each credit"><input id="oa-note" className="ctl" maxLength={500} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
    </Modal>
  );
}

/** how the panel is used: the Bursar's dashboard approves, the Students Account Officer's requests, any other reader reads */
export type PanelMode = "approve" | "request" | "read";

const ORDER = CAUSES;

export function OverpaidPanel({ initial, mode }: { initial: OverpaidFigures; mode: PanelMode }) {
  const [f, setF] = useState<OverpaidFigures>(initial);
  const [session, setSession] = useState(initial.session);
  const [reading, setReading] = useState(false);
  const [approving, setApproving] = useState<CreditBatch | null>(null);
  const [done, setDone] = useState<ActTotals | null>(null);
  const [tick, setTick] = useState(0);

  // the figures the server drew the page with are the first read; every later change of session, and every approval, reads again
  const first = useRef(true);
  useEffect(() => {
    if (first.current) { first.current = false; return; }
    let live = true;
    setReading(true);
    fetch(`${BASE}/figures?session=${encodeURIComponent(session)}`, { cache: "no-store", headers: { "X-Background": "1" } })
      .then(async (r) => { const j = r.ok ? ((await r.json()) as OverpaidFigures) : null; if (live && j) setF(j); })
      .catch(() => undefined)
      .finally(() => { if (live) setReading(false); });
    return () => { live = false; };
  }, [session, tick]);

  const desk = (extra: Record<string, string> = {}) => overpaidHref({ session, ...extra });
  const sessions = f.sessions?.includes(session) ? f.sessions : [session, ...(f.sessions ?? [])];
  const q = f.requests;
  const open = (q.batches ?? []).filter((b) => num(b.pending) > 0);
  const forYouBatches = open.filter((b) => !b.mine);
  const heldWords = commonestHolds(f.held.reasons);
  const over = overDecidedWords(f.overDecided.students, f.overDecided.amount);
  const right = (
    <span className="row row--inline row--tight">
      <select id="op-session" aria-label="Session" className="ctl" style={{ width: "auto" }} value={session} onChange={(e) => setSession(e.target.value)} disabled={reading}>
        {sessions.map((x) => <option key={x} value={x}>{x}</option>)}
      </select>
      <LinkBtn kind="ghost" href={desk()}>Open the desk</LinkBtn>
    </span>
  );

  const waiting: [ReactNode, ReactNode, string | null, ReactNode, string?] = mode === "approve"
    ? ["Waiting for your approval", num(q.forYou).toLocaleString("en-GB"), q.forYou ? "var(--red-ink)" : null,
        `${naira(q.forYouAmount)} in ${count(forYouBatches.length, "request batch", "request batches")}`, desk({ tab: "approvals" })]
    : ["Waiting for the Bursar", num(mode === "request" ? q.mine : q.pending).toLocaleString("en-GB"), null,
        `${naira(mode === "request" ? q.mineAmount : q.pendingAmount)} requested${mode === "request" ? " by you" : ""} · another Bursary officer approves`, desk({ tab: "approvals" })];
  const tiles: [ReactNode, ReactNode, string | null, ReactNode, string?][] = [
    ["Paid twice — ready", num(f.paidTwice.ready).toLocaleString("en-GB"), f.paidTwice.ready ? "var(--green-ink)" : null,
      `${naira(f.paidTwice.readyAmount)} · the repeat makes up the excess exactly · of ${num(f.paidTwice.students).toLocaleString("en-GB")} paid twice not yet decided`,
      desk({ state: "UNDECIDED", held: "false", bulk: "true" })],
    ["Check the fee setup first", num(f.apart.students).toLocaleString("en-GB"), null, `${naira(f.apart.amount)} · not an exact repeated payment; decided one student at a time`,
      desk({ state: "UNDECIDED", held: "false", bulk: "false" })],
    ["Held for a check", num(f.held.students).toLocaleString("en-GB"), f.held.students ? "var(--amber-ink)" : null, heldWords || `${naira(f.held.amount)}`, desk({ state: "UNDECIDED", held: "true" })],
    waiting,
    ...(mode === "request" ? [["Returned to you", num(q.returnedMine).toLocaleString("en-GB"), q.returnedMine ? "var(--red-ink)" : null, "Corrected by withdrawing and requesting again", desk({ tab: "returned" })] as [ReactNode, ReactNode, string | null, ReactNode, string?]] : []),
    ["Credited to wallets", num(f.credited.students).toLocaleString("en-GB"), "var(--green-ink)",
      `${naira(f.credited.amount)} · ${naira(f.credited.applied)} already used on fees · ${naira(f.credited.inWallets)} in wallets`, desk({ state: "CREDITED" })],
    ["Refunds", num(f.refunds.raised + f.refunds.approved + f.refunds.paid).toLocaleString("en-GB"), null,
      `${num(f.refunds.raised)} raised · ${num(f.refunds.approved)} approved · ${num(f.refunds.paid)} paid (${naira(f.refunds.paidAmount)})`, "/finance/refunds"],
  ];

  return (
    <Panel title="Overpaid school fees" right={right}>
      <PBody>
        {!f.computed ? (
          <Note kind="info" title={`Not yet worked out for ${session}`} action={<LinkBtn kind="ghost" href={desk()}>Open the desk</LinkBtn>}>
            The list of students paid above their charge is worked out when the Bursary or the Students Account Officer opens the desk and presses Refresh, and then every ten minutes while payments come in.
          </Note>
        ) : (
          <>
            <div className="sub2">Figures as of {asOf(f.refreshedAt) || "—"} · {num(f.students).toLocaleString("en-GB")} students paid {naira(f.excess)} above their charge{reading ? " · reading…" : ""}</div>
            <Tiles cls={tiles.length > 6 ? "grid--4" : "grid--3"} items={tiles} />
            {over ? <Note kind="info" title="A decision is above what is paid">{over} <Link className="lnk" href={desk({ state: "OVER_DECIDED" })}>Open them on the desk</Link></Note> : null}
            {done ? <ActResult act="approve" totals={done} onClose={() => setDone(null)} /> : null}
            {mode === "approve" && open.length ? (
              <div className="mt-2">
                {open.map((b) => (
                  <div key={b.batch} className="row row--tight" style={{ flexWrap: "wrap", alignItems: "center", padding: "6px 0", borderTop: "1px solid var(--line-2)" }}>
                    <span className="sub2 grow">{batchWords(b)}</span>
                    {b.mine ? <Pil kind="grey">Requested by you — another Bursary officer approves</Pil> : <Btn kind="primary" size="sm" onClick={() => setApproving(b)}>Approve</Btn>}
                    <LinkBtn kind="ghost" href={desk({ tab: "approvals" })}>Review</LinkBtn>
                  </div>
                ))}
              </div>
            ) : null}
            {q.single > 0 ? (
              <div className="sub2 mt-2">{count(q.single, "single request")} wait on Legacy Financial Reconciliation. <Link className="lnk" href="/finance/legacy-reconciliation?tab=requests">Open them</Link></div>
            ) : null}
            <div className="eyebrow mt-2">By cause</div>
            <DTable pageSize={0} cols={["Cause", "Students|num", "Paid above the charge|num", "Not decided|num", "Ready|num", "Held|num"]}
              rows={ORDER.map((c) => {
                const x = f.causes.find((y) => y.cause === c);
                return [
                  <Link key="c" className="lnk" href={desk({ cause: c })}>{CAUSE_WORDS[c]}</Link>,
                  <span key="s" className="tnum">{num(x?.students).toLocaleString("en-GB")}</span>,
                  <span key="e" className="tnum">{naira(x?.excess)}</span>,
                  <span key="u" className="tnum">{num(x?.undecided).toLocaleString("en-GB")} · {naira(x?.undecidedAmount)}</span>,
                  <span key="r" className="tnum">{num(x?.ready).toLocaleString("en-GB")} · {naira(x?.readyAmount)}</span>,
                  <span key="h" className="tnum">{num(x?.held).toLocaleString("en-GB")} · {naira(x?.heldAmount)}</span>,
                ];
              })} />
          </>
        )}
      </PBody>
      {approving ? (
        <ApproveModal title={`Approve ${approving.batch}`} sub={`${f.session}${approving.requestedBy ? ` · requested by ${approving.requestedBy}` : ""}`}
          count={num(approving.pending)} amount={num(approving.amount)} upTo={num(approving.returned) > 0} target={{ batch: approving.batch }}
          onClose={() => setApproving(null)} onDone={(t) => { setApproving(null); if (t) setDone(t); setTick((x) => x + 1); }} />
      ) : null}
    </Panel>
  );
}
