"use client";
/** V734: one inter-departmental transfer application reviewed at its desk — the University's master prompt of 12 November 2026 (part B):
 *  the student's academic profile, the current and proposed department, faculty and College, the reason, the documents the old portal
 *  holds, what is paid and owed, every decision so far, and Approve (with a comment) or Decline (with the reason, shown to the student),
 *  each confirmed first. The server decides who may act (the HOD, or the College's Dean at a College department; the Registry; the
 *  Academic Office's final approval, which waits for the whole fee). There is no return for correction: the workflow has none. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { bandKind, bandWord, naira } from "@/lib/transfer-fees";
import { day } from "@/lib/format";
import { unitLine, type TransferRow } from "../Transfers";

export interface ReviewEvent {
  at: string; from_state: string | null; to_state: string; decision: string; desk: string | null; office: string | null;
  note: string | null; next_desk: string | null; source: string; dept_name: string | null; faculty_name: string | null;
  college_name: string | null; actor_name: string | null;
}
export interface Review {
  application: TransferRow;
  student: { matric_no: string | null; admission_no: string | null; name: string; current_level: number | null; status: string;
    entry_mode: string | null; entry_session: string | null; entry_level: number | null; programme_code: string | null; programme: string | null };
  history: ReviewEvent[];
  payments: { source: string; reference: string; payref: string | null; item: string | null; amount: number | string; paidOn: string | null; status: string }[];
  legacy: { legacyRef: string | null; appliedOn: string | null; stage: string | null; approvals: string | null; documents: string | null } | null;
}

const DESK: Record<string, string> = {
  FROM_DEPARTMENT: "Current department", TO_DEPARTMENT: "New department", REGISTRY: "Registry", ACADEMIC: "Academic Office",
  COMMITTEE: "Senate Admissions Committee", SENATE: "Senate", STUDENT: "The student", OFFICE: "An office",
};
const DECISION: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  APPLIED: ["info", "Applied"], RECORDED: ["info", "Recorded"], APPROVED: ["ok", "Approved"], DECLINED: ["bad", "Declined"],
  WITHDRAWN: ["grey", "Withdrawn"], RECOMMENDED: ["ok", "Recommended"], NOT_RECOMMENDED: ["bad", "Not recommended"], EFFECTED: ["ok", "Effected"],
  CHANGED: ["grey", "Changed"],
};
const OFFICE: Record<string, string> = {
  hod: "Head of Department", dean: "Dean", registrar: "Registrar", dregistrar: "Deputy Registrar", academic: "Academic Office",
  super: "Super Administrator", student: "Student", ict: "ICT", dvc: "Deputy Vice-Chancellor", vc: "Vice-Chancellor",
};

export function TransferReview({ review }: { review: Review }) {
  const router = useRouter();
  const a = review.application;
  const s = review.student;
  const [act, setAct] = useState<"approve" | "decline" | null>(null);
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  async function send() {
    if (!act || busy) return;
    if (act === "decline" && !text.trim()) return;
    setBusy(true);
    setErr(null);
    try {
      const path = act === "approve" ? "approve" : "decline";
      const body = act === "approve" ? { note: text.trim() || null, expectedState: a.state } : { why: text.trim() };
      const r = await fetch(`/api/bff/api/v1/transfers/${encodeURIComponent(a.id)}/${path}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${act === "approve" ? "Approve" : "Decline"} transfer for ${a.name}`) },
        body: JSON.stringify(body),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        const p: Problem = j ?? { status: r.status, title: r.statusText };
        setErr(p);
        notifyProblem(p);
        return;
      }
      const done = act === "approve" ? `${a.name}'s transfer approved` : `${a.name}'s transfer declined`;
      setSaid(done);
      notify(done);
      setAct(null);
      setText("");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const live = Boolean(a.desk);
  return (
    <>
      <div className="row row--inline row--tight" style={{ flexWrap: "wrap", gap: 8 }}>
        <LinkBtn kind="ghost" href="/transfers">All transfer applications</LinkBtn>
      </div>
      {said ? <Note kind="ok" title={said}>On the record, in your name; the student and the next desk are told.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <Panel title={a.name} right={<Pil kind={a.state === "DECLINED" ? "bad" : a.state === "EFFECTED" ? "ok" : "info"}>{a.stageLabel ?? a.state}</Pil>}>
        <PBody>
          <KvGrid pairs={[
            ["Matriculation number", s.matric_no ?? "—"],
            ["Programme now", s.programme ?? a.from_programme],
            ["Level", s.current_level != null ? `${s.current_level} Level` : `${a.from_level} Level`],
            ["Status", s.status],
            ["Entry", [s.entry_mode, s.entry_session, s.entry_level != null ? `${s.entry_level} Level` : null].filter(Boolean).join(" · ") || "—"],
            ["UTME · CGPA at application", [a.utme_score != null ? String(a.utme_score) : null, a.cgpa != null ? Number(a.cgpa).toFixed(2) : null].filter(Boolean).join(" · ") || "—"],
            ["Session of the application", a.session],
            ["Applied", day(a.applied_at)],
          ]} />
        </PBody>
      </Panel>

      <Panel title="From and to">
        <PBody>
          <KvGrid cls="grid--2" pairs={[
            ["Current", <span key="f">{a.from_programme}<div className="sub2">{unitLine(a.from_dept_name, a.from_faculty_name, a.from_college_name) || "—"}</div></span>],
            ["Proposed", <span key="t">{a.to_programme}<div className="sub2">{unitLine(a.to_dept_name, a.to_faculty_name, a.to_college_name) || "—"}</div></span>],
          ]} />
          <div className="mt-1"><span className="sub2">Reason for the transfer</span><div>{a.reason}</div></div>
          {a.decline_note ? <Note kind="bad" title="Declined">{a.decline_note}</Note> : null}
          {a.withdrawn_why ? <Note kind="info" title="Withdrawn">{a.withdrawn_why}</Note> : null}
        </PBody>
      </Panel>

      <Panel title="Where it stands" right={live ? undefined : "Nothing pending"}>
        <PBody>
          {live ? <div>With <b>{a.desk_label}</b>.</div> : <div className="sub2">No desk holds it: {a.stageLabel ?? a.state}.</div>}
          {a.canApprove || a.canDecline ? (
            <div className="row row--inline row--tight mt-1" style={{ gap: 8 }}>
              {a.canApprove ? <Btn kind="go" disabled={busy} onClick={() => { setAct("approve"); setText(""); }}>Approve</Btn> : null}
              {a.canDecline ? <Btn kind="ghost" disabled={busy} onClick={() => { setAct("decline"); setText(""); }}>Decline</Btn> : null}
            </div>
          ) : live ? <div className="sub2 mt-1">It is not at your desk: the office holding it acts.</div> : null}
          {a.state === "REG_OK" && Number(a.balance ?? 0) > 0 ? (
            <Note kind="bad" title="The final approval waits for the whole fee">{naira(a.balance)} is still owed{a.pending ? "; a payment awaits the bank" : ""}.</Note>
          ) : null}
        </PBody>
      </Panel>

      <Panel title="Transfer fee" right={a.band ? <Pil kind={bandKind(a.band)}>{bandWord(a.band)}</Pil> : undefined}>
        <PBody>
          <KvGrid pairs={[
            ["Fee", a.fee_due != null ? naira(a.fee_due) : "Not stated"],
            ["Paid", a.paid_total != null ? naira(a.paid_total) : "—"],
            ["Of it on the old portal", Number(a.old_portal_paid ?? 0) > 0 ? naira(a.old_portal_paid) : "—"],
            ["Balance", a.balance != null ? naira(a.balance) : "—"],
          ]} />
          {review.payments.length ? (
            <DTable cols={["Reference", "Item", "Amount|num", "Paid on|mid", "Status"]} rows={review.payments.map((p) => [
              <span key="r" className="tnum">{p.reference}{p.payref ? <div className="sub2">{p.payref}</div> : null}</span>,
              p.item ?? "—",
              <span key="a" className="tnum">{naira(p.amount)}</span>,
              p.paidOn ? day(p.paidOn) : "—",
              p.status.replace(/_/g, " ").toLowerCase(),
            ])} />
          ) : <div className="sub2 mt-1">No payment counted toward it yet.</div>}
        </PBody>
      </Panel>

      <Panel title="Supporting documents">
        <PBody>
          {review.legacy?.documents
            ? <div><span className="sub2">As the old portal&rsquo;s record gives them ({review.legacy.legacyRef ?? "old portal"}):</span><div>{review.legacy.documents}</div>
                {review.legacy.approvals ? <div className="mt-1"><span className="sub2">Approvals on the old portal:</span><div>{review.legacy.approvals}</div></div> : null}</div>
            : <div className="sub2">None: an application made on this portal carries none — the reason above is the student&rsquo;s case.</div>}
        </PBody>
      </Panel>

      <Panel title="Approval history" right={`${review.history.length} entr${review.history.length === 1 ? "y" : "ies"}`}>
        {review.history.length ? (
          <DTable cols={["When|mid", "Stage", "Unit", "Decision", "By", "Comment or reason", "Next"]} rows={review.history.map((h, i) => [
            <span key={`w${i}`} className="tnum">{day(h.at)}</span>,
            DESK[h.desk ?? ""] ?? h.desk ?? "—",
            unitLine(h.dept_name, h.faculty_name, h.college_name) || "—",
            <Pil key={`d${i}`} kind={(DECISION[h.decision] ?? ["grey", h.decision])[0]}>{(DECISION[h.decision] ?? ["grey", h.decision])[1]}</Pil>,
            <span key={`b${i}`}>{h.actor_name ?? "—"}{h.office ? <div className="sub2">{OFFICE[h.office] ?? h.office}</div> : null}{h.source === "RECORD" ? <div className="sub2">from the desks&rsquo; stamps</div> : null}</span>,
            h.note ?? "—",
            h.next_desk ?? "—",
          ])} />
        ) : <PBody><div className="sub2">No decision yet.</div></PBody>}
      </Panel>

      {act ? (
        <Modal title={act === "approve" ? "Approve this transfer at your desk?" : "Decline this transfer?"}
          sub={<>{a.name} · {a.from_programme} → {a.to_programme}</>}
          onClose={() => { if (!busy) setAct(null); }}
          foot={<div className="row row--inline row--tight row--right" style={{ gap: 8 }}>
            <Btn kind="ghost" disabled={busy} onClick={() => setAct(null)}>Cancel</Btn>
            <Btn kind={act === "approve" ? "go" : "primary"} disabled={busy || (act === "decline" && !text.trim())} onClick={() => void send()}>
              {busy ? "Saving…" : act === "approve" ? "Approve" : "Decline"}</Btn>
          </div>}>
          <PBody>
            {act === "approve"
              ? <div className="sub2">It moves from {a.desk_label ?? "your desk"} to the next office, and the student is told.</div>
              : <div className="sub2">Declining ends the application. The reason is recorded and shown to the student.</div>}
            <label className="sub2 mt-1" htmlFor="tr-text" style={{ display: "block" }}>{act === "approve" ? "Comment (optional, kept in the history)" : "Reason (required)"}</label>
            <textarea id="tr-text" className="ctl" rows={3} maxLength={600} value={text} onChange={(e) => setText(e.target.value)} style={{ width: "100%" }} />
          </PBody>
        </Modal>
      ) : null}
      <div className="sub2 mt-1"><Link href="/transfers">Back to the transfer applications</Link></div>
    </>
  );
}
