"use client";

/** The student's deferment desk (V259): where they stand now; the request form in three steps — the period and
 *  the reason, the documents, the review and declaration — and every request they have made, with its history
 *  and, once approved, the letter. Nothing is submitted until the student presses Submit on the review. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Me } from "@/lib/student-portal";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Steps } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ACTION_WORD, DOC_KIND, SEM, StatePil, ReturnPil, dayOf, periodOf, readBase64, returnOf, whenAt, type Deferment as Row, type DefermentFull, type MyDeferments, type Reason } from "@/lib/deferments";

const OPEN = new Set(["DRAFT", "CORRECTION_REQUIRED"]);
const LIVE = new Set(["SUBMITTED", "DEPT_RECOMMENDED", "FAC_RECOMMENDED", "APPROVED", "ACTIVE"]);

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
  const reason: Reason | undefined = data.reasons.find((r) => r.code === form.reason);
  const sessionRow = data.sessions.find((x) => x.name === form.session);
  const semesters = Array.from({ length: sessionRow?.semesters ?? 2 }, (_, i) => i + 1);
  const eligible = data.eligibility.eligible && !live;
  const editing = live && OPEN.has(live.state) ? live : null;

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
    void openOne(d.id).then(() => { /* the documents show on step 2 */ });
    setDraft(null);
  }
  const current = draft ?? (editing ? opened && opened.id === editing.id ? opened : null : null);

  return (
    <>
      <PageHead title="Deferment" description="Defer a semester or a whole academic session on the record: the department, the faculty and the Registry decide in turn; approved, the period is held and your return is named."
        actions={live && live.state === "ACTIVE" ? <a className="btn btn--primary btn--sm" href={`/student/deferment/letter/${live.id}`} target="_blank" rel="noopener">Download Approval Letter</a> : undefined} />

      {live ? (
        live.state === "ACTIVE" || live.state === "APPROVED" ? (
          <Note kind="ok" title={`DEFERMENT ${live.state === "ACTIVE" ? "ACTIVE" : "APPROVED"} · ${periodOf(live)}`} action={<a className="btn btn--ghost btn--sm" href={`/student/deferment/letter/${live.id}`} target="_blank" rel="noopener">Approval Letter</a>}>
            Reference <b className="tnum">{live.reference}</b>. Expected return: <b>{returnOf(live)}</b>{live.return_on ? ` (${dayOf(live.return_on)})` : ""}. You cannot register courses for the deferred period; the department confirms your return when you present yourself. <ReturnPil status={live.return_status} />
          </Note>
        ) : OPEN.has(live.state) ? (
          <Note kind={live.state === "CORRECTION_REQUIRED" ? "bad" : "info"} title={live.state === "CORRECTION_REQUIRED" ? "Your deferment request requires correction" : "You have a draft deferment request"} action={<Btn kind="primary" onClick={() => startEditing(live)}>Continue the Request</Btn>}>
            {live.state === "CORRECTION_REQUIRED" ? `The desk returned ${live.reference}: ${live.correction_note ?? ""} Correct it and submit again.` : `${live.reference} for ${periodOf(live)} is not yet submitted.`}
          </Note>
        ) : (
          <Note kind="info" title="DEFERMENT REQUEST UNDER REVIEW" action={<Btn kind="ghost" disabled={busy} onClick={() => void cancel(live.id)}>Withdraw Request</Btn>}>
            {live.reference} for {periodOf(live)} is {live.state === "SUBMITTED" ? "with your department" : live.state === "DEPT_RECOMMENDED" ? "with your faculty, recommended by the department" : "with the Registry, recommended by the department and the faculty"}. You are told by email at each turn.
          </Note>
        )
      ) : !data.eligibility.eligible ? (
        <Note kind="bad" title="DEFERMENT REQUEST NOT AVAILABLE">{data.eligibility.reason}</Note>
      ) : (
        <Note kind="info" title="No active deferment">You may ask to defer a semester or a session below. You have used {data.eligibility.used} of the {data.eligibility.allowed} session(s) the University allows.</Note>
      )}

      {problem ? <ProblemNotice problem={problem} /> : null}

      {(eligible || editing) ? (
        <Panel title={editing ? `Deferment request · ${editing.reference}` : "New deferment request"} right={<span className="sub2">Step {step} of 3</span>}>
          <PBody>
            <Steps list={[[step > 1 ? "done" : "now", "Period and reason", ""], [step > 2 ? "done" : step === 2 ? "now" : "todo", "Supporting documents", ""], [step === 3 ? "now" : "todo", "Review and submit", ""]]} />
            <div className="hr" />
            {step === 1 ? (
              <div className="stack">
                <div className="eyebrow">Student information</div>
                <KvGrid cls="grid--4" pairs={[["Student ID", s.matricNo ?? s.admissionNo ?? "—"], ["Name", s.name], ["Faculty", s.faculty], ["Department", s.department], ["Programme", s.programme], ["Level", String(s.level)], ["Current session", data.current.session ?? s.session], ["Current semester", SEM(data.current.semester ?? null) || "None open"]]} />
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
                <Field id="df-words" label="Explanation" required={!!reason && (reason.needs_words || reason.code === "OTHER")} hint={reason?.needs_document ? `A ${reason.label.toLowerCase()} deferment is supported by a document, uploaded at the next step.` : "A few sentences on your circumstances."}>
                  <textarea id="df-words" className="ctl" rows={4} value={form.explanation} onChange={(e) => setForm({ ...form, explanation: e.target.value })} />
                </Field>
                <div className="row row--end"><span className="grow" /><Btn kind="primary" disabled={busy || !form.session || !form.reason} onClick={() => void saveAndNext()}>Save and Continue</Btn></div>
              </div>
            ) : step === 2 ? (
              <div className="stack">
                <div className="sub2">{reason?.needs_document ? <b>A {reason.label.toLowerCase()} deferment requires at least one supporting document.</b> : "Supporting documents are optional for this reason; attach any that help the desk."} PDF, JPEG or PNG, at most 5 MB each, at most six.</div>
                {current?.documents.length ? (
                  <ul className="plain">{current.documents.map((d) => <li key={d.id} className="row row--between" style={{ padding: "6px 0", borderBottom: "1px solid var(--line)" }}><span><a className="lnk" href={`/api/bff/api/v1/me/deferments/${current.id}/documents/${d.id}/content`} target="_blank" rel="noopener">{DOC_KIND[d.kind] ?? d.kind}</a><div className="sub2">{d.filename} · {(d.size_bytes / 1024).toFixed(0)} KB · {dayOf(d.uploaded_at)}</div></span></li>)}</ul>
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
                  ["Reason", reason?.label ?? "—"], ["Expected return", current ? returnOf(current) : "Named on submission"], ["Supporting documents", `${current?.documents.length ?? 0} uploaded`]]} />
                {form.explanation ? <div className="sub2" style={{ whiteSpace: "pre-wrap" }}>{form.explanation}</div> : null}
                <label className="row" style={{ gap: "var(--s-2)", alignItems: "flex-start" }}>
                  <input type="checkbox" checked={form.declared} onChange={(e) => setForm({ ...form, declared: e.target.checked })} />
                  <span>I confirm that the information provided in this deferment request is accurate and understand that approval is subject to the University&rsquo;s academic regulations.</span>
                </label>
                <div className="row row--between"><Btn kind="ghost" onClick={() => setStep(2)}>Back</Btn><Btn kind="go" disabled={busy || !form.declared} onClick={() => void submit()}>Submit Deferment Request</Btn></div>
              </div>
            )}
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Deferment history" right={data.requests.length ? `${data.requests.length} request${data.requests.length === 1 ? "" : "s"}` : "None yet"}>
        {data.requests.length ? (
          <DTable pageSize={0} cols={["Reference", "Type|mid", "Session", "Semester|mid", "Reason", "Status|mid", "Requested|mid", "Decided|mid", "Return", "|num"]}
            rows={data.requests.map((r) => [
              <span key="r" className="tnum b600">{r.reference}</span>, <span key="k">{r.kind === "SESSION" ? "Session" : "Semester"}</span>, <span key="s" className="tnum">{r.session}</span>,
              <span key="m">{r.kind === "SESSION" ? "All" : SEM(r.semester)}</span>, <span key="w">{r.reason}</span>, <StatePil key="st" state={r.state} />,
              <span key="a" className="tnum sub2">{dayOf(r.submitted_at ?? r.created_at)}</span>, <span key="d" className="tnum sub2">{dayOf(r.decided_at)}</span>,
              <span key="rt" className="sub2">{returnOf(r)}</span>,
              <span key="o" className="row row--inline row--tight" style={{ justifyContent: "flex-end" }}>
                {["APPROVED", "ACTIVE", "COMPLETED"].includes(r.state) ? <a className="btn btn--ghost btn--sm" href={`/student/deferment/letter/${r.id}`} target="_blank" rel="noopener">Letter</a> : null}
                <Btn kind="ghost" size="sm" onClick={() => void openOne(r.id)}>History</Btn>
              </span>,
            ])} />
        ) : <PBody><div className="sub2">You have not asked to defer before.</div></PBody>}
      </Panel>

      {opened && !editing ? (
        <Panel title={`${opened.reference} · ${periodOf(opened)}`} right={<StatePil state={opened.state} />}>
          <PBody>
            <KvGrid cls="grid--4" pairs={[["Reason", opened.reason], ["Expected return", returnOf(opened)], ["Department", opened.dept_at ? `${dayOf(opened.dept_at)}${opened.dept_note ? ` · ${opened.dept_note}` : ""}` : "—"], ["Faculty", opened.fac_at ? `${dayOf(opened.fac_at)}${opened.fac_note ? ` · ${opened.fac_note}` : ""}` : "—"], ["Registry", opened.decided_at ? `${dayOf(opened.decided_at)}${opened.decision_note ? ` · ${opened.decision_note}` : ""}` : "—"], ["Return", opened.returned_at ? dayOf(opened.returned_at) : (opened.return_status ? RETURN_WORD(opened.return_status) : "—")]]} />
            <ol className="plain mt-3" style={{ display: "grid", gap: 6 }}>
              {opened.history.map((h, i) => <li key={i} className="row row--base" style={{ gap: "var(--s-3)", flexWrap: "wrap" }}><span className="tnum sub2" style={{ minWidth: 150 }}>{whenAt(h.at)}</span><span className="b600">{ACTION_WORD[h.action] ?? h.action}</span>{h.note ? <span className="sub2">{h.note}</span> : null}{h.actor_office && h.actor_office !== "student" ? <Pil kind="grey">{h.actor_office}</Pil> : null}</li>)}
            </ol>
            <div className="mt-2"><Btn kind="ghost" onClick={() => setOpened(null)}>Close</Btn></div>
          </PBody>
        </Panel>
      ) : null}

      <Note kind="info" title="What a deferment does and does not do">
        An approved deferment holds the period on every register: you cannot register courses for it, and your status reads Deferred while it runs. Your registrations, payments, results and research from other periods stay exactly as they were. A deferment is not a withdrawal, a suspension or a failure; your history shows the period as deferred and your return as confirmed.
      </Note>
    </>
  );
}

const RETURN_WORD = (s: string) => ({ UPCOMING: "Upcoming", DUE: "Due now", OVERDUE: "Overdue", RETURNED: "Returned" } as Record<string, string>)[s] ?? s;
