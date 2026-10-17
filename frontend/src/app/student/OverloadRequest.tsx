"use client";

/**
 * V508: the student asks for an overload — a higher maximum course load for this semester — with a reason, sees where the request
 * stands (waiting, granted with its ceiling, refused with the Head of Department's reason) and withdraws it while it waits. The
 * database decides whether the student may ask and what a grant may reach; a grant is the semester's maximum for every check.
 */
import { useEffect, useState } from "react";
import { Btn, Note } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { unitChoices, type OverloadState } from "@/lib/overloads";

export function OverloadRequest({ session, semester, total, max }: { session: string; semester: number; total: number; max: number }) {
  const [st, setSt] = useState<OverloadState | null>(null);
  // read again after a withdrawal
  const [version, setVersion] = useState(0);
  const [asking, setAsking] = useState(false);
  const [units, setUnits] = useState<number | null>(null);
  const [reason, setReason] = useState("");

  useEffect(() => {
    let alive = true;
    void (async () => {
      const r = await fetch(`/api/bff/api/v1/me/overload?session=${encodeURIComponent(session)}&semester=${semester}`, { cache: "no-store", headers: { "X-Background": "1" } });
      const j = r.ok ? await r.json().catch(() => null) : null;
      if (alive) setSt(j);
    })();
    return () => { alive = false; };
  }, [session, semester, version]);

  async function ask() {
    const r = await fetch("/api/bff/api/v1/me/overload", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ session, semester, units, reason: reason.trim() }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    setAsking(false);
    setSt(j);
    notify("Your request is with your Head of Department. You will be told the decision.");
  }

  async function withdraw(id: string) {
    const r = await fetch(`/api/bff/api/v1/me/overload/${id}/withdraw`, { method: "POST" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    notify("Request withdrawn.");
    setVersion((n) => n + 1);
  }

  if (!st) return null;
  const q = st.request;
  const choices = unitChoices(st.regular_max, st.ceiling);
  const over = total > max;
  return (
    <>
      {q?.status === "GRANTED" ? (
        <Note kind="ok" title={`Overload granted: up to ${q.granted_max} credit units this semester`}>
          Your Head of Department granted it{q.decision_reason ? `: ${q.decision_reason}` : "."} The usual maximum is {st.regular_max}.
        </Note>
      ) : q?.status === "REQUESTED" ? (
        <Note kind="info" title={`Overload request waiting: ${q.requested_max} credit units`}>
          Your request is with your Head of Department; you are told the decision. Until it is granted the maximum is {st.regular_max}.
          <div className="mt-2"><Btn kind="ghost" size="sm" busyLabel="Withdrawing…" onClick={() => withdraw(q.id)}>Withdraw the request</Btn></div>
        </Note>
      ) : q?.status === "REFUSED" && !st.may_ask ? (
        <Note kind="bad" title="Overload refused">{q.decision_reason} Register within {st.regular_max} credit units.</Note>
      ) : null}
      {st.may_ask && choices.length ? (
        <div className="card"><div className="card__body row" style={{ flexWrap: "wrap", gap: 8 }}>
          <span className="sub2" style={{ flex: 1, minWidth: 220 }}>
            {q?.status === "REFUSED" ? <>Your last request was refused: {q.decision_reason} </> : null}
            {over ? <>Your selection is over the maximum of {st.regular_max} credit units. </> : null}
            Need more than {st.regular_max} credit units this semester (for example, final year with carry-overs)? Ask your Head of Department for an overload, up to {st.ceiling}.
          </span>
          <Btn kind={over ? "primary" : "ghost"} size="sm" onClick={() => { setUnits(Math.min(st.ceiling ?? max, Math.max(total, (st.regular_max ?? max) + 1))); setReason(""); setAsking(true); }}>Request an overload</Btn>
        </div></div>
      ) : null}
      {asking ? (
        <Modal title="REQUEST AN OVERLOAD" onClose={() => setAsking(false)}
          foot={<><Btn kind="ghost" onClick={() => setAsking(false)}>Cancel</Btn>
            <Btn kind="primary" disabled={!units || reason.trim().length < 10} busyLabel="Sending…" onClick={() => ask()}>Send to my Head of Department</Btn></>}>
          <div className="stack">
            <div className="sub2">The maximum for {st.level} Level this semester is {st.regular_max} credit units. Your Head of Department may grant up to {st.ceiling}, or less than you ask, or refuse.</div>
            <Field id="ovr-units" label="Credit units you need this semester">
              <select id="ovr-units" className="ctl" value={units ?? ""} onChange={(e) => setUnits(Number(e.target.value))}>
                {choices.map((n) => <option key={n} value={n}>{n}</option>)}
              </select>
            </Field>
            <Field id="ovr-reason" label="Why you need it" required hint="Ten characters or more; your Head of Department reads it">
              <textarea id="ovr-reason" className="ctl" rows={3} value={reason} maxLength={1000} onChange={(e) => setReason(e.target.value)}
                placeholder="e.g. final year: the project, two carry-overs and the remaining core courses" />
            </Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
