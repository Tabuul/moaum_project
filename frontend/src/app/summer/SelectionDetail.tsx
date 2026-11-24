"use client";

/** V779 · one selection in full, for the Academic Office: the student, what the results say of the course (every result of it and of
 *  its twin), the history of the selection (who confirmed, found it not outstanding, rejected, asked, flagged, and what money moved),
 *  the student's other selections of the session, the charge, and a question to the student. The decisions are made from here as
 *  from the list. */
import Link from "next/link";
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, KvGrid, Note, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { day } from "@/lib/format";
import {
  REVIEW_ACTION_WORD, categoryPill, chargeStateWord, evidenceTone, evidenceWord, failedInWord, naira, originSourceWord, registrationCategoryWord, reviewReasonWord, sessionPath,
  verificationTone, verificationWord, viaWord, semesterWord, type SummerSelectionDetail, type SummerSelectionRow,
} from "@/lib/summer";
import { call, read, type DeskResult } from "./deskApi";

type Decision = "CONFIRM" | "NOT_OUTSTANDING" | "REJECT" | "REOPEN";

export function SelectionDetail({ session, id, maySet, onClose, onDecide, onChanged }: {
  session: string; id: string; maySet: boolean; onClose: () => void; onDecide: (decision: Decision, row: SummerSelectionRow) => void; onChanged: () => void;
}) {
  const [loaded, setLoaded] = useState<{ key: string; r: DeskResult<SummerSelectionDetail> } | null>(null);
  const [reload, setReload] = useState(0);
  const [question, setQuestion] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const key = `${id}:${reload}`;
  useEffect(() => {
    let live = true;
    void read<SummerSelectionDetail>(`/summer/${sessionPath(session)}/selections/${encodeURIComponent(id)}`).then((r) => { if (live) setLoaded({ key, r }); });
    return () => { live = false; };
  }, [session, id, key]);
  const res = loaded && loaded.key === key ? loaded.r : null;
  const d = res && res.ok ? res.data : null;
  const sel = d?.selection;
  async function ask() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await call("POST", `/summer/${sessionPath(session)}/selections/${encodeURIComponent(id)}/clarify`, { note: question.trim() }, `Summer Semester ${session}: a question to the student about ${sel?.course_code ?? "a course"}`);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      notify("The student is asked");
      setQuestion("");
      setReload((n) => n + 1);
      onChanged();
    } finally {
      setBusy(false);
    }
  }
  const decided = sel?.state === "NOT_OUTSTANDING" || sel?.state === "REJECTED";
  const actions: [Decision, string, "primary" | "ghost" | "urgent"][] = sel ? ([
    ["CONFIRM", "Confirm", "primary"], ["NOT_OUTSTANDING", "Not outstanding…", "ghost"], ["REJECT", "Reject…", "urgent"], ["REOPEN", "Reopen", "ghost"],
  ] as [Decision, string, "primary" | "ghost" | "urgent"][]).filter(([x]) =>
    !(x === "CONFIRM" && sel.state === "CONFIRMED_OUTSTANDING" && !sel.needs_review) && !(x === "REOPEN" && sel.state === "PENDING_VERIFICATION")
    && !(x === "NOT_OUTSTANDING" && sel.state === "NOT_OUTSTANDING") && !(x === "REJECT" && sel.state === "REJECTED")) : [];
  return (
    <Modal wide title={sel ? `${sel.course_code} · ${sel.name}` : "Selection"} sub={sel?.matric_no ?? undefined} onClose={onClose}
      foot={maySet && sel ? <>{actions.map(([x, label, kind]) => <Btn key={x} kind={kind} size="sm" onClick={() => onDecide(x, { ...sel, charge_amount: d?.charge?.amount ?? sel.charge_amount })}>{label}</Btn>)}</> : undefined}>
      {!res ? <div className="sub2" role="status">Reading the selection…</div> : null}
      {res && !res.ok ? <ProblemNotice problem={res.problem} /> : null}
      {d && sel ? (
        <>
          <KvGrid cls="grid--3" pairs={[
            ["Student", <Link key="s" className="lnk" href={`/students/${d.student.id}`}>{d.student.name}</Link>],
            ["Programme", <span key="p">{d.student.programme ?? "—"}</span>],
            ["Department · faculty", <span key="d">{d.student.department ?? "—"} · {d.student.faculty ?? "—"}</span>],
            ["Level", <span key="l" className="tnum">{d.student.level ?? "—"}{d.student.summerLevel && d.student.summerLevel !== d.student.level ? ` (Summer level ${d.student.summerLevel})` : ""}</span>],
            ["Category", d.student.category ? <Pil key="c" kind="info">{categoryPill(d.student.category)}</Pil> : "—"],
            ["Registration category", registrationCategoryWord(sel.basis)],
          ]} />
          <div className="mt-2">
            <KvGrid cls="grid--3" pairs={[
              ["Course", <span key="c"><b className="tnum">{sel.course_code}</b> {sel.title ?? ""} · {sel.units ?? "—"} unit{sel.units === 1 ? "" : "s"}</span>],
              ["Owed in", <span key="o">{failedInWord(sel)}{sel.original_source ? <span className="blk sub2">{originSourceWord(sel.original_source)}</span> : null}</span>],
              ["Status", <span key="s"><Pil kind={verificationTone(sel.state)}>{verificationWord(sel.state)}</Pil>{sel.verified_via ? <span className="blk sub2">{viaWord(sel.verified_via)}</span> : null}</span>],
              ["Result evidence", sel.evidence ? <Pil key="e" kind={evidenceTone(sel.evidence)}>{evidenceWord(sel.evidence)}</Pil> : "—"],
              ["Flag", sel.needs_review ? <Pil key="f" kind="warn">{reviewReasonWord(sel.review_flag, sel.basis)}</Pil> : "None"],
              ["Charge", d.charge ? <span key="ch" className="tnum">{chargeStateWord(d.charge.state)} · {naira(d.charge.amount)}{d.charge.receiptNo ? ` · receipt ${d.charge.receiptNo}` : ""}</span> : "No charge"],
            ]} />
          </div>
          {decided && sel.decision_reason ? <Note kind="info" title={`Reason the student reads${sel.decided_office ? ` (${sel.decided_office}${sel.decided_at ? `, ${day(sel.decided_at)}` : ""})` : ""}`}>{sel.decision_reason}</Note> : null}
          {sel.student_note ? <Note kind="info" title="The student wrote">{sel.student_note}</Note> : null}
          {sel.clarification_open && sel.clarification_note ? <Note kind="info" title="Asked of the student, not answered yet">{sel.clarification_note}</Note> : null}

          <div className="eyebrow mt-3 mb-1">Results of this course on record</div>
          {d.evidenceRows.length ? (
            <DTable pageSize={0} noPrint cols={["Course", "Session", "Semester", "Outcome", "Points|num"]} rows={d.evidenceRows.map((x, i) => [
              <b key={`c${i}`} className="tnum">{x.course_code}</b>, <span key={`s${i}`} className="tnum">{x.session}</span>, <span key={`m${i}`}>{semesterWord(x.semester)}</span>,
              <span key={`o${i}`}>{x.outcome ?? "—"}</span>, <span key={`p${i}`} className="tnum">{x.points ?? "—"}</span>,
            ])} />
          ) : <div className="sub2">No result of this course, or of its twin, is on the portal. That is not a pass and not a failure: the Office decides against the student&rsquo;s own record.</div>}

          <div className="eyebrow mt-3 mb-1">History of this selection</div>
          {d.history.length ? (
            <DTable pageSize={0} noPrint cols={["When", "What", "By", "Reason or note", "Money"]} rows={d.history.map((h, i) => [
              <span key={`w${i}`} className="sub2 tnum">{day(h.at)}</span>,
              <span key={`a${i}`}>{REVIEW_ACTION_WORD[h.action] ?? h.action}{h.to_state && h.from_state !== h.to_state ? <span className="blk sub2">{verificationWord(h.from_state)} → {verificationWord(h.to_state)}</span> : null}</span>,
              <span key={`b${i}`}>{h.actor_name ?? (h.via === "SYSTEM" ? "The portal" : h.via === "STUDENT" ? "The student" : h.actor_office ?? "—")}</span>,
              <span key={`r${i}`} className="sub2">{[h.reason, h.note].filter(Boolean).join(" · ") || "—"}</span>,
              <span key={`m${i}`} className="sub2">{h.money_effect === "CREDITED" ? `Credited ${naira(h.credit_amount)}` : h.money_effect === "CHARGE_CANCELLED" ? "Charge cancelled" : "—"}{h.removal_ref ? ` · ${h.removal_ref}` : ""}</span>,
            ])} />
          ) : <div className="sub2">Nothing has happened to this selection since it was made.</div>}

          {d.others.length ? (
            <>
              <div className="eyebrow mt-3 mb-1">The student&rsquo;s other selections this Summer</div>
              <DTable pageSize={0} noPrint cols={["Course", "Title", "Status", "Result evidence"]} rows={d.others.map((o) => [
                <b key={`c${o.selection_id}`} className="tnum">{o.course_code}</b>, <span key={`t${o.selection_id}`}>{o.title ?? "—"}</span>,
                <Pil key={`s${o.selection_id}`} kind={verificationTone(o.state)}>{verificationWord(o.state)}</Pil>,
                o.evidence ? <Pil key={`p${o.selection_id}`} kind={evidenceTone(o.evidence)}>{evidenceWord(o.evidence)}</Pil> : <span key={`p${o.selection_id}`} className="sub2">—</span>,
              ])} />
            </>
          ) : null}

          {maySet && !decided ? (
            <div className="mt-3">
              <Field id="sd-ask" label="Ask the student" hint={`A question of ten to five hundred characters; the student answers on their Summer page. ${question.trim().length} so far.`}>
                <textarea id="sd-ask" className="ctl" rows={2} maxLength={500} value={question} onChange={(e) => setQuestion(e.target.value)} />
              </Field>
              <div className="mt-1"><Btn kind="ghost" size="sm" busy={busy} busyLabel="Asking…" disabled={busy || question.trim().length < 10} onClick={() => void ask()}>Ask the student</Btn></div>
              {problem ? <ProblemNotice problem={problem} /> : null}
            </div>
          ) : null}
        </>
      ) : null}
    </Modal>
  );
}
