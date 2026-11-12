"use client";

/**
 * Change application programme (V737): an applicant who applied under the wrong preliminary programme is moved by ICT to the other
 * one — Preliminary Technology & Industrial Studies ⇄ Preliminary Science — on the same application: the same number, the fee
 * paid kept, the history kept. The check is read first (who, what is paid, what the applicant must complete under the new
 * programme, the state it will take); the reason is written; the change is confirmed in a second step before it is sent. A
 * refusal (decided, published, a duplicate, the fee short) comes back in the server's words. Used by the migration desk and by
 * the preliminary desk's application.
 */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { STATE, labelOf, naira, pcall } from "@/lib/preliminary";
import { MIGRATION_API, PAYMENT, changeFactsOf, otherRoute, reasonOk, wordOf, type ChangeFacts } from "@/lib/prelim-migration";

export function PrelimProgrammeChange({ applicationId, fromRoute, applicant, onClose }: {
  applicationId: string; fromRoute: string;
  /** what the opener already shows, until the check answers */
  applicant?: { name?: string | null; applicationNo?: string | null; legacyNo?: string | null };
  onClose: (changed: boolean) => void;
}) {
  const to = otherRoute(fromRoute);
  const [facts, setFacts] = useState<ChangeFacts | null>(null);
  const [problem, setProblem] = useState<Problem | null>(to ? null : {
    status: 422, code: "PRELIM_CHANGE_ROUTE", title: "Only between the two preliminary programmes",
    detail: "An application is moved between Preliminary Technology & Industrial Studies and Preliminary Science only.",
  });
  const [reason, setReason] = useState("");
  const [step, setStep] = useState<"review" | "confirm">("review");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!to) return;
    let live = true;
    void pcall<unknown>(`${MIGRATION_API}/applicants/${applicationId}/change-check?to=${encodeURIComponent(to)}`).then((r) => {
      if (!live) return;
      if (r.ok) setFacts(changeFactsOf(r.data)); else setProblem(r.problem);
    });
    return () => { live = false; };
  }, [applicationId, to]);

  const f = facts;
  const name = f?.name || applicant?.name || "";
  const appNo = f?.applicationNo || applicant?.applicationNo || "";
  const oldNo = f?.legacyNo || applicant?.legacyNo || "";
  const fromName = f?.fromName || fromRoute;
  const toName = f?.toName || to || "";

  async function change() {
    if (!f || !to) return;
    setBusy(true);
    setProblem(null);
    try {
      const r = await pcall<unknown>(`${MIGRATION_API}/applicants/${applicationId}/change-programme`, "POST",
        { to, from: f.fromRoute || fromRoute, reason: reason.trim() }, `Programme changed for ${appNo}: ${fromName} to ${toName}: ${reason.trim()}`);
      if (!r.ok) { setProblem(r.problem); setStep("review"); return; }
      notify(`${appNo} is now under ${toName}: the same application, number and fee. The applicant is told.`);
      onClose(true);
    } finally { setBusy(false); }
  }

  const pay = wordOf(PAYMENT, f?.feeStatus);
  const stateWord = (s: string) => (s ? labelOf(STATE, s)[0] : "—");
  return (
    <Modal wide title="Change application programme" sub={[name, appNo].filter(Boolean).join(" · ")} onClose={() => onClose(false)}
      foot={step === "review" ? (
        <>
          <Btn kind="ghost" onClick={() => onClose(false)}>Cancel</Btn>
          <Btn kind="primary" disabled={!f?.may || !reasonOk(reason)} onClick={() => setStep("confirm")}>Continue</Btn>
        </>
      ) : (
        <>
          <Btn kind="ghost" disabled={busy} onClick={() => setStep("review")}>Back</Btn>
          <Btn kind="primary" disabled={busy} onClick={() => void change()}>{busy ? "Changing…" : "Confirm the change"}</Btn>
        </>
      )}>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!f && !problem ? <div className="sub2">Reading the application…</div> : null}
      {f ? (
        step === "review" ? (
          <>
            <KvGrid cls="grid--2" pairs={[
              ["Applicant", name || "—"],
              ["Application number", oldNo ? `${appNo} (old portal: ${oldNo})` : appNo || "—"],
              ["Current programme", fromName],
              ["New programme", toName],
              ["Payment", <span key="p"><Pil kind={pay[1]}>{pay[0]}</Pil>{f.feePaid ? ` ${naira(f.feePaid)}` : ""}</span>],
              ["Original payment reference", f.feeReferences.length ? f.feeReferences.join(", ") : "—"],
              ["Application state", f.toState && f.toState !== f.state ? `${stateWord(f.state)} → ${stateWord(f.toState)}` : stateWord(f.state)],
              ["New programme's application fee", f.newFee == null ? "—" : `${naira(f.newFee)}${f.feeCovers === true ? " · covered by the fee paid" : f.feeCovers === false ? " · not covered by the fee paid" : ""}`],
            ]} />
            {!f.may ? (
              <Note kind="bad" title={f.refusal?.code ? `${f.refusal.code}: the programme cannot be changed` : "The programme cannot be changed"}>{f.refusal?.message ?? ""}</Note>
            ) : (
              <>
                <Note kind="info" title="What happens">
                  The application stays one record: the same application number{oldNo ? " and old-portal number" : ""}, the fee and its receipts, the documents and the history.
                  The intended programme is chosen again under {toName}; the application is reviewed afresh by that programme&rsquo;s office, and the applicant is told.
                </Note>
                {f.missing.length ? (
                  <Note kind="info" title={`What the applicant must complete under ${toName}`}>
                    <ul>{f.missing.map((m) => <li key={m}>{m}</li>)}</ul>
                  </Note>
                ) : null}
                <Field id="pc-why" label="Reason" required hint="At least 15 characters and three words; kept in the history and the audit trail.">
                  <textarea id="pc-why" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} />
                </Field>
              </>
            )}
          </>
        ) : (
          <>
            <p>Move <b>{appNo}</b>{name ? ` (${name})` : ""} from <b>{fromName}</b> to <b>{toName}</b>?</p>
            <p className="sub2">The application number, the fee paid and the history stay as they are. The admission status is not changed.</p>
            <KvGrid cls="grid--2" pairs={[["Reason", reason.trim()], ["State after the change", stateWord(f.toState || f.state)]]} />
          </>
        )
      ) : null}
    </Modal>
  );
}
