"use client";

/** V562: the months a signed bank reconciliation has closed on the ledger for 1010 or 1020 — no journal moving the account is
 *  posted with a date in them — and the requests to reopen one: asked by one officer of the Bursary on a reason (the latest signed
 *  month of an account only), approved or rejected by another. */
import { useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { money } from "@/components/proto/blocks";

interface Month { id: string; account: string; period_from: string; period_to: string; difference: number; signed_at: string; signed_by_name: string | null; latest: boolean; reopen_asked: boolean }
interface Request {
  id: string; account: string; period_from: string; period_to: string; reason: string; state: "REQUESTED" | "APPROVED" | "REJECTED"; requested_at: string; decided_at: string | null;
  decision_note: string | null; requested_by_name: string | null; decided_by_name: string | null; asked_by_me: boolean;
}
interface Closed { months: Month[]; requests: Request[] }

const ACCOUNT: Record<string, string> = { "1010": "1010 Bank — Fees collection", "1020": "1020 Bank — Disbursements" };
const day = (iso: string | null) => (iso ? new Date(`${iso.slice(0, 10)}T12:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
/** a whole month by its name, any other period by its days */
const period = (from: string, to: string) => {
  const a = new Date(`${from}T12:00:00`), b = new Date(`${to}T12:00:00`), next = new Date(b); next.setDate(b.getDate() + 1);
  return a.getDate() === 1 && next.getDate() === 1 && a.getMonth() === b.getMonth()
    ? a.toLocaleDateString("en-GB", { month: "long", year: "numeric" }) : `${day(from)} to ${day(to)}`;
};
const BASE = "/api/bff/api/v1/finance/bank-reconciliation";

export function ClosedMonths({ may }: { may: boolean }) {
  const [data, setData] = useState<Closed | null>(null);
  const [asking, setAsking] = useState<string | null>(null);
  const [reason, setReason] = useState("");
  const [notes, setNotes] = useState<Record<string, string>>({});

  useEffect(() => {
    let live = true;
    fetch(`${BASE}/closed`, { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null)
      .then((j: Closed | null) => { if (live) setData(j); });
    return () => { live = false; };
  }, []);

  async function post(path: string, body: unknown, why: string, done: string) {
    const r = await fetch(`${BASE}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(body) });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    setData(j as Closed);
    notify(done);
  }

  if (!data || (!data.months.length && !data.requests.length)) return null;
  const pending = data.requests.filter((q) => q.state === "REQUESTED");
  return (
    <Panel title="Closed months" right={`${data.months.length} signed`}>
      <PBody>
        <div className="sub2">A bank reconciliation signed closes its month on the ledger for its account: no journal moving it is posted with a date in the month, and what the ledger posts by itself for it goes on the first open day. Only the latest signed month of an account is reopened, on a reason one officer of the Bursary gives and another approves; it then goes back to prepared.</div>
      </PBody>
      <DTable pageSize={0} cols={["Account", "Month", "Signed", "Unexplained|num", "|num"]} rows={data.months.map((m) => [
        <span key="a">{ACCOUNT[m.account] ?? m.account}</span>,
        <b key="p">{period(m.period_from, m.period_to)}</b>,
        <Two key="s" a={m.signed_by_name ?? "—"} b={day(m.signed_at)} />,
        <span key="d" className="tnum">{Number(m.difference) ? money(Math.abs(Number(m.difference))) : "—"}</span>,
        <span key="x" className="row row--tight row--right" style={{ flexWrap: "wrap" }}>
          {m.reopen_asked ? <Pil kind="info">Reopening asked</Pil>
            : !m.latest ? <span className="sub2">A later month is signed</span>
            : !may ? <Pil kind="ok">Closed</Pil>
            : asking === m.id ? (
              <>
                <input className="ctl" aria-label={`Why ${period(m.period_from, m.period_to)} of ${m.account} is reopened`} placeholder="Why it is reopened" maxLength={2000}
                  value={reason} onChange={(e) => setReason(e.target.value)} style={{ width: 240 }} />
                <Btn kind="primary" size="sm" disabled={!reason.trim()} busyLabel="Asking…"
                  onClick={async () => { await post(`/${m.id}/reopen`, { reason: reason.trim() }, `Reopening ${m.account} for ${m.period_from} to ${m.period_to} asked`, "Reopening asked; another officer of the Bursary decides it"); setAsking(null); setReason(""); }}>Ask</Btn>
                <Btn kind="ghost" size="sm" onClick={() => { setAsking(null); setReason(""); }}>Cancel</Btn>
              </>
            ) : <Btn kind="ghost" size="sm" onClick={() => { setAsking(m.id); setReason(""); }}>Ask to reopen</Btn>}
        </span>,
      ])} />
      {data.requests.length ? (
        <>
          <PBody><b>Requests to reopen</b>{pending.length ? <span className="sub2">{` · ${pending.length} waiting for a decision`}</span> : null}</PBody>
          <DTable pageSize={0} cols={["Month", "Reason", "Asked", "Decision", "|num"]} rows={data.requests.map((q) => [
            <Two key="p" a={period(q.period_from, q.period_to)} b={ACCOUNT[q.account] ?? q.account} />,
            <span key="r">{q.reason}</span>,
            <Two key="a" a={q.requested_by_name ?? "—"} b={day(q.requested_at)} />,
            q.state === "REQUESTED" ? <Pil key="d" kind="info">Waiting</Pil>
              : <Two key="d" a={<Pil kind={q.state === "APPROVED" ? "ok" : "bad"}>{q.state === "APPROVED" ? "Reopened" : "Kept closed"}</Pil>} b={`${q.decided_by_name ?? "—"}, ${day(q.decided_at)}${q.decision_note ? ` · ${q.decision_note}` : ""}`} />,
            <span key="x" className="row row--tight row--right" style={{ flexWrap: "wrap" }}>
              {q.state === "REQUESTED" && may ? (q.asked_by_me ? <span className="sub2">Another officer decides it</span> : (
                <>
                  <input className="ctl" aria-label={`Note on reopening ${period(q.period_from, q.period_to)} of ${q.account}`} placeholder="Note (needed to keep it closed)" maxLength={2000}
                    value={notes[q.id] ?? ""} onChange={(e) => setNotes({ ...notes, [q.id]: e.target.value })} style={{ width: 200 }} />
                  <Btn kind="primary" size="sm" busyLabel="Reopening…" onClick={() => post(`/reopen/${q.id}/decide`, { approve: true, note: (notes[q.id] ?? "").trim() || null },
                    `Reopening ${q.account} for ${q.period_from} to ${q.period_to} approved`, "The month is open on the ledger again; its reconciliation is prepared, not signed")}>Reopen</Btn>
                  <Btn kind="ghost" size="sm" disabled={!(notes[q.id] ?? "").trim()} busyLabel="Saving…" onClick={() => post(`/reopen/${q.id}/decide`, { approve: false, note: (notes[q.id] ?? "").trim() },
                    `Reopening ${q.account} for ${q.period_from} to ${q.period_to} rejected`, "The month stays closed")}>Keep closed</Btn>
                </>
              )) : null}
            </span>,
          ])} />
        </>
      ) : null}
    </Panel>
  );
}
