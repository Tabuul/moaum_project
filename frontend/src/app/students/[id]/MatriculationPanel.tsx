"use client";

/** The student's matriculation, before and after (V267): the number, the date, the status, the sign-in username as it was and as it is. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { Note, Panel, PBody, Pil, KvGrid } from "@/components/proto/ui";
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
  const before = rec.usernameHistory.length ? rec.usernameHistory[rec.usernameHistory.length - 1].previous_username : rec.admission_no;
  const open = rec.proposals.find((p) => p.state === "PROPOSED" && p.batch_state !== "CANCELLED");
  return (
    <Panel title="Matriculation" right={<Pil kind={rec.matriculation_status === "MATRICULATED" ? "ok" : "info"}>{rec.matriculation_status === "MATRICULATED" ? "MATRICULATED" : "PRE-MATRICULATION"}</Pil>}>
      <PBody>
        {rec.matric_no ? (
          <>
            <div className="eyebrow">Matriculation number</div>
            <div className="t-lg b700 tnum mb-2">{rec.matric_no}</div>
            <KvGrid cls="grid--3" pairs={[["Matriculation date", dayOf(rec.matriculated_at)], ["Batch / run", rec.batch_ref ?? rec.run_ref ?? "—"], ["Portal sign-in username", <b key="u" className="tnum">{rec.username}</b>]]} />
            <div className="grid grid--2 mt-2">
              <div><div className="eyebrow mb-1">Before</div><div className="sub2">Username: <span className="tnum">{before ?? "—"}</span></div><div className="sub2">Status: Admitted / Pre-matriculation</div><div className="sub2">Matric number: Not assigned</div></div>
              <div><div className="eyebrow mb-1">After</div><div className="sub2">Username: <b className="tnum">{rec.matric_no}</b></div><div className="sub2">Status: Matriculated</div><div className="sub2">Matric number: <b className="tnum">{rec.matric_no}</b> · {dayOf(rec.matriculated_at)}</div></div>
            </div>
            {rec.usernameHistory.length ? <div className="mt-2"><div className="eyebrow mb-1">Username history</div>{rec.usernameHistory.map((u, i) => <div key={i} className="sub2">{whenAt(u.changed_at)} · {u.previous_username ?? "—"} → <b className="tnum">{u.new_username}</b> · {u.reason}{u.officer ? ` · ${u.officer}` : ""}{u.office ? ` (${u.office})` : ""}{u.batch_ref ? ` · ${u.batch_ref}` : ""}</div>)}</div> : null}
          </>
        ) : (
          <>
            <KvGrid cls="grid--3" pairs={[["Portal sign-in username", <span key="u" className="tnum">{rec.username ?? "—"}</span>], ["Status", "Admitted — not yet matriculated"], ["Proposed number", open ? <span key="p"><b className="tnum">{open.proposed_no}</b> <span className="sub2">on batch {open.batch_ref} ({open.batch_state.replace(/_/g, " ").toLowerCase()})</span></span> : "None yet"]]} />
            {open?.problems?.length ? <Note kind="bad" title="The proposed number is in conflict">{open.problems.join("; ")}</Note> : null}
            <div className="sub2 mt-2">A proposed number is preparation only; the matriculation number and the sign-in username change when the batch is issued on Matriculation Management.</div>
          </>
        )}
      </PBody>
    </Panel>
  );
}
