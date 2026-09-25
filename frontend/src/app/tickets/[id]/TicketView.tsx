"use client";
/** The requester's ticket (V251): the header, what was reported, the desk's resolution when there is one, the
 *  conversation, the evidence, the history — and the acts: confirm the resolution, reopen on a reason, add an
 *  update or a file, withdraw a ticket no longer needed. Internal notes never reach this screen. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Attachments, DetailsGrid, FILE_TYPES, MAX_FILE, PriorityPil, StatusPil, Timeline, readBase64, when, type Ticket } from "@/lib/helpdesk";

export function TicketView({ t }: { t: Ticket }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [say, setSay] = useState("");
  const [reopen, setReopen] = useState<string | null>(null);
  const [withdraw, setWithdraw] = useState<string | null>(null);
  const [file, setFile] = useState<File | null>(null);
  const closed = t.status === "CLOSED";

  async function call(path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/helpdesk/my/tickets/${t.id}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      if (!r.ok) { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return false; }
      notify(reason);
      router.refresh();
      return true;
    } finally { setBusy(false); }
  }
  async function attach() {
    if (!file) return;
    if (!FILE_TYPES.includes(file.type) || file.size > MAX_FILE) { const p = { status: 422, title: "That file cannot be attached", detail: "A PDF, JPEG or PNG of at most 5 MB." }; setProblem(p); notifyProblem(p); return; }
    const b64 = await readBase64(file);
    if (await call("/attachments", { filename: file.name, contentType: file.type, contentBase64: b64 }, `${file.name} attached to ${t.number}`)) setFile(null);
  }

  return (
    <>
      <PageHead eyebrow="ICT support ticket" title={t.number} description={t.subject}
        actions={<>
          <StatusPil status={t.status} /><PriorityPil priority={t.priority} />
          <LinkBtn href="/tickets">My Support Tickets</LinkBtn>
        </>} />
      {problem ? <ProblemNotice problem={problem} /> : null}

      {t.status === "RESOLVED" ? (
        <Note kind="ok" title="Your issue has been marked as resolved" action={<span className="row row--tight">
          <Btn kind="go" disabled={busy} onClick={() => { if (window.confirm(`Confirm that ${t.number} is resolved? The ticket closes.`)) void call("/confirm", {}, `${t.number}: resolution confirmed`); }}>Confirm Resolution</Btn>
          <Btn kind="urgent" disabled={busy} onClick={() => setReopen("")}>Reopen Ticket</Btn>
        </span>}>
          <b>{t.resolution_summary}</b>{t.resolved_by_name ? ` — ${t.resolved_by_name}, ${when(t.resolved_at)}` : ""}
          <div className="mt-2" style={{ whiteSpace: "pre-wrap" }}>{t.resolution_details}</div>
          <div className="sub2 mt-2">If this settles it, confirm and the ticket closes. If not, reopen it and say what is still wrong; the desk picks it up again.</div>
        </Note>
      ) : closed ? (
        <Note kind="info" title={`Closed ${when(t.closed_at)}${t.closed_by_name ? ` by ${t.closed_by_kind === "REQUESTER" ? "you" : t.closed_by_name}` : ""}`}>
          {t.closure_reason ?? "The ticket is closed."}{t.resolution_summary ? <div className="mt-2"><b>Resolution:</b> {t.resolution_summary}</div> : null}
          <div className="sub2 mt-2">A closed ticket takes no more updates. If the problem returns, raise a new ticket and quote this number.</div>
        </Note>
      ) : (
        <Note kind="info" title={t.status === "SUBMITTED" ? "Waiting for the ICT desk to open it" : t.status === "OPENED" ? "The ICT desk has opened your ticket" : t.status === "REOPENED" ? "Reopened; the desk will pick it up again" : "The ICT desk is working on it"}>
          {t.agent ? <>With <b>{t.agent}</b> since {when(t.assigned_at)}. </> : "Not yet assigned to an agent. "}
          You will be told by email at each turn. Add anything the desk should know below.
        </Note>
      )}

      <div className="grid grid--2">
        <Panel title="What you reported" right={`${t.category} · raised ${when(t.created_at)}`}>
          <PBody>
            <div style={{ whiteSpace: "pre-wrap" }}>{t.description}</div>
            <div className="hr" />
            <DetailsGrid fields={t.fields} details={t.details} />
          </PBody>
        </Panel>
        <Panel title="Your details on the ticket" right="As the account had them when you raised it">
          <PBody>
            <div className="stack">
              <div className="row row--base"><span className="sub2" style={{ width: 120 }}>Name</span><strong>{t.requester_name}</strong></div>
              <div className="row row--base"><span className="sub2" style={{ width: 120 }}>{t.requester_kind === "STUDENT" ? "Matriculation no." : "Staff number"}</span><span className="tnum">{t.requester_number ?? "—"}</span></div>
              <div className="row row--base"><span className="sub2" style={{ width: 120 }}>Email</span><span>{t.requester_email ?? "—"}</span></div>
              <div className="row row--base"><span className="sub2" style={{ width: 120 }}>Phone</span><span className="tnum">{t.requester_phone ?? "—"}</span></div>
              <div className="row row--base"><span className="sub2" style={{ width: 120 }}>Department</span><span>{t.department ?? "—"}</span></div>
              <div className="row row--base"><span className="sub2" style={{ width: 120 }}>Faculty</span><span>{t.faculty ?? "—"}</span></div>
            </div>
          </PBody>
        </Panel>
      </div>

      <Panel title="The conversation" right={t.comments.length ? `${t.comments.length} update${t.comments.length === 1 ? "" : "s"}` : "Nothing said yet"}>
        <PBody>
          {t.comments.length ? (
            <div className="stack">
              {t.comments.map((c) => (
                <div key={c.id} className={`msg${c.author_kind === "REQUESTER" ? " msg--mine" : ""}`}>
                  <div className="row row--base row--tight"><strong>{c.author_kind === "REQUESTER" ? "You" : c.author_kind === "AGENT" ? c.author_name : "The portal"}</strong><span className="sub2 tnum">{when(c.created_at)}</span>{c.author_kind === "AGENT" ? <Pil kind="info">ICT desk</Pil> : null}</div>
                  <div style={{ whiteSpace: "pre-wrap" }}>{c.body}</div>
                </div>
              ))}
            </div>
          ) : <div className="sub2">The desk&rsquo;s updates, and yours, appear here.</div>}
          {!closed ? (
            <div className="mt-3">
              <Field id="tk-say" label="Add an update for the desk"><textarea id="tk-say" className="ctl" rows={3} value={say} onChange={(e) => setSay(e.target.value)} maxLength={8000} /></Field>
              <div className="row row--base mt-2">
                <Btn kind="primary" disabled={busy || say.trim().length < 2} onClick={async () => { if (await call("/comments", { body: say.trim() }, `${t.number}: update added`)) setSay(""); }}>Send Update</Btn>
                <input type="file" className="ctl" style={{ flex: "1 1 220px" }} accept=".pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png" onChange={(e) => setFile(e.target.files?.[0] ?? null)} aria-label="Attach a file" />
                <Btn kind="ghost" disabled={busy || !file} onClick={() => void attach()}>Attach File</Btn>
              </div>
            </div>
          ) : null}
        </PBody>
      </Panel>

      <div className="grid grid--2">
        <Panel title="Attachments" right={`${t.attachments.length} file${t.attachments.length === 1 ? "" : "s"}`}>
          <PBody><Attachments items={t.attachments} href={(a) => `/api/bff/api/v1/helpdesk/my/tickets/${t.id}/attachments/${a.id}/content`} /></PBody>
        </Panel>
        <Panel title="History" right="Every step, as it happened">
          <PBody><Timeline events={t.timeline} showInternal={false} /></PBody>
        </Panel>
      </div>

      {!closed && t.status !== "RESOLVED" ? (
        <div className="row row--base">
          <Btn kind="ghost" disabled={busy} onClick={() => setWithdraw("")}>Close this ticket</Btn>
          <span className="sub2">Close it yourself if the problem has gone away or you raised it in error.</span>
        </div>
      ) : null}

      {reopen !== null ? (
        <Modal title={`Reopen ${t.number}`} sub="Tell the desk what is still wrong" onClose={() => setReopen(null)}
          foot={<><Btn kind="ghost" onClick={() => setReopen(null)}>Cancel</Btn><Btn kind="urgent" disabled={busy || reopen.trim().length < 5} onClick={async () => { if (await call("/reopen", { reason: reopen.trim() }, `${t.number}: reopened`)) setReopen(null); }}>Reopen the Ticket</Btn></>}>
          <Field id="tk-reopen" label="Why the resolution did not settle it" required><textarea id="tk-reopen" className="ctl" rows={4} value={reopen} onChange={(e) => setReopen(e.target.value)} maxLength={2000} /></Field>
        </Modal>
      ) : null}
      {withdraw !== null ? (
        <Modal title={`Close ${t.number}`} sub="The ticket closes without a resolution from the desk" onClose={() => setWithdraw(null)}
          foot={<><Btn kind="ghost" onClick={() => setWithdraw(null)}>Keep it open</Btn><Btn kind="primary" disabled={busy} onClick={async () => { if (await call("/close", { reason: withdraw.trim() || null }, `${t.number}: closed by the requester`)) setWithdraw(null); }}>Close the Ticket</Btn></>}>
          <Field id="tk-withdraw" label="Reason" hint="Optional"><input id="tk-withdraw" className="ctl" value={withdraw} onChange={(e) => setWithdraw(e.target.value)} maxLength={2000} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
