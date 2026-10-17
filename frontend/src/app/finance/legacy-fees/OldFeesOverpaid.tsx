"use client";

/** V506, V519: every student overpaid in a session — through old-portal payments or the portal's (a reference paid twice) — and
 *  what the Bursary decides for each excess — carried into
 *  the next session (a CARRIED school-fees record there, which the fee gate counts; the ledger moves the income across, no new
 *  cash) or a refund raised on the Refunds & Credits desk (approved and paid there by two officers, as every refund). All the
 *  undecided at once or one student at a time, with a reason kept on each, the student told; the list as Excel. On Old Fees History
 *  and on Refunds & Credits. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, money } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { DECISION, OVERPAID_HEADERS, decideDone, overpaidRow, type Decision, type OverpaidRow } from "@/lib/old-fees";

interface Overpaid {
  session: string; sessions: string[]; nextSession: string | null; count: number; excess: number | string; undecided: number;
  undecidedExcess: number | string; decided: Partial<Record<Decision, number>>; oldPortal?: number; rows: OverpaidRow[];
}

/** what is being decided: every undecided student of the session, or one */
interface Asking { decision: Decision; who: OverpaidRow | null }

/** tick: a change made elsewhere on the page (the list reads again); onChanged: told when a decision changes the records */
export function OldFeesOverpaid({ may, tick = 0, onChanged }: { may: boolean; tick?: number; onChanged?: () => void }) {
  const [session, setSession] = useState("");
  const [data, setData] = useState<Overpaid | null>(null);
  const [answered, setAnswered] = useState<string | null>(null);
  const [own, setOwn] = useState(0);
  const [busy, setBusy] = useState<string | null>(null);
  const [asking, setAsking] = useState<Asking | null>(null);
  const [reason, setReason] = useState("");
  const [progress, setProgress] = useState<string | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const url = (limit: number) => `/api/bff/api/v1/finance/legacy-fees/overpaid?limit=${limit}${session ? `&session=${encodeURIComponent(session)}` : ""}`;
  const listUrl = url(200);
  const asked = `${listUrl}#${tick}#${own}`;
  const loading = answered !== asked;
  const shown = session || data?.session || "";

  useEffect(() => {
    let alive = true;
    void (async () => {
      const r = await fetch(listUrl, { cache: "no-store" }).catch(() => null);
      const j = r ? await r.json().catch(() => null) : null;
      if (!alive) return;
      setAnswered(asked);
      if (!r || !r.ok) { notifyProblem((j ?? { status: r?.status ?? 0, title: r?.statusText || "The portal could not be reached" }) as Problem); return; }
      setData(j as Overpaid);
    })();
    return () => { alive = false; };
  }, [listUrl, asked]);

  async function excel() {
    setBusy("excel");
    try {
      const r = await fetch(url(100_000), { cache: "no-store" });
      const j = (await r.json().catch(() => null)) as Overpaid | null;
      if (!r.ok || !j) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as unknown as Problem); return; }
      const blob = await brandedXlsx(`Old fees overpaid, ${j.session}`, OVERPAID_HEADERS, j.rows.map(overpaidRow), {
        sheetName: "Overpaid", serial: docSerial("OFO"),
        sub: `${j.count.toLocaleString()} student${j.count === 1 ? "" : "s"} · ${money(Number(j.excess))} paid beyond what the fee setup says was due`,
      });
      downloadBlob(blob, `old-fees-overpaid-${j.session.replace("/", "-")}.xlsx`);
    } finally {
      setBusy(null);
    }
  }

  async function decide() {
    if (!asking || !data) return;
    const { decision, who } = asking;
    setBusy("decide");
    setSaid(null);
    const t = { carried: 0, refunds: 0 };
    try {
      for (;;) {
        const r = await fetch("/api/bff/api/v1/finance/legacy-fees/overpaid/decide", {
          method: "POST",
          headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Overpaid fees of ${data.session} ${decision === "CARRY" ? "carried into the next session" : "to be refunded"}: ${reason.trim()}`) },
          body: JSON.stringify({ session: data.session, decision, students: who ? [who.student_id] : null, reason: reason.trim(), limit: 2000 }),
        });
        const j = await r.json().catch(() => null);
        if (!r.ok) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as Problem); break; }
        const w = j as { carried: number; refunds: number; remaining: number };
        t.carried += Number(w.carried); t.refunds += Number(w.refunds);
        setProgress(`${(t.carried + t.refunds).toLocaleString()} decided${Number(w.remaining) ? `, ${Number(w.remaining).toLocaleString()} to go` : ""}…`);
        if (decideDone(w)) break;
      }
      if (t.carried + t.refunds > 0) {
        setSaid(t.carried
          ? `${t.carried.toLocaleString()} excess${t.carried === 1 ? "" : "es"} carried into ${data.nextSession ?? "the next session"}: each counts there as school fees paid.`
          : `${t.refunds.toLocaleString()} refund${t.refunds === 1 ? "" : "s"} raised on the Refunds & Credits desk, to be approved and paid there.`);
        notify(t.carried ? "Carried into the next session" : "Refunds raised");
      }
      setAsking(null);
      setReason("");
    } finally {
      setProgress(null);
      setBusy(null);
      setOwn((x) => x + 1);
      onChanged?.();
    }
  }

  const decided = data?.decided ?? {};
  const next = data?.nextSession ?? null;
  return (
    <Panel title="Overpaid" right="Students who paid more than the fee setup says was due, through the old portal or the portal: carried into the next session, or refunded">
      <PBody>
        <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
          <Field id="ofo-session" label="Session" style={{ flex: "0 1 160px" }}>
            <select id="ofo-session" className="ctl" value={shown} onChange={(e) => setSession(e.target.value)} disabled={loading}>
              {(data?.sessions.length ? data.sessions : shown ? [shown] : []).map((s) => <option key={s} value={s}>{s}</option>)}
              {data && shown && !data.sessions.includes(shown) ? <option value={shown}>{shown}</option> : null}
            </select>
          </Field>
          <Btn kind="ghost" disabled={loading || !!busy || !data?.count} onClick={() => void excel()}>{busy === "excel" ? "Preparing…" : "Excel"}</Btn>
          {loading && data ? <span className="sub2" role="status">Looking…</span> : null}
        </div>
      </PBody>
      {said ? <PBody><Note kind="ok" title="Decided">{said} Each decision is kept with your reason.</Note></PBody> : null}
      {!data ? <PBody><div className="sub2">{loading ? "Looking…" : ""}</div></PBody>
        : !data.count ? (
          <PBody><div className="sub2">No student paid more than the fee setup says was due for {data.session}.</div></PBody>
        ) : (
          <>
            <PBody>
              <Tiles items={[
                ["Overpaid", data.count.toLocaleString(), "var(--red-ink)", `${money(Number(data.excess))} beyond what was due${data.oldPortal != null ? ` · ${Number(data.oldPortal).toLocaleString()} with old-portal payments` : ""}`],
                ["Not decided", data.undecided.toLocaleString(), data.undecided ? "var(--red-ink)" : null, money(Number(data.undecidedExcess))],
                ["Carried into the next session", (decided.CARRY ?? 0).toLocaleString(), null, next ? `Into ${next}` : "No next session on the calendar"],
                ["Refund raised", (decided.REFUND ?? 0).toLocaleString(), null, "On the Refunds & Credits desk"],
              ]} />
              {may && data.undecided > 0 ? (
                <div className="row mt-2">
                  <Btn kind="primary" disabled={!!busy || loading || !next} onClick={() => setAsking({ decision: "CARRY", who: null })}>
                    {`Carry ${data.undecided.toLocaleString()} into ${next ?? "the next session"}`}
                  </Btn>
                  <Btn kind="ghost" disabled={!!busy || loading} onClick={() => setAsking({ decision: "REFUND", who: null })}>{`Raise ${data.undecided.toLocaleString()} refunds`}</Btn>
                </div>
              ) : null}
              {!next ? <Note kind="info" title="No next session">No session follows {data.session} on the academic calendar, so an excess cannot be carried yet; refunds can be raised.</Note> : null}
            </PBody>
            <DTable pageSize={0} cols={["Student", "Due|num", "Paid|num", "Excess|num", "Decided", ""]}
              rows={data.rows.map((o) => [
                <span key="s"><Two a={o.name} b={o.number} />{o.old_portal ? <span className="sub2">Old-portal payment among them</span> : null}</span>,
                <span key="d" className="tnum">{money(Number(o.due))}</span>,
                <span key="p" className="tnum">{money(Number(o.paid))}</span>,
                <b key="x" className="tnum">{money(Number(o.excess))}</b>,
                o.decision
                  ? <span key="c" className="sub2"><Pil kind="info">{DECISION[o.decision]}</Pil><div className="tnum">{o.reference}{o.refund_state ? ` · ${o.refund_state.toLowerCase()}` : ""}</div></span>
                  : <span key="c" className="sub2">Not decided</span>,
                may && !o.decision ? (
                  <span key="a" className="row" style={{ gap: "var(--s-2)" }}>
                    <Btn kind="ghost" size="sm" disabled={!!busy || loading || !next} onClick={() => setAsking({ decision: "CARRY", who: o })} aria-label={`Carry the excess of ${o.name} into the next session`}>Carry</Btn>
                    <Btn kind="ghost" size="sm" disabled={!!busy || loading} onClick={() => setAsking({ decision: "REFUND", who: o })} aria-label={`Raise a refund of the excess of ${o.name}`}>Refund</Btn>
                  </span>
                ) : <span key="a" />,
              ])} />
            {data.count > data.rows.length ? <PBody><div className="sub2">The first {data.rows.length.toLocaleString()} of {data.count.toLocaleString()}; the Excel list has them all.</div></PBody> : null}
          </>
        )}
      {asking && data ? (
        <Modal title={asking.decision === "CARRY"
            ? (asking.who ? `Carry ${money(Number(asking.who.excess))} into ${next}` : `Carry ${data.undecided.toLocaleString()} excesses into ${next}`)
            : (asking.who ? `Raise a refund of ${money(Number(asking.who.excess))}` : `Raise ${data.undecided.toLocaleString()} refunds`)}
          onClose={() => { if (!busy) setAsking(null); }}
          foot={<><Btn kind="ghost" disabled={!!busy} onClick={() => setAsking(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={!!busy || reason.trim().length < 10} onClick={() => void decide()}>
              {busy === "decide" ? (progress ?? "Deciding…") : asking.decision === "CARRY" ? "Carry" : "Raise the refund" + (asking.who ? "" : "s")}
            </Btn></>}>
          {asking.decision === "CARRY" ? (
            <p>
              {asking.who ? `${asking.who.name}'s excess` : `The excess of every student not yet decided (${money(Number(data.undecidedExcess))} in all)`} is
              recorded as school fees paid in {next}, &ldquo;carried from {data.session}&rdquo;: the fee gate and the student&rsquo;s position count it there.
              It is no new money: the ledger moves the school-fees income from {data.session} to {next}. The overpaid session reads settled,
              and the student is told by e-mail, text and on the portal.
            </p>
          ) : (
            <p>
              A refund of {asking.who ? `${asking.who.name}'s excess` : `each student's excess (${money(Number(data.undecidedExcess))} in all)`} is raised on the Refunds
              &amp; Credits desk, against the payment that covers it. It is approved and paid there by two officers, as every refund; a refund the desk
              rejects comes back here to be decided again. The student is told when it is raised and when it is paid.
            </p>
          )}
          <Field id="ofo-reason" label="Why" required hint="At least ten characters; kept with each decision">
            <textarea id="ofo-reason" className="ctl" rows={2} maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)}
              placeholder={asking.decision === "CARRY" ? "e.g. overpaid old-portal fees counted towards the next session" : "e.g. overpaid old-portal fees returned to the students"} />
          </Field>
        </Modal>
      ) : null}
    </Panel>
  );
}
