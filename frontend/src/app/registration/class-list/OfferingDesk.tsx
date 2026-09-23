"use client";

/**
 * Beside the class list, the offering's own desk (V027): the register the
 * lecturer marks over the roll, lecture by lecture; the slots the
 * department gives it on the timetable; and the paper's slot on the
 * examination timetable, which the student's docket carries.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { ClassList } from "@/lib/results";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface DeskData {
  slots: { id: string; weekday: number; starts_at: string; ends_at: string; venue: string; kind: string }[];
  attendance: { days: { held_on: string; on_roll: number; present: number }[]; students: { student_id: string; matric_no: string; surname: string; other_names: string; held: number; attended: number; rate: number }[] };
  examSlot: { held_on?: string; starts_at?: string; ends_at?: string; venue?: string };
}

const WEEKDAY = ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

export function OfferingDesk({ roll, desk, actingOffice }: { roll: ClassList; desk: DeskData; actingOffice: string | null }) {
  const router = useRouter();
  const teaches = ["lecturer", "hod", "dean", "super"].includes(actingOffice ?? "");
  const examsOffice = ["exams", "facultyexams", "records", "academic", "registrar", "super"].includes(actingOffice ?? "");
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [heldOn, setHeldOn] = useState(new Date().toISOString().slice(0, 10));
  const [present, setPresent] = useState<Set<string>>(new Set(roll.rows.map((r) => r.studentId)));
  const [slot, setSlot] = useState({ weekday: "1", startsAt: "08:00", endsAt: "10:00", venue: "", kind: "LECTURE" });
  const [exam, setExam] = useState({ heldOn: desk.examSlot.held_on ?? "", startsAt: (desk.examSlot.starts_at ?? "09:00").slice(0, 5), endsAt: (desk.examSlot.ends_at ?? "12:00").slice(0, 5), venue: desk.examSlot.venue ?? "" });

  async function send(key: string, method: "POST" | "PUT", path: string, body: unknown, reason: string) {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify(reason);
      router.refresh();
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title={`Attendance · ${roll.courseCode}`} right={desk.attendance.days.length ? `${desk.attendance.days.length} lecture${desk.attendance.days.length === 1 ? "" : "s"} recorded` : "no lecture recorded yet"}>
        <PBody>
          <div className="sub2">The register is marked over the class list and nothing else: tick who is present, and everybody on the roll not ticked is recorded absent for the day. Marking the same day again replaces that day&rsquo;s register.</div>
          <div style={{ display: "flex", gap: 9, flexWrap: "wrap", alignItems: "center" }}>
            <input className="ctl tnum" type="date" value={heldOn} onChange={(e) => setHeldOn(e.target.value)} aria-label="Lecture date" style={{ width: 170 }} disabled={!teaches} />
            <Btn kind="ghost" disabled={!teaches} onClick={() => setPresent(new Set(roll.rows.map((r) => r.studentId)))}>All present</Btn>
            <Btn kind="ghost" disabled={!teaches} onClick={() => setPresent(new Set())}>None</Btn>
            <Btn kind="primary" disabled={!teaches || busy !== null || !heldOn} onClick={() => void send("att", "POST", `/registration/offerings/${roll.offeringId}/attendance`, { heldOn, present: [...present] }, `Attendance of ${roll.courseCode} on ${heldOn}: ${present.size} of ${roll.rows.length} present`)}>{busy === "att" ? "Recording…" : `Record ${present.size} of ${roll.rows.length} present`}</Btn>
          </div>
        </PBody>
        <DTable cols={["Present|mid", "Matriculation number", "Name", "Rate so far|num"]} rows={roll.rows.map((r) => {
          const st = desk.attendance.students.find((s) => s.student_id === r.studentId);
          return [
            <input key="p" type="checkbox" className="chk" checked={present.has(r.studentId)} disabled={!teaches} onChange={(e) => { const n = new Set(present); if (e.target.checked) n.add(r.studentId); else n.delete(r.studentId); setPresent(n); }} aria-label={`Present: ${r.surname}`} />,
            <span className="tnum" key="m">{r.number}</span>,
            <span key="n"><strong>{r.surname}</strong>, {r.otherNames}</span>,
            st ? <span key="r" style={{ display: "inline-flex", gap: 6, alignItems: "center" }}><span className="tnum">{st.attended}/{st.held}</span>{st.rate < 75 ? <Pil kind="bad">{st.rate}%</Pil> : <Pil kind="ok">{st.rate}%</Pil>}</span> : <span className="sub2" key="r">—</span>,
          ];
        })} texts={roll.rows.map((r) => `${r.number} ${r.surname} ${r.otherNames}`)} />
      </Panel>
      <div className="grid grid--2">
        <Panel title="Timetable slots" right="The department's, for this course">
          <DTable cols={["Day", "Time|mid", "Venue", "Kind|mid", "|num"]} rows={desk.slots.map((s) => [
            WEEKDAY[s.weekday], <span className="tnum" key="t">{String(s.starts_at).slice(0, 5)}–{String(s.ends_at).slice(0, 5)}</span>, s.venue, <span className="sub2" key="k">{s.kind.toLowerCase()}</span>,
            <Btn kind="ghost" key="e" disabled={!teaches || busy !== null} onClick={() => void send(`end-${s.id}`, "POST", `/registration/offerings/${roll.offeringId}/slots/${s.id}/end`, {}, `Slot ended for ${roll.courseCode}`)}>End</Btn>,
          ])} />
          <PBody>
            <div className="grid grid--2">
              <Field id="sd" label="Day"><select id="sd" className="ctl" value={slot.weekday} onChange={(e) => setSlot({ ...slot, weekday: e.target.value })} disabled={!teaches}>{[1, 2, 3, 4, 5, 6, 7].map((d) => <option key={d} value={d}>{WEEKDAY[d]}</option>)}</select></Field>
              <Field id="sk" label="Kind"><select id="sk" className="ctl" value={slot.kind} onChange={(e) => setSlot({ ...slot, kind: e.target.value })} disabled={!teaches}><option value="LECTURE">Lecture</option><option value="PRACTICAL">Practical</option><option value="TUTORIAL">Tutorial</option></select></Field>
              <Field id="ss" label="From"><input id="ss" className="ctl tnum" type="time" value={slot.startsAt} onChange={(e) => setSlot({ ...slot, startsAt: e.target.value })} disabled={!teaches} /></Field>
              <Field id="se" label="To"><input id="se" className="ctl tnum" type="time" value={slot.endsAt} onChange={(e) => setSlot({ ...slot, endsAt: e.target.value })} disabled={!teaches} /></Field>
            </div>
            <Field id="sv" label="Venue"><input id="sv" className="ctl" value={slot.venue} onChange={(e) => setSlot({ ...slot, venue: e.target.value })} disabled={!teaches} placeholder="LT 2, Science Complex" /></Field>
            <div><Btn kind="primary" disabled={!teaches || busy !== null || !slot.venue.trim()} onClick={() => void send("slot", "POST", `/registration/offerings/${roll.offeringId}/slots`, { weekday: Number(slot.weekday), startsAt: slot.startsAt, endsAt: slot.endsAt, venue: slot.venue, kind: slot.kind }, `Slot given to ${roll.courseCode}: ${WEEKDAY[Number(slot.weekday)]} ${slot.startsAt}`)}>{busy === "slot" ? "Adding…" : "Add the slot"}</Btn></div>
          </PBody>
        </Panel>
        <Panel title="Examination slot" right={desk.examSlot.held_on ? "on the docket" : "not yet timetabled"}>
          <PBody>
            <div className="sub2">The Examinations Office gives the paper its day, time and venue; every candidate on the roll sees it on the docket the scheme releases.</div>
            <div className="grid grid--2">
              <Field id="ed" label="Date"><input id="ed" className="ctl tnum" type="date" value={exam.heldOn} onChange={(e) => setExam({ ...exam, heldOn: e.target.value })} disabled={!examsOffice} /></Field>
              <Field id="ev" label="Venue"><input id="ev" className="ctl" value={exam.venue} onChange={(e) => setExam({ ...exam, venue: e.target.value })} disabled={!examsOffice} placeholder="CBT Hall A" /></Field>
              <Field id="es" label="From"><input id="es" className="ctl tnum" type="time" value={exam.startsAt} onChange={(e) => setExam({ ...exam, startsAt: e.target.value })} disabled={!examsOffice} /></Field>
              <Field id="ee" label="To"><input id="ee" className="ctl tnum" type="time" value={exam.endsAt} onChange={(e) => setExam({ ...exam, endsAt: e.target.value })} disabled={!examsOffice} /></Field>
            </div>
            <div><Btn kind="primary" disabled={!examsOffice || busy !== null || !exam.heldOn || !exam.venue.trim()} onClick={() => void send("exam", "PUT", `/results/offerings/${roll.offeringId}/exam-slot`, exam, `Examination slot for ${roll.courseCode}: ${exam.heldOn} ${exam.startsAt} ${exam.venue}`)}>{busy === "exam" ? "Saving…" : "Timetable the paper"}</Btn></div>
            {!examsOffice ? <Note kind="info" title="Set by the Examinations Office">The slot is theirs to give; the department sees it here.</Note> : null}
          </PBody>
        </Panel>
      </div>
    </>
  );
}
