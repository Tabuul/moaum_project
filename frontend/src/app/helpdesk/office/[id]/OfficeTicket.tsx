"use client";
/** One ticket as the office it waits on sees it (V328): the agent's question first, then the requester, the issue, the evidence,
 *  the whole conversation (the desk's internal notes included — the office is answering the desk), the history, and the answer.
 *  The answer is an instruction to the agent unless the office chooses to speak to the requester as well. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Attachments, DetailsGrid, PriorityPil, StatusPil, Timeline, requesterKind, requesterNumberLabel, when, type Ticket } from "@/lib/helpdesk";

export function OfficeTicket({ t }: { t: Ticket }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tab, setTab] = useState<"conversation" | "history">("conversation");
  const [answer, setAnswer] = useState("");
  const [toRequester, setToRequester] = useState(false);
  const waiting = !!t.office;

  async function send() {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/helpdesk/office/tickets/${t.id}/answer`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${t.number}: the office answered`) }, body: JSON.stringify({ body: answer.trim(), internal: !toRequester }) });
      if (!r.ok) { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return; }
      notify(`${t.number}: your answer is with the agent`);
      setAnswer("");
      router.refresh();
    } finally { setBusy(false); }
  }

  return (
    <>
      <PageHead eyebrow={`${t.category}${t.queue ? ` · ${t.queue} queue` : ""} · raised ${when(t.created_at)}`} title={t.number} description={t.subject}
        actions={<><StatusPil status={t.status} /><PriorityPil priority={t.priority} />{t.office ? <Pil kind="warn">With {t.office}</Pil> : null}<LinkBtn href="/helpdesk/office">Support Escalations</LinkBtn></>} />
      {problem ? <ProblemNotice problem={problem} /> : null}

      {waiting ? (
        <Note kind="info" title={`${t.escalated_by_name ?? "The support desk"} asks ${t.office} to decide`}>
          <span className="blk" style={{ whiteSpace: "pre-wrap" }}><b>{t.escalation_reason}</b></span>
          <span className="blk sub2 mt-2">Put to your office {when(t.escalated_at)}; the ticket waits since then. Agent on the ticket: {t.agent ?? "none"}.</span>
        </Note>
      ) : (
        <Note kind="info" title="Answered; back with the support desk">The ticket is no longer waiting on your office. It stays readable here.</Note>
      )}

      {waiting ? (
        <Panel title="Your answer" right="Goes to the agent on the ticket; the ticket returns to them">
          <PBody>
            <Field id="of-answer" label="What your office decides, and what the agent should do" required>
              <textarea id="of-answer" className="ctl" rows={5} value={answer} onChange={(e) => setAnswer(e.target.value)} maxLength={8000} placeholder="The decision, the reason, and the instruction to the agent" />
            </Field>
            <div className="row row--base mt-2">
              <Btn kind="primary" disabled={busy || answer.trim().length < 5} onClick={() => void send()}>{busy ? "Sending…" : "Answer the Desk"}</Btn>
              <label className="row row--tight"><input type="checkbox" className="chk" checked={toRequester} onChange={(e) => setToRequester(e.target.checked)} /> <span className="sub2">Show this answer to the requester as well (otherwise the agent relays it)</span></label>
            </div>
            <div className="sub2 mt-2">Your answer changes nothing by itself; the act is taken on your office&rsquo;s own desk.</div>
          </PBody>
        </Panel>
      ) : null}

      <div className="grid grid--2">
        <Panel title="Requester" right={t.requester_kind === "STAFF" ? "Member of staff" : requesterKind(t.requester_kind)}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["Name", <strong key="n">{t.requester_name}</strong>],
              [requesterNumberLabel(t.requester_kind), <span key="m" className="tnum">{t.requester_number ?? "—"}</span>],
              ["Email", t.requester_email ?? "—"],
              ["Phone", <span key="p" className="tnum">{t.requester_phone ?? "—"}</span>],
              ["Department", t.department ?? "—"],
              ["Faculty", t.faculty ?? "—"],
            ]} />
            {t.requester_kind === "STUDENT" && t.requester_number ? <div className="mt-3"><LinkBtn size="sm" href={`/search?q=${encodeURIComponent(t.requester_number)}`}>Open the Student Record</LinkBtn></div> : null}
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
        <PBody><Attachments items={t.attachments} href={(a) => `/api/bff/api/v1/helpdesk/office/tickets/${t.id}/attachments/${a.id}/content`} /></PBody>
      </Panel>

      <Panel title="Conversation and history" right={`${t.comments.length} message${t.comments.length === 1 ? "" : "s"} · ${t.timeline.length} event${t.timeline.length === 1 ? "" : "s"}`}>
        <PBody>
          <div className="mb-3"><Tabs label="Conversation or history" items={[{ id: "conversation", label: "Conversation", count: t.comments.length }, { id: "history", label: "History", count: t.timeline.length }]} value={tab} onChange={setTab} /></div>
          {tab === "history" ? <Timeline events={t.timeline} /> : t.comments.length ? (
            <div className="stack">
              {t.comments.map((c) => (
                <div key={c.id} className={`msg${c.internal ? " msg--internal" : c.author_kind === "REQUESTER" ? " msg--theirs" : ""}`}>
                  <div className="row row--base row--tight"><strong>{c.author_name}</strong><span className="sub2 tnum">{when(c.created_at)}</span>{c.internal ? <Pil kind="grey">Internal to the desk</Pil> : c.author_kind === "REQUESTER" ? <Pil kind="info">Requester</Pil> : c.author_kind === "SYSTEM" ? <Pil kind="grey">The portal</Pil> : <Pil kind="ok">Sent to the requester</Pil>}</div>
                  <div style={{ whiteSpace: "pre-wrap" }}>{c.body}</div>
                </div>
              ))}
            </div>
          ) : <div className="sub2">Nothing said yet.</div>}
        </PBody>
      </Panel>
    </>
  );
}
