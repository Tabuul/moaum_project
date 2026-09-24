"use client";

/** rMySiwes — the students a lecturer supervises for SIWES; the supervisor records the assessment /40. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface MySiwesStudent {
  offering_id: string; course_code: string; title: string; session: string; semester: number;
  student_id: string; number: string | null; surname: string; other_names: string; programme: string | null;
  sheet_id: string | null; sheet_stage: string | null;
  supervisor_mark: number | null; practical_mark: number | null; total: number | null;
}

export function MySiwes({ students }: { students: MySiwesStudent[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  const [marks, setMarks] = useState<Record<string, string>>({});

  async function save(s: MySiwesStudent) {
    const raw = s.student_id in marks ? marks[s.student_id] : String(s.supervisor_mark ?? "");
    const mark = Number(raw);
    if (raw.trim() === "" || Number.isNaN(mark)) return;
    const reason = s.supervisor_mark != null && s.supervisor_mark !== mark
      ? window.prompt(`Why is ${s.surname}'s assessment changing from ${s.supervisor_mark} to ${mark}?`) ?? "" : "";
    if (s.supervisor_mark != null && s.supervisor_mark !== mark && !reason.trim()) return;
    setBusy(s.student_id);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/siwes/mine/students/${s.student_id}/score`, {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`SIWES assessment recorded for ${s.surname}`) },
        body: JSON.stringify({ offering: s.offering_id, mark, reason }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return; }
      notify(`SIWES assessment recorded for ${s.surname}`);
      router.refresh();
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <Note kind="info" title="You supervise these students for SIWES">
        Record each student&rsquo;s assessment out of 40. The SIWES Coordinator records the report of the practicals out of 60; a student&rsquo;s total is complete when both are in. A mark can be entered only while the sheet is at entry.
      </Note>
      {err ? <ProblemNotice problem={err} /> : null}
      <Panel title="My SIWES students" right={`${students.length} student${students.length === 1 ? "" : "s"}`}>
        {students.length ? (
          <DTable cols={["Matric|mid", "Name", "Course", "Assessment /40|num", "Practical /60|mid", "Total|mid", "Sheet|mid"]} rows={students.map((s) => {
            const entry = s.sheet_stage === "ENTRY";
            return [
              <span className="tnum" key="m">{s.number ?? "—"}</span>,
              <strong key="n">{s.surname}, {s.other_names}</strong>,
              <span className="sub2 tnum" key="c">{s.course_code}</span>,
              <div key="a" className="row row--tight row--right">
                <input className="ctl tnum" style={{ width: 64 }} inputMode="numeric" disabled={!entry || busy !== null || !s.sheet_id}
                  value={s.student_id in marks ? marks[s.student_id] : (s.supervisor_mark ?? "")}
                  onChange={(e) => setMarks({ ...marks, [s.student_id]: e.target.value })} />
                <Btn kind="primary" disabled={!entry || busy !== null || !s.sheet_id} onClick={() => void save(s)}>{busy === s.student_id ? "Saving…" : "Save"}</Btn>
              </div>,
              <span className={`tnum${s.practical_mark == null ? " ink-muted" : ""}`} key="p">{s.practical_mark ?? "—"}</span>,
              s.total != null ? <Pil kind="ok" key="t">{s.total}</Pil> : <span className="sub2 tnum" key="t">—</span>,
              s.sheet_stage ? <span className="sub2" key="s">{s.sheet_stage === "ENTRY" ? "Entry open" : s.sheet_stage.toLowerCase().replace(/_/g, " ")}</span> : <span className="sub2 ink-red" key="s">Not open</span>,
            ];
          })} texts={students.map((s) => `${s.number} ${s.surname} ${s.other_names} ${s.course_code}`)} />
        ) : <PBody><div className="sub2">No student is assigned to you for SIWES. The Head of Department or SIWES Coordinator assigns supervisors.</div></PBody>}
      </Panel>
    </>
  );
}
