"use client";

/**
 * The bulk password reset's confirmation, progress and result (V559), shared by the student list and an operation's record (V563:
 * a retry of the students it did not reset). The server has said who may be reset and why not the others (the preview); the agent
 * gives the reason, may have each student's login ticket resolved with the reset (in words the students read), and is told when
 * the operation will wait for a Head's approval. The work runs on the server: its real progress is read until it ends, then every
 * student reset and every one not, with the reset link for those refused for want of a matriculation number. No password is ever
 * sent or shown.
 */
import { useEffect, useMemo, useRef, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, LinkBtn, Note, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { DEFAULT_RESOLUTION, DONE, STATUS, linkable, needsApproval, resultNote, resultWord, running, type Operation, type Preview } from "@/lib/bulk-reset";

export const API = "/api/bff/api/v1/helpdesk/support/password-reset/bulk";
const count = (n: number) => Number(n).toLocaleString("en-NG");

export async function call<T>(path: string, init?: RequestInit): Promise<{ ok: true; data: T } | { ok: false; problem: Problem }> {
  const r = await fetch(`${API}${path}`, { cache: "no-store", ...init });
  const j = await r.json().catch(() => null);
  if (!r.ok) return { ok: false, problem: j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText } };
  return { ok: true, data: j as T };
}

/** the server's word on the students chosen: who may be reset, and why not the others */
export function previewFor(ids: string[]) {
  return call<Preview>("/preview", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ studentIds: ids }) });
}

const newKey = () => (typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`);

interface LinksSent { sent: number; notSent: number; rows: { student_id: string; sent: boolean; to?: string; why?: string }[] }

export function BulkConfirm({ preview, ids, tickets, retryOf, onClose, onEnded }: {
  preview: Preview; ids: string[]; tickets: Record<string, string>; retryOf?: { id: string; reference: string };
  onClose: () => void; onEnded?: (op: Operation) => void;
}) {
  const [step, setStep] = useState<"confirm" | "waiting" | "running" | "done">("confirm");
  const [reason, setReason] = useState(retryOf ? `Retry of ${retryOf.reference}: ` : "");
  const withTicket = ids.filter((id) => tickets[id]).length;
  const [resolve, setResolve] = useState(withTicket > 0);
  const [resolution, setResolution] = useState(DEFAULT_RESOLUTION);
  const [busy, setBusy] = useState<"start" | "cancel" | "links" | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [op, setOp] = useState<Operation | null>(null);
  const [links, setLinks] = useState<LinksSent | null>(null);
  // the request's key, made once when the reset is first started: the same request again is the same operation
  const key = useRef("");
  const waits = needsApproval(preview.selected, preview.policy.approval_over);
  const reasonOk = reason.trim().length >= 10 && (!retryOf || reason.trim() !== `Retry of ${retryOf.reference}:`);
  const resolutionOk = !resolve || resolution.trim().length >= 20;

  async function start() {
    if (!key.current) key.current = newKey();
    setBusy("start");
    setProblem(null);
    const r = await call<Operation>("", {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Bulk password reset: ${reason.trim()}`) },
      body: JSON.stringify({ studentIds: ids, reason: reason.trim(), tickets, key: key.current, resolveTickets: resolve && withTicket > 0,
        resolution: resolve && withTicket > 0 ? resolution.trim() : null, retryOf: retryOf?.id ?? null }),
    });
    setBusy(null);
    if (!r.ok) { setProblem(r.problem); return; }
    setOp(r.data);
    if (r.data.status === "AWAITING_APPROVAL") { setStep("waiting"); onEnded?.(r.data); }
    else setStep("running");
  }

  // the operation's real progress, read from the server until it ends
  useEffect(() => {
    if (step !== "running" || !op) return;
    let alive = true;
    const t = setInterval(() => {
      void (async () => {
        const r = await call<Operation>(`/${op.id}`);
        if (!alive || !r.ok) return;
        setOp(r.data);
        if (!running(r.data.status)) { setStep("done"); onEnded?.(r.data); }
      })();
    }, 1000);
    return () => { alive = false; clearInterval(t); };
    // the operation's id is what is polled
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [step, op?.id]);

  async function cancel() {
    if (!op) return;
    setBusy("cancel");
    const r = await call<Operation>(`/${op.id}/cancel`, { method: "POST", headers: { "X-Reason": reasonHeader(`Bulk password reset ${op.reference} cancelled`) } });
    setBusy(null);
    if (!r.ok) setProblem(r.problem);
  }

  async function sendLinks() {
    if (!op) return;
    setBusy("links");
    setProblem(null);
    const r = await call<LinksSent>(`/${op.id}/links`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Reset links after bulk reset ${op.reference}`) }, body: "{}",
    });
    if (r.ok) {
      setLinks(r.data);
      const again = await call<Operation>(`/${op.id}`);
      if (again.ok) setOp(again.data);
    } else setProblem(r.problem);
    setBusy(null);
  }

  const items = useMemo(() => op?.items ?? [], [op]);
  const ok = items.filter((i) => i.status === "RESET" || i.status === "ALREADY_RESET");
  const bad = items.filter((i) => i.status === "FAILED");
  const toLink = linkable(items);
  const head = ["S/N", "Student", "Matriculation number", "Programme", "Level", "Ticket", "Result", "Reason"];
  const sheet = () => items.map((i, n) => [n + 1, i.name, i.number ?? "", i.programme ?? "", i.level ?? "", i.ticket_number ?? "", resultWord(i), resultNote(i)]);

  if (step === "confirm") {
    return (
      <Modal wide title={retryOf ? `Retry the students ${retryOf.reference} did not reset` : "Bulk password reset"}
        sub={`${count(preview.selected)} student${preview.selected === 1 ? "" : "s"} selected`} onClose={onClose}
        foot={<>
          <Btn kind="ghost" onClick={onClose}>Cancel</Btn>
          <span className="grow" />
          <Btn kind="urgent" busy={busy === "start"} disabled={!preview.eligible || !reasonOk || !resolutionOk || busy !== null} onClick={() => void start()}>
            {waits ? `Ask for approval to reset ${count(preview.eligible)}` : `Reset ${count(preview.eligible)} eligible student${preview.eligible === 1 ? "" : "s"}`}
          </Btn>
        </>}>
        <Tiles cls="grid--3" items={[
          ["Selected", count(preview.selected), null, "students"],
          ["Eligible", count(preview.eligible), preview.eligible ? "var(--green-ink)" : null, "will be reset"],
          ["Not eligible", count(preview.notEligible), preview.notEligible ? "var(--red-ink)" : null, "recorded as failed, with the reason"],
        ]} />
        {waits ? (
          <Note kind="info" title={`More than ${count(preview.policy.approval_over ?? 0)} students: this reset waits for approval`}>
            No student is reset until the Head of the ICT Support Desk or the Director of ICT approves it; they are told now, and you are told of
            the decision. Each student is checked again when it runs. The figure is in ICT Support Settings.
          </Note>
        ) : null}
        <Note kind="info" title="Each student's temporary password will be their matriculation number">
          Every student reset must change the password at the next sign-in before anything else opens, and any open session is ended.
          {resolve && withTicket ? " A student whose ticket is resolved reads it there; the others are told by e-mail that ICT Support reset the password — never what it is."
            : " The student is told by e-mail that ICT Support reset the password — never what it is."}
          {preview.policy.ticket === "REQUIRED" ? " The desk's policy needs each student's own ticket: a student chosen without a login ticket will fail." : ""}
        </Note>
        {preview.notEligible ? (
          <DTable noPrint title="Not eligible" pageSize={10} cols={["Student", "Matriculation number", "Why"]} rows={preview.rows.filter((r) => !r.eligible).map((r) => [
            <span key="n">{r.full_name ?? <span className="sub2">Not shown</span>}</span>,
            <span key="m" className="tnum">{r.matric_no ?? "—"}</span>,
            <span key="w" className="sub2">{r.words}</span>,
          ])} />
        ) : null}
        {withTicket ? (
          <div className="stack">
            <label className="row row--inline row--tight" style={{ gap: 6 }}>
              <input type="checkbox" className="pchk" checked={resolve} onChange={(e) => setResolve(e.target.checked)} />
              Resolve each student&rsquo;s login ticket once the student is reset ({count(withTicket)} ticket{withTicket === 1 ? "" : "s"})
            </label>
            {resolve ? (
              <Field id="br-resolution" label="What the students read on their resolved ticket" hint="E-mailed to each with the resolution; 20 characters or more. A student not reset keeps the ticket open."
                error={resolutionOk ? undefined : "Say what the students should do, in 20 characters or more."}>
                <textarea id="br-resolution" className="ctl" rows={3} maxLength={4000} value={resolution} onChange={(e) => setResolution(e.target.value)} />
              </Field>
            ) : null}
          </div>
        ) : null}
        <Field id="br-why" label="Reason (required)">
          <textarea id="br-why" className="ctl" rows={2} maxLength={2000} value={reason} onChange={(e) => setReason(e.target.value)}
            placeholder="Students reported login issues at the desk; identities checked" />
        </Field>
        {problem ? <ProblemNotice problem={problem} /> : null}
      </Modal>
    );
  }

  if (!op) return null;

  if (step === "waiting") {
    return (
      <Modal wide title="Waiting for approval" sub={`${op.reference} · ${count(op.total)} students`} onClose={onClose}
        foot={<><span className="grow" /><LinkBtn href={`/helpdesk/password-reset/bulk/${op.id}`}>Open the record</LinkBtn><Btn kind="primary" onClick={onClose}>Done</Btn></>}>
        <Note kind="info" title="No student has been reset yet">
          {op.reference} waits for the Head of the ICT Support Desk or the Director of ICT, who have been told. Once it is approved the students
          are reset at once, each checked again; you are told of the decision. You can withdraw it from its record until then.
        </Note>
      </Modal>
    );
  }

  return (
    <Modal wide title={step === "running" ? "Resetting passwords…" : DONE[op.status] ?? "Password reset finished"}
      sub={`${op.reference} · ${STATUS[op.status]?.[0] ?? op.status}`} onClose={() => { if (step === "done") onClose(); }}
      foot={step === "running"
        ? <><span className="sub2 grow">The reset runs on the server; this window can be closed and the result read from the history.</span><Btn kind="ghost" busy={busy === "cancel"} onClick={() => void cancel()}>Cancel the rest</Btn></>
        : <><Btn kind="ghost" disabled={!items.length} onClick={async () => downloadBlob(await brandedXlsx("Bulk Password Reset", head, sheet(), { sheetName: "Bulk reset", serial: docSerial("BPR"), sub: op.reference, meta: [["Reference", op.reference], ["Reason", op.reason], ["Selected", String(op.total)], ["Reset", String(op.succeeded)], ["Failed", String(op.failed)]] }), `${op.reference.replace(/\//g, "-")}.xlsx`)}>Download Excel</Btn>
            <span className="grow" /><LinkBtn href={`/helpdesk/password-reset/bulk/${op.id}`}>Open the record</LinkBtn><Btn kind="primary" onClick={onClose}>Done</Btn></>}>
      <Tiles cls="grid--4" items={[
        ["Processed", `${count(op.processed)} / ${count(op.total)}`, null, step === "running" ? "so far" : "in all"],
        ["Successfully reset", count(op.succeeded), op.succeeded ? "var(--green-ink)" : null, "must change at the next sign-in"],
        ["Failed", count(op.failed), op.failed ? "var(--red-ink)" : null, "not reset, with the reason"],
        ["Status", STATUS[op.status]?.[0] ?? op.status, null, op.performed_by],
      ]} />
      {step === "running" ? (
        <div className="mt-2" role="progressbar" aria-valuemin={0} aria-valuemax={op.total} aria-valuenow={op.processed}
          style={{ height: 8, borderRadius: 4, background: "var(--sunk, #eef1f4)", overflow: "hidden" }}>
          <div style={{ width: `${op.total ? Math.round((100 * op.processed) / op.total) : 0}%`, height: "100%", background: "var(--sky, #2f7fbf)" }} />
        </div>
      ) : (
        <>
          {toLink.length ? (
            <Note kind="info" title={`${count(toLink.length)} student${toLink.length === 1 ? " has" : "s have"} no matriculation number`}
              action={<Btn kind="secondary" busy={busy === "links"} onClick={() => void sendLinks()}>Send reset links ({count(toLink.length)})</Btn>}>
              They sign in with the admission or JAMB number. Each can be sent the one-hour reset link to the e-mail and phone on the record, to choose their own password.
            </Note>
          ) : null}
          {links ? (
            <Note kind={links.notSent ? "bad" : "ok"} title={`${count(links.sent)} reset link${links.sent === 1 ? "" : "s"} sent${links.notSent ? `, ${count(links.notSent)} not sent` : ""}`}>
              {links.notSent ? "Each student not sent a link is named below with the reason." : "Each link works once, for an hour."}
            </Note>
          ) : null}
          {bad.length ? (
            <DTable noPrint title={`Failed (${count(bad.length)})`} pageSize={10} cols={["Student", "Matriculation number", "Reason"]} rows={bad.map((i) => [
              <span key="n">{i.name}</span>, <span key="m" className="tnum">{i.number ?? "—"}</span>, <span key="w" className="sub2">{resultNote(i) || i.failure_code}</span>,
            ])} />
          ) : null}
          <DTable noPrint title={`Successfully reset (${count(ok.length)})`} pageSize={10} cols={["Student", "Matriculation number", "Programme", "Ticket"]} rows={ok.map((i) => [
            <span key="n">{i.name}{i.status === "ALREADY_RESET" ? <span className="sub2"> (reset moments before)</span> : null}</span>,
            <span key="m" className="tnum">{i.number ?? "—"}</span>, <span key="p" className="sub2">{i.programme ?? "—"}</span>,
            <span key="t" className="sub2 tnum">{i.ticket_number ?? "—"}{i.ticket_resolved_at ? " · resolved" : ""}</span>,
          ])} />
          {op.missing ? <Note kind="info" title={`${op.missing} chosen record${op.missing === 1 ? " was" : "s were"} not found`}>Counted as failed: the record no longer exists.</Note> : null}
        </>
      )}
      {problem ? <ProblemNotice problem={problem} /> : null}
    </Modal>
  );
}
