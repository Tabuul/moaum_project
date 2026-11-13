"use client";

/**
 * One preliminary or proficiency application, opened on the desk (V446, V701 every route): the O'Level eligibility screen — the general requirement, the
 * candidate's result as the backend read it, the completion remediation — the results by sitting, the details, the documents
 * (each viewed and accepted, or rejected with the reason the applicant reads), the payments, and the review: taken up, sent back
 * for a correction, the O'Level verified (or found invalid), recommended by the Office, approved by someone else, not admitted
 * or rejected with the reason; the target (with its specialisation) or certificate course changed with a reason; the remediation recorded as it progresses. Every
 * step is the server's to allow: a refusal comes back with its reason.
 * V737: what the application still needs; where an application came from the old portal (its old number, the day it was made,
 * the upload), its old-portal fee and the Bursary's word on it; the programme changes between the two preliminary routes; and the
 * Director of ICT's change of programme.
 */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ACTION, ELIGIBILITY, REMEDIATION, STATE, TARGET_NOTE, VERIFICATION, labelOf, naira, pcall, remediationWords, when, type PrelimBlock, type PrelimLegacy } from "@/lib/preliminary";
import { FEE_STATE, PAYMENT, feeAmountWords, legacyFeeOf, routeChangeOf, wordOf } from "@/lib/prelim-migration";
import { PrelimProgrammeChange } from "@/components/preliminary/PrelimProgrammeChange";

interface Detail {
  application: { id: string; application_no: string; session: string; surname: string; other_names: string; sex: string | null; email?: string; phone?: string;
                 created_at: string; fee_confirmed_at: string | null; decision: string | null; decision_note: string | null; decision_released_at: string | null; next_of_kin?: string | null };
  preliminary: PrelimBlock;
  documents: { id: string; kind: string; label: string; filename: string; content_type: string; bytes: number; uploaded_at: string; status: string; review_note: string | null }[];
  payments: { reference: string; kind: string; amount: number; generated_at: string; expires_at: string; confirmed_at: string | null; receipt_no: string | null; channel: string | null }[];
  letter: { number: string; version: number; issued_on: string } | null;
  /* V737: where an application brought from the old portal came from, its old-portal fees, the programme changes, and whether the reader changes the programme */
  legacy?: PrelimLegacy | null; legacyFees?: Record<string, unknown>[]; routeChanges?: Record<string, unknown>[]; mayChangeProgramme?: boolean;
}

export function PrelimDetail({ id, may, programme, onClose }: { id: string; may: { review: boolean; decide: boolean; recommend: boolean }; programme?: string; onClose: (changed: boolean) => void }) {
  const [d, setD] = useState<Detail | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [note, setNote] = useState("");
  const [target, setTarget] = useState("");
  const [spec, setSpec] = useState("");
  const [rem, setRem] = useState("");
  const [changed, setChanged] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [changing, setChanging] = useState(false);
  const [version, setVersion] = useState(0);
  useEffect(() => {
    let live = true;
    void pcall<Detail>(`/api/v1/admissions/preliminary/applications/${id}`).then((r) => {
      if (!live) return;
      if (r.ok) { setD(r.data); setTarget(r.data.preliminary.targetId ?? ""); setSpec(r.data.preliminary.specialisationId ?? ""); setRem(r.data.preliminary.remediation.status ?? ""); } else setProblem(r.problem);
    });
    return () => { live = false; };
  }, [id, version]);

  async function post(key: string, path: string, body: unknown, reason: string) {
    setBusy(key);
    try {
      const r = await pcall<Detail>(`/api/v1/admissions/preliminary/applications/${id}${path}`, "POST", body, reason);
      if (!r.ok) { notifyProblem(r.problem); return false; }
      setD(r.data); setChanged(true); notify(reason);
      return true;
    } finally { setBusy(null); }
  }
  const act = (action: string, needsNote: boolean, word: string) => {
    if (needsNote && !note.trim()) { notifyProblem({ status: 422, title: "Write the reason or what is asked in the note first" }); return; }
    void post(action, "/act", { action, note: note.trim() || null }, word).then((ok) => { if (ok) setNote(""); });
  };

  if (problem) return <Modal title="The application could not be opened" onClose={() => onClose(false)}><ProblemNotice problem={problem} /></Modal>;
  if (!d) return <Modal title="Opening the application…" onClose={() => onClose(false)}><div className="sub2">One moment.</div></Modal>;
  const p = d.preliminary;
  const a = d.application;
  const rules = p.programmeInfo.rules;
  const elig = p.eligibility;
  const [ew, ek] = labelOf(ELIGIBILITY, elig.status);
  const st = p.state;
  const field = (f: string) => p.fields.find((x) => x.field === f)?.value ?? "—";
  const published = !!a.decision_released_at;
  const info = p.programmeInfo;
  const attempted = rules.kind === "ATTEMPTED_CERTIFICATE";
  const course = p.targetKind === "COURSE" || (info.targets.length > 0 && info.targets.every((t) => t.kind === "COURSE"));
  const chosen = info.targets.find((t) => t.id === target) ?? null;
  const area = info.targets.find((t) => t.id === p.targetId) ?? null;
  const legacy = d.legacy ?? p.legacy ?? null;
  const oldFees = (d.legacyFees ?? []).map(legacyFeeOf);
  const changes = (d.routeChanges ?? []).map(routeChangeOf);
  const decided = ["APPROVED", "ADMITTED", "NOT_ADMITTED", "REJECTED", "WITHDRAWN"].includes(st);
  // the change of programme in place of the application (one dialog at a time), back to it when done
  if (changing) {
    return <PrelimProgrammeChange applicationId={id} fromRoute={p.route} applicant={{ name: `${a.surname}, ${a.other_names}`, applicationNo: a.application_no, legacyNo: legacy?.number ?? null }}
      onClose={(done) => { setChanging(false); if (done) { setChanged(true); setVersion((v) => v + 1); } }} />;
  }

  return (
    <Modal wide title={`${a.surname}, ${a.other_names} · ${a.application_no}`} sub={`${info.name || programme} · ${a.session} · ${labelOf(STATE, st)[0]}${published ? " (published)" : ""}`}
      onClose={() => onClose(changed)}
      foot={<>
        {d.mayChangeProgramme ? <Btn kind="secondary" disabled={busy !== null} onClick={() => setChanging(true)}>Change application programme</Btn> : null}
        <a className="btn btn--ghost btn--sm" href={`/applicant/preliminary/pdf/form?id=${id}`} target="_blank" rel="noopener">Print the application form</a>
        <Btn kind="secondary" onClick={() => onClose(changed)}>Close</Btn>
      </>}>
      {p.problems.length && !decided ? (
        <Note kind="info" title="What the application still needs">
          <ul>{p.problems.map((x, i) => <li key={`${x.step}-${x.field}-${i}`}>{x.message}</li>)}</ul>
        </Note>
      ) : null}
      {p.feeHeld ? <Note kind="info" title="Application fee held for the Bursary">{p.feeHeld}</Note> : null}
      <h3 className="h4">{attempted ? "Entry requirement" : "O’Level eligibility"}</h3>
      <div className="grid grid--2">
        <div className="card" style={{ padding: 10 }}>
          <div className="eyebrow">General requirement</div>
          {attempted ? <KvGrid cls="grid--2" pairs={[["Requirement", info.entryRequirement ?? "An attempted secondary school certificate"], ["Accepted", rules.qualifications.map((q) => q.label).join(", ") || "—"]]} />
            : <KvGrid cls="grid--2" pairs={[["Minimum credits", `${rules.minCredits} (${rules.creditGrade} or better)`], ["Maximum sittings", String(rules.maxSittings)],
            ...(rules.requiredSubjects.length ? [["Required credits", rules.requiredSubjects.join(", ")] as [string, string]] : []),
            ["Minimum credits in the subjects", String(area?.minCoreCredits ?? rules.minCoreCredits)],
            ["Subjects", (rules.coreByTarget ? area?.coreSubjects ?? [] : rules.coreSubjects).join(", ") || (rules.coreByTarget ? `those of the ${info.groupWord} chosen` : "—")], ["Awaiting result", "Not accepted"]]} />}
        </div>
        <div className="card" style={{ padding: 10 }}>
          <div className="eyebrow">Candidate result</div>
          <KvGrid cls="grid--2" pairs={[["Total credits", elig.totalCredits < 0 ? "—" : String(elig.totalCredits)], ["Credits in the subjects", elig.coreCredits < 0 ? "—" : `${elig.coreCredits}${elig.creditedCore.length ? ` (${elig.creditedCore.join(", ")})` : ""}`],
            ["Sittings", String(elig.sittings)], ["O'Level verification", labelOf(VERIFICATION, p.olevelVerification)[0]]]} />
          <div className="row row--inline row--tight mt-1"><b>Status</b><Pil kind={ek as "ok"}>{ew}</Pil></div>
          <div className="mt-1"><b>Programme completion remediation:</b> {p.remediation.status ? `${labelOf(REMEDIATION, p.remediation.status)[0]}${p.remediation.status !== "NOT_REQUIRED" && (p.remediation.subjects.length || p.remediation.creditsShort) ? ` — ${remediationWords(p.remediation)}` : ""}` : "—"}</div>
          {elig.reasons.length ? <ul className="sub2">{elig.reasons.map((x) => <li key={x}>{x}</li>)}</ul> : null}
        </div>
      </div>

      <h3 className="h4 mt-2">{attempted ? "Examination results" : "O’Level results"}</h3>
      <DTable noPrint pageSize={0} cols={["Sitting", "Body", "Examination", "Number", "Year", "Subject", "Grade"]} rows={p.olevel.map((o) => [o.sitting, o.exam_body, o.exam_type ?? "—", o.exam_number, o.exam_year, o.subject, o.grade])} />
      {may.review && ["SUBMITTED", "UNDER_REVIEW", "RECOMMENDED"].includes(st) ? (
        <div className="row row--inline row--tight mt-1">
          <Btn kind="primary" size="sm" disabled={busy !== null} onClick={() => void post("ver", "/verify-olevel", { outcome: "VERIFIED", note: note.trim() || null }, "O'Level verified")}>Verify the O&rsquo;Level</Btn>
          <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => { if (!note.trim()) { notifyProblem({ status: 422, title: "Write what was found in the note first" }); return; } void post("inv", "/verify-olevel", { outcome: "INVALID", note: note.trim() }, "O'Level recorded as invalid"); }}>Record it as invalid</Btn>
        </div>
      ) : null}

      <h3 className="h4 mt-2">Applicant</h3>
      <KvGrid cls="grid--3" pairs={[["Sex", a.sex === "F" ? "Female" : a.sex === "M" ? "Male" : "—"], ["Date of birth", field("date_of_birth")], ["State of origin / LGA", `${field("state_of_origin")} / ${field("lga")}`],
        ["Nationality", field("nationality")], ["Address", field("home_address")], ["Next of kin", a.next_of_kin ?? `${field("kin_name")} (${field("kin_relationship")})`],
        ...(a.email ? [["Email", a.email] as [string, string], ["Phone", a.phone ?? "—"] as [string, string]] : []), ["Started", when(a.created_at)], ["Submitted", p.submittedAt ? when(p.submittedAt) : "not yet"]]} />

      {legacy ? (
        <>
          <h3 className="h4 mt-2">Old portal</h3>
          <KvGrid cls="grid--3" pairs={[["Old application number", legacy.number], ["Applied on the old portal", legacy.appliedOn ?? "—"],
            ["Upload", legacy.batchReference ? `${legacy.batchReference}${legacy.migratedAt ? ` · ${when(legacy.migratedAt)}` : ""}` : "—"],
            ...(legacy.migratedBy ? [["Brought across by", `${legacy.migratedBy}${legacy.migratedOffice ? ` (${legacy.migratedOffice})` : ""}`] as [string, string]] : []),
            ...(legacy.programmeAsWritten ? [["Programme as the old portal wrote it", legacy.programmeAsWritten] as [string, string]] : []),
            ...(legacy.status || legacy.admission ? [["Old portal's status", [legacy.status, legacy.admission].filter(Boolean).join(" · ")] as [string, string]] : [])]} />
        </>
      ) : null}

      <h3 className="h4 mt-2">{course ? "Certificate course" : info.targetWord.charAt(0).toUpperCase() + info.targetWord.slice(1)}</h3>
      {course ? null : <div className="sub2 mb-1">{info.targetNote ?? TARGET_NOTE}</div>}
      <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
        <b>{p.targetName ?? "not chosen"}{p.specialisationName ? ` — ${p.specialisationName}` : ""}</b>{p.targetGroup && p.targetGroup !== p.targetName ? <span className="sub2">{p.targetGroup}</span> : null}
        {may.review && !published && st !== "WITHDRAWN" ? (
          <>
            <div style={{ minWidth: 280 }}><SearchSelect id="pd-target" value={target} onChange={(t) => { setTarget(t); setSpec(""); }} options={info.targets.map((t) => ({ value: t.id, label: t.name, sub: t.group }))} /></div>
            {chosen?.specialisations.length ? <div style={{ minWidth: 220 }}><SearchSelect id="pd-spec" value={spec} onChange={setSpec} placeholder="Specialisation"
              options={chosen.specialisations.map((x) => ({ value: x.id, label: x.name }))} /></div> : null}
            <Btn kind="ghost" size="sm" disabled={busy !== null || !target || (target === p.targetId && (spec || null) === p.specialisationId) || (!!chosen?.specialisations.length && !spec)}
              onClick={() => { if (!note.trim()) { notifyProblem({ status: 422, title: "Write the reason for the change in the note first" }); return; } void post("target", "/target", { targetId: target, specialisationId: spec || null, note: note.trim() }, course ? "Certificate course changed" : "Target changed"); }}>
              {course ? "Change the course" : "Change the target"}</Btn>
          </>
        ) : null}
      </div>

      <h3 className="h4 mt-2">Documents</h3>
      <DTable noPrint pageSize={0} cols={["Document", "File", "Status", ""]} rows={d.documents.map((x) => [
        <b key="l">{x.label}</b>,
        <a key="f" className="lnk" href={`/api/bff/api/v1/admissions/preliminary/applications/${id}/documents/${x.id}/content`} target="_blank" rel="noopener">{x.filename}</a>,
        <span key="s"><Pil kind={x.status === "ACCEPTED" ? "ok" : x.status === "REJECTED" ? "bad" : "grey"}>{x.status === "PENDING" ? "Not yet checked" : x.status === "ACCEPTED" ? "Accepted" : "Rejected"}</Pil>{x.review_note ? <div className="sub2">{x.review_note}</div> : null}</span>,
        may.review && ["SUBMITTED", "UNDER_REVIEW", "CORRECTION_REQUIRED", "RECOMMENDED"].includes(st) ? (
          <span key="a" className="row row--inline row--tight">
            <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => void post(`acc-${x.id}`, `/documents/${x.id}/review`, { status: "ACCEPTED" }, `${x.label} accepted`)}>Accept</Btn>
            <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => { if (!note.trim()) { notifyProblem({ status: 422, title: "Write the reason the applicant reads in the note first" }); return; } void post(`rej-${x.id}`, `/documents/${x.id}/review`, { status: "REJECTED", note: note.trim() }, `${x.label} rejected`); }}>Reject</Btn>
          </span>
        ) : <span key="a" />,
      ])} />

      <h3 className="h4 mt-2">Payments</h3>
      <DTable noPrint pageSize={0} cols={["Fee", "Reference", "Amount|num", "Receipt", "Verified"]} rows={d.payments.map((x) => [x.kind === "APPLICATION" ? "Application fee" : x.kind, x.reference, naira(x.amount), x.receipt_no ?? "—", x.confirmed_at ? `${when(x.confirmed_at)}${x.channel ? ` · ${x.channel}` : ""}` : "not paid"])} />
      {oldFees.length ? (
        <DTable noPrint pageSize={0} cols={["Paid on the old portal", "Reference", "Amount|num", "Paid on", "Standing"]} rows={oldFees.map((x) => {
          const w = wordOf(FEE_STATE, x.state);
          return ["Application fee", x.reference || "none given", feeAmountWords(x, naira), x.paidOn || "—",
            <span key="s"><Pil kind={w[1]}>{w[0]}</Pil>{x.decidedAt ? <div className="sub2">{when(x.decidedAt)}{x.note ? ` · ${x.note}` : ""}</div> : null}</span>];
        })} />
      ) : null}

      {may.review && !published && st !== "WITHDRAWN" ? (
        <>
          <h3 className="h4 mt-2">Review</h3>
          <Field id="pd-note" label="Note (the reason, or what the applicant is asked for)"><textarea id="pd-note" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
          <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
            {st === "SUBMITTED" ? <Btn kind="primary" size="sm" disabled={busy !== null} onClick={() => act("START", false, "Taken up for review")}>Take up for review</Btn> : null}
            {["SUBMITTED", "UNDER_REVIEW", "RECOMMENDED"].includes(st) ? <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => act("REQUEST_CORRECTION", true, "Returned to the applicant for a correction")}>Ask for a correction</Btn> : null}
            {st === "CORRECTION_REQUIRED" ? <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => act("RESUME", false, "Taken back under review")}>Take it back under review</Btn> : null}
            {st === "UNDER_REVIEW" && may.recommend ? <Btn kind="primary" size="sm" disabled={busy !== null} onClick={() => act("RECOMMEND", false, "Recommended for admission")}>Recommend for admission</Btn> : null}
            {st === "RECOMMENDED" && may.decide ? <Btn kind="go" size="sm" disabled={busy !== null} onClick={() => act("APPROVE", false, "Admission approved")}>Approve the admission</Btn> : null}
            {["SUBMITTED", "UNDER_REVIEW", "CORRECTION_REQUIRED", "RECOMMENDED", "APPROVED"].includes(st) ? (
              <>
                <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => act("NOT_ADMIT", true, "Recorded as not admitted")}>Not admitted</Btn>
                <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => act("REJECT", true, "Application rejected")}>Reject</Btn>
              </>
            ) : null}
            {["APPROVED", "NOT_ADMITTED", "REJECTED"].includes(st) && may.decide ? <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => act("REOPEN", true, "Decision reopened")}>Reopen the decision</Btn> : null}
          </div>
          {["APPROVED", "NOT_ADMITTED", "REJECTED"].includes(st) ? <Note kind="info" title="Decided, not yet published">The Academic Office publishes the decided applications from the desk; each applicant is told then.</Note> : null}
        </>
      ) : null}

      {may.review && !attempted && ["ELIGIBLE", "ELIGIBLE_WITH_REMEDIATION"].includes(elig.status) ? (
        <>
          <h3 className="h4 mt-2">Remediation</h3>
          <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
            <select className="ctl" aria-label="Remediation status" value={rem} onChange={(e) => setRem(e.target.value)}>{Object.entries(REMEDIATION).map(([k, [l]]) => <option key={k} value={k}>{l}</option>)}</select>
            <Btn kind="ghost" size="sm" disabled={busy !== null || !rem || rem === p.remediation.status} onClick={() => { if (!note.trim()) { notifyProblem({ status: 422, title: "Write the reason or evidence in the note first" }); return; } void post("rem", "/remediation", { status: rem, note: note.trim() }, "Remediation recorded"); }}>Record the remediation</Btn>
            {p.remediation.note ? <span className="sub2">Last note: {p.remediation.note}</span> : null}
          </div>
        </>
      ) : null}

      <h3 className="h4 mt-2">History</h3>
      <DTable noPrint pageSize={0} cols={["When", "What", "Office"]} rows={p.events.map((e) => [when(e.at), <span key="a">{ACTION[e.action] ?? e.action}{e.note ? <div className="sub2">{e.note}</div> : null}</span>, e.office ?? "—"])} />
      {changes.length ? (
        <DTable noPrint pageSize={0} cols={["Programme changed", "From", "To", "Reason", "Fee", "By"]} rows={changes.map((c) => {
          const fee = wordOf(PAYMENT, c.feeStatus);
          return [<span key="w">{when(c.at)}<div className="sub2">{c.reference}</div></span>, <span key="f">{c.fromName}{c.fromTarget ? <div className="sub2">{c.fromTarget}</div> : null}</span>, c.toName,
            <span key="r" className="sub2">{c.result === "REFUSED" ? `Refused: ${c.refusal}. ` : ""}{c.reason}</span>, c.feeStatus ? <Pil key="p" kind={fee[1]}>{fee[0]}</Pil> : "—",
            `${c.by || "—"}${c.office ? ` (${c.office})` : ""}`];
        })} />
      ) : null}
    </Modal>
  );
}
