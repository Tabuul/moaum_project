"use client";

/**
 * Voluntary withdrawals (V247): the University's regulation removes from its records a student who has not
 * registered for courses in four consecutive semesters. The record names who is due — the closed semesters
 * since the last approved registration, or since entry — and the Registry closes them here. A change of
 * status is a person's act on an instrument, so the click is the act and the regulation is the instrument;
 * the change is on each record with the semesters missed.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";

export interface VoluntaryDue {
  student_id: string; number: string; surname: string; other_names: string; programme_code: string; programme: string | null;
  current_level: number; status: string; semesters: number; last_registered: string | null; first_missed: string | null;
}
export interface VoluntarySummary { due: VoluntaryDue[]; closed: number }

const INSTRUMENT = "University regulation: four consecutive semesters without course registration";

export function VoluntaryPanel({ summary }: { summary: VoluntarySummary }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [open, setOpen] = useState(false);
  const due = summary.due ?? [];
  const n = (v: number) => Number(v ?? 0);

  async function close(studentIds: string[] | null) {
    const count = studentIds ? studentIds.length : due.length;
    if (!window.confirm(`Close ${count} record${count === 1 ? "" : "s"} as voluntary withdrawal? The student${count === 1 ? "" : "s"} will be off every roll and sheet and refused at the portal; the change is on the record with its instrument.`)) return;
    setBusy(studentIds ? studentIds[0] : "all"); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/student/students/voluntary-withdrawals/close", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Voluntary withdrawal after four consecutive semesters without registration") },
        body: JSON.stringify({ studentIds, instrument: INSTRUMENT }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify(`${n(j.closed)} record${n(j.closed) === 1 ? "" : "s"} closed as voluntary withdrawal`);
      router.refresh();
    } finally { setBusy(null); }
  }

  return (
    <Panel title="Voluntary withdrawals" right="Four consecutive semesters without registering">
      <PBody>
        <Tiles items={[
          ["Due now", String(due.length), due.length ? "var(--red-ink)" : null, due.length ? "Four or more closed semesters without an approved registration" : "Nobody has missed four semesters"],
          ["Closed so far", String(n(summary.closed)), null, "Records closed as voluntary withdrawal"],
        ]} />
        {problem ? <ProblemNotice problem={problem} /> : null}
        {due.length ? (
          <>
            <Note kind="bad" title="The regulation names these students; the Registry closes the records">
              A student who has not registered for courses in four consecutive semesters has withdrawn voluntarily and is removed from the University&rsquo;s records. The count runs over the calendar&rsquo;s closed semesters since the last approved registration, or since entry. Closing a record puts the student off every roll, class list and result sheet and refuses them at the portal; the change stays on the record with the regulation as its instrument.
            </Note>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 8 }}>
              <Btn kind="urgent" onClick={() => close(null)} disabled={busy !== null}>{busy === "all" ? "Closing…" : `Close all ${due.length} due`}</Btn>
              <Btn kind="ghost" onClick={() => setOpen((o) => !o)}>{open ? "Hide the list" : "Show the list"}</Btn>
            </div>
            {open ? (
              <DTable cols={["Matric no.", "Name", "Programme", "Level|mid", "Semesters missed|mid", "From", "Last registered", ""]} rows={due.map((d) => [
                <span className="tnum" key="n">{d.number}</span>,
                <strong key="nm">{d.surname}, {d.other_names}</strong>,
                <span className="sub2" key="p">{d.programme ?? d.programme_code}</span>,
                <span className="tnum" key="l">{d.current_level}</span>,
                <strong className="tnum" style={{ color: "var(--red-ink)" }} key="s">{d.semesters}</strong>,
                <span className="sub2" key="f">{d.first_missed ?? "—"}</span>,
                <span className="sub2" key="lr">{d.last_registered ?? "Never"}</span>,
                <Btn kind="ghost" key="b" onClick={() => close([d.student_id])} disabled={busy !== null}>{busy === d.student_id ? "Closing…" : "Close"}</Btn>,
              ])} />
            ) : null}
          </>
        ) : null}
      </PBody>
    </Panel>
  );
}
