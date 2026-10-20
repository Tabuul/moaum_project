"use client";

/** The student's matriculation, before and after (V267): the number, the date, the status, the sign-in username as it was and as it is. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { LinkBtn, Note, Panel, PBody, Pil, KvGrid } from "@/components/proto/ui";
import { dayOf, whenAt, type StudentMatricRecord } from "@/lib/matric-manage";

export function MatriculationPanel({ studentId }: { studentId: string }) {
  const [rec, setRec] = useState<StudentMatricRecord | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  useEffect(() => {
    let live = true;
    fetch(`/api/bff/api/v1/matriculation/students/${studentId}/record`, { cache: "no-store" })
      .then(async (r) => { const j = await r.json().catch(() => null); if (!live) return; if (!r.ok) setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); else setRec(j as StudentMatricRecord); })
      .catch(() => { if (live) setProblem({ status: 0, title: "Could not read the matriculation record." }); });
    return () => { live = false; };
  }, [studentId]);
  if (problem) return null;
  if (!rec) return <Panel title="Matriculation"><PBody><div className="sub2">Reading…</div></PBody></Panel>;
  // the sign-in before matriculation: the oldest change that was not a correction of the number (V579), else the admission number
  const issued = rec.usernameHistory.filter((u) => !u.reason.startsWith("Matriculation number corrected"));
  const before = issued.length ? issued[issued.length - 1].previous_username : rec.admission_no;
  const open = rec.proposals.find((p) => p.state === "PROPOSED" && p.batch_state !== "CANCELLED");
  // V579: the number's corrections — the one made last, and one waiting for a decision
  const corrected = (rec.corrections ?? []).find((c) => c.state === "COMPLETED");
  const waiting = (rec.corrections ?? []).find((c) => c.state === "PENDING_REVIEW");
  return (
    <Panel title="Matriculation" right={<Pil kind={rec.matriculation_status === "MATRICULATED" ? "ok" : "info"}>{rec.matriculation_status === "MATRICULATED" ? "MATRICULATED" : "PRE-MATRICULATION"}</Pil>}>
      <PBody>
        {rec.matric_no ? (
          <>
            <div className="eyebrow">Matriculation number</div>
            <div className="t-lg b700 tnum mb-2">{rec.matric_no}</div>
            {corrected ? <div className="sub2 mb-2"><Pil kind="info">Corrected</Pil> from <span className="tnum">{corrected.old_no}</span> ({corrected.ref}, {dayOf(corrected.decided_at)}); the old number is kept and still finds this record.</div> : null}
            {waiting ? <Note kind="info" title={`${waiting.ref}: a correction to ${waiting.new_no} waits for a decision`} action={<LinkBtn size="sm" href={`/matriculation/corrections?student=${rec.id}`}>Open</LinkBtn>}>{waiting.reason}</Note> : null}
            <KvGrid cls="grid--3" pairs={[["Matriculation date", dayOf(rec.matriculated_at)], ["Batch / run", rec.batch_ref ?? rec.run_ref ?? "—"], ["Portal sign-in username", <b key="u" className="tnum">{rec.username}</b>]]} />
            <div className="grid grid--2 mt-2">
              <div><div className="eyebrow mb-1">Before</div><div className="sub2">Username: <span className="tnum">{before ?? "—"}</span></div><div className="sub2">Status: Admitted / Pre-matriculation</div><div className="sub2">Matric number: Not assigned</div></div>
              <div><div className="eyebrow mb-1">After</div><div className="sub2">Username: <b className="tnum">{rec.matric_no}</b></div><div className="sub2">Status: Matriculated</div><div className="sub2">Matric number: <b className="tnum">{rec.matric_no}</b> · {dayOf(rec.matriculated_at)}</div></div>
            </div>
            {(rec.numberHistory ?? []).some((h) => h.event === "CORRECTED") ? <div className="mt-2"><div className="eyebrow mb-1">Matriculation number history</div>{(rec.numberHistory ?? []).map((h, i) => <div key={i} className="sub2">{whenAt(h.at)} · {h.event === "CORRECTED" ? <>corrected <span className="tnum">{h.previous_no}</span> → <b className="tnum">{h.matric_no}</b></> : h.event === "ISSUED" ? <>issued <b className="tnum">{h.matric_no}</b></> : <>on the register as <b className="tnum">{h.matric_no}</b></>}{h.ref ? ` · ${h.ref}` : ""}{h.by_name ? ` · ${h.by_name}` : ""}{h.office ? ` (${h.office})` : ""}{h.event === "CORRECTED" && h.reason ? ` · ${h.reason}` : ""}</div>)}</div> : null}
            {rec.usernameHistory.length ? <div className="mt-2"><div className="eyebrow mb-1">Username history</div>{rec.usernameHistory.map((u, i) => <div key={i} className="sub2">{whenAt(u.changed_at)} · {u.previous_username ?? "—"} → <b className="tnum">{u.new_username}</b> · {u.reason}{u.officer ? ` · ${u.officer}` : ""}{u.office ? ` (${u.office})` : ""}{u.batch_ref ? ` · ${u.batch_ref}` : ""}</div>)}</div> : null}
          </>
        ) : (
          <>
            <KvGrid cls="grid--3" pairs={[["Portal sign-in username", <span key="u" className="tnum">{rec.username ?? "—"}</span>], ["Status", "Admitted — not yet matriculated"], ["Proposed number", open ? <span key="p"><b className="tnum">{open.proposed_no}</b> <span className="sub2">on batch {open.batch_ref} ({open.batch_state.replace(/_/g, " ").toLowerCase()})</span></span> : "None yet"]]} />
            {open?.problems?.length ? <Note kind="bad" title="The proposed number is in conflict">{open.problems.join("; ")}</Note> : null}
            <div className="sub2 mt-2">The number and sign-in username change only when the batch is issued.</div>
          </>
        )}
      </PBody>
    </Panel>
  );
}
