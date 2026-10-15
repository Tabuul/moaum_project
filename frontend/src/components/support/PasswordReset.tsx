"use client";

/**
 * A student's password reset at the ICT Support Desk (V346, V485) — the one reset screen, used on the Student Password Reset page
 * and from the student's support record. The student and the account as the server reads them (never a hash, never a password);
 * the method: the default student credential where the record allows it (the matriculation number, changed at the next sign-in),
 * a reset link to the student's address, or a temporary password on the student's ticket; the reason, the ticket, the unlock
 * choice; RESET STUDENT PASSWORD, confirmed, RESETTING PASSWORD… while the server works, then the outcome in words. The server
 * decides every part of it again — the capability, the scope, the record, the policy — and keeps the record of it.
 */
import { useEffect, useState, type ReactNode } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import {
  PASSWORD_STATUS_WORD, RESET_REASON_MIN, accountWord, failureWords, methodsFor, reasonOk, resetBody,
  type ResetMethod, type ResetProblem, type ResetState,
} from "@/lib/password-reset";

export interface TicketRef { id: string; number: string; subject?: string }
interface TicketRow { id: string; number: string; subject: string; status: string }

const METHOD_LABEL: Record<ResetMethod, string> = {
  DEFAULT: "Reset to the default student credential — the student signs in with the matriculation number and must change the password at once",
  LINK: "Send a secure reset link to the student's email and phone",
  TEMPORARY: "Issue a temporary password at the desk — random, one sign-in, 24 hours, changed at once",
};

const when = (iso: string | null) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

function Kv({ k, v }: { k: string; v: ReactNode }) {
  return <div className="kv"><span className="k">{k}</span><span className="v">{v}</span></div>;
}

export function PasswordReset({ studentId, ticket, inline, onClose, onDone }: {
  studentId: string; ticket: TicketRef | null; inline?: boolean; onClose?: () => void; onDone?: () => void;
}) {
  const [state, setState] = useState<ResetState | null>(null);
  const [loadFailed, setLoadFailed] = useState<string | null>(null);
  const [tickets, setTickets] = useState<TicketRow[]>([]);
  const [reload, setReload] = useState(0);
  const [method, setMethod] = useState<ResetMethod | null>(null);
  const [reason, setReason] = useState("");
  const [chosenTicket, setChosenTicket] = useState("");
  const [unlock, setUnlock] = useState<boolean | null>(null);
  const [stage, setStage] = useState<"form" | "confirm" | "done" | "failed">("form");
  const [working, setWorking] = useState(false);
  const [result, setResult] = useState<Record<string, unknown> | null>(null);
  const [failure, setFailure] = useState("");

  const hasTicket = !!ticket;
  useEffect(() => {
    let alive = true;
    void (async () => {
      const r = await fetch(`/api/bff/api/v1/helpdesk/support/students/${studentId}/password`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!alive) return;
      if (!r.ok) { setLoadFailed(failureWords(j ?? { status: r.status })); return; }
      setState(j as ResetState);
      if (!hasTicket) {
        const t = await fetch(`/api/bff/api/v1/helpdesk/support/students/${studentId}/tickets`, { cache: "no-store" });
        const rows = t.ok ? ((await t.json()) as TicketRow[]) : [];
        if (alive) setTickets(rows.filter((x) => x.status !== "CLOSED"));
      }
    })();
    return () => { alive = false; };
  }, [studentId, hasTicket, reload]);

  const ticketId = ticket?.id ?? (chosenTicket || null);
  const methods = state ? methodsFor(state, !!ticketId) : [];
  const chosen: ResetMethod | null = method ?? (state ? (state.eligible ? "DEFAULT" : "LINK") : null);
  const unlockNow = unlock ?? state?.policy.unlock_by_default ?? true;
  const ticketNeeded = chosen === "TEMPORARY" || (chosen === "DEFAULT" && state?.policy.ticket === "REQUIRED");
  const ready = !!state && state.mayReset && !!chosen && methods.find((m) => m.method === chosen)?.enabled === true && reasonOk(reason) && (!ticketNeeded || !!ticketId);

  async function confirm() {
    if (!chosen || working) return;
    setWorking(true);
    try {
      const r = await fetch(`/api/bff/api/v1/helpdesk/support/students/${studentId}/password`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Student password reset at the ICT Support Desk: ${reason.trim()}`) },
        body: JSON.stringify(resetBody(chosen, reason, ticketId, unlockNow)),
      });
      const j = (await r.json().catch(() => null)) as Record<string, unknown> | null;
      if (!r.ok) {
        setFailure(failureWords((j as ResetProblem | null) ?? { status: r.status }));
        setStage("failed");
        return;
      }
      setResult(j);
      setStage("done");
      notify("PASSWORD RESET SUCCESSFUL");
      onDone?.();
      setReload((n) => n + 1);
    } catch {
      setFailure(failureWords(null));
      setStage("failed");
    } finally {
      setWorking(false);
    }
  }

  const s = state;
  const [acct, acctKind] = s ? accountWord(s) : ["", "grey" as const];
  const pw = s ? PASSWORD_STATUS_WORD[s.passwordStatus] ?? [s.passwordStatus, "grey" as const] : null;

  const details = s ? (
    <div className="grid grid--2" aria-label="Student information">
      <Kv k="Student" v={<b>{s.full_name}</b>} />
      <Kv k="Matriculation number" v={<span className="tnum">{s.matric_no ?? "—"}</span>} />
      <Kv k="JAMB number" v={<span className="tnum">{s.jamb_reg_no ?? "—"}</span>} />
      <Kv k="Faculty" v={s.faculty ?? "—"} />
      <Kv k="Department" v={s.department ?? "—"} />
      <Kv k="Programme" v={s.programme ?? "—"} />
      <Kv k="Current level" v={s.current_level ?? "—"} />
      <Kv k="Student status" v={s.status} />
      <Kv k="Username" v={<span className="tnum">{s.username ?? "—"}</span>} />
      <Kv k="Account" v={<Pil kind={acctKind}>{acct}</Pil>} />
      <Kv k="Password status" v={pw ? <Pil kind={pw[1]}>{pw[0]}</Pil> : "—"} />
      <Kv k="Last signed in" v={when(s.last_signed_in_at)} />
    </div>
  ) : null;

  const form = s ? (
    <div className="stack">
      {details}
      {!s.mayReset ? <Note kind="bad" title="YOU ARE NOT AUTHORIZED TO RESET THIS STUDENT'S PASSWORD.">Your posting does not carry password resets for this student. The Head of the ICT Support Desk grants it.</Note> : null}
      {s.mayReset && !s.eligible ? <Note kind="bad" title="The default student credential is not available">{s.refusalWords}</Note> : null}
      {s.mayReset ? (
        <>
          <Field id="pr-method" label="Method">
            <div className="stack" style={{ gap: 4 }}>
              {methods.map((m) => (
                <label key={m.method} className="row row--inline row--tight" style={{ opacity: m.enabled ? 1 : 0.55 }}>
                  <input type="radio" name="pr-method" disabled={!m.enabled} checked={chosen === m.method} onChange={() => setMethod(m.method)} />
                  {METHOD_LABEL[m.method]}{m.why ? <span className="sub2"> — {m.why}</span> : null}
                </label>
              ))}
            </div>
          </Field>
          <Field id="pr-reason" label="Reason" required hint={`At least ${RESET_REASON_MIN} characters; recorded on the support ledger${ticketId ? " and the ticket" : ""}`}>
            <textarea id="pr-reason" className="ctl" rows={2} maxLength={2000} value={reason} onChange={(e) => setReason(e.target.value)}
              placeholder="e.g. Student forgot portal password; identity checked at the desk" />
          </Field>
          {ticket ? <Kv k="Support ticket" v={<span className="tnum">{ticket.number}{ticket.subject ? ` — ${ticket.subject}` : ""}</span>} /> : (
            <Field id="pr-ticket" label={`Support ticket${ticketNeeded ? "" : " (optional)"}`} required={ticketNeeded}
              hint={tickets.length ? "The reset is written on the ticket's timeline" : "The student has no open ticket; raise one from the student's support record"}>
              <select id="pr-ticket" className="ctl" value={chosenTicket} onChange={(e) => setChosenTicket(e.target.value)}>
                <option value="">{ticketNeeded ? "Choose the ticket" : "No ticket"}</option>
                {tickets.map((t) => <option key={t.id} value={t.id}>{t.number} — {t.subject}</option>)}
              </select>
            </Field>
          )}
          {chosen === "DEFAULT" ? (
            <label className="row row--inline row--tight">
              <input type="checkbox" className="chk" checked={unlockNow} onChange={(e) => setUnlock(e.target.checked)} />
              Unlock account{s.locked ? " — it is locked after failed sign-ins" : " (if it is locked)"}
            </label>
          ) : null}
          {ticketNeeded && !ticketId ? <Note kind="info" title="A ticket is needed">{chosen === "TEMPORARY" ? "A temporary password is issued only on the student's ticket." : "The desk's policy asks for the student's ticket with this reset."}</Note> : null}
        </>
      ) : null}
    </div>
  ) : loadFailed ? <Note kind="bad" title={loadFailed}>The student could not be opened for a reset.</Note> : <div className="sub2">Reading the student&rsquo;s account…</div>;

  const r = result ?? {};
  const outcome = stage === "done" ? (
    <div className="stack">
      {r.alreadyDone ? <Note kind="info" title="PASSWORD RESET SUCCESSFUL">This student&rsquo;s password was reset moments ago; nothing more was done.</Note>
        : r.method === "TEMPORARY_PASSWORD" ? (
          <Note kind="ok" title="PASSWORD RESET SUCCESSFUL — give the temporary password to the student now">
            <span className="tnum" style={{ display: "block", fontSize: 22, letterSpacing: 2, margin: "6px 0" }}>{String(r.temporaryPassword)}</span>
            <span className="sub2" style={{ display: "block" }}>It is not shown again and is kept only as a hash. It opens one sign-in within 24 hours, and the student must choose a new password there.</span>
          </Note>
        ) : r.method === "RESET_LINK" ? <Note kind="ok" title="PASSWORD RESET SUCCESSFUL">A one-hour, single-use link went to {String(r.sentTo)}. The student sets the new password; ICT Support never sees it.</Note>
        : (
          <Note kind="ok" title="PASSWORD RESET SUCCESSFUL">
            Student password has been reset successfully. The student will be required to change the password at next login.
            {r.unlocked ? <span className="sub2" style={{ display: "block" }}>The account was unlocked.</span> : null}
            {Number(r.sessionsEnded ?? 0) > 0 ? <span className="sub2" style={{ display: "block" }}>{String(r.sessionsEnded)} open session{Number(r.sessionsEnded) === 1 ? "" : "s"} ended.</span> : null}
          </Note>
        )}
      {details}
    </div>
  ) : stage === "failed" ? <Note kind="bad" title="PASSWORD RESET FAILED">{failure}</Note> : null;

  const confirmBody = s && chosen ? (
    <div className="stack">
      <div className="grid grid--2">
        <Kv k="Student" v={<b>{s.full_name}</b>} />
        <Kv k="Matriculation number" v={<span className="tnum">{s.matric_no ?? "—"}</span>} />
      </div>
      <p style={{ margin: 0 }}>
        {chosen === "DEFAULT" ? "The password will be reset to the configured default credential and the student will be required to change it at next login."
          : chosen === "LINK" ? "A one-hour reset link goes to the email and phone on the student's record; the student sets the new password."
          : "A temporary password is issued and shown to you once; it opens one sign-in, where the student must change it."}
        {chosen === "DEFAULT" && unlockNow && s.locked ? " The account will be unlocked." : ""}
        {" "}Any session the student has open is ended.
      </p>
      <Kv k="Reason" v={reason.trim()} />
    </div>
  ) : null;

  const resetBtn = <Btn kind="primary" disabled={!ready} onClick={() => setStage("confirm")}>RESET STUDENT PASSWORD</Btn>;
  const confirmBtns = (
    <>
      <Btn kind="ghost" disabled={working} onClick={() => setStage("form")}>CANCEL</Btn>
      <Btn kind="primary" busy={working} busyLabel="RESETTING PASSWORD..." onClick={() => confirm()}>CONFIRM RESET</Btn>
    </>
  );
  const again = <Btn kind="ghost" onClick={() => { setStage("form"); setResult(null); setFailure(""); setReason(""); }}>{stage === "failed" ? "Back" : "Another reset"}</Btn>;

  if (inline) {
    return (
      <>
        {stage === "done" || stage === "failed" ? <>{outcome}<div className="row row--inline mt-2">{again}</div></> : <>{form}{s?.mayReset ? <div className="row row--inline mt-2">{resetBtn}</div> : null}</>}
        {stage === "confirm" ? (
          <Modal title="RESET STUDENT PASSWORD?" sub="A sensitive act: it is recorded with your name, the reason and the ticket" onClose={() => { if (!working) setStage("form"); }} foot={confirmBtns}>
            {confirmBody}
          </Modal>
        ) : null}
      </>
    );
  }
  return (
    <Modal title={stage === "confirm" ? "RESET STUDENT PASSWORD?" : "STUDENT PASSWORD RESET"}
      sub={stage === "confirm" ? "A sensitive act: it is recorded with your name, the reason and the ticket" : "The student's password is never shown and never recorded"}
      onClose={() => { if (!working) onClose?.(); }}
      foot={stage === "confirm" ? confirmBtns : stage === "form" ? <><Btn kind="ghost" onClick={() => onClose?.()}>Cancel</Btn>{s?.mayReset ? resetBtn : null}</> : <Btn kind="primary" onClick={() => onClose?.()}>Done</Btn>}>
      {stage === "confirm" ? confirmBody : stage === "form" ? form : outcome}
    </Modal>
  );
}
