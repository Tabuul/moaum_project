"use client";

/** One application reviewed (V259, revised by V264): who the student is and how their record stands; the application
 *  fee; the financial verification the Bursary reads from the finance record (the last school-fee payment, the balance —
 *  never typed); the request and its documents, opened in a modal on this page; each desk's word and the approval
 *  timeline; the academic effect once approved; and the act this desk may take at this stage — the Bursary's approval,
 *  the department's, the faculty's, the Academic Office's forwarding, the DVC's final decision with a comment
 *  — or a return for correction, a rejection with the reason, a cancellation, a return
 *  confirmed. Every act and every reading goes on the trail. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ACTION_WORD, ApprovalTimeline, COURSE_STATE, DOC_KIND, FeePil, OFFICE_OF, SEM, StatePil, ReturnPil, dayOf, effectPairs, naira, periodOf, returnOf, whenAt, type DefermentFull } from "@/lib/deferments";
import { DocViewer } from "@/lib/deferment-viewer";

const ACTS: Record<string, [string, string, "primary" | "go" | "urgent" | "ghost" | "secondary", boolean]> = {
  bursaryApprove: ["BURSARY_APPROVE", "Approve (financial verification done)", "go", false],
  recommend: ["RECOMMEND", "Approve and send to the Faculty", "go", false],
  facRecommend: ["FAC_RECOMMEND", "Approve and send to the Academic Office", "go", false],
  dvcApprove: ["DVC_APPROVE", "Approve with comment (final approval)", "go", true],
  correction: ["CORRECTION", "Return for Correction", "secondary", true],
  reject: ["REJECT", "Reject", "urgent", true],
  cancel: ["CANCEL", "Cancel Application", "ghost", true],
};

export function Review({ d }: { d: DefermentFull }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [ask, setAsk] = useState<string | null>(null);
  const [note, setNote] = useState("");
  const [viewing, setViewing] = useState<{ url: string; title: string; image: boolean } | null>(null);
  const may = d.may ?? {};
  const fin = d.financials;
  const tl = d.timeline;

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
    if (needsNote && !note.trim()) { const pr: Problem = { status: 422, title: key === "reject" ? "A rejection carries its reason." : key === "correction" ? "Say what the student must correct." : key === "dvcApprove" ? "The DVC's decision carries a comment." : "A cancellation carries its reason." }; setProblem(pr); notifyProblem(pr); return; }
    void act("/action", { action, note: note.trim() || null }, `${label}: ${d.reference}`);
  };
  const confirmKeys = new Set(["bursaryApprove", "recommend", "facRecommend", "dvcApprove", "reject"]);
  const askTitle: Record<string, string> = { bursaryApprove: "Bursary approval", recommend: "Head of Department's approval", facRecommend: "Faculty approval", dvcApprove: "Deputy Vice-Chancellor's final approval", reject: "Rejection", return: "Confirm the return" };

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href="/deferments">Deferments</Link><span>›</span><strong>{d.reference}</strong></div>
      <PageHead title={`${d.surname}, ${d.other_names}`} description={`${d.number} · ${d.programme} · ${d.department} · ${d.faculty} · ${d.level} Level. Application ${d.reference} to defer ${periodOf(d)}.`}
        actions={<>
          <StatePil state={d.state} />{["ACTIVE", "APPROVED"].includes(d.state) ? <ReturnPil status={d.return_status} /> : null}
          {may.download ? <a className="btn btn--secondary btn--sm" href={`/deferments/${d.id}/application`} target="_blank" rel="noopener">Download Application</a> : <span className="sub2">Downloadable once the faculty approves</span>}
          {["APPROVED", "ACTIVE", "COMPLETED"].includes(d.state) ? <a className="btn btn--primary btn--sm" href={`/deferments/${d.id}/letter`} target="_blank" rel="noopener">Approval Letter</a> : null}
          <LinkBtn href={`/students/${d.student_id}`}>Student Record</LinkBtn>
        </>} />
      {problem ? <ProblemNotice problem={problem} /> : null}

      {Object.entries(may).some(([k, v]) => v && k !== "download") ? (
        <Panel title="This desk's act" right={<span>{OFFICE_OF[d.state] ? `Waiting: ${OFFICE_OF[d.state]}` : d.stage_label}</span>}>
          <PBody>
            {may.bursaryApprove ? <Note kind="info" title="Financial verification">The last school-fee payment and the outstanding balance below are read from the finance record and recorded with your approval; nothing is typed. {fin && !fin.found ? <b>No qualifying school-fee payment found.</b> : null}</Note> : null}
            {may.dvcApprove ? <Note kind="info" title="Final approval">Your approval is the final approval and carries your comment. It applies the academic effect at once: the period is marked deferred, the courses of the period are set aside as DEFERRED (never failed), the CGPA is untouched, the completion timeline moves by the period deferred, the approval letter is issued and the student is told. The comment is required.</Note> : null}
            <Field id="rv-note" label={may.dvcApprove ? "DVC comment" : "Comment"} hint={may.dvcApprove ? "Required for the DVC's decision." : "Required for a rejection, a correction or a cancellation; optional for an approval."}><textarea id="rv-note" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
            <div className="row mt-2">
              {Object.entries(ACTS).filter(([k]) => may[k]).map(([k, [, label, kind]]) => <Btn key={k} kind={kind} disabled={busy} onClick={() => (confirmKeys.has(k) ? setAsk(k) : doAct(k))}>{label}</Btn>)}
              {may.forward ? <LinkBtn kind="primary" href="/deferments?state=FAC_RECOMMENDED">Forward to DVC (from the desk)</LinkBtn> : null}
              {may.confirmReturn ? <Btn kind="go" disabled={busy} onClick={() => setAsk("return")}>Confirm Return / Resumption</Btn> : null}
            </div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Approval timeline" right={<StatePil state={d.state} />}><PBody><ApprovalTimeline d={d} /></PBody></Panel>

      <div className="grid grid--2">
        <Panel title="Deferment information" right={d.kind === "SESSION" ? "Academic session" : "Semester"}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[["Application number", <span key="r" className="tnum b600">{d.reference}</span>], ["Type", d.kind === "SESSION" ? "Academic session" : "Semester"], ["Session", d.session], ["Semester", d.kind === "SESSION" ? "Whole session" : SEM(d.semester)],
              ["Reason", d.reason], ["Requested period from", dayOf(d.period_from)], ["Expected return", returnOf(d)], ["Return date", dayOf(d.return_on)], ["Submitted", whenAt(d.submitted_at)], ["Declaration", d.declared ? "Confirmed by the student" : "Not confirmed"],
              ["Current stage", OFFICE_OF[d.state] ?? "—"], ["Batch", d.batch_reference ? `${d.batch_reference} · ${dayOf(d.batch_forwarded_at)}` : "—"]]} />
            {d.explanation ? <div className="mt-3" style={{ whiteSpace: "pre-wrap" }}>{d.explanation}</div> : null}
            {d.extension_of ? <div className="mt-2"><Pil kind="info">An extension of an earlier deferment</Pil></div> : null}
          </PBody>
        </Panel>
        <Panel title="Supporting documents" right={`${d.documents.length}${d.needs_document ? " · required for this reason" : ""}`}>
          {d.documents.length ? (
            <ul className="plain">{d.documents.map((x) => <li key={x.id} className="row row--between" style={{ padding: "8px var(--s-4)", borderBottom: "1px solid var(--line)" }}><span><b>{DOC_KIND[x.kind] ?? x.kind}</b><div className="sub2">{x.filename} · {(x.size_bytes / 1024).toFixed(0)} KB · {dayOf(x.uploaded_at)}</div></span><Btn kind="secondary" size="sm" onClick={() => setViewing({ url: `/api/bff/api/v1/deferments/${d.id}/documents/${x.id}/content`, title: x.filename, image: x.content_type.startsWith("image/") })}>View</Btn></li>)}</ul>
          ) : <PBody><div className="sub2">{d.needs_document ? "None uploaded; the reason requires one — return the request for correction." : "None uploaded."}</div></PBody>}
          <PBody><div className="sub2">A document opens here, in a viewer on this page; it is served through the authorised door and never by a public link.</div></PBody>
        </Panel>
      </div>

      <div className="grid grid--2">
        <Panel title="Financial verification" right={d.bursary_at ? <Pil kind="ok">Verified by the Bursary {dayOf(d.bursary_at)}</Pil> : <Pil kind="grey">Read from the finance record</Pil>}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["Deferment application fee", d.fee_amount != null ? naira(d.fee_amount) : "—"], ["Fee payment status", <FeePil key="f" state={d.fee_state ?? (d.fee_id ? "CONFIRMED" : null)} />],
              ["Fee reference · receipt", `${d.fee_reference ?? "—"}${d.fee_receipt_no ? ` · ${d.fee_receipt_no}` : ""}`], ["Fee paid on", dayOf(d.fee_confirmed_at)],
              ["Last school-fee payment", d.bursary_last_fee_amount != null ? naira(d.bursary_last_fee_amount) : fin?.found ? naira(fin.last_fee_amount) : <span key="n" className="ink-red">No qualifying school-fee payment found.</span>],
              ["Payment date", dayOf(d.bursary_last_fee_at ?? fin?.last_fee_at)], ["Payment reference", d.bursary_last_fee_ref ?? fin?.last_fee_ref ?? "—"], ["Session of that payment", d.bursary_last_fee_session ?? fin?.last_fee_session ?? "—"],
              ["Position this session", fin ? `${fin.position_status?.replace(/_/g, " ").toLowerCase() ?? ""} · paid ${naira(fin.paid)} of ${naira(fin.due)}` : "—"],
              ["Outstanding balance", d.bursary_balance != null ? `${naira(d.bursary_balance)} (${d.bursary_balance_session})` : fin?.balance != null ? `${naira(fin.balance)} (${fin.balance_session})` : "—"],
              ["Arrears", fin?.has_arrears ? "Yes — an earlier session is owed" : "None"], ["Bursary officer", d.bursary_officer ? `${d.bursary_officer}${d.bursary_note ? ` · ${d.bursary_note}` : ""}` : "—"]]} />
          </PBody>
        </Panel>
        <Panel title="The student's record" right={d.student_status.charAt(0) + d.student_status.slice(1).toLowerCase().replace(/_/g, " ")}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[["Status", d.student_status], ["Standing", d.standing?.standing ? `${d.standing.standing}${d.standing.cgpa != null ? ` · CGPA ${Number(d.standing.cgpa).toFixed(2)}` : ""}` : "—"], ["Entry session", d.entry_session], ["Level", `${d.level} Level`],
              ["Programme duration", tl ? `${tl.original_semesters} semesters → ${tl.adjusted_semesters} adjusted` : "—"], ["Expected completion", tl ? `${tl.adjusted_completion_session} · ${SEM(tl.adjusted_completion_semester)}` : "—"]]} />
            <div className="eyebrow mt-3 mb-1">Recent registrations</div>
            {d.registration?.length ? <ul className="plain">{d.registration.map((r, i) => <li key={i} className="sub2 tnum">{r.session} · {SEM(r.semester)} · {r.status.toLowerCase()}{r.submitted_at ? ` · ${dayOf(r.submitted_at)}` : ""}</li>)}</ul> : <div className="sub2">No course registration on record.</div>}
            <div className="eyebrow mt-3 mb-1">Previous deferments</div>
            {d.previous?.length ? <ul className="plain">{d.previous.map((p, i) => <li key={i} className="sub2"><span className="tnum">{p.reference}</span> · {p.kind === "SESSION" ? p.session : `${p.session} ${SEM(p.semester)}`} · {p.stage_label.toLowerCase()}</li>)}</ul> : <div className="sub2">None.</div>}
          </PBody>
        </Panel>
      </div>

      <Panel title="The desks" right="Each word on the record">
        <PBody>
          <KvGrid cls="grid--1" pairs={[
            ["Bursary", d.bursary_at ? <span key="b"><b>Approved</b> {dayOf(d.bursary_at)}{d.bursary_officer ? ` by ${d.bursary_officer}` : ""}{d.bursary_note ? <div className="sub2">{d.bursary_note}</div> : null}</span> : <span key="b" className="sub2">Awaiting</span>],
            ["Head of Department", d.dept_at ? <span key="d"><b>Approved</b> {dayOf(d.dept_at)}{d.dept_officer ? ` by ${d.dept_officer}` : ""}{d.dept_note ? <div className="sub2">{d.dept_note}</div> : null}</span> : <span key="d" className="sub2">Awaiting</span>],
            ["Faculty", d.fac_at ? <span key="f"><b>Approved</b> {dayOf(d.fac_at)}{d.faculty_officer ? ` by ${d.faculty_officer}` : ""}{d.fac_note ? <div className="sub2">{d.fac_note}</div> : null}</span> : <span key="f" className="sub2">Awaiting</span>],
            ["Academic Office", d.forwarded_at ? <span key="a"><b>Forwarded</b> {dayOf(d.forwarded_at)}{d.forwarded_officer ? ` by ${d.forwarded_officer}` : ""}{d.batch_reference ? <div className="sub2 tnum">Batch {d.batch_reference}</div> : null}</span> : <span key="a" className="sub2">Awaiting</span>],
            ["Deputy Vice-Chancellor (final approval)", d.dvc_at ? <span key="v"><b>Approved</b> {dayOf(d.dvc_at)}{d.dvc_officer ? ` by ${d.dvc_officer}` : ""}{d.dvc_note ? <div className="sub2">{d.dvc_note}</div> : null}</span> : d.state === "REJECTED" ? <span key="v"><b>Rejected</b> {dayOf(d.decided_at)} by the {OFFICE_OF[d.returned_from_state ?? ""] ?? d.returned_by_office ?? "desk"}{d.decision_note ? <div className="sub2">{d.decision_note}</div> : null}</span> : <span key="v" className="sub2">Awaiting</span>],
            ["Return", d.returned_at ? <span key="rt"><b>Confirmed</b> {dayOf(d.returned_at)}{d.returned_officer ? ` by ${d.returned_officer}` : ""}{d.return_note ? <div className="sub2">{d.return_note}</div> : null}</span> : <span key="rt" className="sub2">{returnOf(d)}</span>],
          ]} />
          {d.correction_note ? <Note kind="bad" title={`Returned for correction by the ${OFFICE_OF[d.returned_from_state ?? ""] ?? d.returned_by_office ?? "desk"}`}>{d.correction_note}</Note> : null}
          {d.cancel_note ? <Note kind="info" title="Cancelled">{d.cancel_note}</Note> : null}
        </PBody>
      </Panel>

      {d.effect?.applied ? (
        <div className="grid grid--2">
          <Panel title="Academic effect of deferment" right={<Pil kind="ok">Applied {dayOf(d.effect.effect_applied_at)}</Pil>}><PBody><KvGrid cls="grid--2" pairs={effectPairs(d.effect)} /></PBody></Panel>
          <Panel title="Courses of the deferred period" right={`${d.deferredCourses.length} · DEFERRED, not failed`}>
            {d.deferredCourses.length ? <DTable pageSize={0} cols={["Course", "Units|num", "Source", "Status|mid", "Taken"]} rows={d.deferredCourses.map((c) => [<span key="c"><strong className="tnum">{c.course_code}</strong><div className="sub2">{c.title}</div></span>, <span key="u" className="tnum">{c.units}</span>, <span key="s" className="sub2">{c.source === "REGISTRATION" ? "The student's registration" : "The curriculum"}</span>, <Pil key="st" kind={COURSE_STATE[c.status]?.[1] ?? "grey"}>{COURSE_STATE[c.status]?.[0] ?? c.status}</Pil>, <span key="t" className="sub2">{c.taken_session ? `${c.taken_session} · ${SEM(c.taken_semester)}${c.grade ? ` · ${c.grade}` : ""}` : c.due ? "Due on the registration form" : "After the return"}</span>])} /> : <PBody><div className="sub2">No course fell in the deferred period.</div></PBody>}
          </Panel>
        </div>
      ) : null}

      <Panel title="History" right="Every act and reading on this application">
        <PBody>
          <ol className="plain" style={{ display: "grid", gap: 6 }}>{d.history.map((h, i) => <li key={i} className="row row--base" style={{ gap: "var(--s-3)", flexWrap: "wrap" }}><span className="tnum sub2" style={{ minWidth: 150 }}>{whenAt(h.at)}</span><span className="b600">{ACTION_WORD[h.action] ?? h.action}</span>{h.note ? <span className="sub2">{h.note}</span> : null}<span className="sub2">{[h.actor, h.actor_office].filter(Boolean).join(" · ")}</span></li>)}</ol>
        </PBody>
      </Panel>

      {viewing ? <DocViewer url={viewing.url} title={viewing.title} image={viewing.image} onClose={() => setViewing(null)} /> : null}

      {ask ? (
        <Modal title={ask === "return" ? `Confirm the return of ${d.surname}, ${d.other_names}` : `${askTitle[ask] ?? ask} · ${d.reference}`} sub={periodOf(d)} onClose={() => setAsk(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Back</Btn>
            {ask === "return" ? <Btn kind="go" disabled={busy} onClick={() => void act("/return", { note: note.trim() || null }, `Return confirmed: ${d.reference}`)}>Confirm Return</Btn>
              : <Btn kind={ask === "reject" ? "urgent" : "go"} disabled={busy} onClick={() => doAct(ask)}>{ask === "reject" ? "Reject" : "Approve"}</Btn>}</>}>
          {ask === "return" ? <p>The student&rsquo;s status is restored and normal academic activity resumes for {returnOf(d)}. The courses of the deferred period become due on their registration form as deferred courses. Add a note if you wish.</p>
            : ask === "bursaryApprove" ? <p>Your approval records the last school-fee payment ({fin?.found ? `${naira(fin.last_fee_amount)} on ${dayOf(fin.last_fee_at)}, ${fin.last_fee_ref}` : "none found"}) and the outstanding balance ({naira(fin?.balance)}) as read from the finance record, and sends the application to the Head of Department.</p>
            : ask === "dvcApprove" ? <p>Your approval is final. Your comment goes on the record with it; the deferred period is held on every register, the courses of the period are marked DEFERRED (never failed), the CGPA is untouched, the programme timeline is extended by {d.kind === "SESSION" ? "one academic session" : "one semester"}, the approval letter is issued and the student is told. This cannot be undone.</p>
            : ask === "reject" ? <p>The student is told the reason you have written above. This cannot be undone.</p>
            : <p>The application moves to the next desk and the student is told.</p>}
          {note.trim() ? <div className="sub2 mt-2">Comment: {note.trim()}</div> : null}
        </Modal>
      ) : null}
    </>
  );
}
