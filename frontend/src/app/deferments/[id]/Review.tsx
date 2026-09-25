"use client";

/** One request reviewed (V259): who the student is and how their record stands — registration, fees, standing,
 *  previous deferments — the request and its documents, each earlier desk's word, and the act this desk may
 *  take at this stage: recommend, approve, return for correction with instructions, reject with the reason,
 *  cancel, or confirm the return. Every act goes on the trail. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ACTION_WORD, DOC_KIND, SEM, StatePil, ReturnPil, dayOf, periodOf, returnOf, whenAt, type DefermentFull } from "@/lib/deferments";

const ACTS: Record<string, [string, string, "primary" | "go" | "urgent" | "ghost" | "secondary", boolean]> = {
  recommend: ["RECOMMEND", "Recommend to the Faculty", "primary", false],
  facRecommend: ["FAC_RECOMMEND", "Recommend to the Registry", "primary", false],
  approve: ["APPROVE", "Approve Deferment", "go", false],
  correction: ["CORRECTION", "Request Correction", "secondary", true],
  reject: ["REJECT", "Reject", "urgent", true],
  cancel: ["CANCEL", "Cancel Request", "ghost", true],
};
const naira = (n: number | undefined) => (n == null ? "—" : "₦" + Number(n).toLocaleString("en-NG", { maximumFractionDigits: 0 }));

export function Review({ d }: { d: DefermentFull }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [ask, setAsk] = useState<string | null>(null);
  const [note, setNote] = useState("");
  const may = d.may ?? {};

  async function act(path: string, body: unknown, label: string) {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/deferments/${d.id}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(label) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return false; }
      notify(label); setAsk(null); setNote(""); router.refresh(); return true;
    } finally { setBusy(false); }
  }
  const doAct = (key: string) => {
    const [action, label, , needsNote] = ACTS[key];
    if (needsNote && !note.trim()) { const pr: Problem = { status: 422, title: key === "reject" ? "A rejection carries its reason." : key === "correction" ? "Say what the student must correct." : "A cancellation carries its reason." }; setProblem(pr); notifyProblem(pr); return; }
    void act("/action", { action, note: note.trim() || null }, `${label}: ${d.reference}`);
  };

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href="/deferments">Deferments</Link><span>›</span><strong>{d.reference}</strong></div>
      <PageHead title={`${d.surname}, ${d.other_names}`} description={`${d.number} · ${d.programme} · ${d.department} · ${d.faculty} · ${d.level} Level. Request ${d.reference} to defer ${periodOf(d)}.`}
        actions={<>
          <StatePil state={d.state} />{["ACTIVE", "APPROVED"].includes(d.state) ? <ReturnPil status={d.return_status} /> : null}
          {["APPROVED", "ACTIVE", "COMPLETED"].includes(d.state) ? <a className="btn btn--primary btn--sm" href={`/deferments/${d.id}/letter`} target="_blank" rel="noopener">Approval Letter</a> : null}
          <LinkBtn href={`/students/${d.student_id}`}>Student Record</LinkBtn>
        </>} />
      {problem ? <ProblemNotice problem={problem} /> : null}

      {Object.values(may).some(Boolean) ? (
        <Panel title="This desk's act" right={d.state.toLowerCase().replace(/_/g, " ")}>
          <PBody>
            <Field id="rv-note" label="Comment" hint="Required for a rejection, a correction or a cancellation; optional for a recommendation or approval."><textarea id="rv-note" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
            <div className="row mt-2">
              {Object.entries(ACTS).filter(([k]) => may[k]).map(([k, [, label, kind]]) => <Btn key={k} kind={kind} disabled={busy} onClick={() => (k === "approve" || k === "reject" ? setAsk(k) : doAct(k))}>{label}</Btn>)}
              {may.confirmReturn ? <Btn kind="go" disabled={busy} onClick={() => setAsk("return")}>Confirm Return</Btn> : null}
            </div>
          </PBody>
        </Panel>
      ) : null}

      <div className="grid grid--2">
        <Panel title="The request" right={d.kind === "SESSION" ? "Academic session" : "Semester"}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[["Deferment number", <span key="r" className="tnum b600">{d.reference}</span>], ["Type", d.kind === "SESSION" ? "Academic session" : "Semester"], ["Session", d.session], ["Semester", d.kind === "SESSION" ? "Whole session" : SEM(d.semester)],
              ["Reason", d.reason], ["Effective from", dayOf(d.period_from)], ["Expected return", returnOf(d)], ["Return date", dayOf(d.return_on)], ["Submitted", whenAt(d.submitted_at)], ["Declaration", d.declared ? "Confirmed by the student" : "Not confirmed"]]} />
            {d.explanation ? <div className="mt-3" style={{ whiteSpace: "pre-wrap" }}>{d.explanation}</div> : null}
            {d.extension_of ? <div className="mt-2"><Pil kind="info">An extension of an earlier deferment</Pil></div> : null}
          </PBody>
        </Panel>
        <Panel title="Supporting documents" right={`${d.documents.length}${d.needs_document ? " · required for this reason" : ""}`}>
          {d.documents.length ? (
            <ul className="plain">{d.documents.map((x) => <li key={x.id} className="row row--between" style={{ padding: "8px var(--s-4)", borderBottom: "1px solid var(--line)" }}><span><a className="lnk b600" href={`/api/bff/api/v1/deferments/${d.id}/documents/${x.id}/content`} target="_blank" rel="noopener">{DOC_KIND[x.kind] ?? x.kind}</a><div className="sub2">{x.filename} · {(x.size_bytes / 1024).toFixed(0)} KB · {dayOf(x.uploaded_at)}</div></span></li>)}</ul>
          ) : <PBody><div className="sub2">{d.needs_document ? "None uploaded; the reason requires one — return the request for correction." : "None uploaded."}</div></PBody>}
        </Panel>
      </div>

      <div className="grid grid--2">
        <Panel title="The student's record" right={d.student_status.charAt(0) + d.student_status.slice(1).toLowerCase().replace(/_/g, " ")}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[["Status", d.student_status], ["Standing", d.standing?.standing ? `${d.standing.standing}${d.standing.cgpa != null ? ` · CGPA ${Number(d.standing.cgpa).toFixed(2)}` : ""}` : "—"],
              ["Fees this session", d.fees ? `${d.fees.status.replace(/_/g, " ").toLowerCase()} · paid ${naira(d.fees.paid)} of ${naira(d.fees.payable)}` : "—"], ["Outstanding", d.fees ? naira(d.fees.outstanding) : "—"]]} />
            <div className="eyebrow mt-3 mb-1">Recent registrations</div>
            {d.registration?.length ? <ul className="plain">{d.registration.map((r, i) => <li key={i} className="sub2 tnum">{r.session} · {SEM(r.semester)} · {r.status.toLowerCase()}{r.submitted_at ? ` · ${dayOf(r.submitted_at)}` : ""}</li>)}</ul> : <div className="sub2">No course registration on record.</div>}
            <div className="eyebrow mt-3 mb-1">Previous deferments</div>
            {d.previous?.length ? <ul className="plain">{d.previous.map((p, i) => <li key={i} className="sub2"><span className="tnum">{p.reference}</span> · {p.kind === "SESSION" ? p.session : `${p.session} ${SEM(p.semester)}`} · {p.state.toLowerCase().replace(/_/g, " ")}</li>)}</ul> : <div className="sub2">None.</div>}
          </PBody>
        </Panel>
        <Panel title="The desks" right="Each word on the record">
          <PBody>
            <KvGrid cls="grid--1" pairs={[
              ["Department", d.dept_at ? <span key="d"><b>Recommended</b> {dayOf(d.dept_at)}{d.dept_officer ? ` by ${d.dept_officer}` : ""}{d.dept_note ? <div className="sub2">{d.dept_note}</div> : null}</span> : <span key="d" className="sub2">Awaiting</span>],
              ["Faculty", d.fac_at ? <span key="f"><b>Recommended</b> {dayOf(d.fac_at)}{d.faculty_officer ? ` by ${d.faculty_officer}` : ""}{d.fac_note ? <div className="sub2">{d.fac_note}</div> : null}</span> : <span key="f" className="sub2">Awaiting</span>],
              ["Registry", d.decided_at ? <span key="r"><b>{d.state === "REJECTED" ? "Rejected" : "Approved"}</b> {dayOf(d.decided_at)}{d.decided_officer ? ` by ${d.decided_officer}` : ""}{d.decision_note ? <div className="sub2">{d.decision_note}</div> : null}</span> : <span key="r" className="sub2">Awaiting</span>],
              ["Return", d.returned_at ? <span key="rt"><b>Confirmed</b> {dayOf(d.returned_at)}{d.returned_officer ? ` by ${d.returned_officer}` : ""}{d.return_note ? <div className="sub2">{d.return_note}</div> : null}</span> : <span key="rt" className="sub2">{returnOf(d)}</span>],
            ]} />
            {d.correction_note ? <Note kind="bad" title="Returned for correction">{d.correction_note}</Note> : null}
            {d.cancel_note ? <Note kind="info" title="Cancelled">{d.cancel_note}</Note> : null}
          </PBody>
        </Panel>
      </div>

      <Panel title="History" right="Every act on this request">
        <PBody>
          <ol className="plain" style={{ display: "grid", gap: 6 }}>{d.history.map((h, i) => <li key={i} className="row row--base" style={{ gap: "var(--s-3)", flexWrap: "wrap" }}><span className="tnum sub2" style={{ minWidth: 150 }}>{whenAt(h.at)}</span><span className="b600">{ACTION_WORD[h.action] ?? h.action}</span>{h.note ? <span className="sub2">{h.note}</span> : null}<span className="sub2">{[h.actor, h.actor_office].filter(Boolean).join(" · ")}</span></li>)}</ol>
        </PBody>
      </Panel>

      {ask ? (
        <Modal title={ask === "return" ? `Confirm the return of ${d.surname}, ${d.other_names}` : ask === "approve" ? `Approve ${d.reference}` : `Reject ${d.reference}`} sub={periodOf(d)} onClose={() => setAsk(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Back</Btn>
            {ask === "return" ? <Btn kind="go" disabled={busy} onClick={() => void act("/return", { note: note.trim() || null }, `Return confirmed: ${d.reference}`)}>Confirm Return</Btn>
              : <Btn kind={ask === "approve" ? "go" : "urgent"} disabled={busy} onClick={() => doAct(ask)}>{ask === "approve" ? "Approve" : "Reject"}</Btn>}</>}>
          {ask === "return" ? <p>The student&rsquo;s status is restored and normal academic activity resumes for {returnOf(d)}. Add a note if you wish.</p>
            : ask === "approve" ? <p>The deferred period will be held on every register; the student cannot register for it and their status reads Deferred while it runs. The approval letter is issued at once.</p>
            : <p>The student is told the reason you have written above. This cannot be undone.</p>}
          {note.trim() ? <div className="sub2 mt-2">Comment: {note.trim()}</div> : null}
        </Modal>
      ) : null}
    </>
  );
}
