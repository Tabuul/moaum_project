"use client";

/**
 * V521: ICT Support opens a student's portal as the student — the reason (and the ticket, where the agent came from one), then the
 * portal opens read-only for thirty minutes. Used on the support record and on the student record (Student 360).
 */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export function OpenStudentPortal({ studentId, name, matricNo, ticket, back, onClose }: {
  studentId: string; name: string; matricNo: string | null; ticket?: { id: string; number: string } | null; back: string; onClose: () => void;
}) {
  const [reason, setReason] = useState(ticket ? `Checking the student's portal for ticket ${ticket.number}` : "");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function open() {
    setBusy(true);
    setProblem(null);
    const r = await fetch("/api/auth/support-view", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ studentId, reason: reason.trim(), ticket: ticket?.id ?? null, back }),
    }).catch(() => null);
    const j = r ? await r.json().catch(() => null) : null;
    if (!r || !r.ok) {
      setProblem((j as Problem) ?? { status: r?.status ?? 503, title: "The student's portal could not be opened" });
      setBusy(false);
      return;
    }
    window.location.assign((j as { redirect?: string }).redirect ?? "/student");
  }

  return (
    <Modal title="OPEN STUDENT PORTAL" sub={`${name}${matricNo ? ` · ${matricNo}` : ""}`} onClose={() => { if (!busy) onClose(); }}
      foot={<>
        <Btn kind="ghost" disabled={busy} onClick={onClose}>Cancel</Btn>
        <Btn kind="primary" disabled={reason.trim().length < 10} busy={busy} busyLabel="Opening..." onClick={() => void open()}>OPEN STUDENT PORTAL</Btn>
      </>}>
      <Note kind="info" title="You will see the portal as the student sees it">
        For thirty minutes, without the student&rsquo;s password. It is read-only: nothing can be changed from it — no registration, payment,
        password or record. Your own session waits; LEAVE STUDENT VIEW at the top brings it back. The opening is recorded on the support
        ledger{ticket ? " and the ticket" : ""} with your reason.
      </Note>
      <div className="mt-2">
        <Field id="osp-reason" label="Reason" required hint="Ten characters or more; kept on the support ledger">
          <input id="osp-reason" className="ctl" value={reason} maxLength={500} autoFocus onChange={(e) => setReason(e.target.value)}
            placeholder="e.g. The student says the registration page shows no courses" />
        </Field>
      </div>
      {problem ? <div className="mt-2"><ProblemNotice problem={problem} /></div> : null}
    </Modal>
  );
}
