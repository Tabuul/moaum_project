"use client";

/** V766: one online inter-university transfer application, as a desk reads it. The Registry (t/iutapp) checks each document while the
 *  application is submitted (D7), returns it to the applicant or sends it to the Head of Department; after the department's word it
 *  approves a recommended application into the V763 transfer of one (D9: the approver is its preparer, so another officer decides it on
 *  the Inter-University Transfer page), sends it back to the department, or rejects it with words the applicant reads; it puts a
 *  university the applicant named on the list (D16). The Head of Department, or the College Dean (V734), reads it without the contact or
 *  the fee and recommends a level the window opens, or declines with a reason (t/iuthodapp). Each act sends the state it was taken on,
 *  so an application another officer moved meanwhile is refused (IUT_STATE_MOVED) rather than acted on twice. */
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { DocViewer, type ViewDoc } from "@/app/jupeb/DocViewer";
import { ACTION, STATUS, TRANSFER, type Action } from "@/lib/university-transfer";
import {
  KEEPERS, NO_LEVEL_TO_RECOMMEND, STUDENT_HERE, cgpaOf, dayWords, docWords, eventWords, hodMay, naira, officeActions, officeFeePill, officeFeeWords, officeGuidance, officeWords,
  referencePill, sizeWords, studentHere, type ActionButton, type IutDocument, type OfficeDetail,
} from "@/lib/transfer-application";
import { OFFICE, call } from "@/app/transfer/call";

export interface University { code: string; name: string; country?: string | null; active: boolean }
type Desk = "registry" | "hod";

const sexWord = (s: string | null | undefined) => (s === "F" ? "Female" : s === "M" ? "Male" : "—");
const val = (v: string | number | null | undefined) => (v === null || v === undefined || v === "" ? "—" : String(v));
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
const UNIVERSITY_STATES = ["SUBMITTED", "CORRECTION_REQUIRED", "WITH_HOD", "RECOMMENDED", "NOT_RECOMMENDED"];

export function TransferApplicationDetail({ view, desk, office, universities = [], back }: {
  view: OfficeDetail; desk: Desk; office: string | null; universities?: University[]; back: string;
}) {
  const router = useRouter();
  const base = `${OFFICE}/applications/${encodeURIComponent(view.id)}`;
  const [viewing, setViewing] = useState<number | null>(null);
  const [state, label] = [view.state, officeWords(view.state)];
  const a = view.applicant ?? {}, p = view.previous ?? {}, ap = view.applied ?? {};
  const keeper = desk === "registry" && KEEPERS.includes(office ?? "");
  const current = view.documents ?? [];
  const docs: ViewDoc[] = current.map((d) => ({ key: d.id, label: d.label ?? d.kind, sub: docWords(d.status)[0], filename: d.filename, url: `${base}/documents/${encodeURIComponent(d.id)}` }));
  const reason = (what: string) => `${view.applicationNo}: ${what}`;

  async function done(r: { ok: boolean; problem?: unknown }, words: string): Promise<boolean> {
    if (!r.ok) { notifyProblem((r as { problem: Parameters<typeof notifyProblem>[0] }).problem); router.refresh(); return false; }
    notify(words);
    router.refresh();
    return true;
  }

  return (
    <div className="stack">
      <Note kind={label[1] === "bad" ? "bad" : label[1] === "ok" ? "ok" : "info"} title={`${view.applicationNo} · ${a.surname ?? ""}, ${a.otherNames ?? ""}`}
        action={<LinkBtn kind="ghost" href={back}>Back to the list</LinkBtn>}>
        <span className="row row--inline row--tight"><Pil kind={label[1]}>{label[0]}</Pil><span className="sub2">{view.session} · applied for {ap.programmeName ?? ap.programme}{ap.level ? `, ${ap.level} Level` : ""}</span></span>
      </Note>

      {desk === "registry" && state === "APPROVED" && view.transfer ? (
        <Note kind="info" title="Awaiting another officer's decision"
          action={view.transfer.batchId ? <LinkBtn kind="primary" href={`/transfers/inter-university?batch=${encodeURIComponent(view.transfer.batchId)}`}>Open batch {view.transfer.batchRef ?? ""}</LinkBtn> : undefined}>
          Approved{view.registry?.byName ? ` by ${view.registry.byName}` : ""} into the transfer {view.transfer.batchRef ?? ""}. Another officer of the Academic Office or the Registry — not the one who
          approved it — decides it on the Inter-University Transfer page; the applicant is admitted at that decision, and told.
          <div className="mt-1">{officeGuidance(view)}.</div>
        </Note>
      ) : null}
      {state === "ADMITTED" && view.student ? (
        <Note kind="ok" title={`Admitted: ${view.student.admissionNo ?? view.student.matricNo ?? ""}`}
          action={desk === "registry" && view.student.id ? <LinkBtn kind="ghost" href={`/students/${view.student.id}`}>Open the student record</LinkBtn> : undefined}>
          On the register by transfer{view.hod?.level ? ` at ${view.hod.level} Level` : ""}; the matriculation number follows under Matriculation Management.
        </Note>
      ) : null}

      <Panel title="Particulars">
        <PBody>
          <KvGrid cls="grid--3" pairs={[
            ["Name", `${a.surname ?? ""}, ${a.otherNames ?? ""}`], ["Sex", sexWord(a.sex)], ["Date of birth", dayWords(a.dateOfBirth) || "—"],
            ["JAMB registration number", val(a.jambRegNo)],
            ...(desk === "registry" ? [["E-mail", val(a.email)], ["Phone", val(a.phone)]] as [string, string][] : []),
            ["Submitted", view.submittedAt ? dayWords(view.submittedAt) : "Not yet"], ...(view.lastSubmittedAt && view.lastSubmittedAt !== view.submittedAt ? [["Submitted again", dayWords(view.lastSubmittedAt)] as [string, string]] : []),
          ]} />
          {view.reason ? <div className="mt-2"><div className="eyebrow">The applicant&rsquo;s reason for transferring</div><div style={{ whiteSpace: "pre-line" }}>{view.reason}</div></div> : null}
        </PBody>
      </Panel>

      <Panel title="Present university" right={!p.universityCode && p.universityNamed ? <Pil kind="warn">Not on the list</Pil> : p.universityCode ? <span className="sub2 tnum">{p.universityCode}</span> : undefined}>
        <PBody>
          <KvGrid cls="grid--3" pairs={[
            ["University", val(p.universityName ?? p.universityNamed)], ...(p.universityCode && p.universityNamed ? [["As the applicant named it", p.universityNamed] as [string, string]] : []),
            ["Matriculation number there", val(p.matricNo)], ["Programme there", val(p.programme)], ["Level there", p.level ? `${p.level} Level` : "—"],
            ["Session entered there", val(p.entrySession)], ["CGPA there", cgpaOf(p.cgpa, p.cgpaScale)],
          ]} />
          {keeper && UNIVERSITY_STATES.includes(state) ? <SetUniversity base={base} named={p.universityNamed ?? null} code={p.universityCode ?? null} universities={universities} reason={reason} onDone={done} /> : null}
        </PBody>
      </Panel>

      <Panel title="Applied for">
        <PBody>
          <KvGrid cls="grid--3" pairs={[
            ["Programme", `${ap.programmeName ?? ""}${ap.programme ? ` (${ap.programme})` : ""}`], ["Level", ap.level ? `${ap.level} Level` : "—"],
            ["Department", val(ap.deptName ?? ap.dept)], ["Faculty", val(ap.facultyName ?? ap.faculty)], ...(ap.college ? [["College", ap.collegeName ?? ap.college] as [string, string]] : []),
            ["Levels the window opens", (ap.levelsOpen ?? []).length ? (ap.levelsOpen ?? []).map((l) => `${l}`).join(", ") : "—"],
          ]} />
        </PBody>
      </Panel>

      <Documents view={view} base={base} keeper={keeper} docs={docs} onView={setViewing} reason={reason} onDone={done} />
      {viewing !== null && docs[viewing] ? <DocViewer docs={docs} index={viewing} onIndex={setViewing} onClose={() => setViewing(null)} /> : null}

      {desk === "registry" && view.fee ? (
        <Panel title="Application fee" right={<Pil kind={officeFeePill(view)[1]}>{officeFeePill(view)[0]}</Pil>}>
          <PBody><div>{officeFeeWords(view)}</div></PBody>
          {(view.fee.references ?? []).length ? (
            <DTable cols={["Reference", "Amount|num", "Confirmed", "Receipt", "Channel", ""]} rows={(view.fee.references ?? []).map((r) => [
              <span key="r" className="tnum">{r.reference}</span>, <span key="a" className="tnum">{naira(r.amount)}</span>,
              <span key="c" className="sub2">{r.confirmedAt ? dayWords(r.confirmedAt) : `Not paid${r.expiresAt ? `; good until ${when(r.expiresAt)}` : ""}`}</span>,
              <span key="n" className="tnum">{r.receiptNo ?? "—"}</span>, <span key="h" className="sub2">{r.channel ?? ""}</span>,
              referencePill(r) ? <Pil key="o" kind={referencePill(r)![1]}>{referencePill(r)![0]}</Pil> : <span key="o" />,
            ])} />
          ) : null}
        </Panel>
      ) : null}

      {desk === "registry" && view.transferCheck ? <TransferCheckPanel check={view.transferCheck} /> : null}

      <HodPanel view={view} desk={desk} office={office} base={base} reason={reason} onDone={done} />

      {desk === "registry" && view.registry?.at ? (
        <Panel title="The Registry's last word">
          <PBody>
            <KvGrid cls="grid--3" pairs={[["By", `${view.registry.byName ?? "—"}${view.registry.office ? ` (${view.registry.office})` : ""}`], ["On", when(view.registry.at)],
              ["Approval reference", val(view.registry.approvalRef)]]} />
            {view.registry.note ? <div className="mt-1" style={{ whiteSpace: "pre-line" }}>{view.registry.note}</div> : null}
          </PBody>
        </Panel>
      ) : null}
      {desk === "registry" && view.transfer?.status ? (
        <Panel title="The transfer" right={TRANSFER[view.transfer.status as "COMPLETED"] ? <Pil kind={TRANSFER[view.transfer.status as "COMPLETED"][1]}>{TRANSFER[view.transfer.status as "COMPLETED"][0]}</Pil> : undefined}>
          <PBody>
            <KvGrid cls="grid--3" pairs={[["Batch", val(view.transfer.batchRef)], ["Prepared by", val(view.transfer.preparedByName)],
              ["Decided on", view.transfer.batchId ? <Link key="b" className="lnk" href={`/transfers/inter-university?batch=${encodeURIComponent(view.transfer.batchId)}`}>Inter-University Transfer</Link> : "—"]]} />
          </PBody>
        </Panel>
      ) : null}

      {keeper ? <Actions view={view} office={office} base={base} reason={reason} onDone={done} /> : null}
      <History view={view} />
    </div>
  );
}

type Done = (r: { ok: boolean; problem?: unknown }, words: string) => Promise<boolean>;

function Documents({ view, base, keeper, docs, onView, reason, onDone }: { view: OfficeDetail; base: string; keeper: boolean; docs: ViewDoc[]; onView: (i: number) => void;
  reason: (w: string) => string; onDone: Done }) {
  const [rejecting, setRejecting] = useState<IutDocument | null>(null);
  const [note, setNote] = useState("");
  const reviewing = keeper && view.state === "SUBMITTED";
  const current = view.documents ?? [];
  const superseded = view.superseded ?? [];
  async function review(d: IutDocument, verdict: "ACCEPTED" | "REJECTED", n: string | null) {
    const r = await call("POST", `${base}/documents/${encodeURIComponent(d.id)}/review`, { verdict, note: n }, reason(`${d.label ?? d.kind} ${verdict.toLowerCase()}`));
    if (await onDone(r, `${d.label ?? d.kind}: ${verdict === "ACCEPTED" ? "accepted" : "rejected"}`)) { setRejecting(null); setNote(""); }
  }
  return (
    <Panel title="Documents" right={<a className="btn btn--ghost btn--sm" href={`${base}/documents.pdf`} target="_blank" rel="noopener">All documents as one PDF</a>}>
      {reviewing ? <PBody><div className="sub2">Accept each document, or reject it with a note the applicant reads; then send the application to the Head of Department, or return it to the applicant to replace the ones rejected.</div></PBody> : null}
      {current.length ? (
        <DTable cols={["Document", "File", "Uploaded", "Status", "|num"]} rows={current.map((d, i) => {
          const [w, pill] = docWords(d.status);
          return [
            <span key="d"><b>{d.label ?? d.kind}</b>{d.required ? <span className="sub2"> required</span> : null}</span>,
            <span key="f"><button type="button" className="lnk" onClick={() => onView(docs.findIndex((x) => x.key === d.id) >= 0 ? docs.findIndex((x) => x.key === d.id) : i)}>{d.filename}</button>
              {d.bytes ? <span className="sub2"> · {sizeWords(d.bytes)}</span> : null}</span>,
            <span key="u" className="sub2">{when(d.uploadedAt)}</span>,
            <span key="s"><Pil kind={pill}>{w}</Pil>{d.note ? <div className="sub2">{d.note}</div> : null}</span>,
            reviewing ? (
              <span key="x" className="row row--inline row--tight">
                {d.status !== "ACCEPTED" ? <Btn kind="ghost" size="sm" onClick={() => review(d, "ACCEPTED", null)}>Accept</Btn> : null}
                {d.status !== "REJECTED" ? <Btn kind="ghost" size="sm" onClick={() => { setRejecting(d); setNote(""); }}>Reject</Btn> : null}
              </span>
            ) : <span key="x" />,
          ];
        })} />
      ) : <PBody><div className="sub2">No document uploaded.</div></PBody>}
      {superseded.length ? (
        <PBody>
          <details><summary className="sub2">Documents replaced or removed ({superseded.length})</summary>
            <DTable cols={["Document", "File", "Uploaded", "Status", "Replaced"]} rows={superseded.map((d) => [
              <span key="d">{d.label ?? d.kind}</span>, <span key="f" className="tnum">{d.filename}</span>, <span key="u" className="sub2">{when(d.uploadedAt)}</span>,
              <span key="s"><Pil kind={docWords(d.status)[1]}>{docWords(d.status)[0]}</Pil>{d.note ? <div className="sub2">{d.note}</div> : null}</span>,
              <span key="r" className="sub2">{when(d.supersededAt)}</span>,
            ])} />
          </details>
        </PBody>
      ) : null}
      {rejecting ? (
        <Modal title={`Reject ${rejecting.label ?? rejecting.kind}`} sub={rejecting.filename} onClose={() => setRejecting(null)}
          foot={<><Btn kind="ghost" onClick={() => setRejecting(null)}>Cancel</Btn><span className="grow" /><Btn kind="urgent" disabled={note.trim().length < 10} onClick={() => review(rejecting, "REJECTED", note.trim())}>Reject</Btn></>}>
          <Field id="ir-note" label="What is wrong with it" required hint="Ten to 1,000 characters; the applicant reads it beside the document">
            <textarea id="ir-note" className="ctl" rows={3} maxLength={1000} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
        </Modal>
      ) : null}
    </Panel>
  );
}

function SetUniversity({ base, named, code, universities, reason, onDone }: { base: string; named: string | null; code: string | null; universities: University[];
  reason: (w: string) => string; onDone: Done }) {
  const [chosen, setChosen] = useState("");
  const [adding, setAdding] = useState<{ code: string; name: string; country: string } | null>(null);
  const active = universities.filter((u) => u.active);
  async function set(c: string) {
    const r = await call("POST", `${base}/university`, { code: c }, reason(`university set to ${c}`));
    await onDone(r, `The university is set: ${c}`);
  }
  async function addAndSet() {
    if (!adding) return;
    const c = adding.code.trim().toUpperCase();
    const r = await call("POST", "/api/bff/api/v1/transfers/inter-university/universities", { code: c, name: adding.name.trim(), country: adding.country.trim() || null, active: true },
      `University added: ${c}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    setAdding(null);
    await set(c);
  }
  if (code && !named) return null;
  return (
    <div className="mt-2" style={{ borderTop: "1px solid var(--line)", paddingTop: "var(--s-2)" }}>
      <div className="eyebrow mb-1">{code ? "Change the university" : "Set the university from the list"}</div>
      {!code ? <div className="sub2 mb-1">The applicant named a university not on the list{named ? `: “${named}”` : ""}. It is approved only once a university from the list is set.</div> : null}
      {adding ? (
        <div className="row row--inline row--tight" style={{ flexWrap: "wrap", alignItems: "flex-end" }}>
          <Field id="iu-acode" label="Code" hint="Capital letters and digits"><input id="iu-acode" className="ctl tnum" style={{ maxWidth: 130 }} maxLength={16} value={adding.code} onChange={(e) => setAdding({ ...adding, code: e.target.value.toUpperCase() })} /></Field>
          <Field id="iu-aname" label="Name"><input id="iu-aname" className="ctl" style={{ minWidth: 260 }} maxLength={200} value={adding.name} onChange={(e) => setAdding({ ...adding, name: e.target.value })} /></Field>
          <Field id="iu-acountry" label="Country"><input id="iu-acountry" className="ctl" style={{ maxWidth: 140 }} maxLength={80} value={adding.country} onChange={(e) => setAdding({ ...adding, country: e.target.value })} /></Field>
          <Btn kind="primary" disabled={adding.code.trim().length < 2 || adding.name.trim().length < 3} onClick={() => addAndSet()}>Add to the list and set it</Btn>
          <Btn kind="ghost" onClick={() => setAdding(null)}>Cancel</Btn>
        </div>
      ) : (
        <div className="row row--inline row--tight" style={{ flexWrap: "wrap", alignItems: "flex-end" }}>
          <Field id="iu-set" label="University" style={{ minWidth: 300 }}>
            <SearchSelect id="iu-set" value={chosen} onChange={setChosen} placeholder="Choose from the list…" options={active.map((u) => ({ value: u.code, label: u.name, sub: u.code }))} />
          </Field>
          <Btn kind="primary" disabled={!chosen} onClick={() => set(chosen)}>Set university</Btn>
          <Btn kind="ghost" onClick={() => setAdding({ code: "", name: named ?? "", country: "Nigeria" })}>Add to the list</Btn>
        </div>
      )}
    </div>
  );
}

function TransferCheckPanel({ check }: { check: NonNullable<OfficeDetail["transferCheck"]> }) {
  const s = STATUS[check.status as "VALID"] ?? null;
  const problems = check.problems ?? [], warnings = check.warnings ?? [];
  return (
    <Panel title="What the transfer check says" right={s ? <Pil kind={s[1]}>{s[0]}</Pil> : undefined}>
      <PBody>
        <div className="sub2 mb-1">The check the Inter-University Transfer Form runs, on the transfer this application would register: whether the student is already on the register,
          a transfer under the number is waiting, the university is on the list, the name matches.</div>
        {check.action && check.status !== "INVALID" ? <div className="mb-1">The decision would make: <b>{ACTION[check.action as Action] ?? check.action}</b>{check.student ? ` (${check.student})` : ""}</div> : null}
        {studentHere(check) ? <Note kind="bad" title="Not approved online">{STUDENT_HERE}.</Note> : null}
        {problems.length ? <Note kind="bad" title="Problems"><ul style={{ margin: 0, paddingLeft: "1.2em" }}>{problems.map((x) => <li key={x.code}>{x.text || x.code}</li>)}</ul></Note> : null}
        {warnings.length ? <Note kind="info" title="Points to look at"><ul style={{ margin: 0, paddingLeft: "1.2em" }}>{warnings.map((x) => <li key={x.code}>{x.text || x.code}</li>)}</ul></Note> : null}
        {!problems.length && !warnings.length ? <div className="sub2">Nothing stands in the way.</div> : null}
      </PBody>
    </Panel>
  );
}

function HodPanel({ view, desk, office, base, reason, onDone }: { view: OfficeDetail; desk: Desk; office: string | null; base: string; reason: (w: string) => string; onDone: Done }) {
  const levels = view.applied?.levelsOpen ?? [];
  const [accept, setAccept] = useState<boolean | null>(null);
  const [level, setLevel] = useState(String(view.applied?.level && levels.includes(view.applied.level) ? view.applied.level : levels[0] ?? ""));
  const [note, setNote] = useState("");
  const h = view.hod ?? null;
  const may = desk === "hod" && hodMay(view, office);
  async function recommend() {
    if (accept === null) return;
    const r = await call("POST", `${base}/recommend`, { accept, level: accept ? Number(level) : null, note: note.trim() || null, expectedState: view.state },
      reason(accept ? `recommended for ${level} Level` : "not recommended"));
    if (await onDone(r, accept ? `Recommended for ${level} Level: the Registry decides next` : "Not recommended: the Registry decides next")) { setAccept(null); setNote(""); }
  }
  if (!may && !h?.decision) {
    return desk === "hod" ? (
      <Panel title="Recommendation"><PBody><div className="sub2">{view.state === "WITH_HOD" ? "Recommended by the Head of Department of the programme, or the College Dean." : "Not with the department now."}</div></PBody></Panel>
    ) : null;
  }
  return (
    <Panel title={desk === "hod" ? "Your recommendation" : "The Head of Department's recommendation"}>
      {h?.decision ? (
        <PBody>
          <KvGrid cls="grid--3" pairs={[
            ["Recommendation", h.decision === "ACCEPT" ? <Pil key="d" kind="ok">{`Accept at ${h.level ?? "—"} Level`}</Pil> : <Pil key="d" kind="bad">Decline</Pil>],
            ["By", `${h.byName ?? "—"}${h.office ? ` (${h.office})` : ""}`], ["On", when(h.at)],
          ]} />
          {h.note ? <div className="mt-1" style={{ whiteSpace: "pre-line" }}>{h.note}</div> : null}
        </PBody>
      ) : null}
      {may ? (
        <PBody>
          <div className="sub2 mb-1">Assess the applicant&rsquo;s standing at their present university: accept them at a level the window opens for the programme, or decline with a reason. The Registry decides after you; the applicant is not told your recommendation.</div>
          <div className="row row--inline" role="radiogroup" aria-label="Recommendation" style={{ gap: 16 }}>
            <label className="row row--inline row--tight"><input type="radio" name="ih-accept" checked={accept === true} onChange={() => setAccept(true)} /> Accept</label>
            <label className="row row--inline row--tight"><input type="radio" name="ih-accept" checked={accept === false} onChange={() => setAccept(false)} /> Decline</label>
          </div>
          {accept === true && !levels.length ? <div className="sub2 mt-1">{NO_LEVEL_TO_RECOMMEND}.</div> : null}
          {accept === true ? (
            <div className="grid grid--2 mt-1">
              <Field id="ih-level" label="Level the student comes into" required hint={`Applied for ${view.applied?.level ?? "—"} Level`}>
                <select id="ih-level" className="ctl" value={level} onChange={(e) => setLevel(e.target.value)}>
                  {levels.map((l) => <option key={l} value={l}>{l} Level</option>)}
                </select>
              </Field>
              <Field id="ih-anote" label="Assessment note" hint="Optional: courses to make up, credits recognised">
                <textarea id="ih-anote" className="ctl" rows={2} maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} />
              </Field>
            </div>
          ) : accept === false ? (
            <Field id="ih-dnote" label="Why the applicant is not recommended" required hint="Ten characters or more; for the Registry">
              <textarea id="ih-dnote" className="ctl" rows={2} maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} />
            </Field>
          ) : null}
          {accept !== null ? (
            <div className="row mt-2">
              <Btn kind={accept ? "go" : "urgent"} disabled={accept ? !level : note.trim().length < 10} onClick={() => recommend()}>{accept ? "Recommend" : "Decline"}</Btn>
            </div>
          ) : null}
        </PBody>
      ) : null}
    </Panel>
  );
}

function Actions({ view, office, base, reason, onDone }: { view: OfficeDetail; office: string | null; base: string; reason: (w: string) => string; onDone: Done }) {
  const acts = officeActions(view, office);
  const [asking, setAsking] = useState<ActionButton | null>(null);
  const [note, setNote] = useState("");
  const [approvalRef, setApprovalRef] = useState("");
  if (!acts.length) return null;
  async function run(b: ActionButton) {
    if (b.action === "APPROVE") {
      const r = await call<{ batchId?: string; batchRef?: string }>("POST", `${base}/approve`, { approvalRef: approvalRef.trim() || null, note: note.trim() || null, expectedState: view.state },
        reason(`approved${approvalRef.trim() ? ` under ${approvalRef.trim()}` : ""}`));
      if (await onDone(r, r.ok ? `Approved: ${(r.data as { batchRef?: string }).batchRef ?? "the transfer"} waits for another officer's decision` : "")) setAsking(null);
      return;
    }
    const r = await call("POST", `${base}/act`, { action: b.action, note: note.trim() || null, expectedState: view.state }, reason(`${b.label.toLowerCase()}${note.trim() ? `: ${note.trim()}` : ""}`));
    if (await onDone(r, `${b.label}: done`)) { setAsking(null); setNote(""); }
  }
  return (
    <Panel title="The Registry's decision" right={officeWords(view.state)[0]}>
      <PBody>
        <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
          {acts.map((b) => (
            <span key={b.action} title={b.why ?? undefined}>
              <Btn kind={b.kind} disabled={!b.enabled} onClick={() => { setNote(""); setApprovalRef(""); if (b.note === "none" && b.action !== "APPROVE") { if (window.confirm(`${b.label}?`)) void run(b); } else setAsking(b); }}>{b.label}</Btn>
            </span>
          ))}
        </div>
        {acts.filter((b) => !b.enabled && b.why).map((b) => <div key={b.action} className="sub2 mt-1">{b.label}: {b.why}.</div>)}
        {acts.filter((b) => b.enabled && b.warning).map((b) => <div key={`w-${b.action}`} className="sub2 mt-1"><b>{b.label}:</b> {b.warning}.</div>)}
        {officeGuidance(view) ? <div className="sub2 mt-1">{officeGuidance(view)}.</div> : null}
      </PBody>
      {asking ? (
        <Modal title={asking.label} sub={`${view.applicationNo} · ${officeWords(view.state)[0]}`} onClose={() => setAsking(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsking(null)}>Cancel</Btn><span className="grow" />
            <Btn kind={asking.kind} disabled={note.trim().length < asking.noteMin} onClick={() => run(asking)}>{asking.label}</Btn></>}>
          {asking.action === "APPROVE" ? (
            <>
              <div className="sub2 mb-1">The approval registers the transfer of one student (incoming, at {view.hod?.level ?? "the recommended"} Level) exactly as the Inter-University Transfer Form
                does. You become its preparer: another officer decides it.</div>
              <Field id="ia-ref" label="Approval reference" hint="The Senate minute or memo number (optional)">
                <input id="ia-ref" className="ctl" maxLength={120} value={approvalRef} onChange={(e) => setApprovalRef(e.target.value)} />
              </Field>
            </>
          ) : null}
          {asking.warning ? <Note kind="bad" title={`${asking.warning}.`} /> : null}
          <Field id="ia-note" label={asking.noteLabel || "Note"} required={asking.note === "required"}>
            <textarea id="ia-note" className="ctl" rows={3} maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
        </Modal>
      ) : null}
    </Panel>
  );
}

function History({ view }: { view: OfficeDetail }) {
  const rows = view.history ?? [];
  if (!rows.length) return null;
  return (
    <Panel title="History" right={`${rows.length}`}>
      <DTable cols={["When", "What", "State", "Note", "By"]} rows={rows.map((h, i) => [
        <span key={`w${i}`} className="sub2 tnum">{when(h.at)}</span>,
        <span key={`a${i}`}>{eventWords(h.action)}</span>,
        <span key={`s${i}`} className="sub2">{h.fromState && h.toState && h.fromState !== h.toState ? `${officeWords(h.fromState)[0]} → ${officeWords(h.toState)[0]}` : ""}</span>,
        <span key={`n${i}`} className="sub2" style={{ whiteSpace: "pre-line" }}>{h.note ?? ""}</span>,
        <span key={`b${i}`} className="sub2">{h.byName ?? ""}{h.office ? ` (${h.office})` : ""}</span>,
      ])} />
    </Panel>
  );
}
