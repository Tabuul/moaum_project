"use client";

/**
 * V700: the corrections the Director of ICT asked of this sheet's desk of entry. The desk corrects the mark on the sheet while it is
 * at entry, or raises the amendment once it is published (onRaise fills the amendment's form from the request), or declines it with
 * its reason. A new version of the mark closes the request; the request follows an amendment raised for the result.
 */
import { useState } from "react";
import { useJson } from "@/lib/use-json";
import { Field, Modal } from "@/components/proto/blocks";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import { markWords, REASON_WORD, REQUEST_STATE_TONE, REQUEST_STATE_WORD, requestOpen } from "@/lib/result-monitor";
import type { CorrectionRequest } from "./RecordDetail";

const ENTRY_DESKS = ["lecturer", "exams", "gst", "eps"];

export interface RaisePrefill { studentId: string; outcome: string; ca: string; exam: string; reason: string }

export function CorrectionRequests({ sheetId, stage, actingOffice, onRaise }: {
  sheetId: string; stage: string; actingOffice: string | null; onRaise?: (p: RaisePrefill) => void;
}) {
  const [tick, setTick] = useState(0);
  const { data: rows } = useJson<CorrectionRequest[]>(`/api/bff/api/v1/results/sheets/${sheetId}/correction-requests`, tick);
  const [decline, setDecline] = useState<{ q: CorrectionRequest; note: string } | null>(null);
  const [busy, setBusy] = useState(false);

  const open = (rows ?? []).filter((q) => requestOpen(q.state));
  if (!open.length) return null;
  const entryDesk = !!actingOffice && ENTRY_DESKS.includes(actingOffice);
  const published = stage === "PUBLISHED";

  async function sendDecline() {
    if (!decline || decline.note.trim().length < 10) return;
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/results/correction-requests/${decline.q.id}/decline`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Correction ${decline.q.ref} declined: ${decline.note.trim()}`) },
        body: JSON.stringify({ note: decline.note.trim() }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: "The correction was not declined" }); return; }
      notify(`Correction ${decline.q.ref} declined; the Director of ICT sees your reason.`);
      setDecline(null);
      setTick((x) => x + 1);
    } finally { setBusy(false); }
  }

  return (
    <Panel title={`Corrections asked of this sheet (${open.length})`} right={<span className="sub2">From the Director of ICT</span>}>
      <PBody>
        <Note kind="bad" title={published ? "Raise the amendment for each, or decline it with your reason" : "Correct the mark on this sheet, or decline it with your reason"}>
          {published
            ? "The published mark changes only by an amendment through the chain; the request follows it and closes when it is applied."
            : "The request closes when the corrected mark is saved on the sheet. Every version of the mark is kept."}
        </Note>
        <DTable noPrint pageSize={0} cols={["Ref", "State", "Student", "As it stands", "Asked for", "Why", ""]}
          rows={open.map((q) => [q.ref, <Pil key="s" kind={REQUEST_STATE_TONE[q.state] ?? "grey"}>{REQUEST_STATE_WORD[q.state] ?? q.state}</Pil>,
            `${q.surname.toUpperCase()}, ${q.otherNames} (${q.number ?? "—"})`,
            markWords({ ca: q.wasCa, exam: q.wasExam, total: q.wasTotal, grade: q.wasGrade, outcome: q.wasOutcome }),
            q.ca != null || q.outcome ? markWords({ ca: q.ca, exam: q.exam, outcome: q.outcome }) : "Remove or move the result",
            <span key="w">{REASON_WORD[q.reasonKind] ?? q.reasonKind}: {q.note}{q.amendmentRef ? <><br /><span className="sub2">Amendment {q.amendmentRef}</span></> : null}</span>,
            entryDesk && q.state === "OPEN" ? (
              <span key="a" className="row row--inline">
                {published && onRaise ? <Btn kind="primary" onClick={() => onRaise({ studentId: q.studentId, outcome: q.outcome ?? "GRADED", ca: q.ca != null ? String(q.ca) : "",
                  exam: q.exam != null ? String(q.exam) : "", reason: `${q.ref} (${REASON_WORD[q.reasonKind] ?? q.reasonKind}): ${q.note}` })}>Raise the amendment</Btn> : null}
                <Btn kind="ghost" onClick={() => setDecline({ q, note: "" })}>Decline</Btn>
              </span>
            ) : ""])} />
      </PBody>
      {decline ? (
        <Modal title={`Decline ${decline.q.ref}`} sub="Your reason goes on the record and back to the Director of ICT" onClose={() => setDecline(null)}
          foot={<><Btn kind="ghost" onClick={() => setDecline(null)}>Cancel</Btn><span className="grow" /><Btn kind="urgent" disabled={decline.note.trim().length < 10 || busy} busy={busy} onClick={() => void sendDecline()}>Decline it</Btn></>}>
          <Field id="crq-decline" label="Why the result stands" hint="Ten characters or more">
            <textarea id="crq-decline" className="ctl" rows={3} value={decline.note} onChange={(e) => setDecline({ ...decline, note: e.target.value })} />
          </Field>
        </Modal>
      ) : null}
    </Panel>
  );
}
