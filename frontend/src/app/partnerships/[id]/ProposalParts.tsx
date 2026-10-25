"use client";
/** V658: the working parts of a proposal's page — reviews and internal notes, the applicant's messages and requests,
 *  due diligence, documents, agreements, and the partnership under way. Each shows what the acting office may do and
 *  leaves the deciding to the server. */
import { useRef, useState } from "react";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import {
  AGREEMENT_KINDS, AGREEMENT_STATUS, ATTACHMENT_KINDS, CURRENCIES, DD_STATUS, RECOMMENDATIONS, bytes, dateWords, fileProblem, money, word,
} from "@/lib/partnerships";
import { SCHOOL, downloadBlob } from "@/lib/exportbrand";
import { PTN, can, ptnCall, readDataUrl, type DeskData } from "../ptn-call";

export type Row = Record<string, unknown>;
export interface Detail {
  proposal: Row; mayConfidential: boolean; permissions: string[]; actions: string[]; attachments: Row[]; events: Row[]; messages: Row[]; requests: Row[];
  reviewers: Row[]; dueDiligence: Row[]; agreements: Row[]; activities: Row[]; outcomes: Row[];
}
type After = (msg: string) => Promise<void>;
const s = (v: unknown) => (v == null || v === "" ? "—" : String(v));

/** one write, its problem shown beside the form that made it */
function useWrite() {
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  async function run<T>(key: string, path: string, init: { method: "POST" | "PUT" | "DELETE"; body?: unknown; reason: string }, then: (data: T) => Promise<void> | void) {
    setBusy(key); setProblem(null);
    try {
      const r = await ptnCall<T>(path, init);
      if (!r.ok) { setProblem(r.problem); return false; }
      await then(r.data);
      return true;
    } finally { setBusy(null); }
  }
  return { busy, problem, setProblem, run };
}

/* ── reviews and internal notes ── */

export function Review({ d, desk, terminal, after }: { d: Detail; desk: DeskData; terminal: boolean; after: After }) {
  const p = d.proposal;
  const w = useWrite();
  const [office, setOffice] = useState("");
  const [scope, setScope] = useState("");
  const [role, setRole] = useState("");
  const [due, setDue] = useState("");
  const [conf, setConf] = useState(false);
  const [rec, setRec] = useState("");
  const [comment, setComment] = useState("");
  const [note, setNote] = useState("");
  const [noteConf, setNoteConf] = useState(false);
  const mine = d.reviewers.find((r) => r.mine && !r.withdrawn_at);
  const notes = d.messages.filter((m) => m.kind === "INTERNAL_NOTE");
  const mayNote = can(d, "REVIEW_PARTNERSHIP") || can(d, "SCREEN_PARTNERSHIP");
  const scopes = office === "dean" ? desk.faculties.map((f) => [f.code, f.name]) : office === "hod" ? desk.departments.map((x) => [x.code, x.name]) : [];

  return (
    <div className="stack">
      <Panel title="Reviewers">
        <div className="tablewrap" tabIndex={0}>
          <table className="tbl--data">
            <thead><tr><th>Office</th><th>Asked</th><th>Due</th><th>Recommendation</th><th>Comment</th><th></th></tr></thead>
            <tbody>
              {d.reviewers.length ? d.reviewers.map((r) => (
                <tr key={String(r.id)}>
                  <td>{s(r.office)}{r.scope_name ? <div className="sub2">{String(r.scope_name)}</div> : null}{r.person_name ? <div className="sub2">{String(r.person_name)}</div> : null}
                    {r.role_label ? <div className="sub2">{String(r.role_label)}</div> : null}{r.see_confidential ? <div className="sub2">May read the confidential disclosure</div> : null}</td>
                  <td className="sub2">{dateWords(r.assigned_at as string)}</td>
                  <td className="sub2">{r.due_on ? dateWords(r.due_on as string) : "—"}</td>
                  <td>{r.withdrawn_at ? <Pil kind="grey">Withdrawn</Pil> : r.recommendation ? <Pil kind={r.recommendation === "DO_NOT_SUPPORT" ? "bad" : r.recommendation === "SUPPORT" ? "ok" : "warn"}>{word(RECOMMENDATIONS, r.recommendation as string)}</Pil> : <Pil kind="info">Awaited</Pil>}
                    {r.completed_at ? <div className="sub2">{s(r.completed_by_name)}, {dateWords(r.completed_at as string)}</div> : null}</td>
                  <td className="ptn-text">{s(r.comment)}</td>
                  <td>{can(d, "ASSIGN_PARTNERSHIP") && !terminal && !r.withdrawn_at && !r.completed_at ? (
                    <Btn kind="ghost" busy={w.busy === `wd-${r.id}`} busyLabel="Withdrawing…" onClick={() => void w.run(`wd-${r.id}`, `/reviewers/${r.id}`, { method: "DELETE", reason: `Reviewer withdrawn: ${p.reference}` }, () => after("The reviewer is withdrawn"))}>Withdraw</Btn>
                  ) : null}</td>
                </tr>
              )) : <tr><td colSpan={6} className="sub2">No reviewer asked yet.</td></tr>}
            </tbody>
          </table>
        </div>
      </Panel>

      {can(d, "ASSIGN_PARTNERSHIP") && !terminal ? (
        <Panel title="Ask a reviewer">
          <PBody>
            <div className="grid grid--3">
              <Field id="rv-office" label="Office" required>
                <select id="rv-office" className="ctl" value={office} onChange={(e) => { setOffice(e.target.value); setScope(""); }}>
                  <option value="">Choose…</option>{desk.reviewerOffices.map((o) => <option key={o.code} value={o.code}>{o.label}</option>)}
                </select>
              </Field>
              {scopes.length ? (
                <Field id="rv-scope" label={office === "dean" ? "Faculty" : "Department"} required>
                  <select id="rv-scope" className="ctl" value={scope} onChange={(e) => setScope(e.target.value)}><option value="">Choose…</option>{scopes.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
                </Field>
              ) : null}
              <Field id="rv-role" label="What is asked" hint="Optional: academic fit, financial implications…"><input id="rv-role" className="ctl" maxLength={120} value={role} onChange={(e) => setRole(e.target.value)} /></Field>
              <Field id="rv-due" label="Due" hint={`Optional: ${String(desk.settings.review_days ?? 10)} working days when left empty`}><input id="rv-due" type="date" className="ctl" value={due} onChange={(e) => setDue(e.target.value)} /></Field>
            </div>
            {d.mayConfidential ? <label className="row row--tight mt-1"><input type="checkbox" checked={conf} onChange={(e) => setConf(e.target.checked)} /> The reviewer may read the confidential conflict-of-interest disclosure</label> : null}
            <div className="row mt-1"><Btn kind="primary" busy={w.busy === "add"} busyLabel="Asking…" disabled={!office || (scopes.length > 0 && !scope)}
              onClick={() => void w.run("add", `/${p.id}/reviewers`, { method: "POST", body: { office, scope: scope || undefined, role: role || undefined, due: due || undefined, confidential: conf },
                reason: `Reviewer asked: ${p.reference}` }, async () => { setOffice(""); setScope(""); setRole(""); setDue(""); setConf(false); await after("The reviewer is asked and told"); })}>Ask</Btn></div>
          </PBody>
        </Panel>
      ) : null}

      {mine && !terminal ? (
        <Panel title={mine.completed_at ? "Your office's review (you may revise it)" : "Your office's review"}>
          <PBody>
            <Note kind="info" title="A recommendation informs the decision; the Vice-Chancellor approves or declines." />
            <div className="grid grid--2 mt-1">
              <Field id="my-rec" label="Recommendation" required>
                <select id="my-rec" className="ctl" value={rec} onChange={(e) => setRec(e.target.value)}><option value="">Choose…</option>{RECOMMENDATIONS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
              </Field>
              <Field id="my-comment" label="Comment" required full hint="Conditions, concerns, what more is needed"><textarea id="my-comment" className="ctl" rows={4} maxLength={4000} value={comment} onChange={(e) => setComment(e.target.value)} /></Field>
            </div>
            <div className="row mt-1"><Btn kind="primary" busy={w.busy === "review"} busyLabel="Saving…" disabled={!rec || comment.trim().length < 5}
              onClick={() => void w.run("review", `/${p.id}/review`, { method: "POST", body: { recommendation: rec, comment }, reason: `Partnership review: ${p.reference}` },
                async () => { setRec(""); setComment(""); await after("Your review is recorded and the owner told"); })}>Submit review</Btn></div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Internal notes" right={<span className="sub2">Never shown to the applicant</span>}>
        <PBody>
          {notes.length ? <div className="stack">{notes.map((m) => (
            <div key={String(m.id)} className="ptn-msg internal">
              <div className="row" style={{ gap: 8, flexWrap: "wrap" }}><strong>{s(m.author_name)}</strong><span className="sub2">{dateWords(m.at as string, true)}</span>{m.confidential ? <Pil kind="warn">Confidential</Pil> : null}</div>
              <div className="ptn-text">{String(m.body)}</div>
            </div>
          ))}</div> : <p className="sub2">No notes yet.</p>}
          {mayNote && !terminal ? (
            <div className="mt-1">
              <Field id="nt-body" label="Add a note"><textarea id="nt-body" className="ctl" rows={3} maxLength={8000} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
              <div className="row mt-1" style={{ gap: 12, flexWrap: "wrap" }}>
                {d.mayConfidential ? <label className="row row--tight"><input type="checkbox" checked={noteConf} onChange={(e) => setNoteConf(e.target.checked)} /> Confidential (only those who may read the disclosure)</label> : null}
                <span className="grow" />
                <Btn kind="secondary" busy={w.busy === "note"} busyLabel="Saving…" disabled={!note.trim()} onClick={() => void w.run("note", `/${p.id}/notes`, { method: "POST",
                  body: { kind: "INTERNAL_NOTE", body: note, confidential: noteConf }, reason: `Internal note: ${p.reference}` }, async () => { setNote(""); setNoteConf(false); await after("The note is kept"); })}>Add note</Btn>
              </div>
            </div>
          ) : null}
        </PBody>
      </Panel>
      {w.problem ? <ProblemNotice problem={w.problem} /> : null}
    </div>
  );
}

/* ── the applicant: messages, replies and requests for information ── */

export function Messages({ d, terminal, after }: { d: Detail; terminal: boolean; after: After }) {
  const p = d.proposal;
  const w = useWrite();
  const [body, setBody] = useState("");
  const thread = d.messages.filter((m) => m.kind !== "INTERNAL_NOTE");
  return (
    <div className="stack">
      <Panel title="Information requests">
        <PBody>
          {d.requests.length ? <div className="stack">{d.requests.map((r) => (
            <div key={String(r.id)} className="ptn-msg">
              <div className="row" style={{ gap: 8, flexWrap: "wrap" }}>
                <strong>Asked {dateWords(r.requested_at as string)}</strong><span className="sub2">by {s(r.requested_by_name)} · deadline {dateWords(r.deadline as string)}</span>
                {r.answered_at ? <Pil kind="ok">Answered {dateWords(r.answered_at as string)}</Pil> : r.withdrawn_at ? <Pil kind="grey">Withdrawn</Pil> : <Pil kind="warn">Waiting</Pil>}
              </div>
              <div className="ptn-text">{String(r.question)}</div>
              {r.documents ? <div className="sub2">Documents asked for: {String(r.documents)}</div> : null}
              {r.reason ? <div className="sub2">Internal reason: {String(r.reason)}</div> : null}
              {r.answer ? <div className="ptn-text mt-1"><strong>Answer:</strong> {String(r.answer)}</div> : null}
            </div>
          ))}</div> : <p className="sub2">No information requested. Use Request information above to ask the applicant.</p>}
        </PBody>
      </Panel>
      <Panel title="Messages with the applicant" right={<span className="sub2">E-mailed to the applicant and shown on their status page</span>}>
        <PBody>
          {thread.length ? <div className="stack">{thread.map((m) => (
            <div key={String(m.id)} className="ptn-msg">
              <div className="row" style={{ gap: 8, flexWrap: "wrap" }}>
                <strong>{m.kind === "APPLICANT_REPLY" ? `${s(p.first_name)} ${p.last_name ?? ""} (applicant)` : `${s(m.author_name)} (University)`}</strong>
                <span className="sub2">{dateWords(m.at as string, true)}</span>
              </div>
              <div className="ptn-text">{String(m.body)}</div>
            </div>
          ))}</div> : <p className="sub2">No messages yet.</p>}
          {can(d, "REQUEST_INFORMATION") && !terminal ? (
            <div className="mt-1">
              <Field id="ms-body" label="Message to the applicant" hint="Courteous and specific; it is e-mailed. Internal matters belong in an internal note.">
                <textarea id="ms-body" className="ctl" rows={4} maxLength={8000} value={body} onChange={(e) => setBody(e.target.value)} />
              </Field>
              <div className="row mt-1"><span className="grow" /><Btn kind="primary" busy={w.busy === "msg"} busyLabel="Sending…" disabled={body.trim().length < 2}
                onClick={() => void w.run("msg", `/${p.id}/notes`, { method: "POST", body: { kind: "APPLICANT_MESSAGE", body }, reason: `Message to the applicant: ${p.reference}` },
                  async () => { setBody(""); await after("The message is sent to the applicant"); })}>Send message</Btn></div>
            </div>
          ) : null}
          {w.problem ? <ProblemNotice problem={w.problem} /> : null}
        </PBody>
      </Panel>
    </div>
  );
}

/* ── due diligence ── */

export function DueDiligence({ d, terminal, after }: { d: Detail; terminal: boolean; after: After }) {
  const p = d.proposal;
  const w = useWrite();
  const [edits, setEdits] = useState<Record<string, { status: string; note: string }>>({});
  const may = can(d, "DUE_DILIGENCE") && !terminal;
  if (!d.dueDiligence.length) {
    return <Note kind="info" title="Due diligence has not started">{d.actions.includes("START_DUE_DILIGENCE") ? "Start due diligence (above) opens the checklist and asks the University Legal Officer to review." : "The checklist opens when the proposal moves to due diligence."}</Note>;
  }
  const open = d.dueDiligence.filter((x) => x.status === "PENDING").length;
  const concerns = d.dueDiligence.filter((x) => x.status === "CONCERN").length;
  return (
    <Panel title="Due-diligence checklist" right={<span className="sub2">{open} pending · {concerns} concern{concerns === 1 ? "" : "s"}</span>}>
      <Note kind="info" title="Checks informed by the University's own review and the documents provided. The checklist records the review; it does not replace legal advice." />
      <div className="tablewrap" tabIndex={0}>
        <table className="tbl--data">
          <thead><tr><th>Check</th><th>Status</th><th>Note</th><th>Checked</th>{may ? <th></th> : null}</tr></thead>
          <tbody>{d.dueDiligence.map((x) => {
            const code = String(x.code);
            const e = edits[code] ?? { status: String(x.status), note: String(x.note ?? "") };
            const dirty = e.status !== String(x.status) || e.note !== String(x.note ?? "");
            return (
              <tr key={code}>
                <td>{String(x.label)}</td>
                <td>{may ? (
                  <select aria-label={`${x.label}: status`} className="ctl" value={e.status} onChange={(ev) => setEdits({ ...edits, [code]: { ...e, status: ev.target.value } })}>
                    {DD_STATUS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                  </select>
                ) : <Pil kind={x.status === "CONCERN" ? "bad" : x.status === "SATISFACTORY" ? "ok" : "grey"}>{word(DD_STATUS, x.status as string)}</Pil>}</td>
                <td>{may ? <input aria-label={`${x.label}: note`} className="ctl" maxLength={2000} value={e.note} onChange={(ev) => setEdits({ ...edits, [code]: { ...e, note: ev.target.value } })} />
                  : <span className="ptn-text">{s(x.note)}</span>}</td>
                <td className="sub2">{x.checked_at ? `${s(x.checked_by_name)}, ${dateWords(x.checked_at as string)}` : "—"}</td>
                {may ? <td><Btn kind="secondary" disabled={!dirty || (e.status === "CONCERN" && e.note.trim().length < 5)} busy={w.busy === code} busyLabel="Saving…"
                  onClick={() => void w.run(code, `/${p.id}/due-diligence/${code}`, { method: "PUT", body: { status: e.status, note: e.note }, reason: `Due diligence: ${x.label} — ${p.reference}` },
                    async () => { setEdits((o) => { const n = { ...o }; delete n[code]; return n; }); await after(`${x.label}: ${word(DD_STATUS, e.status).toLowerCase()}`); })}>Save</Btn></td> : null}
              </tr>
            );
          })}</tbody>
        </table>
      </div>
      {w.problem ? <PBody><ProblemNotice problem={w.problem} /></PBody> : null}
    </Panel>
  );
}

/* ── documents ── */

const maxMb = (desk: DeskData) => Number(desk.settings.max_file_mb ?? 5);

/** a document opened: fetched and saved under its own name (the portal's relay passes the file, not its name); the API keeps the look */
function DocLink({ proposal, a }: { proposal: string; a: Row }) {
  const [state, setState] = useState<"idle" | "busy" | "failed">("idle");
  async function open() {
    setState("busy");
    try {
      const r = await fetch(`${PTN}/${proposal}/attachments/${a.id}`, { cache: "no-store" });
      if (!r.ok) { setState("failed"); return; }
      downloadBlob(await r.blob(), String(a.filename));
      setState("idle");
    } catch { setState("failed"); }
  }
  return (
    <span>
      <button type="button" className="linklike" onClick={() => void open()} disabled={state === "busy"}>{String(a.filename)}</button>
      {state === "busy" ? <span className="sub2"> opening…</span> : state === "failed" ? <span className="sub2" style={{ color: "var(--red-ink)" }}> could not be opened</span> : null}
    </span>
  );
}

const STAFF_KINDS: [string, string][] = [...ATTACHMENT_KINDS.filter(([k]) => k !== "OTHER"), ["INTERNAL", "Internal document"], ["OTHER", "Other"]];

function Upload({ d, kinds, agreement, label, maxMb, after }: { d: Detail; kinds: [string, string][]; agreement?: string; label: string; maxMb: number; after: After }) {
  const p = d.proposal;
  const w = useWrite();
  const [kind, setKind] = useState(kinds[0]?.[0] ?? "OTHER");
  const ref = useRef<HTMLInputElement>(null);
  async function pick(f: File | undefined) {
    if (!f) return;
    const bad = fileProblem(f.name, f.size, maxMb);
    if (bad) { w.setProblem({ status: 422, title: bad }); if (ref.current) ref.current.value = ""; return; }
    await w.run("up", `/${p.id}/attachments`, { method: "POST", body: { kind, filename: f.name, dataUrl: await readDataUrl(f), agreement }, reason: `Partnership document: ${p.reference}` },
      () => after(`${f.name} is added`));
    if (ref.current) ref.current.value = "";
  }
  return (
    <div className="stack">
      <div className="row" style={{ gap: 8, flexWrap: "wrap", alignItems: "flex-end" }}>
        {kinds.length > 1 ? (
          <Field id={`up-kind-${agreement ?? "p"}`} label="Kind of document">
            <select id={`up-kind-${agreement ?? "p"}`} className="ctl" value={kind} onChange={(e) => setKind(e.target.value)}>{kinds.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
          </Field>
        ) : null}
        <Field id={`up-file-${agreement ?? "p"}`} label={label} hint={`PDF, DOCX, XLSX or PPTX of up to ${maxMb} MB; the content is checked on upload`}>
          <input ref={ref} id={`up-file-${agreement ?? "p"}`} type="file" className="ctl" accept=".pdf,.docx,.xlsx,.pptx" disabled={w.busy === "up"} onChange={(e) => void pick(e.target.files?.[0])} />
        </Field>
      </div>
      {w.busy === "up" ? <span className="sub2">Uploading…</span> : null}
      {w.problem ? <ProblemNotice problem={w.problem} /> : null}
    </div>
  );
}

export function Documents({ d, desk, after }: { d: Detail; desk: DeskData; after: After }) {
  const p = d.proposal;
  if (!can(d, "VIEW_ATTACHMENTS")) return <Note kind="info" title="Your office does not read this proposal's documents." />;
  const agr = (id: unknown) => d.agreements.find((a) => a.id === id)?.reference;
  return (
    <div className="stack">
      <Panel title="Documents" right={<span className="sub2">Each opening is kept on the timeline</span>}>
        <div className="tablewrap" tabIndex={0}>
          <table className="tbl--data">
            <thead><tr><th>File</th><th>Kind</th><th>Size</th><th>From</th><th>Added</th></tr></thead>
            <tbody>{d.attachments.length ? d.attachments.map((a) => (
              <tr key={String(a.id)}>
                <td><DocLink proposal={String(p.id)} a={a} /></td>
                <td className="sub2">{word([...STAFF_KINDS, ["REQUESTED_DOCUMENT", "Requested document"], ["AGREEMENT", "Agreement"]], a.kind as string)}{a.agreement_id ? ` (${agr(a.agreement_id) ?? "agreement"})` : ""}</td>
                <td className="sub2 tnum">{bytes(Number(a.size_bytes))}</td>
                <td className="sub2">{a.from_applicant ? "The applicant" : s(a.added_by_name)}</td>
                <td className="sub2">{dateWords(a.added_at as string, true)}</td>
              </tr>
            )) : <tr><td colSpan={5} className="sub2">No documents.</td></tr>}</tbody>
          </table>
        </div>
      </Panel>
      {can(d, "UPLOAD_DOCUMENTS") ? <Panel title="Add a document"><PBody><Upload d={d} kinds={STAFF_KINDS} label="File" maxMb={maxMb(desk)} after={after} /></PBody></Panel> : null}
    </div>
  );
}

/* ── agreements ── */

const AGR_ACTIONS: Record<string, { label: string; perm: string; note?: "required" | "optional"; dates?: "execute" | "update"; legal?: boolean }> = {
  SEND_TO_LEGAL: { label: "Send for legal review", perm: "MANAGE_AGREEMENT" },
  LEGAL_CLEAR: { label: "Clear (legal review)", perm: "MANAGE_AGREEMENT", note: "required", legal: true },
  LEGAL_RETURN: { label: "Return for changes", perm: "MANAGE_AGREEMENT", note: "required", legal: true },
  APPROVE: { label: "Approve the agreement", perm: "APPROVE_PARTNERSHIP" },
  EXECUTE: { label: "Record as executed", perm: "MANAGE_AGREEMENT", dates: "execute" },
  UPDATE_DATES: { label: "Update the dates", perm: "MANAGE_AGREEMENT", note: "required", dates: "update" },
  TERMINATE: { label: "Terminate", perm: "MANAGE_AGREEMENT", note: "required" },
  WITHDRAW: { label: "Withdraw", perm: "MANAGE_AGREEMENT", note: "required" },
};
const AGR_NEXT: Record<string, string[]> = {
  DRAFT: ["SEND_TO_LEGAL", "WITHDRAW"], LEGAL_REVIEW: ["LEGAL_CLEAR", "LEGAL_RETURN", "WITHDRAW"], APPROVAL: ["APPROVE", "WITHDRAW"],
  SIGNING: ["EXECUTE", "WITHDRAW"], EXECUTED: ["UPDATE_DATES", "TERMINATE"], EXPIRED: ["UPDATE_DATES"],
};

export function Agreements({ d, desk, after }: { d: Detail; desk: DeskData; after: After }) {
  const p = d.proposal;
  const w = useWrite();
  const [type, setType] = useState("");
  const [other, setOther] = useState("");
  const [title, setTitle] = useState("");
  const [parties, setParties] = useState(`${SCHOOL}; ${s(p.org_name)}`);
  const [acting, setActing] = useState<{ a: Row; action: string } | null>(null);
  const mayCreate = can(d, "MANAGE_AGREEMENT") && ["APPROVED_FOR_DEVELOPMENT", "AGREEMENT_REVIEW", "AGREEMENT_EXECUTED", "IMPLEMENTATION", "ACTIVE"].includes(String(p.status));
  const actionsOf = (a: Row) => (AGR_NEXT[String(a.status)] ?? []).filter((x) => can(d, AGR_ACTIONS[x].perm) && (!AGR_ACTIONS[x].legal || ["legal", "super"].includes(desk.office)));
  return (
    <div className="stack">
      {d.agreements.length ? d.agreements.map((a) => {
        const signed = d.attachments.filter((x) => x.agreement_id === a.id);
        return (
          <Panel key={String(a.id)} title={<span><span className="tnum">{String(a.reference)}</span> · {String(a.title)}</span>}
            right={<Pil kind={a.status === "EXECUTED" ? "ok" : ["TERMINATED", "WITHDRAWN", "EXPIRED"].includes(String(a.status)) ? "grey" : "warn"}>{AGREEMENT_STATUS[String(a.status)] ?? String(a.status)}</Pil>}>
            <PBody>
              {a.expiring ? <Note kind="bad" title={`Expires ${dateWords(a.expires_on as string)}`}>Plan the renewal or the close; the agreement is never renewed by itself.</Note> : null}
              <div className="ptn-meta">
                <div><span>Type</span><span>{a.agreement_type === "OTHER" ? s(a.type_other) : word(AGREEMENT_KINDS, a.agreement_type as string)}</span></div>
                <div><span>Parties</span><span className="ptn-text">{s(a.parties)}</span></div>
                <div><span>Legal review</span><span>{a.legal_at ? `${s(a.legal_by_name)}, ${dateWords(a.legal_at as string)}` : "—"}</span></div>
                <div><span>Approved</span><span>{a.approved_at ? `${s(a.approved_by_name)} (${s(a.approved_office)}), ${dateWords(a.approved_at as string)}` : "—"}</span></div>
                <div><span>Signed</span><span>{a.signed_on ? dateWords(a.signed_on as string) : "—"}</span></div>
                <div><span>Effective</span><span>{a.effective_on ? dateWords(a.effective_on as string) : "—"}</span></div>
                <div><span>Expires</span><span>{a.expires_on ? dateWords(a.expires_on as string) : "—"}</span></div>
                <div><span>Renewal review</span><span>{a.renewal_on ? dateWords(a.renewal_on as string) : "—"}</span></div>
              </div>
              {a.legal_note ? <p className="ptn-text mt-1"><strong>Legal note:</strong> {String(a.legal_note)}</p> : null}
              {a.ended_note ? <p className="ptn-text mt-1"><strong>Ended:</strong> {String(a.ended_note)}</p> : null}
              {signed.length ? <p className="mt-1">Signed copy: {signed.map((x, i) => <span key={String(x.id)}>{i ? ", " : ""}<DocLink proposal={String(p.id)} a={x} /></span>)}</p> : null}
              {a.status === "SIGNING" && can(d, "UPLOAD_DOCUMENTS") ? <div className="mt-1"><Upload d={d} kinds={[["AGREEMENT", "Signed agreement"]]} agreement={String(a.id)} label="Signed copy" maxMb={maxMb(desk)} after={after} /></div> : null}
              {actionsOf(a).length ? (
                <div className="row mt-1" style={{ gap: 8, flexWrap: "wrap" }}>
                  {actionsOf(a).map((x) => <Btn key={x} kind={x === "APPROVE" || x === "EXECUTE" || x === "LEGAL_CLEAR" ? "go" : x === "TERMINATE" || x === "WITHDRAW" ? "ghost" : "secondary"}
                    onClick={() => setActing({ a, action: x })}>{AGR_ACTIONS[x].label}</Btn>)}
                </div>
              ) : null}
            </PBody>
          </Panel>
        );
      }) : <Note kind="info" title="No agreement yet">{mayCreate ? "Prepare one below: it goes to the University Legal Officer, then for approval, then signing." : "An agreement is prepared once the Vice-Chancellor has approved the partnership for development."}</Note>}

      {mayCreate ? (
        <Panel title="Prepare an agreement">
          <PBody>
            <div className="grid grid--2">
              <Field id="ag-type" label="Type of agreement" required>
                <select id="ag-type" className="ctl" value={type} onChange={(e) => setType(e.target.value)}><option value="">Choose…</option>{AGREEMENT_KINDS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
              </Field>
              {type === "OTHER" ? <Field id="ag-other" label="Kind of agreement" required><input id="ag-other" className="ctl" maxLength={120} value={other} onChange={(e) => setOther(e.target.value)} /></Field> : null}
              <Field id="ag-title" label="Title" required full><input id="ag-title" className="ctl" maxLength={300} value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
              <Field id="ag-parties" label="Parties" required full><textarea id="ag-parties" className="ctl" rows={2} maxLength={1000} value={parties} onChange={(e) => setParties(e.target.value)} /></Field>
            </div>
            <div className="row mt-1"><Btn kind="primary" busy={w.busy === "agr"} busyLabel="Preparing…" disabled={!type || !title.trim() || !parties.trim() || (type === "OTHER" && other.trim().length < 3)}
              onClick={() => void w.run("agr", `/${p.id}/agreements`, { method: "POST", body: { type, typeOther: other || undefined, title, parties }, reason: `Agreement prepared: ${p.reference}` },
                async () => { setType(""); setOther(""); setTitle(""); await after("The agreement is prepared and the Legal Officer told"); })}>Prepare agreement</Btn></div>
            {w.problem ? <ProblemNotice problem={w.problem} /> : null}
          </PBody>
        </Panel>
      ) : null}
      {acting ? <AgreementModal a={acting.a} action={acting.action} onClose={() => setActing(null)} onDone={async (m) => { setActing(null); await after(m); }} /> : null}
    </div>
  );
}

function AgreementModal({ a, action, onClose, onDone }: { a: Row; action: string; onClose: () => void; onDone: After }) {
  const spec = AGR_ACTIONS[action];
  const [note, setNote] = useState("");
  const [signedOn, setSignedOn] = useState(String(a.signed_on ?? ""));
  const [effectiveOn, setEffectiveOn] = useState(String(a.effective_on ?? ""));
  const [expiresOn, setExpiresOn] = useState(String(a.expires_on ?? ""));
  const [renewalOn, setRenewalOn] = useState(String(a.renewal_on ?? ""));
  const w = useWrite();
  const ready = (spec.note !== "required" || note.trim().length >= 5) && (spec.dates !== "execute" || (!!signedOn && !!effectiveOn));
  return (
    <Modal title={spec.label} sub={`${a.reference} · ${a.title}`} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" /><Btn kind="primary" busy={w.busy === "x"} busyLabel="Saving…" disabled={!ready}
        onClick={() => void w.run<{ status: string }>("x", `/agreements/${a.id}/act`, { method: "POST", body: { action, data: { note: note || undefined, signedOn: signedOn || undefined,
          effectiveOn: effectiveOn || undefined, expiresOn: expiresOn || undefined, renewalOn: renewalOn || undefined } }, reason: `${spec.label}: ${a.reference}` },
          (r) => onDone(`${spec.label}: ${(AGREEMENT_STATUS[r.status] ?? r.status).toLowerCase()}`))}>{spec.label}</Btn></>}>
      <div className="stack">
        {action === "EXECUTE" ? <Note kind="info" title="The signed copy is attached first; the applicant is told the agreement is executed." /> : null}
        {spec.dates ? (
          <div className="grid grid--2">
            {spec.dates === "execute" ? <>
              <Field id="am-signed" label="Date signed" required><input id="am-signed" type="date" className="ctl" value={signedOn} onChange={(e) => setSignedOn(e.target.value)} /></Field>
              <Field id="am-effective" label="Takes effect" required><input id="am-effective" type="date" className="ctl" value={effectiveOn} onChange={(e) => setEffectiveOn(e.target.value)} /></Field>
            </> : null}
            <Field id="am-expires" label="Expires" hint="Optional: alerts begin before it"><input id="am-expires" type="date" className="ctl" value={expiresOn} onChange={(e) => setExpiresOn(e.target.value)} /></Field>
            <Field id="am-renewal" label="Renewal review" hint="Optional"><input id="am-renewal" type="date" className="ctl" value={renewalOn} onChange={(e) => setRenewalOn(e.target.value)} /></Field>
          </div>
        ) : null}
        {spec.note ? (
          <Field id="am-note" label={spec.legal ? "Legal review note" : "Reason"} required={spec.note === "required"} hint="5 characters at least; kept on the timeline">
            <textarea id="am-note" className="ctl" rows={3} maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
        ) : <p className="sub2">This is kept on the timeline.</p>}
        {w.problem ? <ProblemNotice problem={w.problem} /> : null}
      </div>
    </Modal>
  );
}

/* ── the partnership under way: activities, deliverables, reports, outcomes ── */

const ACT_KINDS: [string, string][] = [["ACTIVITY", "Activity"], ["DELIVERABLE", "Deliverable"], ["REPORT", "Report"]];
const ACT_STATUS: [string, string][] = [["PLANNED", "Planned"], ["IN_PROGRESS", "In progress"], ["DONE", "Done"], ["CANCELLED", "Cancelled"]];

export function Progress({ d, desk, after }: { d: Detail; desk: DeskData; after: After }) {
  const p = d.proposal;
  const st = String(p.status);
  const w = useWrite();
  const mayAct = can(d, "SCREEN_PARTNERSHIP") && ["APPROVED_FOR_DEVELOPMENT", "AGREEMENT_REVIEW", "AGREEMENT_EXECUTED", "IMPLEMENTATION", "ACTIVE"].includes(st);
  const mayOut = can(d, "SCREEN_PARTNERSHIP") && ["AGREEMENT_EXECUTED", "IMPLEMENTATION", "ACTIVE", "CLOSED"].includes(st);
  const [act, setAct] = useState({ kind: "ACTIVITY", title: "", lead: "", due: "", status: "PLANNED", note: "" });
  const [out, setOut] = useState({ kind: "", description: "", occurredOn: "", quantity: "", amount: "", currency: "" });

  return (
    <div className="stack">
      <Panel title="Activities, deliverables and reports">
        <div className="tablewrap" tabIndex={0}>
          <table className="tbl--data">
            <thead><tr><th>Kind</th><th>Title</th><th>Lead</th><th>Due</th><th>Status</th><th>Note</th></tr></thead>
            <tbody>{d.activities.length ? d.activities.map((x) => (
              <tr key={String(x.id)}>
                <td className="sub2">{word(ACT_KINDS, x.kind as string)}</td><td>{String(x.title)}</td><td className="sub2">{s(x.lead)}</td>
                <td className="sub2">{x.due_on ? dateWords(x.due_on as string) : "—"}</td>
                <td>{mayAct ? (
                  <select aria-label={`${x.title}: status`} className="ctl" value={String(x.status)} disabled={w.busy === String(x.id)} onChange={(e) => void w.run(String(x.id), `/${p.id}/activities/${x.id}`, { method: "PUT",
                    body: { kind: x.kind, title: x.title, lead: x.lead ?? undefined, due: x.due_on ?? undefined, status: e.target.value, note: x.note ?? undefined }, reason: `Activity updated: ${p.reference}` },
                    () => after(`${x.title}: ${word(ACT_STATUS, e.target.value).toLowerCase()}`))}>
                    {ACT_STATUS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                  </select>
                ) : word(ACT_STATUS, x.status as string)}{x.done_on ? <div className="sub2">{dateWords(x.done_on as string)}</div> : null}</td>
                <td className="ptn-text sub2">{s(x.note)}</td>
              </tr>
            )) : <tr><td colSpan={6} className="sub2">None recorded.</td></tr>}</tbody>
          </table>
        </div>
        {mayAct ? (
          <PBody>
            <div className="grid grid--3">
              <Field id="ac-kind" label="Kind"><select id="ac-kind" className="ctl" value={act.kind} onChange={(e) => setAct({ ...act, kind: e.target.value })}>{ACT_KINDS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
              <Field id="ac-title" label="Title" required><input id="ac-title" className="ctl" maxLength={300} value={act.title} onChange={(e) => setAct({ ...act, title: e.target.value })} /></Field>
              <Field id="ac-lead" label="Lead"><input id="ac-lead" className="ctl" maxLength={200} value={act.lead} onChange={(e) => setAct({ ...act, lead: e.target.value })} /></Field>
              <Field id="ac-due" label="Due"><input id="ac-due" type="date" className="ctl" value={act.due} onChange={(e) => setAct({ ...act, due: e.target.value })} /></Field>
              <Field id="ac-status" label="Status"><select id="ac-status" className="ctl" value={act.status} onChange={(e) => setAct({ ...act, status: e.target.value })}>{ACT_STATUS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
              <Field id="ac-note" label="Note"><input id="ac-note" className="ctl" maxLength={2000} value={act.note} onChange={(e) => setAct({ ...act, note: e.target.value })} /></Field>
            </div>
            <div className="row mt-1"><Btn kind="secondary" busy={w.busy === "act"} busyLabel="Adding…" disabled={!act.title.trim()} onClick={() => void w.run("act", `/${p.id}/activities`, { method: "POST",
              body: { ...act, lead: act.lead || undefined, due: act.due || undefined, note: act.note || undefined }, reason: `Activity added: ${p.reference}` },
              async () => { setAct({ kind: "ACTIVITY", title: "", lead: "", due: "", status: "PLANNED", note: "" }); await after("The activity is added"); })}>Add</Btn></div>
          </PBody>
        ) : null}
      </Panel>

      <Panel title="Outcomes">
        <div className="tablewrap" tabIndex={0}>
          <table className="tbl--data">
            <thead><tr><th>Outcome</th><th>Description</th><th>When</th><th className="num">Quantity</th><th className="num">Amount</th><th>Recorded</th></tr></thead>
            <tbody>{d.outcomes.length ? d.outcomes.map((o) => (
              <tr key={String(o.id)}>
                <td>{String(o.kind_label)}</td><td className="ptn-text">{String(o.description)}</td><td className="sub2">{o.occurred_on ? dateWords(o.occurred_on as string) : "—"}</td>
                <td className="num tnum">{o.quantity == null ? "—" : String(o.quantity)}</td><td className="num tnum">{o.amount == null ? "—" : money(o.amount, o.currency as string)}</td>
                <td className="sub2">{s(o.recorded_by_name)}, {dateWords(o.recorded_at as string)}</td>
              </tr>
            )) : <tr><td colSpan={6} className="sub2">None recorded.</td></tr>}</tbody>
          </table>
        </div>
        {mayOut ? (
          <PBody>
            <div className="grid grid--3">
              <Field id="oc-kind" label="Outcome" required><select id="oc-kind" className="ctl" value={out.kind} onChange={(e) => setOut({ ...out, kind: e.target.value })}><option value="">Choose…</option>{desk.outcomeKinds.map((k) => <option key={k.code} value={k.code}>{k.label}</option>)}</select></Field>
              <Field id="oc-desc" label="Description" required><input id="oc-desc" className="ctl" maxLength={2000} value={out.description} onChange={(e) => setOut({ ...out, description: e.target.value })} /></Field>
              <Field id="oc-on" label="When"><input id="oc-on" type="date" className="ctl" value={out.occurredOn} onChange={(e) => setOut({ ...out, occurredOn: e.target.value })} /></Field>
              <Field id="oc-q" label="Quantity" hint="Students exchanged, papers…"><input id="oc-q" inputMode="numeric" className="ctl" value={out.quantity} onChange={(e) => setOut({ ...out, quantity: e.target.value.replace(/\D/g, "") })} /></Field>
              <Field id="oc-amt" label="Amount" hint="Funding secured"><input id="oc-amt" inputMode="decimal" className="ctl" value={out.amount} onChange={(e) => setOut({ ...out, amount: e.target.value.replace(/[^\d.]/g, "") })} /></Field>
              <Field id="oc-cur" label="Currency"><select id="oc-cur" className="ctl" value={out.currency} onChange={(e) => setOut({ ...out, currency: e.target.value })}><option value="">None</option>{CURRENCIES.map((c) => <option key={c} value={c}>{c}</option>)}</select></Field>
            </div>
            <div className="row mt-1"><Btn kind="secondary" busy={w.busy === "out"} busyLabel="Recording…" disabled={!out.kind || !out.description.trim() || (!!out.amount && !out.currency)}
              onClick={() => void w.run("out", `/${p.id}/outcomes`, { method: "POST", body: { kind: out.kind, description: out.description, occurredOn: out.occurredOn || undefined,
                quantity: out.quantity ? Number(out.quantity) : undefined, amount: out.amount ? Number(out.amount) : undefined, currency: out.currency || undefined }, reason: `Outcome recorded: ${p.reference}` },
                async () => { setOut({ kind: "", description: "", occurredOn: "", quantity: "", amount: "", currency: "" }); await after("The outcome is recorded"); })}>Record outcome</Btn></div>
          </PBody>
        ) : null}
      </Panel>
      {w.problem ? <ProblemNotice problem={w.problem} /> : null}
    </div>
  );
}
