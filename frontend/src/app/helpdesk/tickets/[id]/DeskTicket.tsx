"use client";
/** The desk's ticket (V251): the header with status, priority, category, dates and agent; the requester; the issue
 *  and the category's fields; the attachments; the conversation with internal notes kept apart from the updates the
 *  requester sees; the resolution; the history as a timeline; and the acts — take or assign, start work, change
 *  priority, escalate, note, update, attach, resolve, reopen, close on a reason. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Attachments, DetailsGrid, FILE_TYPES, MAX_FILE, PRIORITY, PriorityPil, StatusPil, Timeline, readBase64, when, type Agent, type Ticket } from "@/lib/helpdesk";

type Dialog = "assign" | "escalate" | "resolve" | "close" | "reopen" | null;

export function DeskTicket({ t, me, director, agents }: { t: Ticket; me: string; director: boolean; agents: Agent[] }) {
  void director;
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tab, setTab] = useState<"conversation" | "history">("conversation");
  const [dialog, setDialog] = useState<Dialog>(null);
  const [note, setNote] = useState("");
  const [internal, setInternal] = useState(true);
  const [file, setFile] = useState<File | null>(null);
  const [fileInternal, setFileInternal] = useState(false);
  const [agent, setAgent] = useState(t.assigned_to ?? "");
  const [reason, setReason] = useState("");
  const [summary, setSummary] = useState(t.resolution_summary ?? "");
  const [details, setDetails] = useState(t.resolution_details ?? "");
  const closed = t.status === "CLOSED";
  const mine = t.assigned_to === me;

  async function call(path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/helpdesk/tickets/${t.id}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
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
    if (await call("/attachments", { filename: file.name, contentType: file.type, contentBase64: b64, internal: fileInternal }, `${file.name} attached to ${t.number}${fileInternal ? " (internal)" : ""}`)) setFile(null);
  }
  const closeDialog = () => { setDialog(null); setReason(""); };

  return (
    <>
      <PageHead eyebrow={`${t.category} · raised ${when(t.created_at)}`} title={t.number} description={t.subject}
        actions={<>
          <StatusPil status={t.status} /><PriorityPil priority={t.priority} />
          {t.overdue ? <Pil kind="bad">Overdue</Pil> : t.response_overdue ? <Pil kind="warn">No response yet</Pil> : null}
          {t.escalated ? <Pil kind="warn">Escalated</Pil> : null}
          <LinkBtn href="/helpdesk">The Queue</LinkBtn>
        </>} />
      {problem ? <ProblemNotice problem={problem} /> : null}

      {!closed ? (
        <Panel title="Act on the ticket" right={t.agent ? `With ${t.agent}${mine ? " (you)" : ""} since ${when(t.assigned_at)}` : "Not assigned"}>
          <PBody>
            <div className="row">
              {!mine ? <Btn kind="primary" disabled={busy} onClick={() => void call("/assign", { agentId: me }, `${t.number}: taken by you`)}>{t.agent ? "Take it over" : "Accept the Ticket"}</Btn> : null}
              <Btn kind="secondary" disabled={busy} onClick={() => setDialog("assign")}>{t.agent ? "Reassign" : "Assign to an Agent"}</Btn>
              {t.status === "OPENED" || t.status === "REOPENED" ? <Btn kind="go" disabled={busy} onClick={() => void call("/status", { status: "IN_PROGRESS" }, `${t.number}: work started`)}>Start Work</Btn> : null}
              {t.status === "IN_PROGRESS" ? <Btn kind="go" disabled={busy} onClick={() => setDialog("resolve")}>Resolve</Btn> : null}
              {t.status === "RESOLVED" ? <Btn kind="go" disabled={busy} onClick={() => void call("/status", { status: "CLOSED", reason: "Closed by the desk after the resolution" }, `${t.number}: closed`)}>Close as Resolved</Btn> : null}
              {t.status === "RESOLVED" ? <Btn kind="ghost" disabled={busy} onClick={() => setDialog("reopen")}>Reopen</Btn> : null}
              <Btn kind="ghost" disabled={busy} onClick={() => setDialog("escalate")}>Escalate</Btn>
              <select className="ctl" value={t.priority} disabled={busy} onChange={(e) => void call("/priority", { priority: e.target.value }, `${t.number}: priority ${PRIORITY[e.target.value]?.[0] ?? e.target.value}`)} aria-label="Priority">
                {Object.entries(PRIORITY).map(([k, v]) => <option key={k} value={k}>{v[0]} priority</option>)}
              </select>
              <span className="grow" />
              {t.status !== "RESOLVED" ? <Btn kind="urgent" disabled={busy} onClick={() => setDialog("close")}>Close on a Reason</Btn> : null}
            </div>
            <div className="sub2 mt-2">
              {t.status === "SUBMITTED" ? "Just opened by you. " : ""}
              Due {when(t.due_at)} by the {PRIORITY[t.priority]?.[0].toLowerCase() ?? ""} SLA{t.first_response_at ? `; first response ${when(t.first_response_at)}` : `; first response due ${when(t.response_due_at)}`}.
              {t.escalated_to_name ? ` Escalated to ${t.escalated_to_name} by ${t.escalated_by_name} on ${when(t.escalated_at)}: ${t.escalation_reason}.` : ""}
            </div>
          </PBody>
        </Panel>
      ) : (
        <Note kind="info" title={`Closed ${when(t.closed_at)} by ${t.closed_by_name ?? "the portal"}`} action={<Btn kind="ghost" disabled={busy} onClick={() => setDialog("reopen")}>Reopen</Btn>}>
          {t.closure_reason ?? "No reason recorded."}{t.reopen_count ? ` Reopened ${t.reopen_count} time${t.reopen_count === 1 ? "" : "s"} before.` : ""}
        </Note>
      )}

      {t.resolution_summary ? (
        <Note kind={t.status === "RESOLVED" ? "ok" : "info"} title={`Resolution: ${t.resolution_summary}`}>
          <div style={{ whiteSpace: "pre-wrap" }}>{t.resolution_details}</div>
          <div className="sub2 mt-2">{t.resolved_by_name}, {when(t.resolved_at)}{t.status === "RESOLVED" ? " · awaiting the requester's confirmation" : ""}</div>
        </Note>
      ) : null}

      <div className="grid grid--2">
        <Panel title="Requester" right={t.requester_kind === "STUDENT" ? "Student" : "Member of staff"}>
          <PBody>
            <div className="stack">
              <div className="row row--base"><span className="sub2" style={{ width: 120 }}>Name</span><strong>{t.requester_name}</strong></div>
              <div className="row row--base"><span className="sub2" style={{ width: 120 }}>{t.requester_kind === "STUDENT" ? "Matriculation no." : "Staff number"}</span><span className="tnum">{t.requester_number ?? "—"}</span></div>
              <div className="row row--base"><span className="sub2" style={{ width: 120 }}>Email</span><span>{t.requester_email ? <a className="lnk" href={`mailto:${t.requester_email}`}>{t.requester_email}</a> : "—"}</span></div>
              <div className="row row--base"><span className="sub2" style={{ width: 120 }}>Phone</span><span className="tnum">{t.requester_phone ?? "—"}</span></div>
              <div className="row row--base"><span className="sub2" style={{ width: 120 }}>Department</span><span>{t.department ?? "—"}</span></div>
              <div className="row row--base"><span className="sub2" style={{ width: 120 }}>Faculty</span><span>{t.faculty ?? "—"}</span></div>
              {t.requester_kind === "STUDENT" && t.requester_number ? <div><LinkBtn size="sm" href={`/search?q=${encodeURIComponent(t.requester_number)}`}>Open the student record</LinkBtn></div> : null}
            </div>
          </PBody>
        </Panel>
        <Panel title="Issue details" right={t.opened_by_name ? `Opened by ${t.opened_by_name}, ${when(t.opened_at)}` : "Not yet opened"}>
          <PBody>
            <div style={{ whiteSpace: "pre-wrap" }}>{t.description}</div>
            <div className="hr" />
            <DetailsGrid fields={t.fields} details={t.details} />
          </PBody>
        </Panel>
      </div>

      <Panel title="Attachments" right={`${t.attachments.length} file${t.attachments.length === 1 ? "" : "s"}`}>
        <PBody>
          <Attachments items={t.attachments} href={(a) => `/api/bff/api/v1/helpdesk/tickets/${t.id}/attachments/${a.id}/content`} />
          <div className="row row--base mt-3">
            <input type="file" className="ctl" style={{ flex: "1 1 220px" }} accept=".pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png" onChange={(e) => setFile(e.target.files?.[0] ?? null)} aria-label="Attach a file" />
            <label className="row row--tight"><input type="checkbox" checked={fileInternal} onChange={(e) => setFileInternal(e.target.checked)} /> <span className="sub2">Internal (the requester does not see it)</span></label>
            <Btn kind="ghost" disabled={busy || !file} onClick={() => void attach()}>Attach File</Btn>
          </div>
        </PBody>
      </Panel>

      <Panel title="Conversation and history" right={<Tabs items={[{ id: "conversation", label: "Conversation", count: t.comments.length }, { id: "history", label: "History", count: t.timeline.length }]} value={tab} onChange={setTab} />}>
        <PBody>
          {tab === "history" ? <Timeline events={t.timeline} /> : (
            <>
              {t.comments.length ? (
                <div className="stack">
                  {t.comments.map((c) => (
                    <div key={c.id} className={`msg${c.internal ? " msg--internal" : c.author_kind === "REQUESTER" ? " msg--theirs" : ""}`}>
                      <div className="row row--base row--tight"><strong>{c.author_name}</strong><span className="sub2 tnum">{when(c.created_at)}</span>{c.internal ? <Pil kind="grey">Internal note</Pil> : c.author_kind === "REQUESTER" ? <Pil kind="info">Requester</Pil> : <Pil kind="ok">Sent to the requester</Pil>}</div>
                      <div style={{ whiteSpace: "pre-wrap" }}>{c.body}</div>
                    </div>
                  ))}
                </div>
              ) : <div className="sub2">Nothing said yet.</div>}
              <div className="mt-3">
                <div className="row row--base mb-2">
                  <Btn kind={internal ? "primary" : "ghost"} size="sm" onClick={() => setInternal(true)}>Internal note</Btn>
                  <Btn kind={!internal ? "primary" : "ghost"} size="sm" onClick={() => setInternal(false)}>Update to the requester</Btn>
                  <span className="sub2">{internal ? "Seen by the ICT desk only." : "Sent to the requester by email and shown on their ticket."}</span>
                </div>
                <textarea className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} maxLength={8000} aria-label={internal ? "Internal note" : "Update to the requester"} placeholder={internal ? "What was found, what was tried, what to check next…" : "What the requester should know…"} />
                <div className="row row--base mt-2">
                  <Btn kind={internal ? "secondary" : "primary"} disabled={busy || note.trim().length < 2} onClick={async () => { if (await call("/comments", { body: note.trim(), internal }, `${t.number}: ${internal ? "internal note added" : "update sent to the requester"}`)) setNote(""); }}>{internal ? "Add Internal Note" : "Send Update"}</Btn>
                </div>
              </div>
            </>
          )}
        </PBody>
      </Panel>

      {dialog === "assign" ? (
        <Modal title={t.agent ? `Reassign ${t.number}` : `Assign ${t.number}`} sub="To an ICT Support Agent or the Director" onClose={closeDialog}
          foot={<><Btn kind="ghost" onClick={closeDialog}>Cancel</Btn><Btn kind="primary" disabled={busy || !agent || agent === t.assigned_to} onClick={async () => { if (await call("/assign", { agentId: agent, reason: reason.trim() || null }, `${t.number}: ${t.agent ? "reassigned" : "assigned"} to ${agents.find((a) => a.id === agent)?.name ?? "an agent"}`)) closeDialog(); }}>{t.agent ? "Reassign" : "Assign"}</Btn></>}>
          <div className="stack">
            <Field id="hd-agent" label="Agent" required>
              <select id="hd-agent" className="ctl" value={agent} onChange={(e) => setAgent(e.target.value)}>
                <option value="">Choose…</option>
                {agents.map((a) => <option key={a.id} value={a.id}>{a.name} · {a.offices} · {a.open} open{a.reachable ? "" : " · no email"}</option>)}
              </select>
            </Field>
            <Field id="hd-assign-reason" label="Note" hint="Optional; goes on the history"><input id="hd-assign-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} /></Field>
          </div>
        </Modal>
      ) : null}
      {dialog === "escalate" ? (
        <Modal title={`Escalate ${t.number}`} sub="To a senior agent or the Director of ICT, on a reason; they are told" onClose={closeDialog}
          foot={<><Btn kind="ghost" onClick={closeDialog}>Cancel</Btn><Btn kind="urgent" disabled={busy || !agent || agent === me || reason.trim().length < 5} onClick={async () => { if (await call("/escalate", { toPersonId: agent, reason: reason.trim() }, `${t.number}: escalated to ${agents.find((a) => a.id === agent)?.name ?? ""}`)) closeDialog(); }}>Escalate</Btn></>}>
          <div className="stack">
            <Field id="hd-esc-to" label="Escalate to" required>
              <select id="hd-esc-to" className="ctl" value={agent === me ? "" : agent} onChange={(e) => setAgent(e.target.value)}>
                <option value="">Choose…</option>
                {agents.filter((a) => a.id !== me).sort((a, b) => Number(b.director) - Number(a.director)).map((a) => <option key={a.id} value={a.id}>{a.name} · {a.director ? "Director of ICT" : a.offices}</option>)}
              </select>
            </Field>
            <Field id="hd-esc-reason" label="Reason" required><textarea id="hd-esc-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={2000} /></Field>
          </div>
        </Modal>
      ) : null}
      {dialog === "resolve" ? (
        <Modal title={`Resolve ${t.number}`} sub="The requester is told, and asked to confirm or reopen" onClose={closeDialog} wide
          foot={<><Btn kind="ghost" onClick={closeDialog}>Cancel</Btn><Btn kind="go" disabled={busy || summary.trim().length < 5 || details.trim().length < 20} onClick={async () => { if (await call("/resolve", { summary: summary.trim(), details: details.trim() }, `${t.number}: resolved`)) closeDialog(); }}>Mark as Resolved</Btn></>}>
          <div className="stack">
            <Field id="hd-res-sum" label="Resolution summary" required hint="One line the requester reads first"><input id="hd-res-sum" className="ctl" value={summary} onChange={(e) => setSummary(e.target.value)} maxLength={300} /></Field>
            <Field id="hd-res-det" label="Resolution details" required hint="What was found, what was changed, what the requester should do now; at least a sentence or two"><textarea id="hd-res-det" className="ctl" rows={6} value={details} onChange={(e) => setDetails(e.target.value)} maxLength={8000} /></Field>
            <div className="sub2">A file with the resolution can be attached from the Attachments panel once the ticket is resolved.</div>
          </div>
        </Modal>
      ) : null}
      {dialog === "close" ? (
        <Modal title={`Close ${t.number} on a reason`} sub="An administrative closure: the requester is told, and the reason goes on the record" onClose={closeDialog}
          foot={<><Btn kind="ghost" onClick={closeDialog}>Cancel</Btn><Btn kind="urgent" disabled={busy || reason.trim().length < 5} onClick={async () => { if (await call("/status", { status: "CLOSED", reason: reason.trim() }, `${t.number}: closed by the desk`)) closeDialog(); }}>Close the Ticket</Btn></>}>
          <Field id="hd-close-reason" label="Closure reason" required><textarea id="hd-close-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={2000} /></Field>
        </Modal>
      ) : null}
      {dialog === "reopen" ? (
        <Modal title={`Reopen ${t.number}`} sub="Back to the desk, on a reason" onClose={closeDialog}
          foot={<><Btn kind="ghost" onClick={closeDialog}>Cancel</Btn><Btn kind="primary" disabled={busy || reason.trim().length < 5} onClick={async () => { if (await call("/status", { status: "REOPENED", reason: reason.trim() }, `${t.number}: reopened by the desk`)) closeDialog(); }}>Reopen</Btn></>}>
          <Field id="hd-reopen-reason" label="Why" required><textarea id="hd-reopen-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={2000} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
