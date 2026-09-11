"use client";

/** The Super Administrator's clean slate (V089): clear all uploaded operational data — admissions,
 *  students, results, courses, fees, payments, wallets — keeping reference data, configuration, staff
 *  logins and the audit trail. Guarded by typing RESET and a reason; the deletion is on the spine. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export function ResetData({ office }: { office: string | null }) {
  const router = useRouter();
  const may = office === "super" || office === "ict";
  const [open, setOpen] = useState(false);
  const [confirm, setConfirm] = useState("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [done, setDone] = useState<string | null>(null);

  if (!may) return null;

  async function run() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/platform/reset-data", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`All uploaded data reset: ${reason.trim()}`) },
        body: JSON.stringify({ confirm: confirm.trim(), reason: reason.trim() }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const c = j as Record<string, number>;
      setDone(`Cleared: ${c.students ?? 0} students, ${c.candidates ?? 0} candidates, ${c.applications ?? 0} applications, ${c.results ?? 0} result marks, ${c.courses ?? 0} courses, ${c.fee_lines ?? 0} fee lines, ${c.payments ?? 0} payment references, ${c.wallet_entries ?? 0} wallet entries.`);
      setOpen(false); setConfirm(""); setReason("");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Panel title="Danger zone — reset uploaded data" right="Super Administrator & Director of ICT">
      <PBody>
        <Note kind="bad" title="Clear all uploaded operational data and start afresh">
          This permanently deletes the admissions and JAMB/CAPS lists, applicants, students, course registrations,
          results, uploaded courses, fee schedules, payments and wallets, and the records hung on students across the
          modules. It <b>keeps</b> reference data (faculties, programmes, offices, fee items), configuration (sessions,
          the admission policy, the clearance scheme, fee settings, funding sources), staff logins, and the whole audit
          trail. It <b>cannot be undone</b>. Every deletion is recorded on the audit spine in your name.
        </Note>
        {problem ? <ProblemNotice problem={problem} /> : null}
        {done ? <Note kind="ok" title="Uploaded data cleared">{done}</Note> : null}
        <div style={{ marginTop: 6 }}>
          <Btn kind="urgent" onClick={() => { setOpen(true); setConfirm(""); setReason(""); setProblem(null); setDone(null); }}>Reset all uploaded data…</Btn>
        </div>
      </PBody>
      {open ? (
        <Modal title="Reset all uploaded data" sub="This cannot be undone" onClose={() => setOpen(false)}
          foot={<><Btn kind="ghost" onClick={() => setOpen(false)}>Cancel</Btn><span style={{ flexGrow: 1 }} />
            <Btn kind="urgent" disabled={busy || confirm.trim().toUpperCase() !== "RESET" || !reason.trim()} onClick={() => void run()}>{busy ? "Clearing…" : "Clear everything"}</Btn></>}>
          <Note kind="bad" title="Read this before you continue">
            Every student, applicant, result, uploaded course, fee schedule, payment and wallet will be permanently
            deleted. Reference data, configuration, staff logins and the audit trail are kept. There is no undo.
          </Note>
          <Field id="rd-confirm" label="Type RESET to confirm" hint="In capitals"><input id="rd-confirm" className="ctl tnum" value={confirm} onChange={(e) => setConfirm(e.target.value)} placeholder="RESET" autoComplete="off" /></Field>
          <Field id="rd-reason" label="Reason" hint="Recorded on the audit trail in your name"><input id="rd-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Clearing the test load before go-live" /></Field>
        </Modal>
      ) : null}
    </Panel>
  );
}
