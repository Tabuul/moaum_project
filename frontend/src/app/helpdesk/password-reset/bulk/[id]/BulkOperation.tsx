"use client";

/** One bulk password reset (V559): the operation — reference, who made it, the reason, when, the counts — and each student's
 *  result with the reason a student was not reset; read again every two seconds while it runs. V563: a Head other than the one who
 *  asked approves or declines one waiting for approval; the students refused for want of a matriculation number are sent the reset
 *  link; the students not reset are tried again as a new operation. No password is on it, nor on its Excel or PDF. */
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { STATUS, linkable, notReset, resultNote, resultWord, running, ticketsOf, type Operation, type OpItem, type Preview } from "@/lib/bulk-reset";
import { BulkConfirm, previewFor } from "../BulkConfirm";

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
const count = (n: number) => Number(n).toLocaleString("en-NG");
const RESULT: Record<string, "grey" | "ok" | "bad" | "info"> = { PENDING: "grey", RESET: "ok", ALREADY_RESET: "info", FAILED: "bad" };

export function BulkOperation({ op }: { op: Operation }) {
  const router = useRouter();
  const [show, setShow] = useState<"ALL" | "OK" | "FAILED">("ALL");
  const [note, setNote] = useState("");
  const [retry, setRetry] = useState<Preview | null>(null);
  const isRunning = running(op.status);
  const waiting = op.status === "AWAITING_APPROVAL";

  useEffect(() => {
    if (!isRunning) return;
    const t = setInterval(() => router.refresh(), 2000);
    return () => clearInterval(t);
  }, [isRunning, router]);

  const items: OpItem[] = op.items ?? [];
  const toLink = linkable(items);
  const again = notReset(items);
  const shown = items.filter((i) => show === "ALL" || (show === "FAILED" ? i.status === "FAILED" : i.status === "RESET" || i.status === "ALREADY_RESET"));
  const HEAD = ["S/N", "Student", "Matriculation number", "Programme", "Faculty", "Level", "Ticket", "Result", "Reason", "Processed"];
  const line = (i: OpItem, n: number) => [n + 1, i.name, i.number ?? "", i.programme ?? "", i.faculty ?? "", i.level ?? "", i.ticket_number ?? "",
    resultWord(i), resultNote(i), when(i.processed_at)];
  const meta: [string, string][] = [["Reference", op.reference], ["Performed by", op.performed_by], ["Reason", op.reason], ["Date", when(op.created_at)],
    ["Selected", String(op.total)], ["Reset", String(op.succeeded)], ["Failed", String(op.failed)], ["Status", STATUS[op.status]?.[0] ?? op.status]];

  async function post(path: string, body: unknown, why: string, done: string) {
    const r = await fetch(`/api/bff/api/v1/helpdesk/support/password-reset/bulk/${op.id}${path}`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(body ?? {}),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: "That could not be done just now." }); return null; }
    notify(done);
    router.refresh();
    return j;
  }

  async function sendLinks() {
    const r = await post("/links", {}, `Reset links after bulk reset ${op.reference}`, "Reset links sent");
    if (r && r.notSent) notifyProblem({ status: 422, title: `${r.notSent} student${r.notSent === 1 ? " was" : "s were"} not sent a link: each is named with the reason.` });
  }

  async function openRetry() {
    const r = await previewFor(again.map((i) => i.student_id));
    if (!r.ok) { notifyProblem(r.problem); return; }
    setRetry(r.data);
  }

  return (
    <>
      <PageHead title={op.reference} eyebrow="Bulk password reset"
        description={<>By {op.performed_by}{op.office ? ` (${op.office})` : ""} on {when(op.created_at)}{op.completed_at ? `, finished ${when(op.completed_at)}` : ""}. Reason: {op.reason}</>}
        actions={<>
          {(isRunning || waiting) && op.mayAct ? <Btn kind="ghost" onClick={() => void post("/cancel", {}, `Bulk password reset ${op.reference} cancelled`, waiting ? "Withdrawn" : "Cancelled")}>{waiting ? "Withdraw it" : "Cancel the rest"}</Btn> : null}
          <LinkBtn href="/helpdesk/password-reset/bulk/history">Bulk reset history</LinkBtn>
          <LinkBtn href="/helpdesk/password-reset/bulk">Bulk password reset</LinkBtn>
        </>} />

      {op.retry_of ? <div className="sub2" style={{ marginBottom: 8 }}>Tries again the students <Link className="lnk tnum" href={`/helpdesk/password-reset/bulk/${op.retry_of}`}>{op.retry_of_reference}</Link> did not reset.</div> : null}

      {waiting ? (
        <Panel title="Waiting for approval">
          <PBody>
            <div className="stack">
              <Note kind="info" title={`${count(op.total)} students — more than the ${count(op.approval_over ?? 0)} a bulk reset may reset without approval`}>
                No student is reset until the Head of the ICT Support Desk or the Director of ICT approves it. Each student is checked again when it runs.
                {op.resolve_tickets ? " Their login tickets will be resolved with the reset." : ""}
              </Note>
              {op.mayDecide ? (
                <>
                  <Field id="bo-note" label="Note (required to decline)">
                    <textarea id="bo-note" className="ctl" rows={2} maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} placeholder="Identities checked by the CPO; go ahead" />
                  </Field>
                  <div className="row" style={{ gap: 8 }}>
                    <Btn kind="primary" onClick={() => void post("/approve", { note: note.trim() || null }, `Bulk password reset ${op.reference} approved`, "Approved: the students are being reset")}>Approve and reset</Btn>
                    <Btn kind="urgent" disabled={note.trim().length < 10} onClick={() => void post("/reject", { note: note.trim() }, `Bulk password reset ${op.reference} declined`, "Declined: no student was reset")}>Decline</Btn>
                  </div>
                </>
              ) : <div className="sub2">{op.mayAct ? "It was sent to the Head of the ICT Support Desk; you are told of the decision. You may withdraw it." : "A Head other than the one who asked decides it."}</div>}
            </div>
          </PBody>
        </Panel>
      ) : null}
      {op.decided_by ? (
        <div className="sub2" style={{ marginBottom: 8 }}>
          {op.status === "REJECTED" ? "Declined" : "Approved"} by {op.decided_by} on {when(op.decided_at)}{op.decision_note ? ` — ${op.decision_note}` : ""}.
        </div>
      ) : null}

      <Tiles cls="grid--4" items={[
        ["Status", <Pil key="s" kind={STATUS[op.status]?.[1] ?? "grey"}>{STATUS[op.status]?.[0] ?? op.status}</Pil>, null, isRunning ? `${count(op.processed)} of ${count(op.total)} processed` : waiting ? "not started" : "final"],
        ["Selected", count(op.total), null, op.resolve_tickets ? "tickets resolved with the reset" : "students"],
        ["Successfully reset", count(op.succeeded), op.succeeded ? "var(--green-ink)" : null, "must change at the next sign-in"],
        ["Failed", count(op.failed), op.failed ? "var(--red-ink)" : null, "not reset, with the reason"],
      ]} />

      {!isRunning && !waiting && op.mayAct && (toLink.length || again.length) ? (
        <Panel title="The students not reset">
          <PBody>
            <div className="stack">
              {toLink.length ? (
                <Note kind="info" title={`${count(toLink.length)} without a matriculation number`} action={<Btn kind="secondary" onClick={() => void sendLinks()}>Send reset links ({count(toLink.length)})</Btn>}>
                  They sign in with the admission or JAMB number: each is sent the one-hour reset link to the e-mail and phone on the record, to choose their own password.
                </Note>
              ) : null}
              {again.length ? (
                <Note kind="info" title={`${count(again.length)} not reset`} action={<Btn kind="secondary" onClick={() => void openRetry()}>Retry the students not reset ({count(again.length)})</Btn>}>
                  Once the cause is put right (a matriculation number issued, a status changed, the student brought within your scope), try them again as a new operation; each is checked again.
                </Note>
              ) : null}
            </div>
          </PBody>
        </Panel>
      ) : null}

      {op.retries?.length ? (
        <div className="sub2" style={{ marginBottom: 8 }}>Tried again in {op.retries.map((r, n) => (
          <span key={r.id}>{n ? ", " : ""}<Link className="lnk tnum" href={`/helpdesk/password-reset/bulk/${r.id}`}>{r.reference}</Link> ({STATUS[r.status]?.[0] ?? r.status})</span>
        ))}.</div>
      ) : null}

      <Panel title="Students" right={<div className="row row--inline" style={{ gap: 6 }}>
        {(["ALL", "OK", "FAILED"] as const).map((k) => (
          <Btn key={k} kind={show === k ? "secondary" : "ghost"} onClick={() => setShow(k)}>{k === "ALL" ? `All (${count(items.length)})` : k === "OK" ? "Reset" : "Failed"}</Btn>
        ))}
        <Btn kind="ghost" disabled={!items.length} onClick={async () => downloadBlob(await brandedXlsx("Bulk Password Reset", HEAD, items.map(line), { sheetName: "Bulk reset", serial: docSerial("BPR"), sub: op.reference, meta }), `${op.reference.replace(/\//g, "-")}.xlsx`)}>Excel</Btn>
        <Btn kind="ghost" disabled={!items.length} onClick={() => brandedPrint("Bulk Password Reset", op.reference, HEAD, items.map(line), docSerial("BPR"), { meta, orientation: "landscape" })}>PDF</Btn>
      </div>}>
        <DTable pageSize={25} texts={shown.map((i) => `${i.name} ${i.number ?? ""} ${i.programme ?? ""} ${i.ticket_number ?? ""}`)}
          cols={["S/N|num", "Student", "Matriculation number", "Programme", "Level|num", "Ticket", "Result|mid", "Reason", "Processed"]}
          rows={shown.map((i, n) => [
            <span key="n" className="tnum sub2">{n + 1}</span>,
            <Link key="s" className="lnk" href={`/helpdesk/students/${i.student_id}?tab=history`}>{i.name}</Link>,
            <span key="m" className="tnum">{i.number ?? "—"}</span>,
            <span key="p" className="sub2">{i.programme ?? "—"}<div>{i.faculty ?? ""}</div></span>,
            <span key="l" className="tnum">{i.level ?? "—"}</span>,
            <span key="t" className="tnum sub2">{i.ticket_id ? <Link className="lnk" href={`/helpdesk/tickets/${i.ticket_id}`}>{i.ticket_number}</Link> : "—"}{i.ticket_resolved_at ? <div>resolved</div> : null}</span>,
            <Pil key="r" kind={i.link_sent_at ? "info" : RESULT[i.status] ?? "grey"}>{resultWord(i)}</Pil>,
            <span key="w" className="sub2">{resultNote(i) || (i.status === "ALREADY_RESET" ? "Reset moments before; not reset twice" : "")}</span>,
            <span key="d" className="sub2 tnum">{when(i.processed_at)}</span>,
          ])} />
        {op.missing ? <div className="sub2" style={{ padding: "8px 16px" }}>{op.missing} chosen record{op.missing === 1 ? " was" : "s were"} not found, and counted as failed.</div> : null}
      </Panel>

      {retry ? (
        <BulkConfirm preview={retry} ids={again.map((i) => i.student_id)} tickets={ticketsOf(again)} retryOf={{ id: op.id, reference: op.reference }}
          onClose={() => setRetry(null)} onEnded={() => router.refresh()} />
      ) : null}
    </>
  );
}
