"use client";

/** The Super Administrator's clean slate (V089): clear all uploaded operational data — admissions,
 *  students, results, courses, fees, payments, wallets — keeping reference data, configuration, staff
 *  logins and the audit trail. Guarded by typing RESET and a reason; the deletion is on the spine. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
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
  const [demoOpen, setDemoOpen] = useState(false);
  const [demoConfirm, setDemoConfirm] = useState("");
  const [demoBusy, setDemoBusy] = useState(false);
  const [demoDone, setDemoDone] = useState<string | null>(null);
  const [courseOpen, setCourseOpen] = useState(false);
  const [courseConfirm, setCourseConfirm] = useState("");
  const [courseBusy, setCourseBusy] = useState(false);

  if (!may) return null;

  async function removeDemoCourses() {
    setCourseBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/platform/remove-demo-courses", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Demo courses removed from the catalogue") },
        body: JSON.stringify({ confirm: courseConfirm.trim() }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const c = j as Record<string, number>;
      setDemoDone(`Removed ${c.demo_courses ?? 0} demo course(s) and ${c.demo_offerings ?? 0} demo course session(s) from the catalogue. No student, candidate or real course was touched.`);
      setCourseOpen(false); setCourseConfirm("");
      notify("Demo courses removed");
      router.refresh();
    } finally {
      setCourseBusy(false);
    }
  }

  async function removeDemo() {
    setDemoBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/platform/remove-demo", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Demo data removed, keeping demo logins") },
        body: JSON.stringify({ confirm: demoConfirm.trim() }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const c = j as Record<string, number>;
      setDemoDone(`Removed ${c.demo_students ?? 0} demo student(s), ${c.demo_courses ?? 0} demo course(s) and ${c.demo_candidates ?? 0} demo candidate(s). The demo staff logins and all real data are kept.`);
      setDemoOpen(false); setDemoConfirm("");
      notify("Demo data removed");
      router.refresh();
    } finally {
      setDemoBusy(false);
    }
  }

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
      notify("All uploaded data reset");
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
        {demoDone ? <Note kind="ok" title="Demo data removed">{demoDone}</Note> : null}
        <Note kind="info" title="Just clearing the demo? Use the targeted removal">
          <b>Remove demo data only</b> deletes the walkthrough seed — the demo students (surname DEMO), the
          &ldquo;DMO&rdquo; courses and the demo JAMB candidates — and <b>keeps</b> the demo staff sign-ins
          (demo.bursar, demo.hod &hellip;) and every real record you have uploaded. Use this instead of the full reset
          when your real data should stay.
        </Note>
        <Note kind="info" title="Only stray demo courses left? Remove just those">
          <b>Remove demo courses only</b> deletes the walkthrough courses in the catalogue — those coded
          &ldquo;DMO&rdquo; or &ldquo;DMC&rdquo;, or titled &ldquo;Demo &hellip;&rdquo; — with their offerings,
          materials, score sheets and any registration entries on them. It touches <b>no</b> student, candidate or real
          course. Use this when the only demo left over is courses like <b>DMC 301 — Demo DMC 301</b>.
        </Note>
        <div style={{ marginTop: 6, display: "flex", gap: 8, flexWrap: "wrap" }}>
          <Btn kind="primary" onClick={() => { setCourseOpen(true); setCourseConfirm(""); setProblem(null); setDemoDone(null); }}>Remove demo courses only…</Btn>
          <Btn kind="primary" onClick={() => { setDemoOpen(true); setDemoConfirm(""); setProblem(null); setDemoDone(null); }}>Remove demo data only…</Btn>
          <Btn kind="urgent" onClick={() => { setOpen(true); setConfirm(""); setReason(""); setProblem(null); setDone(null); }}>Reset ALL uploaded data…</Btn>
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
      {courseOpen ? (
        <Modal title="Remove demo courses only" sub="Keeps every student, candidate and real course" onClose={() => setCourseOpen(false)}
          foot={<><Btn kind="ghost" onClick={() => setCourseOpen(false)}>Cancel</Btn><span style={{ flexGrow: 1 }} />
            <Btn kind="primary" disabled={courseBusy || courseConfirm.trim().toUpperCase() !== "REMOVE DEMO"} onClick={() => void removeDemoCourses()}>{courseBusy ? "Removing…" : "Remove demo courses"}</Btn></>}>
          <Note kind="info" title="What this removes">
            Only the demo courses in the catalogue — those coded &ldquo;DMO&rdquo; or &ldquo;DMC&rdquo;, or titled
            &ldquo;Demo &hellip;&rdquo; — with their offerings, materials, assignments, score sheets and any registration
            entries on them. No student, candidate or real course is touched. It runs in one transaction.
          </Note>
          <Field id="dc-confirm" label="Type REMOVE DEMO to confirm" hint="In capitals"><input id="dc-confirm" className="ctl tnum" value={courseConfirm} onChange={(e) => setCourseConfirm(e.target.value)} placeholder="REMOVE DEMO" autoComplete="off" /></Field>
        </Modal>
      ) : null}
      {demoOpen ? (
        <Modal title="Remove demo data only" sub="Keeps demo logins and all real data" onClose={() => setDemoOpen(false)}
          foot={<><Btn kind="ghost" onClick={() => setDemoOpen(false)}>Cancel</Btn><span style={{ flexGrow: 1 }} />
            <Btn kind="primary" disabled={demoBusy || demoConfirm.trim().toUpperCase() !== "REMOVE DEMO"} onClick={() => void removeDemo()}>{demoBusy ? "Removing…" : "Remove demo data"}</Btn></>}>
          <Note kind="info" title="What this removes">
            Only the db/demo.sql seed: the demo students (surname DEMO), the &ldquo;DMO&rdquo; courses and their
            offerings, and the demo JAMB candidates, with the records hung on them. The demo staff sign-ins and every
            real student, course, payment and result you uploaded are kept. It runs in one transaction.
          </Note>
          <Field id="dd-confirm" label="Type REMOVE DEMO to confirm" hint="In capitals"><input id="dd-confirm" className="ctl tnum" value={demoConfirm} onChange={(e) => setDemoConfirm(e.target.value)} placeholder="REMOVE DEMO" autoComplete="off" /></Field>
        </Modal>
      ) : null}
    </Panel>
  );
}
