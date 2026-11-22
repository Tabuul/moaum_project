"use client";

/** V766: the transfer applicant's own portal — their inter-university transfer application in the portal's shell: where it stands in
 *  plain words (D11: what the Registry and the department decide is not shown before another officer confirms it), the particulars and
 *  what the state lets them change, the application fee (none due, paid with its receipt, or a reference to pay through the gateways
 *  every fee uses), the documents asked (each checked in the browser for its type and size first; uploaded after the fee, D12), the
 *  submission under a declaration, the acknowledgement with its QR, the history, withdrawing, and applying again in a later window once
 *  an application is declined or withdrawn. Every act is the account's own; the database refuses another's (IUT_NOT_YOURS). */
import { useCallback, useEffect, useRef, useState } from "react";
import type { Problem } from "@/lib/api";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { Shell, type Me as ShellMe } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ReceiptCheck } from "@/components/ReceiptCheck";
import { PayByCard, StepList } from "@/app/applicant/common";
import { DocViewer, type ViewDoc } from "@/app/jupeb/DocViewer";
import { signOut } from "@/lib/sign-out";
import {
  IUT_COOKIE, MAX_DOCUMENT_BYTES, STAGES, applicantWords, applyBody, applyErrors, canSubmit, dayWords, docWords, documentChecklist, documentType, editableFields,
  eventWords, feeClosed, feeWords, fileProblem, formFromView, hasAcknowledgement, mayWithdraw, naira, num, paymentTitle, programmesWithCurrent, sizeWords, stageIndex,
  typedDataUrl, updateBody, withdrawFromRegistry, zeroDue,
  type ApiField, type ApplyField, type ApplyForm, type ChecklistRow, type IutMe, type IutReference, type PublicOptions,
} from "@/lib/transfer-application";
import { ApplyFields } from "../ApplyFields";
import { ME, call } from "../call";

type Load = { kind: "loading" } | { kind: "signin" } | { kind: "none"; problem: Problem } | { kind: "problem"; problem: Problem } | { kind: "ready"; me: IutMe };

const sexWord = (s: string | null | undefined) => (s === "F" ? "Female" : s === "M" ? "Male" : "—");
const val = (v: string | number | null | undefined) => (v === null || v === undefined || v === "" ? "—" : String(v));

function readFile(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result ?? ""));
    r.onerror = () => reject(r.error ?? new Error("The file could not be read"));
    r.readAsDataURL(file);
  });
}

export function TransferPortal({ options }: { options: PublicOptions | null }) {
  const [state, setState] = useState<Load>({ kind: "loading" });
  const [verifying, setVerifying] = useState(false);

  const load = useCallback(async (): Promise<IutMe | null> => {
    const r = await call<IutMe>("GET", ME);
    if (r.ok) { setState({ kind: "ready", me: r.data }); return r.data; }
    if (r.problem.status === 401) setState({ kind: "signin" });
    else if (r.problem.status === 404 || r.problem.status === 403) {
      // no transfer application on this account: a transfer cookie left on this browser by an earlier sign-in would send its home
      // page here again, and "Back to my portal" back to this page — dropped
      document.cookie = `${IUT_COOKIE}=; path=/; max-age=0`;
      setState({ kind: "none", problem: r.problem });
    }
    else setState({ kind: "problem", problem: r.problem });
    return null;
  }, []);

  /* back from a gateway (?paid=<reference>): the payment is verified and the application read again a few times, as a gateway can take
     a moment to settle after its "success" page */
  useEffect(() => {
    const paid = new URLSearchParams(window.location.search).get("paid");
    void (async () => {
      const first = await load();
      if (!paid || first?.fee?.settled) return;
      setVerifying(true);
      try {
        for (let i = 0; i < 6; i++) {
          await call("POST", "/api/bff/api/v1/payments/verify", { reference: paid });
          const m = await load();
          if (m?.fee?.settled) { notify("Your application fee is paid."); break; }
          await new Promise((res) => setTimeout(res, 4000));
        }
      } finally {
        setVerifying(false);
      }
    })();
  }, [load]);

  if (state.kind === "loading") return <Bare><Note kind="info" title="Loading your application…">One moment.</Note></Bare>;
  if (state.kind === "signin") {
    return (
      <Bare>
        <Note kind="info" title="Sign in to see your application">Sign in with the e-mail you applied with, or your application number (IUT/APP/…), and your password.</Note>
        <div className="mt-3"><LinkBtn kind="primary" href="/login?next=/transfer/portal">Sign in</LinkBtn></div>
      </Bare>
    );
  }
  if (state.kind === "none") {
    return (
      <Bare>
        <Note kind="info" title="No inter-university transfer application on this account">This account is not a transfer applicant&rsquo;s. A student of another university applies at the address below.</Note>
        <div className="row mt-3"><LinkBtn kind="primary" href="/transfer/apply">Apply for an inter-university transfer</LinkBtn><LinkBtn kind="ghost" href="/">Back to my portal</LinkBtn></div>
      </Bare>
    );
  }
  if (state.kind === "problem") return <Bare><ProblemNotice problem={state.problem} /></Bare>;
  return <Portal me={state.me} options={options} reload={load} verifying={verifying} />;
}

function Bare({ children }: { children: React.ReactNode }) {
  return <div style={{ maxWidth: 640, margin: "var(--s-6) auto", padding: "0 var(--s-4)" }}>{children}</div>;
}

function Portal({ me, options, reload, verifying }: { me: IutMe; options: PublicOptions | null; reload: () => Promise<IutMe | null>; verifying: boolean }) {
  const name = `${me.applicant?.surname ?? ""}, ${me.applicant?.otherNames ?? ""}`.replace(/^, |, $/g, "");
  const shellMe: ShellMe = { actorId: "", activeOffice: "iutapplicant", offices: ["iutapplicant"], menu: "iutapplicant", name, staffNumber: me.applicationNo, sessionId: null,
    unit: me.applied?.programmeName ?? null, waiting: {} };
  const settled = !!me.fee?.settled;
  const words = applicantWords(me.state, me);
  const idx = stageIndex(me.state);
  const decided = idx === 4;
  const checklist = documentChecklist(me.kinds, me.documents, me.state, settled, zeroDue(me));
  const required = checklist.filter((r) => r.required);
  const uploaded = required.filter((r) => r.status !== "MISSING").length;
  // D5: the programme and level of a draft change only while its session's window is open
  const windowOpen = me.windowStatus ? me.windowStatus === "OPEN" : !!me.openSession && me.openSession === me.session;
  const editable = editableFields(me.state, windowOpen);
  const admissionNo = me.student?.admissionNo ?? me.student?.matricNo ?? null;

  return (
    <Shell route="iut/portal" me={shellMe} sub={`${me.applicationNo} · ${me.session}`}>
      <Note kind={words.tone} title={`${me.applicationNo} · ${me.session} · ${words.stage}`}
        action={me.state === "ADMITTED" ? <Btn kind="primary" onClick={() => signOut("/login")}>Sign in as a student</Btn> : undefined}>
        {words.words}
        {me.state === "ADMITTED" && admissionNo ? <div className="mt-1">Your admission number is <b className="tnum">{admissionNo}</b>. Pay your school fees and register your courses in the student portal.</div> : null}
      </Note>
      {verifying ? <Note kind="info" title="Confirming your payment…">The page updates once the payment reaches the University.</Note> : null}

      <Tiles items={[
        ["Stage", words.stage, me.state === "ADMITTED" ? "var(--green-ink)" : me.state === "REJECTED" ? "var(--red-ink)" : null, me.session],
        feeClosed(me)
          ? ["Application fee", "None", null, "not taken"]
          : ["Application fee", settled ? (me.fee?.basis === "NONE_DUE" ? "None due" : "Paid") : zeroDue(me) ? "None due" : me.fee?.due != null ? naira(me.fee.due) : "—", settled ? "var(--green-ink)" : "var(--chrome)", settled ? "settled" : "to pay"],
        ["Documents", `${uploaded}/${required.length}`, uploaded === required.length ? null : "var(--chrome)", "required, uploaded"],
        me.state === "ADMITTED" && me.student?.level
          ? ["Admitted at", `${me.student.level} Level`, "var(--green-ink)", me.applied?.programmeName ?? me.applied?.programme ?? ""]
          : ["Applied for", me.applied?.level ? `${me.applied.level} Level` : "—", null, me.applied?.programmeName ?? me.applied?.programme ?? ""],
      ]} />

      <Panel title="Where it stands" right={words.stage}>
        <StepList list={STAGES.map(([t, s], i) => [decided || i < idx ? "done" : i === idx ? "now" : "todo", t, s])} />
      </Panel>

      <Particulars me={me} editable={editable} windowOpen={windowOpen} options={options} reload={reload} />
      <FeePanel me={me} reload={reload} />
      <Documents me={me} rows={checklist} reload={reload} />
      <Submit me={me} reload={reload} />

      {hasAcknowledgement(me) ? (
        <Panel title="Acknowledgement" right={me.lastSubmittedAt ? `Submitted ${dayWords(me.lastSubmittedAt)}` : undefined}>
          <PBody>
            <div className="sub2 mb-2">The acknowledgement of your submission, with a QR that opens the University&rsquo;s verification page. It attests that the application was submitted; it is not an admission.</div>
            <div className="row row--inline row--tight">
              <a className="btn btn--primary btn--sm" href="/transfer/portal/acknowledgement?download=1">Download acknowledgement (PDF)</a>
              <a className="btn btn--ghost btn--sm" href="/transfer/portal/acknowledgement" target="_blank" rel="noopener">Print acknowledgement</a>
            </div>
          </PBody>
        </Panel>
      ) : null}

      <History me={me} />
      {mayWithdraw(me.state) ? <Withdraw me={me} reload={reload} /> : withdrawFromRegistry(me.state) ? (
        <Panel title="Withdraw">
          <PBody>
            <div className="sub2">Your application is with the Registry for a decision. To withdraw it now, write to the Registry. The application fee is not refunded
              when an application is withdrawn.</div>
          </PBody>
        </Panel>
      ) : null}
      {me.canApplyAgain ? <ApplyAgain me={me} options={options} reload={reload} /> : null}
      {(me.applications ?? []).length > 1 ? (
        <Panel title="Your applications" right={`${me.applications!.length}`}>
          <DTable cols={["Application", "Session", "Stage"]} rows={me.applications!.map((a) => [
            <span key="n" className="tnum">{a.applicationNo}</span>, <span key="s" className="tnum">{a.session}</span>, <span key="t">{applicantWords(a.state).stage}</span>,
          ])} />
        </Panel>
      ) : null}
    </Shell>
  );
}

/** 1 · the particulars: a summary, and the edit form the state allows */
function Particulars({ me, editable, windowOpen, options, reload }: { me: IutMe; editable: ApiField[]; windowOpen: boolean; options: PublicOptions | null; reload: () => Promise<IutMe | null> }) {
  const [editing, setEditing] = useState<ApplyForm | null>(null);
  const [tried, setTried] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const was = formFromView(me, me.account);
  const sameSession = !!options && (options.session ?? options.window?.session) === me.session;
  // the application's own programme and level stay among the choices when the Office stops new applications on that line, so an edit
  // of anything else is not refused for them (the API re-checks a line only when it changes)
  const programmes = windowOpen && sameSession ? programmesWithCurrent(options?.programmes ?? [], me.applied) : [];
  // the programme and level are checked only where they can be chosen; the university list is the server's to hold the code against
  const only = editable.filter((k) => (k === "programme" || k === "level" ? programmes.length > 0 : true));
  const errors = editing ? applyErrors(editing, { programmes, universities: null, session: me.session, only }) : {};
  const a = me.applicant ?? {}, p = me.previous ?? {}, ap = me.applied ?? {};

  async function save() {
    if (!editing) return;
    setTried(true);
    setProblem(null);
    const first = Object.keys(errors)[0] as ApplyField | undefined;
    if (first) { notifyProblem({ status: 400, title: "The form is not complete", detail: errors[first] ?? "" }); document.getElementById(`te-${first}`)?.focus(); return; }
    const body = updateBody(editing, was, only);
    if (!Object.keys(body).length) { setEditing(null); return; }
    const r = await call("PUT", ME, body);
    if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
    notify("Your particulars are saved.");
    setEditing(null);
    setTried(false);
    await reload();
  }

  return (
    <Panel title="1 · Your particulars" right={editable.length ? (editing ? undefined : <Btn kind="ghost" size="sm" onClick={() => { setEditing(was); setTried(false); setProblem(null); }}>Edit</Btn>) : <span className="sub2">As submitted</span>}>
      <PBody>
        {editing ? (
          <>
            {problem ? <ProblemNotice problem={problem} /> : null}
            {editable.length === 2 ? <div className="sub2 mb-1">Only your e-mail and phone are changed now; the rest is as you submitted it.</div> : null}
            <ApplyFields f={editing} set={(x) => setEditing((e) => (e ? { ...e, ...x } : e))} programmes={programmes} universities={options?.universities ?? []} session={me.session}
              errors={errors} shown={tried} editable={editable} prefix="te" universityLabel={p.universityName ?? null}
              fixedProgramme={`${ap.programmeName ?? ap.programme ?? "—"}${ap.level ? `, ${ap.level} Level` : ""}`} />
            <div className="row mt-2">
              <Btn kind="ghost" onClick={() => { setEditing(null); setProblem(null); }}>Cancel</Btn>
              <span className="grow" />
              <Btn kind="primary" onClick={() => save()}>Save changes</Btn>
            </div>
          </>
        ) : (
          <KvGrid cls="grid--2" pairs={[
            ["Name", `${a.surname ?? ""}, ${a.otherNames ?? ""}`], ["Sex", sexWord(a.sex)], ["Date of birth", dayWords(a.dateOfBirth) || "—"],
            ["JAMB registration number", val(a.jambRegNo)], ["E-mail", val(me.account?.email ?? a.email)], ["Phone", val(me.account?.phone ?? a.phone)],
            ["Present university", p.universityName ?? (p.universityNamed ? `${p.universityNamed} (not on the list)` : "—")], ["Matriculation number there", val(p.matricNo)],
            ["Programme there", val(p.programme)], ["Level there", p.level ? `${p.level} Level` : "—"], ["Session entered there", val(p.entrySession)],
            ["CGPA there", p.cgpa != null && p.cgpa !== "" ? `${num(p.cgpa).toFixed(2)} of ${p.cgpaScale ?? 5}` : "—"],
            ["Programme applied for", val(ap.programmeName ?? ap.programme)], ["Level applied for", ap.level ? `${ap.level} Level` : "—"],
            ["Department", val(ap.deptName ?? ap.dept)], ["Faculty", val(ap.facultyName ?? ap.faculty)],
          ]} />
        )}
        {!editing && me.reason ? <div className="mt-2"><div className="eyebrow">Your reason for transferring</div><div className="sub2" style={{ whiteSpace: "pre-line" }}>{me.reason}</div></div> : null}
      </PBody>
    </Panel>
  );
}

/** 2 · the application fee: none due, paid with its receipt, or a reference to pay */
function FeePanel({ me, reload }: { me: IutMe; reload: () => Promise<IutMe | null> }) {
  const settled = !!me.fee?.settled;
  // a reference is drawn on request: a live one is given back as it is (iut_fee_reference_draw reuses it), a new one is free
  const [ref, setRef] = useState<{ reference: string; amount: number } | null>(null);
  const [checking, setChecking] = useState(false);
  const paid = (me.fee?.references ?? []).filter((r) => r.confirmedAt);

  async function draw() {
    const r = await call<{ settled: boolean; due?: number; reference?: string; amount?: number; expiresAt?: string }>("POST", `${ME}/fee-reference`, {});
    if (!r.ok) { notifyProblem(r.problem); return; }
    if (r.data.settled) { notify("No application fee is due: you can upload your documents."); await reload(); return; }
    if (r.data.reference) setRef({ reference: r.data.reference, amount: num(r.data.amount) });
  }
  async function checkNow() {
    if (!ref) return;
    setChecking(true);
    try {
      await call("POST", "/api/bff/api/v1/payments/verify", { reference: ref.reference });
      const m = await reload();
      if (m?.fee?.settled) notify("Your application fee is paid.");
      else notify("The payment has not reached the University yet. Try again in a few minutes.", "info");
    } finally {
      setChecking(false);
    }
  }

  return (
    <Panel title="2 · Application fee" right={settled ? <Pil kind="ok">{me.fee?.basis === "NONE_DUE" ? "None due" : "Paid"}</Pil> : feeClosed(me) ? <Pil kind="grey">Not taken</Pil>
        : zeroDue(me) ? <Pil kind="info">None due</Pil> : <Pil kind="warn">To pay</Pil>}>
      <PBody>
        <div className="mb-2">{feeWords(me)}</div>
        {!settled && me.state === "DRAFT" ? (
          ref ? (
            <>
              <PayByCard reference={ref.reference} amount={ref.amount} />
              <div className="row mt-2">
                <Btn kind="go" busy={checking} busyLabel="Checking…" onClick={() => checkNow()}>I&rsquo;ve paid — check now</Btn>
                <span className="sub2">Reference <b className="tnum">{ref.reference}</b>; it is good for 24 hours, and a new one is free.</span>
              </div>
            </>
          ) : <Btn kind="primary" onClick={() => draw()}>{zeroDue(me) ? "Confirm that no fee is due" : "Get a payment reference"}</Btn>
        ) : null}
        {paid.map((r: IutReference) => (
          <div key={r.reference} className="mt-3" style={{ borderTop: "1px solid var(--line)", paddingTop: "var(--s-3)" }}>
            <div className="b700 mb-1">{paymentTitle(r, me)}</div>
            <div className="mb-2 sub2">Paid <b>{naira(r.amount)}</b> · <span className="tnum">{r.reference}</span>{r.receiptNo ? ` · receipt ${r.receiptNo}` : ""}{r.confirmedAt ? ` · ${dayWords(r.confirmedAt)}` : ""}{r.channel ? ` · ${r.channel}` : ""}</div>
            <ReceiptCheck reference={r.reference} source={`${ME}/receipts/${encodeURIComponent(r.reference)}`} pdf={`/transfer/portal/receipt/${encodeURIComponent(r.reference)}`} />
          </div>
        ))}
      </PBody>
    </Panel>
  );
}

/** 3 · the documents asked: each checked in the browser for its type and size before it is read and sent */
function Documents({ me, rows, reload }: { me: IutMe; rows: ChecklistRow[]; reload: () => Promise<IutMe | null> }) {
  const [viewing, setViewing] = useState<number | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const picker = useRef<HTMLInputElement>(null);
  const [kind, setKind] = useState<ChecklistRow | null>(null);
  const docs: ViewDoc[] = rows.filter((r) => r.document).map((r) => ({
    key: r.document!.id, label: r.label, sub: docWords(r.status)[0], filename: r.document!.filename, url: `${ME}/documents/${encodeURIComponent(r.document!.id)}`,
  }));
  const settled = !!me.fee?.settled;

  function choose(r: ChecklistRow) {
    setKind(r);
    if (picker.current) { picker.current.value = ""; picker.current.accept = r.imagesAllowed ? "application/pdf,image/jpeg,image/png,.pdf,.jpg,.jpeg,.png" : "application/pdf,.pdf"; picker.current.click(); }
  }
  async function upload(file: File | undefined) {
    if (!file || !kind) return;
    const why = fileProblem({ type: file.type, size: file.size, name: file.name }, kind, MAX_DOCUMENT_BYTES);
    if (why) { notifyProblem({ status: 400, title: `${kind.label}: not uploaded`, detail: why }); return; }
    setBusy(kind.code);
    try {
      const dataUrl = typedDataUrl(await readFile(file), documentType(file));
      const r = await call("POST", `${ME}/documents`, { kind: kind.code, filename: file.name.slice(0, 200), dataUrl });
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`${kind.label}: uploaded`);
      await reload();
    } catch {
      notifyProblem({ status: 400, title: "The file could not be read", detail: "Choose it again, or save it again as a PDF." });
    } finally {
      setBusy(null);
    }
  }
  async function remove(r: ChecklistRow) {
    if (!r.document || !window.confirm(`Remove ${r.document.filename} (${r.label})? You can upload another.`)) return;
    const a = await call("DELETE", `${ME}/documents/${encodeURIComponent(r.document.id)}`);
    if (!a.ok) { notifyProblem(a.problem); return; }
    notify(`${r.label}: removed`);
    await reload();
  }

  return (
    <Panel title="3 · Your documents" right={`PDF, JPEG or PNG · at most ${sizeWords(MAX_DOCUMENT_BYTES)} each`}>
      <input ref={picker} type="file" hidden onChange={(e) => void upload(e.target.files?.[0])} />
      {!settled && (me.state === "DRAFT") ? (zeroDue(me)
        ? <PBody><Note kind="info" title="Confirm the fee first">No application fee is due: confirm it under the application fee, then upload your documents.</Note></PBody>
        : <PBody><Note kind="info" title="Pay the application fee first">Your documents are uploaded once the application fee is paid.</Note></PBody>) : null}
      <DTable cols={["Document", "Status", "File", "|num"]} rows={rows.map((r) => {
        const [word, pill] = docWords(r.status);
        const at = docs.findIndex((d) => d.key === r.document?.id);
        return [
          <span key="d"><b>{r.label}</b> <span className="sub2">{r.required ? "required" : "optional"}</span>{r.hint ? <div className="sub2">{r.hint}</div> : null}
            {!r.imagesAllowed ? <div className="sub2">PDF only</div> : null}</span>,
          <span key="s"><Pil kind={pill}>{word}</Pil>{r.note ? <div className="sub2" style={{ color: "var(--red-ink)" }}>{r.note}</div> : null}</span>,
          <span key="f">{r.document ? <><button type="button" className="lnk" onClick={() => setViewing(at)}>{r.document.filename}</button>
            {r.document.bytes ? <span className="sub2"> · {sizeWords(r.document.bytes)}</span> : null}</> : <span className="sub2">—</span>}</span>,
          <span key="a" className="row row--inline row--tight">
            {r.canUpload ? <Btn kind={r.status === "MISSING" ? "primary" : "ghost"} size="sm" busy={busy === r.code} busyLabel="Uploading…" disabled={busy !== null} onClick={() => choose(r)}>
              {r.status === "MISSING" ? "Upload" : "Replace"}</Btn> : <span className="sub2" title={r.why ?? undefined}>{r.status === "ACCEPTED" ? "" : r.why ?? ""}</span>}
            {r.canRemove ? <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => remove(r)}>Remove</Btn> : null}
          </span>,
        ];
      })} />
      {viewing !== null && docs[viewing] ? <DocViewer docs={docs} index={viewing} onIndex={setViewing} onClose={() => setViewing(null)} /> : null}
    </Panel>
  );
}

/** 4 · the submission, under the declaration */
function Submit({ me, reload }: { me: IutMe; reload: () => Promise<IutMe | null> }) {
  const [declared, setDeclared] = useState(false);
  const open = me.state === "DRAFT" || me.state === "CORRECTION_REQUIRED";
  const reasons = canSubmit(me);
  async function submit() {
    const r = await call("POST", `${ME}/submit`, { declaration: true });
    if (!r.ok) { notifyProblem(r.problem); return; }
    notify("Your application is submitted. The Registry checks your documents next.");
    setDeclared(false);
    await reload();
  }
  return (
    <Panel title="4 · Submit" right={open ? undefined : me.submittedAt ? `Submitted ${dayWords(me.lastSubmittedAt ?? me.submittedAt)}` : undefined}>
      <PBody>
        {open ? (
          <>
            {reasons.length ? (
              <Note kind="info" title="Not ready to submit">
                <ul style={{ margin: 0, paddingLeft: "1.2em" }}>{reasons.map((x) => <li key={x}>{x}</li>)}</ul>
              </Note>
            ) : null}
            <label className="row row--inline row--tight mt-2" htmlFor="tp-declare" style={{ alignItems: "flex-start" }}>
              <input id="tp-declare" type="checkbox" checked={declared} onChange={(e) => setDeclared(e.target.checked)} style={{ marginTop: 3 }} />
              <span>The particulars and documents I have given are true. I understand that a false one ends this application and any admission it leads to.</span>
            </label>
            <div className="row mt-2">
              <Btn kind="primary" size="md" disabled={!declared || reasons.length > 0} title={reasons.length ? reasons.join(" ") : !declared ? "Tick the declaration first" : undefined}
                onClick={() => submit()}>{me.state === "CORRECTION_REQUIRED" ? "Submit again" : "Submit application"}</Btn>
            </div>
          </>
        ) : (
          <div className="sub2">{me.submittedAt ? `Submitted on ${dayWords(me.submittedAt)}${me.lastSubmittedAt && me.lastSubmittedAt !== me.submittedAt ? `, and again on ${dayWords(me.lastSubmittedAt)}` : ""}.` : "Not submitted."}</div>
        )}
      </PBody>
    </Panel>
  );
}

function History({ me }: { me: IutMe }) {
  const rows = me.history ?? [];
  if (!rows.length) return null;
  return (
    <Panel title="History" right={`${rows.length}`}>
      <DTable cols={["When", "What", "Note"]} rows={rows.map((h, i) => [
        <span key={`w${i}`} className="sub2 tnum">{new Date(h.at).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" })}</span>,
        <span key={`a${i}`}>{eventWords(h.action, true)}</span>,
        <span key={`n${i}`} className="sub2">{h.note ?? ""}</span>,
      ])} />
    </Panel>
  );
}

function Withdraw({ me, reload }: { me: IutMe; reload: () => Promise<IutMe | null> }) {
  const [asking, setAsking] = useState(false);
  const [reason, setReason] = useState("");
  async function withdraw() {
    const r = await call("POST", `${ME}/withdraw`, { reason: reason.trim() || null });
    if (!r.ok) { notifyProblem(r.problem); return; }
    notify(`${me.applicationNo} is withdrawn.`);
    setAsking(false);
    await reload();
  }
  return (
    <Panel title="Withdraw">
      <PBody>
        {/* D11: shown until the department has assessed the application; with the Registry for a decision it is asked of the Registry alike */}
        <div className="sub2">You may withdraw your application here until the Head of Department has assessed it; after that, you write to the Registry.
          The application fee is not refunded when an application is withdrawn.</div>
        <div className="mt-2"><Btn kind="ghost" onClick={() => { setAsking(true); setReason(""); }}>Withdraw my application</Btn></div>
      </PBody>
      {asking ? (
        <Modal title={`Withdraw ${me.applicationNo}?`} sub="This cannot be undone: you may apply again in a later window." onClose={() => setAsking(false)}
          foot={<><Btn kind="ghost" onClick={() => setAsking(false)}>Keep it</Btn><span className="grow" /><Btn kind="urgent" onClick={() => withdraw()}>Withdraw</Btn></>}>
          <Field id="tp-withdraw" label="Why (optional)" hint="At most 500 characters">
            <textarea id="tp-withdraw" className="ctl" rows={3} maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} />
          </Field>
        </Modal>
      ) : null}
    </Panel>
  );
}

/** a later window: the last application's particulars filled in, the programme chosen again from those open */
function ApplyAgain({ me, options, reload }: { me: IutMe; options: PublicOptions | null; reload: () => Promise<IutMe | null> }) {
  const [f, setF] = useState<ApplyForm | null>(null);
  const [tried, setTried] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const session = options?.session ?? options?.window?.session ?? me.openSession ?? null;
  const programmes = session && session === me.openSession ? options?.programmes ?? [] : [];
  const universities = options?.universities ?? [];
  const errors = f ? applyErrors(f, { programmes, universities, session, again: true }) : {};
  async function send() {
    if (!f) return;
    setTried(true);
    setProblem(null);
    const first = Object.keys(errors)[0] as ApplyField | undefined;
    if (first) { notifyProblem({ status: 400, title: "The form is not complete", detail: errors[first] ?? "" }); document.getElementById(`tg-${first}`)?.focus(); return; }
    const r = await call<{ applicationNo?: string }>("POST", `${ME}/applications`, applyBody(f, { again: true }));
    if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
    notify(`${r.data.applicationNo ?? "Your new application"}: started.`);
    setF(null);
    await reload();
  }
  return (
    <Panel title="Apply again" right={me.openSession ? `The ${me.openSession} window is open` : undefined}>
      <PBody>
        {!f ? (
          <>
            <div className="sub2">The window for {me.openSession} is open. Your particulars are filled in from this application; choose the programme and level again, and check each one.</div>
            <div className="mt-2"><Btn kind="primary" onClick={() => { setF({ ...formFromView(me, me.account), programme: "", level: "" }); setTried(false); }}>Apply for {me.openSession}</Btn></div>
          </>
        ) : (
          <>
            {problem ? <ProblemNotice problem={problem} /> : null}
            <ApplyFields f={f} set={(x) => setF((y) => (y ? { ...y, ...x } : y))} programmes={programmes} universities={universities} session={session} errors={errors} shown={tried}
              contact={false} prefix="tg" universityLabel={me.previous?.universityName ?? null} />
            <div className="row mt-2">
              <Btn kind="ghost" onClick={() => setF(null)}>Cancel</Btn>
              <span className="grow" />
              <Btn kind="primary" onClick={() => send()}>Start the new application</Btn>
            </div>
          </>
        )}
      </PBody>
    </Panel>
  );
}

