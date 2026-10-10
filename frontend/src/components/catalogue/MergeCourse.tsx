"use client";

/** V386: one course merged into another — a dry run first (what moves, what differs, or why it cannot), then the merge by
 *  the Academic Office or the Registry with a reason. The database decides; this dialog only shows what it said. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { EVIDENCE, type MergeResult } from "@/lib/catalogue";

const TABLE_WORDS: Record<string, string> = {
  "catalogue.offering.course_code": "session classes (with their registrations, sheets and results)",
  "catalogue.course_offer.course_code": "programme bindings", "catalogue.course_offer_history.course_code": "past bindings",
  "catalogue.course_prerequisite.course_code": "prerequisites it requires", "catalogue.course_prerequisite.requires_code": "courses requiring it",
  "assessment.cbt_exam.course_code": "CBT examinations", "assessment.question.course_code": "questions",
  "people.deferred_course.course_code": "deferred courses", "assessment.legacy_result_holding.course_code": "held old-portal results",
  "catalogue.offer_proposal.course_code": "offer proposals", "extexam.project.course_code": "external examination projects",
  bindingsAlreadyHeld: "bindings the course kept already had (kept as they are)", prerequisitesAlreadyHeld: "prerequisites already held (kept as they are)",
};

async function post(path: string, body: unknown, reason: string): Promise<MergeResult | null> {
  const r = await fetch(`/api/bff/api/v1/catalogue${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
  return j as MergeResult;
}

export function MergeCourse({ keep, merge, mayMerge, onClose }: { keep: string; merge: string; mayMerge: boolean; onClose: () => void }) {
  const router = useRouter();
  const [preview, setPreview] = useState<MergeResult | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    void post("/courses/merge/preview", { keep, merge }, `Preview merging ${merge} into ${keep}`).then((r) => { if (live) setPreview(r); });
    return () => { live = false; };
  }, [keep, merge]);
  const moved = Object.entries(preview?.moved ?? {}).filter(([, n]) => Number(n) > 0);
  return (
    <Modal title={`Merge ${merge} into ${keep}`} sub="One course, held once: everything on the code merged moves to the course kept" onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Close</Btn>{mayMerge ? (
        <Btn kind="urgent" disabled={busy || !preview || !!preview.blocked || !reason.trim()} onClick={async () => {
          if (!window.confirm(`Merge ${merge} into ${keep}? Every class, registration, result, binding and examination of ${merge} moves to ${keep}, and ${merge} answers for ${keep} from now on.`)) return;
          setBusy(true);
          try {
            const done = await post("/courses/merge", { keep, merge, reason: reason.trim() }, `Merged ${merge} into ${keep}`);
            if (done) { notify(`${merge} merged into ${keep}`); onClose(); router.refresh(); }
          } finally { setBusy(false); }
        }}>{busy ? "Merging…" : "Merge"}</Btn>) : null}</>}>
      {!preview ? <div className="sub2">Reading what the merge would do…</div> : (
        <div className="stack">
          {preview.blocked ? <Note kind="bad" title="This merge is refused">{preview.blocked.replace(/^[A-Z_]+: /, "")}</Note>
            : <Note kind="ok" title={`One course: ${preview.evidence ? EVIDENCE[preview.evidence] ?? preview.evidence : ""}`}>{preview.keep} — {preview.keepTitle} is kept; {preview.merge} — {preview.mergeTitle} becomes its alias.</Note>}
          {preview.warnings.length ? <Note kind="info" title="What differs">{preview.warnings.join("; ")}.</Note> : null}
          {moved.length ? (
            <div><div className="b600 mb-1">What moves to {preview.keep}</div>
              <ul className="sub2" style={{ margin: 0, paddingLeft: 18 }}>{moved.map(([k, n]) => <li key={k}><span className="tnum">{n}</span> {TABLE_WORDS[k] ?? k}</li>)}</ul></div>
          ) : !preview.blocked ? <div className="sub2">Nothing is recorded on {preview.merge} yet; only the code moves.</div> : null}
          {mayMerge && !preview.blocked ? <Field id="mg-why" label="Why" required full><input id="mg-why" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="The old portal wrote it without its space" maxLength={400} /></Field> : null}
          {!mayMerge ? <div className="sub2">The Academic Office or the Registry makes the merge.</div> : null}
        </div>
      )}
    </Modal>
  );
}
