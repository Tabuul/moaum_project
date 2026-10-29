"use client";

/**
 * V700: one student's result in one course, as the Director of ICT sees it — the student, the course, the result as the broadsheet
 * reads it (assessment.course_final), each sitting's sheet and where it stands, every version of the mark (who entered it, when,
 * why), the sheet's chain, the amendments and the correction requests. The Director of ICT asks the course's desk of entry for a
 * correction here — the result as it stands beside the one proposed, a reason and a note — and never changes the mark.
 */
import { useState } from "react";
import { useJson } from "@/lib/use-json";
import { Field, Modal } from "@/components/proto/blocks";
import { Btn, KvGrid, Note, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import { roleLabel } from "@/lib/offices";
import {
  markWords, NEEDS_MARKS, OUTCOME_WORD, proposalBody, proposalProblem, REASON_KINDS, REASON_WORD, REQUEST_STATE_TONE, REQUEST_STATE_WORD,
  requestOpen, stageWord, type Proposal, type ReasonKind,
} from "@/lib/result-monitor";

type N = number | null;
interface Mark { ca: N; exam: N; total: N; grade?: string | null; points?: N; outcome: string | null }
export interface CorrectionRequest {
  id: string; ref: string; state: string; reasonKind: ReasonKind; note: string; sheetId: string; studentId: string; offeringId: string;
  courseCode: string; session: string; semester: number; stage: string; number: string | null; surname: string; otherNames: string;
  programmeCode: string; wasVersion: N; wasCa: N; wasExam: N; wasTotal: N; wasGrade: string | null; wasOutcome: string | null; wasStage: string;
  ca: N; exam: N; outcome: string | null; requestedOffice: string; requestedAt: string; requestedBy: string | null;
  amendmentRef: string | null; amendmentStage: string | null; resolvedVersion: N; closedAt: string | null; closedOffice: string | null;
  closedNote: string | null; closedBy: string | null;
}
interface Detail {
  student: { id: string; number: string | null; jamb: string | null; surname: string; otherNames: string; status: string; currentLevel: number;
    programmeCode: string; programme: string | null; department: string | null; faculty: string | null };
  course: { id: string; courseCode: string; title: string; courseUnits: number; kind: string; caMax: number; courseLevel: number; department: string | null;
    session: string; semester: number; stream: string; lecturer: string | null };
  registration: { level: number; status: string; approvedAt: string | null; units: number; entryType: string; entryStatus: string; basis: string | null } | null;
  result: (Mark & { sheet_id: string | null; stage: string | null; published_at: string | null; senate_minute: string | null; sitting: string | null }) | null;
  sittings: (Mark & { sheetId: string; sitting: string; stage: string; submittedAt: string | null; publishedAt: string | null; senateMinute: string | null; version: N })[];
  versions: (Mark & { sheetId: string; sitting: string; version: number; reason: string | null; imported: boolean; enteredAt: string; enteredOffice: string | null;
    onBehalf: boolean; onBehalfReason: string | null; enteredBy: string | null })[];
  chain: { sheetId: string; from: string | null; to: string | null; kind: string; office: string | null; comment: string | null; at: string; actor: string | null }[];
  amendments: { id: string; ref: string; kind: string; stage: string; wasCa: N; wasExam: N; wasOutcome: string | null; ca: N; exam: N; outcome: string | null;
    reason: string; raisedOffice: string | null; raisedAt: string; appliedAt: string | null; closedReason: string | null; raisedBy: string | null }[];
  requests: CorrectionRequest[];
  mayRequest: boolean;
}

const when = (s: string | null | undefined) => (s ? new Date(s).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const EMPTY: Proposal = { reasonKind: "", note: "", ca: "", exam: "", outcome: "" };

export function RecordDetail({ offeringId, studentId, onClose, onChanged }: {
  offeringId: string; studentId: string; onClose: () => void; onChanged?: () => void;
}) {
  const [tick, setTick] = useState(0);
  const { data: d, failed } = useJson<Detail>(`/api/bff/api/v1/results/monitor/records/${offeringId}/${studentId}`, tick);
  const [ask, setAsk] = useState<Proposal | null>(null);
  const [withdraw, setWithdraw] = useState<{ r: CorrectionRequest; note: string } | null>(null);
  const [busy, setBusy] = useState(false);

  const sheetId = d?.result?.sheet_id ?? d?.sittings[0]?.sheetId ?? null;
  const current = d && sheetId ? d.sittings.find((s) => s.sheetId === sheetId) ?? null : null;
  const openRequest = d?.requests.find((q) => requestOpen(q.state)) ?? null;
  const problem = ask ? proposalProblem(ask, current, d?.course.caMax ?? 40) : null;

  async function send() {
    if (!ask || !sheetId || problem) return;
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/results/monitor/corrections", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Correction asked of ${d?.course.courseCode} for ${d?.student.number}: ${ask.note.trim()}`) },
        body: JSON.stringify(proposalBody(sheetId, studentId, ask)),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: "The correction was not sent" }); return; }
      notify(`Correction ${j?.ref ?? ""} sent to the desk of entry of ${d?.course.courseCode}.`);
      setAsk(null);
      setTick((x) => x + 1);
      onChanged?.();
    } finally { setBusy(false); }
  }

  async function sendWithdraw() {
    if (!withdraw || withdraw.note.trim().length < 10) return;
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/results/monitor/corrections/${withdraw.r.id}/withdraw`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Correction ${withdraw.r.ref} withdrawn: ${withdraw.note.trim()}`) },
        body: JSON.stringify({ note: withdraw.note.trim() }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: "The correction was not withdrawn" }); return; }
      notify(`Correction ${withdraw.r.ref} withdrawn.`);
      setWithdraw(null);
      setTick((x) => x + 1);
      onChanged?.();
    } finally { setBusy(false); }
  }

  const title = d ? `${d.course.courseCode} — ${d.student.surname.toUpperCase()}, ${d.student.otherNames}` : "Result details";
  const proposedTotal = ask && ask.ca !== "" && ask.exam !== "" ? Number(ask.ca) + Number(ask.exam) : null;

  return (
    <Modal wide title={title} sub={d ? `${d.course.session} · semester ${d.course.semester} · ${d.student.number ?? ""}` : "Loading the result…"} onClose={onClose}
      foot={<>
        <Btn kind="ghost" onClick={onClose}>Close</Btn>
        <span className="grow" />
        {d?.mayRequest && sheetId && !openRequest && !ask ? <Btn kind="primary" onClick={() => setAsk({ ...EMPTY })}>Request a correction</Btn> : null}
      </>}>
      {failed ? <Note kind="bad" title="Unable to load the result">{failed}</Note> : null}
      {!d && !failed ? <p className="sub2">Loading the result…</p> : null}
      {d ? (
        <>
          <h4>Student</h4>
          <KvGrid pairs={[
            ["Name", `${d.student.surname.toUpperCase()}, ${d.student.otherNames}`], ["Matric No.", d.student.number ?? "—"], ["JAMB No.", d.student.jamb ?? "—"],
            ["Programme", d.student.programme ?? d.student.programmeCode], ["Department", d.student.department ?? "—"], ["Faculty", d.student.faculty ?? "—"],
            ["Level", d.registration ? `${d.registration.level} (registered)` : `${d.student.currentLevel} (record)`], ["Session", d.course.session],
            ["Semester", String(d.course.semester)], ["Status", d.student.status],
          ]} />
          <h4>Course</h4>
          <KvGrid pairs={[
            ["Course", `${d.course.courseCode} — ${d.course.title}`], ["Units", String(d.registration?.units ?? d.course.courseUnits)],
            ["Course type", `${d.course.kind}${d.registration ? ` · ${d.registration.entryType.toLowerCase()}${d.registration.basis ? ` (${d.registration.basis})` : ""}` : ""}`],
            ["Owned by", d.course.department ?? "—"], ["Lecturer", d.course.lecturer ?? "—"],
            ["Registration", d.registration ? `${d.registration.status.toLowerCase()} · course ${d.registration.entryStatus.toLowerCase()}` : "No registration of this course"],
          ]} />
          {!d.registration ? <Note kind="bad" title="No registration of this course">The student has a result for a course their registration does not carry — see Result exceptions.</Note> : null}
          <h4>Result</h4>
          <KvGrid pairs={[
            ["CA", d.result?.ca ?? "—"], ["Exam", d.result?.exam ?? "—"], ["Total", d.result?.total ?? "—"], ["Grade", d.result?.grade ?? (d.result?.outcome ? OUTCOME_WORD[d.result.outcome] ?? d.result.outcome : "—")],
            ["Grade point", d.result?.points ?? "—"], ["Quality point", d.result?.points != null && d.registration ? (d.result.points * d.registration.units).toFixed(2) : "—"],
            ["Sitting", d.result?.sitting ?? "—"], ["Stage", stageWord(d.result?.stage ?? (d.sittings.length ? null : "NO_SHEET"))],
          ]} />
          {!d.result?.outcome ? <Note kind="info" title="No result yet">No mark is recorded for this course. It is not a fail: the result is not available.</Note> : null}

          <h4>Workflow</h4>
          <DTable noPrint pageSize={0} cols={["Sitting", "Stage", "Mark", "Submitted", "Published", "Senate minute"]}
            rows={d.sittings.map((s) => [s.sitting, stageWord(s.stage), markWords(s), when(s.submittedAt), when(s.publishedAt), s.senateMinute ?? "—"])} />
          {d.chain.length ? (
            <DTable noPrint pageSize={0} cols={["When", "Step", "By", "Office", "Comment"]}
              rows={d.chain.map((c) => [when(c.at), `${stageWord(c.from)} → ${stageWord(c.to)}${c.kind === "RETURN" ? " (returned)" : ""}`, c.actor ?? "—", c.office ? roleLabel(c.office) : "—", c.comment ?? ""])} />
          ) : <p className="sub2">No step of the chain is recorded for this course&rsquo;s sheet.</p>}

          <h4>History of the mark</h4>
          {d.versions.length ? (
            <DTable noPrint pageSize={0} cols={["Version|num", "Sitting", "Mark", "Why", "Entered by", "Office", "When"]}
              rows={d.versions.map((v) => [v.version, v.sitting, markWords(v),
                <span key="w">{v.reason ?? (v.version === 1 ? "First entry" : "—")}{v.imported ? <> <Pil kind="info">old portal</Pil></> : null}{v.onBehalf ? <> <Pil kind="info" title={v.onBehalfReason ?? ""}>on behalf</Pil></> : null}</span>,
                v.enteredBy ?? "—", v.enteredOffice ? roleLabel(v.enteredOffice) : "—", when(v.enteredAt)])} />
          ) : <p className="sub2">No mark has been entered.</p>}

          {d.amendments.length ? (
            <>
              <h4>Amendments</h4>
              <DTable noPrint pageSize={0} cols={["Ref", "Stage", "Before", "After", "Reason", "Raised by", "When"]}
                rows={d.amendments.map((a) => [a.ref, stageWord(a.stage), markWords({ ca: a.wasCa, exam: a.wasExam, outcome: a.wasOutcome }),
                  markWords({ ca: a.ca, exam: a.exam, outcome: a.outcome }), a.closedReason ? `${a.reason} — ${a.closedReason}` : a.reason,
                  `${a.raisedBy ?? "—"}${a.raisedOffice ? ` (${roleLabel(a.raisedOffice)})` : ""}`, when(a.raisedAt)])} />
            </>
          ) : null}

          {d.requests.length ? (
            <>
              <h4>Correction requests</h4>
              <DTable noPrint pageSize={0} cols={["Ref", "State", "Reason", "As it stood", "Proposed", "Asked by", ""]}
                rows={d.requests.map((q) => [q.ref, <Pil key="s" kind={REQUEST_STATE_TONE[q.state] ?? "grey"}>{REQUEST_STATE_WORD[q.state] ?? q.state}</Pil>,
                  <span key="r">{REASON_WORD[q.reasonKind] ?? q.reasonKind}: {q.note}{q.closedNote ? <><br /><span className="sub2">{q.closedNote}</span></> : null}{q.amendmentRef ? <><br /><span className="sub2">Amendment {q.amendmentRef} · {stageWord(q.amendmentStage)}</span></> : null}</span>,
                  markWords({ ca: q.wasCa, exam: q.wasExam, total: q.wasTotal, grade: q.wasGrade, outcome: q.wasOutcome }),
                  q.ca != null || q.outcome ? markWords({ ca: q.ca, exam: q.exam, outcome: q.outcome }) : "Removed or moved by the desk",
                  `${q.requestedBy ?? "—"} · ${when(q.requestedAt)}`,
                  d.mayRequest && q.state === "OPEN" ? <Btn key="w" kind="ghost" onClick={() => setWithdraw({ r: q, note: "" })}>Withdraw</Btn> : ""])} />
            </>
          ) : null}

          {ask ? (
            <div className="panel" style={{ marginTop: 12 }}>
              <h4>Request a correction</h4>
              <p className="sub2">The request goes to the course&rsquo;s desk of entry ({d.course.lecturer ?? "the course lecturer"}). They correct the mark on the sheet while it is at entry, or raise the amendment once it is published; the result changes only through them, and every version is kept.</p>
              <div className="grid grid--2" style={{ alignItems: "start" }}>
                <div>
                  <b>Before — the result as it stands</b>
                  <KvGrid cls="grid--2" pairs={[["CA", current?.ca ?? "—"], ["Exam", current?.exam ?? "—"], ["Total", current?.total ?? "—"], ["Grade", current?.grade ?? (current?.outcome ? OUTCOME_WORD[current.outcome] ?? current.outcome : "No mark")]]} />
                </div>
                <div>
                  <b>After — the result proposed</b>
                  <KvGrid cls="grid--2" pairs={[["CA", ask.ca || "—"], ["Exam", ask.exam || "—"], ["Total", proposedTotal ?? "—"], ["Outcome", ask.outcome ? OUTCOME_WORD[ask.outcome] : ask.ca ? "Graded" : "—"]]} />
                  <span className="sub2">The grade follows the University&rsquo;s grading when the desk enters it.</span>
                </div>
              </div>
              <div className="grid grid--3">
                <Field id="crq-kind" label="Reason" required>
                  <select id="crq-kind" className="ctl" value={ask.reasonKind} onChange={(e) => setAsk({ ...ask, reasonKind: e.target.value as ReasonKind })}>
                    <option value="">Choose…</option>
                    {REASON_KINDS.map((k) => <option key={k} value={k}>{REASON_WORD[k]}</option>)}
                  </select>
                </Field>
                <Field id="crq-ca" label={`CA (out of ${d.course.caMax})`} hint={ask.reasonKind && !NEEDS_MARKS.includes(ask.reasonKind as ReasonKind) ? "Leave blank when the result is to be removed or moved" : undefined}>
                  <input id="crq-ca" className="ctl tnum" inputMode="numeric" value={ask.ca} onChange={(e) => setAsk({ ...ask, ca: e.target.value.replace(/[^0-9]/g, "") })} />
                </Field>
                <Field id="crq-exam" label={`Examination (out of ${100 - d.course.caMax})`}>
                  <input id="crq-exam" className="ctl tnum" inputMode="numeric" value={ask.exam} onChange={(e) => setAsk({ ...ask, exam: e.target.value.replace(/[^0-9]/g, "") })} />
                </Field>
                <Field id="crq-outcome" label="Outcome">
                  <select id="crq-outcome" className="ctl" value={ask.outcome} onChange={(e) => setAsk({ ...ask, outcome: e.target.value })}>
                    <option value="">{ask.ca ? "Graded" : "Unchanged"}</option>
                    {Object.entries(OUTCOME_WORD).map(([k, w]) => <option key={k} value={k}>{w}</option>)}
                  </select>
                </Field>
                <Field id="crq-note" label="What is wrong" required full hint="Ten characters or more; it goes on the record with the request">
                  <textarea id="crq-note" className="ctl" rows={3} value={ask.note} onChange={(e) => setAsk({ ...ask, note: e.target.value })} />
                </Field>
              </div>
              {problem ? <p className="sub2" role="alert">{problem}</p> : null}
              <div className="row">
                <Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn>
                <span className="grow" />
                <Btn kind="primary" disabled={!!problem || busy} busy={busy} busyLabel="Sending the correction…" onClick={() => void send()}>Send to the desk of entry</Btn>
              </div>
            </div>
          ) : null}
          {openRequest && d.mayRequest ? <Note kind="info" title={`Correction ${openRequest.ref} is ${REQUEST_STATE_WORD[openRequest.state]?.toLowerCase() ?? openRequest.state}`}>A second request waits until this one is closed.</Note> : null}
        </>
      ) : null}
      {withdraw ? (
        <Modal title={`Withdraw ${withdraw.r.ref}`} sub="The reason goes on the record" onClose={() => setWithdraw(null)}
          foot={<><Btn kind="ghost" onClick={() => setWithdraw(null)}>Cancel</Btn><span className="grow" /><Btn kind="urgent" disabled={withdraw.note.trim().length < 10 || busy} busy={busy} onClick={() => void sendWithdraw()}>Withdraw it</Btn></>}>
          <Field id="crq-withdraw" label="Why it is withdrawn" hint="Ten characters or more">
            <textarea id="crq-withdraw" className="ctl" rows={3} value={withdraw.note} onChange={(e) => setWithdraw({ ...withdraw, note: e.target.value })} />
          </Field>
        </Modal>
      ) : null}
    </Modal>
  );
}
