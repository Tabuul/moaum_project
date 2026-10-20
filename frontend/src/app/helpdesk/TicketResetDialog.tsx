"use client";

/** V582: the tickets ticked on the queue, reset from the tickets. The server checks each ticket first and says what would happen
 *  — the students to reset (one for every student however many tickets they raised), the tickets left out and why — then, on
 *  confirmation, resets them and resolves their tickets; the progress is the operation's own, read as it runs; the result lists
 *  every ticket with what became of it, the failed ones left open on the desk. No password is ever shown. */
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import type { Problem } from "@/lib/api";
import { OP_STATUS, TICKET_RESULT, progressWords, running, type Operation, type Validation } from "@/lib/ticket-reset";

const BASE = "/api/bff/api/v1/helpdesk/tickets/password-reset";
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }) : "—");

export function TicketResetDialog({ ticketIds, onClose }: { ticketIds: string[]; onClose: (done: boolean) => void }) {
  const [check, setCheck] = useState<Validation | null>(null);
  const [refused, setRefused] = useState<Problem | null>(null);
  const [reason, setReason] = useState("Students' login and password tickets at the ICT Support Desk");
  const [resolution, setResolution] = useState("");
  const [unlock, setUnlock] = useState(true);
  const [op, setOp] = useState<Operation | null>(null);
  const [waiting, setWaiting] = useState(false);
  // the request's key, made once on the first press: a second press is the same operation
  const key = useRef<string | null>(null);

  useEffect(() => {
    let live = true;
    (async () => {
      const r = await fetch(`${BASE}/validate`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ticketIds }) });
      const j = await r.json().catch(() => null);
      if (!live) return;
      if (!r.ok) { setRefused((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      const v = j as Validation;
      setCheck(v);
      setResolution(v.resolution);
      setUnlock(v.policy.unlock_by_default);
    })();
    return () => { live = false; };
  }, [ticketIds]);

  // the operation's progress, read as it runs
  useEffect(() => {
    if (!op || !running(op.status)) return;
    const t = window.setTimeout(async () => {
      const r = await fetch(`${BASE}/operations/${op.id}`, { cache: "no-store" });
      if (r.ok) setOp((await r.json()) as Operation);
    }, 1000);
    return () => window.clearTimeout(t);
  }, [op]);

  async function execute() {
    if (!key.current) key.current = `tkt-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    setWaiting(true);
    try {
      const r = await fetch(`${BASE}/execute`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason.trim()) },
        body: JSON.stringify({ ticketIds, reason: reason.trim(), resolution: resolution.trim(), unlock, key: key.current }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setOp(j as Operation);
      notify(`${(j as Operation).reference}: resetting the passwords of ${(j as Operation).students} student${(j as Operation).students === 1 ? "" : "s"}`);
    } finally { setWaiting(false); }
  }

  const done = op && !running(op.status);
  const failed = op ? op.tickets.filter((t) => t.status === "FAILED") : [];
  const left = check ? check.rows.filter((r) => !r.eligible) : [];

  return (
    <Modal wide title={op ? (done ? "Password reset completed" : "Resetting passwords") : "Reset student passwords"}
      sub={op ? `${op.reference} · ${OP_STATUS[op.status]?.[0] ?? op.status}` : "Only login and password tickets are included; the server checks every ticket"}
      onClose={() => { if (!op || done || op.status === "AWAITING_APPROVAL") onClose(!!op); }}
      foot={op ? (
        <Btn kind="primary" disabled={!done && op.status !== "AWAITING_APPROVAL"} onClick={() => onClose(true)}>{done || op.status === "AWAITING_APPROVAL" ? "Close" : "Resetting…"}</Btn>
      ) : (
        <>
          <Btn kind="ghost" onClick={() => onClose(false)}>Cancel</Btn>
          <Btn kind="primary" disabled={!check || !check.eligible || reason.trim().length < 10 || waiting} busyLabel="Resetting…" onClick={() => execute()}>
            {check ? `Reset ${check.students} eligible student${check.students === 1 ? "" : "s"}` : "Checking…"}
          </Btn>
        </>
      )}>
      {refused ? <Note kind="bad" title="The tickets could not be checked">{refused.detail ?? refused.title}</Note>
        : !check ? <div className="sub2">Checking the {ticketIds.length} ticket{ticketIds.length === 1 ? "" : "s"} selected…</div> : !op ? (
        <div className="stack">
          <KvGrid cls="grid--3" pairs={[
            ["Selected", check.selected], ["Eligible tickets", check.eligible], ["Students to reset", check.students],
            ["Duplicate tickets consolidated", check.consolidated], ["Already reset or in a reset", check.alreadyDone], ["Not eligible", check.notEligible],
          ]} />
          <Note kind="info" title={`You are about to reset the passwords of ${check.students} student${check.students === 1 ? "" : "s"}`}>
            Each signs in with the matriculation number as username and temporary password, and must choose a new password at once; open sessions end.
            Every eligible ticket of theirs is resolved with the reset. No password is shown or sent.
            {check.policy.approval_over != null && check.students > check.policy.approval_over ? ` More than ${check.policy.approval_over} students: the reset waits for a Head's approval.` : ""}
          </Note>
          {check.grouped.length ? (
            <div><div className="eyebrow mb-1">One reset for several tickets</div>
              {check.grouped.map((g) => <div key={g.student_id} className="sub2">{g.full_name} <span className="tnum">{g.matric_no}</span> · tickets {g.tickets.join(", ")} · one reset</div>)}
            </div>
          ) : null}
          {left.length ? (
            <DTable title="Left out" cols={["Ticket", "Student", "Why"]} rows={left.map((r) => [
              <span key="t" className="tnum">{r.number ?? "—"}</span>,
              <span key="s">{r.full_name ?? "—"}{r.matric_no ? <div className="sub2 tnum">{r.matric_no}</div> : null}</span>,
              <span key="w" className="sub2">{r.words}</span>,
            ])} />
          ) : null}
          <Field id="tr-reason" label="Reason" required hint="Ten characters or more; kept with every reset and on the support ledger">
            <input id="tr-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} maxLength={2000} />
          </Field>
          <Field id="tr-resolution" label="What the students read on their resolved tickets" hint="Twenty characters or more; no password">
            <textarea id="tr-resolution" className="ctl" rows={3} value={resolution} onChange={(e) => setResolution(e.target.value)} maxLength={2000} />
          </Field>
          <label className="row row--tight" style={{ alignItems: "center", gap: 8 }}>
            <input type="checkbox" className="chk" checked={unlock} onChange={(e) => setUnlock(e.target.checked)} />
            <span>Unlock the accounts too (clear failed sign-ins)</span>
          </label>
        </div>
      ) : (
        <div className="stack">
          {op.status === "AWAITING_APPROVAL" ? (
            <Note kind="info" title="Waiting for a Head's approval">More than {op.approval_over} students: a Head of the Support Desk or the Director of ICT approves it under Bulk Password Reset. Nothing is reset until then.</Note>
          ) : (
            <KvGrid cls="grid--4" pairs={[
              ["Progress", progressWords(op)], ["Tickets", op.ticketCount], ["Unique students", op.students], ["Duplicate tickets consolidated", op.consolidated],
              ["Successful", op.succeeded], ["Failed", op.failed], ["Tickets resolved", op.resolved], ["Status", <Pil key="s" kind={OP_STATUS[op.status]?.[1] ?? "grey"}>{OP_STATUS[op.status]?.[0] ?? op.status}</Pil>],
            ]} />
          )}
          {done && failed.length ? (
            <Note kind="bad" title={`${failed.length} ticket${failed.length === 1 ? "" : "s"} not reset — left open on the desk`}>
              {failed.map((t) => <div key={t.ticket_id}><Link className="lnk tnum" href={`/helpdesk/tickets/${t.ticket_id}`}>{t.number}</Link> · {t.full_name ?? "—"} · {t.reason ?? "Not reset"}</div>)}
            </Note>
          ) : null}
          <DTable cols={["S/N|num", "Ticket", "Student", "Matric number", "Issue", "Result", "Reason", "Processed"]} rows={op.tickets.map((t, i) => [
            <span key="n" className="tnum sub2">{i + 1}</span>,
            <Link key="t" className="lnk tnum" href={`/helpdesk/tickets/${t.ticket_id}`}>{t.number}</Link>,
            <span key="s">{t.full_name ?? "—"}</span>,
            <span key="m" className="tnum">{t.matric_no ?? "—"}</span>,
            <span key="i" className="sub2">{t.subject}</span>,
            <Pil key="r" kind={TICKET_RESULT[t.status][1]}>{TICKET_RESULT[t.status][0]}</Pil>,
            <span key="w" className="sub2">{t.reason ?? ""}</span>,
            <span key="p" className="sub2 tnum">{when(t.processed_at)}</span>,
          ])} texts={op.tickets.map((t) => `${t.number} ${t.full_name ?? ""} ${t.matric_no ?? ""}`)} />
        </div>
      )}
    </Modal>
  );
}
