"use client";

/** The student's deferment desk (V259, revised by V264): the application fee first — generated, paid by card or at the
 *  bank, confirmed — and only then the form in three steps; where the request stands on the six-desk chain, with the
 *  approval timeline; the academic effect of an approved deferment (no failure, no CGPA penalty, the programme timeline
 *  extended by the period deferred); the deferred courses and where each stands; and every request with its history. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Me } from "@/lib/student-portal";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Steps } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PayByCard } from "../common";
import { ACTION_WORD, ApprovalTimeline, COURSE_STATE, DOC_KIND, FeePil, IN_REVIEW, LIVE, OFFICE_OF, OPEN, SEM, STATE, StatePil, ReturnPil, dayOf, effectPairs, naira, periodOf, readBase64, returnOf, whenAt, type Deferment as Row, type DefermentFull, type MyDeferments, type Reason } from "@/lib/deferments";
import { DocViewer } from "@/lib/deferment-viewer";

export function Deferment({ s, data }: { s: Me; data: MyDeferments }) {
  const router = useRouter();
  const live = data.requests.find((r) => LIVE.has(r.state) || OPEN.has(r.state)) ?? null;
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [draft, setDraft] = useState<DefermentFull | null>(null);
  const [step, setStep] = useState(1);
  const [form, setForm] = useState({ kind: "SEMESTER", session: data.current.session ?? data.sessions[0]?.name ?? "", semester: String(data.current.semester ?? 1), reason: "", explanation: "", declared: false });
  const [docKind, setDocKind] = useState("MEDICAL");
  const [file, setFile] = useState<File | null>(null);
  const [fileKey, setFileKey] = useState(0);
  const [opened, setOpened] = useState<DefermentFull | null>(null);
  const [viewing, setViewing] = useState<{ url: string; title: string; image: boolean } | null>(null);
  const reason: Reason | undefined = data.reasons.find((r) => r.code === form.reason);
  // the rule the database applies at submission, met here first: a reason that needs words has at least twenty characters
  const needsWords = !!reason && (reason.needs_words || reason.code === "OTHER");
  const wordsShort = needsWords && form.explanation.trim().length < 20;
  const sessionRow = data.sessions.find((x) => x.name === form.session);
  const semesters = Array.from({ length: sessionRow?.semesters ?? 2 }, (_, i) => i + 1);
  const fee = data.fee;
  const feePaid = !!fee && fee.state === "CONFIRMED" && !fee.used_by;
  const feeAmount = Number(data.setting.fee ?? 0);
  const eligible = data.eligibility.eligible && !live;
  const editing = live && OPEN.has(live.state) ? live : null;
  const formOpen = (eligible && (feePaid || feeAmount <= 0)) || !!editing;

  async function call<T>(path: string, method: "GET" | "POST" | "PUT", body: unknown, reason: string): Promise<T | null> {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/me/deferments${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: method === "GET" ? undefined : JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return null; }
      return j as T;
    } finally { setBusy(false); }
  }
  const payload = () => ({ kind: form.kind, session: form.session, semester: form.kind === "SEMESTER" ? Number(form.semester) : null, reason: form.reason, explanation: form.explanation.trim() || null, declared: form.declared });

  async function startFee() {
    const r = await call<{ reference: string }>("/fee", "POST", {}, "Deferment application fee reference generated");
    if (r) { notify(`Reference ${r.reference} generated`); router.refresh(); }
  }
  async function saveAndNext() {
    const d = draft ?? editing ? await call<DefermentFull>(`/${(draft ?? editing)!.id}`, "PUT", payload(), "Deferment request changed") : await call<DefermentFull>("", "POST", payload(), "Deferment request opened");
    if (d) { setDraft(d); setStep(2); }
  }
  async function upload() {
    const d = draft ?? editing; if (!d || !file) return;
    const type = file.type === "image/jpg" ? "image/jpeg" : file.type;
    if (!["application/pdf", "image/jpeg", "image/png"].includes(type) || file.size > 5 * 1024 * 1024) { const pr: Problem = { status: 422, title: "A supporting document is a PDF, JPEG or PNG of at most 5 MB." }; setProblem(pr); notifyProblem(pr); return; }
    const b64 = await readBase64(file);
    const r = await call<DefermentFull>(`/${d.id}/documents`, "POST", { kind: docKind, filename: file.name, contentType: type, contentBase64: b64 }, `${DOC_KIND[docKind]} uploaded`);
    if (r) { setDraft(r); setFile(null); setFileKey((k) => k + 1); notify("Document uploaded"); }
  }
  async function submit() {
    const d = draft ?? editing; if (!d) return;
    const saved = await call<DefermentFull>(`/${d.id}`, "PUT", payload(), "Deferment request reviewed");
    if (!saved) return;
    const r = await call<DefermentFull>(`/${d.id}/submit`, "POST", {}, "Deferment request submitted");
    if (r) { notify(`Deferment request ${r.reference} submitted successfully`); setDraft(null); setStep(1); router.refresh(); }
  }
  async function cancel(id: string) {
    const why = window.prompt("Why do you withdraw this request?"); if (why === null) return;
    const r = await call<DefermentFull>(`/${id}/cancel`, "POST", { note: why }, "Deferment request withdrawn");
    if (r) { notify("Request withdrawn"); router.refresh(); }
  }
  async function openOne(id: string) {
    const r = await call<DefermentFull>(`/${id}`, "GET", null, "Deferment read");
    if (r) setOpened(r);
  }
  function startEditing(d: Row) {
    setForm({ kind: d.kind, session: d.session, semester: String(d.semester ?? 1), reason: d.reason_code, explanation: d.explanation ?? "", declared: d.declared });
    setStep(1);
    void openOne(d.id);
    setDraft(null);
  }
  const current = draft ?? (editing ? opened && opened.id === editing.id ? opened : null : null);
  const tl = data.timeline;
  const deferred = data.deferredCourses;

  return (
    <>
      <PageHead title="Deferment" description="Defer a semester or a whole academic session on the record. The application fee is paid first; the Bursary, your Head of Department, your faculty, the Academic Office, the Deputy Vice-Chancellor and the Senate Business Committee decide in turn; approved, the period is held, your courses for it are marked deferred (never failed) and your completion timeline moves by exactly the period deferred."
        actions={live && ["ACTIVE", "APPROVED"].includes(live.state) ? <a className="btn btn--primary btn--sm" href={`/student/deferment/letter/${live.id}`} target="_blank" rel="noopener">Download Approval Letter</a> : undefined} />

      {live ? (
        live.state === "ACTIVE" || live.state === "APPROVED" ? (
          <Note kind="ok" title={`DEFERMENT ${live.state === "ACTIVE" ? "IN FORCE" : "APPROVED"} · ${periodOf(live)}`} action={<a className="btn btn--ghost btn--sm" href={`/student/deferment/letter/${live.id}`} target="_blank" rel="noopener">Approval Letter</a>}>
            Application number <b className="tnum">{live.reference}</b>. Expected return: <b>{returnOf(live)}</b>{live.return_on ? ` (${dayOf(live.return_on)})` : ""}. You cannot register courses for the deferred period; your department confirms your return when you present yourself, and your deferred courses then appear on your registration form. <ReturnPil status={live.return_status} />
          </Note>
        ) : OPEN.has(live.state) ? (
          <Note kind={live.state === "CORRECTION_REQUIRED" ? "bad" : "info"} title={live.state === "CORRECTION_REQUIRED" ? "Your deferment application requires correction" : "You have a draft deferment application"} action={<Btn kind="primary" onClick={() => startEditing(live)}>Continue the Application</Btn>}>
            {live.state === "CORRECTION_REQUIRED" ? <>Returned by the <b>{live.returned_by_office ? (OFFICE_OF[live.returned_from_state ?? ""] ?? live.returned_by_office) : "desk"}</b> on {dayOf(live.updated_at)}: {live.correction_note ?? ""} Correct it and submit it again; it goes back to the same desk.</> : `${live.reference} for ${periodOf(live)} is not yet submitted.`}
          </Note>
        ) : (
          <Note kind="info" title={`DEFERMENT APPLICATION · ${STATE[live.state]?.[0] ?? live.state}`} action={IN_REVIEW.has(live.state) ? <Btn kind="ghost" disabled={busy} onClick={() => void cancel(live.id)}>Withdraw Application</Btn> : undefined}>
            {live.reference} for {periodOf(live)} is with the <b>{OFFICE_OF[live.state] ?? "desk"}</b>. You are told by email and text at each turn.
          </Note>
        )
      ) : !data.eligibility.eligible ? (
        <Note kind="bad" title="DEFERMENT APPLICATION NOT AVAILABLE">{data.eligibility.reason}</Note>
      ) : (
        <Note kind="info" title="No active deferment">You may apply to defer a semester or a session. You have used {data.eligibility.used} of the {data.eligibility.allowed} session(s) the University allows. The application fee is {naira(feeAmount)}; the form opens once it is confirmed.</Note>
      )}

      {problem ? <ProblemNotice problem={problem} /> : null}

      {live && !OPEN.has(live.state) ? (
        <Panel title="Deferment application" right={<StatePil state={live.state} />}>
          <PBody>
            <KvGrid cls="grid--4" pairs={[["Application number", <span key="r" className="tnum b600">{live.reference}</span>], ["Application fee", live.fee_amount != null ? naira(live.fee_amount) : naira(feeAmount)], ["Payment status", <FeePil key="f" state={live.fee_state ?? (live.fee_id ? "CONFIRMED" : null)} />],
              ["Application status", <StatePil key="s" state={live.state} />], ["Current office", OFFICE_OF[live.state] ?? (["APPROVED", "ACTIVE"].includes(live.state) ? "Registry (in force)" : "—")], ["Period", periodOf(live)], ["Expected return", returnOf(live)], ["Submitted", dayOf(live.submitted_at)]]} />
            <div className="eyebrow mt-3 mb-1">Approval timeline</div>
            <ApprovalTimeline d={live} />
          </PBody>
        </Panel>
      ) : null}

      {eligible && !editing && feeAmount > 0 ? (
        <Panel title="Deferment application fee" right={<FeePil state={feePaid ? "CONFIRMED" : fee?.state ?? null} />}>
          <PBody>
            {feePaid ? (
              <>
                <KvGrid cls="grid--4" pairs={[["Amount", naira(fee!.amount)], ["Payment status", "PAID"], ["Transaction reference", <span key="r" className="tnum">{fee!.reference}</span>], ["Payment date", dayOf(fee!.confirmed_at)], ["Receipt", fee!.receipt_no ?? "—"]]} />
                <div className="row mt-2">
                  {fee!.receipt_no ? <><LinkBtn kind="ghost" href={`/student/receipt/${encodeURIComponent(fee!.reference)}`}>View Receipt</LinkBtn><a className="btn btn--ghost btn--sm" href={`/student/receipt/${encodeURIComponent(fee!.reference)}/pdf`} target="_blank" rel="noopener">Download Receipt</a></> : null}
                  <span className="sub2">The application form below is open to you.</span>
                </div>
              </>
            ) : fee && fee.state === "PENDING" ? (
              <>
                <KvGrid cls="grid--3" pairs={[["Amount", naira(fee.amount)], ["Payment status", "NOT PAID"], ["Payment reference", <span key="r" className="tnum">{fee.reference}</span>], ["Reference expires", whenAt(fee.expires_at)]]} />
                <div className="mt-2"><PayByCard reference={fee.reference} amount={Number(fee.amount)} /></div>
                <div className="sub2 mt-2">Pay by card or USSD here, or at any bank branch quoting the reference; the Bursary confirms a bank payment. The form opens the moment the payment is confirmed. The fee is not refunded if the application is refused.</div>
              </>
            ) : (
              <>
                <KvGrid cls="grid--3" pairs={[["Application fee", naira(feeAmount)], ["Payment status", "NOT PAID"], ["Session", data.current.session ?? s.session]]} />
                {fee && fee.state === "EXPIRED" ? <div className="sub2 mt-1">Your earlier reference {fee.reference} expired unpaid; generate a new one.</div> : null}
                <div className="row mt-2"><Btn kind="primary" disabled={busy} onClick={() => void startFee()}>Pay {naira(feeAmount)} Deferment Fee</Btn><span className="sub2">A payment reference is generated; the application form opens when the payment is confirmed.</span></div>
              </>
            )}
          </PBody>
        </Panel>
      ) : null}

      {formOpen ? (
        <Panel title={editing ? `Deferment application · ${editing.reference}` : "New deferment application"} right={<span className="sub2">Step {step} of 3</span>}>
          <PBody>
            <Steps list={[[step > 1 ? "done" : "now", "Period and reason", ""], [step > 2 ? "done" : step === 2 ? "now" : "todo", "Supporting documents", ""], [step === 3 ? "now" : "todo", "Review and submit", ""]]} />
            <div className="hr" />
            {step === 1 ? (
              <div className="stack">
                <div className="eyebrow">Student information</div>
                <KvGrid cls="grid--4" pairs={[["Student ID", s.matricNo ?? s.admissionNo ?? "—"], ["Name", s.name], ["Faculty", s.faculty], ["Department", s.department], ["Programme", s.programme], ["Level", String(s.level)], ["Current session", data.current.session ?? s.session], ["Current semester", SEM(data.current.semester ?? null) || "None open"]]} />
                <div className="sub2">Your identity, programme and standing are read from the record; they are not typed here.</div>
                <div className="eyebrow">Deferment information</div>
                <div className="row row--end">
                  <Field id="df-kind" label="Deferment type" required style={{ flex: "1 1 200px" }}>
                    <select id="df-kind" className="ctl" value={form.kind} onChange={(e) => setForm({ ...form, kind: e.target.value })}><option value="SEMESTER">A semester</option><option value="SESSION">The whole academic session</option></select>
                  </Field>
                  <Field id="df-session" label="Academic session" required style={{ flex: "1 1 200px" }}>
                    <select id="df-session" className="ctl" value={form.session} onChange={(e) => setForm({ ...form, session: e.target.value })}>{data.sessions.map((x) => <option key={x.name} value={x.name}>{x.name}{x.state === "CURRENT" ? " · current" : ""}</option>)}</select>
                  </Field>
                  {form.kind === "SEMESTER" ? (
                    <Field id="df-sem" label="Semester" required style={{ flex: "1 1 200px" }}>
                      <select id="df-sem" className="ctl" value={form.semester} onChange={(e) => setForm({ ...form, semester: e.target.value })}>{semesters.map((n) => <option key={n} value={String(n)}>{SEM(n)}</option>)}</select>
                    </Field>
                  ) : null}
                  <Field id="df-reason" label="Reason" required style={{ flex: "1 1 200px" }}>
                    <select id="df-reason" className="ctl" value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })}><option value="">Choose…</option>{data.reasons.map((r) => <option key={r.code} value={r.code}>{r.label}</option>)}</select>
                  </Field>
                </div>
                <Field id="df-words" label="Additional explanation" required={needsWords} hint={needsWords ? `A ${reason!.label.toLowerCase()} deferment is explained in a few sentences — at least twenty characters (${form.explanation.trim().length} so far).${reason!.needs_document ? " A supporting document is uploaded at the next step." : ""}` : reason?.needs_document ? `A ${reason.label.toLowerCase()} deferment is supported by a document, uploaded at the next step. A few words here are optional.` : "A few sentences on your circumstances (optional for this reason)."}>
                  <textarea id="df-words" className="ctl" rows={4} value={form.explanation} onChange={(e) => setForm({ ...form, explanation: e.target.value })} />
                </Field>
                {wordsShort && form.explanation.trim().length > 0 ? <div className="sub2 ink-red">Write at least twenty characters; the desks read this explanation.</div> : null}
                <div className="row row--end"><span className="grow" /><Btn kind="primary" disabled={busy || !form.session || !form.reason || wordsShort} onClick={() => void saveAndNext()}>Save and Continue</Btn></div>
              </div>
            ) : step === 2 ? (
              <div className="stack">
                <div className="sub2">{reason?.needs_document ? <b>A {reason.label.toLowerCase()} deferment requires at least one supporting document.</b> : "Supporting documents are optional for this reason; attach any that help the desks."} PDF, JPEG or PNG, at most 5 MB each, at most six.</div>
                {current?.documents.length ? (
                  <ul className="plain">{current.documents.map((d) => <li key={d.id} className="row row--between" style={{ padding: "6px 0", borderBottom: "1px solid var(--line)" }}><span><button type="button" className="lnk" onClick={() => setViewing({ url: `/api/bff/api/v1/me/deferments/${current.id}/documents/${d.id}/content`, title: d.filename, image: d.content_type.startsWith("image/") })}>{DOC_KIND[d.kind] ?? d.kind}</button><div className="sub2">{d.filename} · {(d.size_bytes / 1024).toFixed(0)} KB · {dayOf(d.uploaded_at)}</div></span></li>)}</ul>
                ) : <div className="sub2">Nothing uploaded yet.</div>}
                <div className="row row--end">
                  <Field id="df-dk" label="Document" style={{ flex: "1 1 200px" }}><select id="df-dk" className="ctl" value={docKind} onChange={(e) => setDocKind(e.target.value)}>{Object.entries(DOC_KIND).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
                  <Field id="df-file" label="File" style={{ flex: "2 1 240px" }}><input key={fileKey} id="df-file" type="file" className="ctl" accept=".pdf,.jpg,.jpeg,.png" onChange={(e) => setFile(e.target.files?.[0] ?? null)} /></Field>
                  <Btn kind="secondary" disabled={busy || !file} onClick={() => void upload()}>Upload</Btn>
                </div>
                <div className="row row--between"><Btn kind="ghost" onClick={() => setStep(1)}>Back</Btn><Btn kind="primary" disabled={busy} onClick={() => setStep(3)}>Continue to Review</Btn></div>
              </div>
            ) : (
              <div className="stack">
                <div className="eyebrow">Deferment summary</div>
                <KvGrid cls="grid--2" pairs={[["Student", s.name], ["Student ID", s.matricNo ?? s.admissionNo ?? "—"], ["Programme", s.programme], ["Department", s.department], ["Faculty", s.faculty],
                  ["Deferment type", form.kind === "SESSION" ? "Academic session" : "Semester"], ["Academic session", form.session], ["Semester", form.kind === "SESSION" ? "Whole session" : SEM(Number(form.semester))],
                  ["Reason", reason?.label ?? "—"], ["Expected return", current ? returnOf(current) : "Named on submission"], ["Supporting documents", `${current?.documents.length ?? 0} uploaded`],
                  ["Application fee", current?.fee_receipt_no ? `${naira(current.fee_amount)} · receipt ${current.fee_receipt_no}` : feePaid && fee ? `${naira(fee.amount)} · receipt ${fee.receipt_no ?? fee.reference}` : "Waived"]]} />
                {form.explanation.trim() ? <div><div className="eyebrow">Additional explanation</div><div style={{ whiteSpace: "pre-wrap" }}>{form.explanation}</div></div> : null}
                {wordsShort ? <Note kind="bad" title="The explanation is too short to submit" action={<Btn kind="secondary" onClick={() => setStep(1)}>Back to step 1</Btn>}>A {reason!.label.toLowerCase()} deferment is explained in at least twenty characters; the desks read it.</Note> : null}
                <label className="row" style={{ gap: "var(--s-2)", alignItems: "flex-start" }}>
                  <input type="checkbox" checked={form.declared} onChange={(e) => setForm({ ...form, declared: e.target.checked })} />
                  <span>I confirm that the information provided in this deferment application is accurate and understand that approval is subject to the University&rsquo;s academic regulations, that the application fee is not refunded, and that an approved deferment extends my expected completion by the period deferred.</span>
                </label>
                <div className="row row--between"><Btn kind="ghost" onClick={() => setStep(2)}>Back</Btn><Btn kind="go" disabled={busy || !form.declared || wordsShort} onClick={() => void submit()}>Submit Deferment Application</Btn></div>
              </div>
            )}
          </PBody>
        </Panel>
      ) : null}

      {tl && (tl.approved_count > 0 || deferred.length) ? (
        <div className="grid grid--2">
          <Panel title="Academic effect of your deferment" right={`${tl.approved_count} approved`}>
            <PBody>
              <KvGrid cls="grid--2" pairs={[["Original programme duration", `${tl.original_semesters} semesters (${tl.original_semesters / tl.semesters_per_session} sessions)`], ["Approved deferment", `${tl.approved_semesters} semester${tl.approved_semesters === 1 ? "" : "s"}`],
                ["Adjusted programme duration", `${tl.adjusted_semesters} semesters`], ["CGPA effect", "None — deferred courses carry no grade"],
                ["Original expected completion", `${tl.original_completion_session} · ${SEM(tl.original_completion_semester)}`], ["Adjusted expected completion", `${tl.adjusted_completion_session} · ${SEM(tl.adjusted_completion_semester)}${tl.adjusted_completion_on ? ` (${dayOf(tl.adjusted_completion_on)})` : ""}`],
                ["Entry session", `${tl.entry_session} — unchanged`], ["Expected return", tl.live_return_session ? `${tl.live_return_session} · ${SEM(tl.live_return_semester)}` : "—"]]} />
            </PBody>
          </Panel>
          <Panel title="Deferred courses" right={deferred.length ? `${deferred.filter((c) => c.status === "DEFERRED").length} still to take` : "None"}>
            {deferred.length ? (
              <DTable pageSize={0} cols={["Course", "Units|num", "Original period", "Status|mid", "Taken"]} rows={deferred.map((c) => [
                <span key="c"><strong className="tnum">{c.course_code}</strong><div className="sub2">{c.title}</div></span>, <span key="u" className="tnum">{c.units}</span>,
                <span key="p" className="tnum">{c.original_session} · {SEM(c.original_semester)}</span>, <Pil key="s" kind={COURSE_STATE[c.status]?.[1] ?? "grey"}>{COURSE_STATE[c.status]?.[0] ?? c.status}</Pil>,
                <span key="t" className="sub2">{c.taken_session ? `${c.taken_session} · ${SEM(c.taken_semester)}${c.grade ? ` · grade ${c.grade}` : ""}` : c.due ? "Due on your registration form" : "After your return"}</span>])} />
            ) : <PBody><div className="sub2">No course is deferred.</div></PBody>}
          </Panel>
        </div>
      ) : null}

      <Panel title="Deferment history" right={data.requests.length ? `${data.requests.length} application${data.requests.length === 1 ? "" : "s"}` : "None yet"}>
        {data.requests.length ? (
          <DTable pageSize={0} cols={["Application No.", "Type|mid", "Period", "Reason", "Fee|mid", "Status|mid", "Current office", "Submitted|mid", "Return", "|num"]}
            rows={data.requests.map((r) => [
              <span key="r" className="tnum b600">{r.reference}</span>, <span key="k">{r.kind === "SESSION" ? "Session" : "Semester"}</span>, <span key="s" className="tnum">{periodOf(r)}</span>,
              <span key="w">{r.reason}</span>, <FeePil key="f" state={r.fee_state ?? (r.fee_id ? "CONFIRMED" : null)} />, <StatePil key="st" state={r.state} />,
              <span key="o" className="sub2">{OFFICE_OF[r.state] ?? "—"}</span>,
              <span key="a" className="tnum sub2">{dayOf(r.submitted_at ?? r.created_at)}</span>, <span key="rt" className="sub2">{returnOf(r)}</span>,
              <span key="x" className="row row--inline row--tight" style={{ justifyContent: "flex-end" }}>
                {["APPROVED", "ACTIVE", "COMPLETED"].includes(r.state) ? <a className="btn btn--ghost btn--sm" href={`/student/deferment/letter/${r.id}`} target="_blank" rel="noopener">Letter</a> : null}
                <Btn kind="ghost" size="sm" onClick={() => void openOne(r.id)}>Timeline</Btn>
              </span>,
            ])} />
        ) : <PBody><div className="sub2">You have not applied to defer before.</div></PBody>}
      </Panel>

      {opened && !editing ? (
        <Panel title={`${opened.reference} · ${periodOf(opened)}`} right={<StatePil state={opened.state} />}>
          <PBody>
            <div className="eyebrow mb-1">Approval timeline</div>
            <ApprovalTimeline d={opened} />
            {opened.effect?.applied ? <><div className="eyebrow mt-3 mb-1">Academic effect of deferment</div><KvGrid cls="grid--3" pairs={effectPairs(opened.effect)} /></> : null}
            <div className="eyebrow mt-3 mb-1">Every act on the record</div>
            <ol className="plain" style={{ display: "grid", gap: 6 }}>
              {opened.history.filter((h) => !["VIEWED", "DOCUMENT_VIEWED", "DOWNLOADED"].includes(h.action)).map((h, i) => <li key={i} className="row row--base" style={{ gap: "var(--s-3)", flexWrap: "wrap" }}><span className="tnum sub2" style={{ minWidth: 150 }}>{whenAt(h.at)}</span><span className="b600">{ACTION_WORD[h.action] ?? h.action}</span>{h.note ? <span className="sub2">{h.note}</span> : null}{h.actor_office && h.actor_office !== "student" ? <Pil kind="grey">{h.actor_office}</Pil> : null}</li>)}
            </ol>
            <div className="mt-2"><Btn kind="ghost" onClick={() => setOpened(null)}>Close</Btn></div>
          </PBody>
        </Panel>
      ) : null}

      {viewing ? <DocViewer url={viewing.url} title={viewing.title} image={viewing.image} onClose={() => setViewing(null)} /> : null}

      <Note kind="info" title="What an approved deferment does and does not do">
        It holds the period on every register: you cannot register courses for it, and your status reads Deferred while it runs. The courses of that period are marked <b>DEFERRED</b> — not failed, no F, no zero, no carry-over — and your GPA and CGPA are not touched. Your expected completion moves by exactly the period deferred (one semester, or one session); your entry session and matriculation number never change. When you return, the deferred courses appear on your registration form under their own heading and count only when you take them and a result is published.
      </Note>
    </>
  );
}
