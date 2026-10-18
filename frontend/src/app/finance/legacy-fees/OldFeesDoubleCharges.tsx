"use client";

/** V561: old-portal payments the bank may have charged twice — one student, session, item, day and amount under two or more of
 *  the old portal's payment numbers. Each is checked against the bank statement or the gateway's report before its excess is
 *  carried or refunded: every payment received (the excess is real), or not all — naming those that never arrived, which are then
 *  raised for withdrawal for another Bursary officer to approve. Until checked, the student is held on the Overpaid list. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, money } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { DOUBLE_CHARGE_HEADERS, VERDICT, doubleChargeRow, notReceivedOk, payrefOf, verdictWord, type DoubleCharge, type DoubleCharges, type Verdict } from "@/lib/double-charges";

interface Checking { g: DoubleCharge; verdict: Verdict | ""; evidence: string; note: string; notReceived: string[] }

export function OldFeesDoubleCharges({ may, tick = 0, onChanged }: { may: boolean; tick?: number; onChanged?: () => void }) {
  const [session, setSession] = useState("");
  const [data, setData] = useState<DoubleCharges | null>(null);
  const [answered, setAnswered] = useState<string | null>(null);
  const [own, setOwn] = useState(0);
  const [checking, setChecking] = useState<Checking | null>(null);

  const listUrl = `/api/bff/api/v1/finance/legacy-fees/double-charges${session ? `?session=${encodeURIComponent(session)}` : ""}`;
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
      setData(j as DoubleCharges);
    })();
    return () => { alive = false; };
  }, [listUrl, asked]);

  async function excel() {
    if (!data?.rows.length) return;
    const rows = [...data.rows].sort((x, y) => x.name.localeCompare(y.name));
    const blob = await brandedXlsx(`Possible bank double charges, ${data.session === "all" ? "every session" : data.session}`, DOUBLE_CHARGE_HEADERS, rows.map(doubleChargeRow), {
      sheetName: "Double charges", serial: docSerial("ODC"),
      sub: `${data.count.toLocaleString()} group${data.count === 1 ? "" : "s"} · ${data.unchecked.toLocaleString()} not checked with the bank`,
    });
    downloadBlob(blob, `possible-double-charges-${String(data.session).replace("/", "-")}.xlsx`);
  }

  async function check() {
    if (!checking || !checking.verdict) return;
    const { g, verdict, evidence, note, notReceived } = checking;
    const r = await fetch("/api/bff/api/v1/finance/legacy-fees/double-charges/check", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Bank check of a possible double charge (${g.number}): ${VERDICT[verdict][0]} — ${evidence.trim()}`) },
      body: JSON.stringify({ studentId: g.student_id, session: g.session, purpose: g.purpose, paidOn: g.paid_on, amount: Number(g.amount), verdict,
        evidence: evidence.trim(), note: note.trim() || null, notReceived: verdict === "NOT_RECEIVED" ? notReceived : [] }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as Problem); return; }
    const raised = ((j as { raised?: string[] } | null)?.raised ?? []);
    notify(verdict === "RECEIVED" ? "Recorded: the bank received every payment"
      : `Recorded; withdrawal ${raised.join(", ")} raised for another Bursary officer to approve`);
    setChecking(null);
    setOwn((x) => x + 1);
    onChanged?.();
  }

  const ok = !!checking?.verdict && (checking?.evidence.trim().length ?? 0) >= 5
    && (checking?.verdict !== "NOT_RECEIVED" || notReceivedOk(checking.notReceived, checking.g.refs));
  return (
    <Panel title="Possible bank double charges" right="Old-portal payments of one student, day and amount under two payment numbers: checked with the bank before the excess is carried or refunded">
      <PBody>
        <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
          <Field id="odc-session" label="Session" style={{ flex: "0 1 160px" }}>
            <select id="odc-session" className="ctl" value={shown} onChange={(e) => setSession(e.target.value)} disabled={loading}>
              <option value="all">Every session</option>
              {(data?.sessions ?? []).map((s) => <option key={s} value={s}>{s}</option>)}
              {data && shown && shown !== "all" && !data.sessions.includes(shown) ? <option value={shown}>{shown}</option> : null}
            </select>
          </Field>
          <Btn kind="ghost" disabled={loading || !data?.count} onClick={() => excel()}>Excel</Btn>
          {loading && data ? <span className="sub2" role="status">Looking…</span> : null}
        </div>
      </PBody>
      {!data ? <PBody><div className="sub2">{loading ? "Looking…" : ""}</div></PBody>
        : !data.count ? (
          <PBody><div className="sub2">No student has two old-portal payments of the same day and amount under different payment numbers{data.session === "all" ? "" : ` in ${data.session}`}.</div></PBody>
        ) : (
          <>
            <PBody>
              <Tiles items={[
                ["Possible double charges", data.count.toLocaleString(), null, `${data.received.toLocaleString()} every payment received · ${data.notReceived.toLocaleString()} not all`],
                ["Not checked with the bank", data.unchecked.toLocaleString(), data.unchecked ? "var(--red-ink)" : null, `${money(Number(data.atStake))} at stake; these students wait on the Overpaid list`],
                ["Withdrawal waiting", data.waiting.toLocaleString(), data.waiting ? "var(--amber-ink)" : null, "For another Bursary officer to approve, below"],
              ]} cls="grid--3" />
            </PBody>
            <DTable pageSize={0} cols={["S/N|num", "Student", "Item", "Paid on|mid", "Amount|num", "Records and payment numbers", "Bank check", ""]}
              rows={data.rows.map((g, i) => [
                <span key="n" className="tnum sub2">{i + 1}</span>,
                <Two key="s" a={g.name} b={g.number} />,
                <span key="p">{g.purpose}<div className="sub2">{g.session}</div></span>,
                <span key="d" className="tnum">{g.paid_on}</span>,
                <span key="a" className="tnum">{money(Number(g.amount))}<div className="sub2">× {g.payments}</div></span>,
                <span key="r" className="sub2 tnum">{g.refs.map((ref) => <div key={ref}>{ref} · {payrefOf(g, ref)}</div>)}</span>,
                <span key="c"><Pil kind={verdictWord(g.verdict)[1]}>{verdictWord(g.verdict)[0]}</Pil>
                  {g.evidence ? <div className="sub2">{g.evidence}{g.checked_by ? ` — ${g.checked_by}` : ""}</div> : null}
                  {g.open_requests ? <div className="sub2 ink-amber">Withdrawal waiting for approval</div> : null}</span>,
                may && !g.open_requests ? <Btn key="b" kind={g.verdict ? "ghost" : "secondary"} size="sm" onClick={() => setChecking({ g, verdict: "", evidence: "", note: "", notReceived: [] })}
                  aria-label={`Check the payments of ${g.name} with the bank`}>{g.verdict ? "Check again" : "Check with the bank…"}</Btn> : <span key="b" />,
              ])} />
          </>
        )}
      {checking ? (
        <Modal title={`Check with the bank — ${checking.g.name}`} sub={`${checking.g.payments} payments of ${money(Number(checking.g.amount))} on ${checking.g.paid_on} (${checking.g.purpose})`}
          onClose={() => setChecking(null)}
          foot={<><Btn kind="ghost" onClick={() => setChecking(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={!ok} busyLabel="Recording…" onClick={() => check()}>Record the check</Btn></>}>
          <Note kind="info" title="What the bank shows decides">
            Look for each payment on the University&rsquo;s bank statement (or the gateway&rsquo;s collections report) for {checking.g.paid_on}. A charge the bank sent back
            to the student never reached the University. Name the statement and the line you read: it is kept with the check.
          </Note>
          <Field id="odc-verdict" label="The bank received">
            <select id="odc-verdict" className="ctl" value={checking.verdict} onChange={(e) => setChecking({ ...checking, verdict: e.target.value as Verdict | "", notReceived: [] })}>
              <option value="">Choose…</option>
              <option value="RECEIVED">Every payment — the excess is real</option>
              <option value="NOT_RECEIVED">Not all of them</option>
            </select>
          </Field>
          {checking.verdict === "NOT_RECEIVED" ? (
            <Field id="odc-which" label="The records the bank never received (at least one did arrive)">
              <div>
                {checking.g.refs.map((ref) => (
                  <label key={ref} style={{ display: "flex", alignItems: "flex-start", gap: "var(--s-2)", marginBottom: "var(--s-2)" }}>
                    <input type="checkbox" aria-label={`Never received: ${ref}`} checked={checking.notReceived.includes(ref)}
                      onChange={(e) => setChecking({ ...checking, notReceived: e.target.checked ? [...checking.notReceived, ref] : checking.notReceived.filter((x) => x !== ref) })} />
                    <span className="tnum sub2" style={{ overflowWrap: "anywhere" }}>{ref} · {payrefOf(checking.g, ref)}</span>
                  </label>
                ))}
              </div>
            </Field>
          ) : null}
          <Field id="odc-evidence" label="Evidence" required hint="The statement or report, its date and the line read">
            <input id="odc-evidence" className="ctl" maxLength={500} value={checking.evidence} onChange={(e) => setChecking({ ...checking, evidence: e.target.value })}
              placeholder="e.g. Zenith collections statement, 23 Mar 2026: one credit of ₦85,294" />
          </Field>
          <Field id="odc-note" label="Note (optional)">
            <input id="odc-note" className="ctl" maxLength={500} value={checking.note} onChange={(e) => setChecking({ ...checking, note: e.target.value })} />
          </Field>
          {checking.verdict === "NOT_RECEIVED" ? <div className="sub2">Each record named is raised for withdrawal; another Bursary officer approves it before anything changes on the student&rsquo;s account.</div> : null}
        </Modal>
      ) : null}
    </Panel>
  );
}
