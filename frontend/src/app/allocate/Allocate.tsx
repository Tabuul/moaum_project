"use client";

/** rAllocate — proto/part17.html: the department's offerings, and assigning a lecturer
 *  (which sets the second examiner and opens the score sheet at the same moment). */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Dept { code: string; name: string; faculty_code: string }
export interface Lecturer { id: string; name: string; staff_number: string | null; load: number }
export interface Offering {
  id: string; course_code: string; title: string; units: number; allocated_on: string | null; registered: number;
  lecturer_id: string | null; lecturer: string | null; second_examiner_id: string | null; second_examiner: string | null; sheet: boolean;
}

const MAX_UNITS = 12;

export function Allocate({ depts, sessions, dept, session, semester, offerings, lecturers, problem }: {
  depts: Dept[]; sessions: string[]; dept: string; session: string; semester: number;
  offerings: Offering[]; lecturers: Lecturer[]; problem: Problem | null;
}) {
  const router = useRouter();
  const [open, setOpen] = useState<Offering | null>(null);
  const [lecturer, setLecturer] = useState("");
  const [second, setSecond] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const unassigned = offerings.filter((o) => !o.lecturer_id).length;
  const noSecond = offerings.filter((o) => o.lecturer_id && !o.second_examiner_id).length;

  function go(next: { dept?: string; session?: string; sem?: number }) {
    const q = new URLSearchParams();
    q.set("dept", next.dept ?? dept);
    q.set("session", next.session ?? session);
    q.set("sem", String(next.sem ?? semester));
    router.push(`/allocate?${q.toString()}`);
  }

  function openAssign(o: Offering) {
    setOpen(o);
    setLecturer(o.lecturer_id ?? "");
    setSecond(o.second_examiner_id ?? "");
    setErr(null);
  }

  async function assign(overload: boolean) {
    if (!open || !lecturer) return;
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/allocation/${open.id}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Allocate ${open.course_code}`) },
        body: JSON.stringify({ lecturer, secondExaminer: second || null, overload }),
      });
      if (!r.ok) { setErr((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }); return; }
      const who = lecturers.find((l) => l.id === lecturer)?.name ?? "the lecturer";
      setSaid(`${open.course_code} assigned to ${who}`);
      setOpen(null);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const chosenLoad = lecturers.find((l) => l.id === lecturer)?.load ?? 0;
  const after = open ? chosenLoad + open.units : 0;
  const overloaded = after > MAX_UNITS;

  return (
    <>
      <div className="card"><div className="card__body" style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "flex-end" }}>
        <div className="field" style={{ minWidth: 220 }}><label htmlFor="al-dept">Department</label>
          <select id="al-dept" className="ctl" value={dept} onChange={(e) => go({ dept: e.target.value })}>
            {depts.map((d) => <option key={d.code} value={d.code}>{d.name}</option>)}
          </select></div>
        <div className="field" style={{ minWidth: 150 }}><label htmlFor="al-session">Session</label>
          <select id="al-session" className="ctl" value={session} onChange={(e) => go({ session: e.target.value })}>
            {(sessions.includes(session) ? sessions : [session, ...sessions]).map((s) => <option key={s} value={s}>{s}</option>)}
          </select></div>
        <div className="field" style={{ minWidth: 130 }}><label htmlFor="al-sem">Semester</label>
          <select id="al-sem" className="ctl" value={semester} onChange={(e) => go({ sem: Number(e.target.value) })}>
            <option value={1}>First</option><option value={2}>Second</option>
          </select></div>
      </div></div>

      {said ? <Note kind="ok" title={said}>The score sheet opens in the lecturer&rsquo;s name once the examination session is open, and the second examiner is set for verification.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}

      {unassigned ? (
        <Note kind="bad" title={`${unassigned} course${unassigned === 1 ? " is" : "s are"} unassigned`}>
          Assigning a lecturer opens the course space, the score sheet and the attendance register, and lets the timetable place the class. Until then those students have nothing.
        </Note>
      ) : offerings.length ? (
        <Note kind="ok" title="Every course this semester has a lecturer">{noSecond ? `${noSecond} still needs a second examiner before it can reach verification.` : "Every one also has a second examiner set."}</Note>
      ) : null}

      <Tiles items={[
        ["Courses", String(offerings.length), null, `${session} · ${semester === 1 ? "first" : "second"} semester`],
        ["Unassigned", String(unassigned), unassigned ? "var(--red-ink)" : "var(--green-ink)", "No lecturer yet"],
        ["No second examiner", String(noSecond), noSecond ? "var(--red-ink)" : null, "Blocks verification"],
        ["Lecturers", String(lecturers.length), null, "In this department"],
      ]} />

      <Panel title="Teaching allocation" right={`${depts.find((d) => d.code === dept)?.name ?? dept} · ${session} · ${semester === 1 ? "first" : "second"} semester`}>
        {offerings.length ? (
          <DTable cols={["Course", "Units|mid", "Registered|mid", "Lecturer", "Second examiner", "Action|num"]} rows={offerings.map((o) => [
            <span key="c"><strong className="tnum">{o.course_code}</strong><div className="sub2">{o.title}</div></span>,
            <span className="tnum" key="u">{o.units}</span>,
            <span className="tnum" key="r">{o.registered}</span>,
            o.lecturer ? <span key="l"><strong>{o.lecturer}</strong>{o.allocated_on ? <div className="sub2">Assigned {o.allocated_on}</div> : null}</span> : <span key="l" style={{ color: "var(--red-ink)", fontWeight: 700 }}>Unassigned</span>,
            o.second_examiner ? <Pil kind="ok" key="s">{o.second_examiner}</Pil> : o.lecturer_id ? <Pil kind="bad" key="s">Not set</Pil> : <span className="sub2" key="s">&mdash;</span>,
            <Btn key="a" kind={o.lecturer_id ? "ghost" : "urgent"} onClick={() => openAssign(o)}>{o.lecturer_id ? "Reassign" : "Assign a lecturer"}</Btn>,
          ])} texts={offerings.map((o) => `${o.course_code} ${o.title} ${o.lecturer ?? ""}`)} />
        ) : <PBody><div className="sub2">No offering is recorded for {depts.find((d) => d.code === dept)?.name ?? dept} in {session}, {semester === 1 ? "first" : "second"} semester. An offering appears when the department offers the course for the session.</div></PBody>}
      </Panel>

      <Note kind="info" title="Assigning a lecturer does four things at once">
        It opens the course space and enrols the registered students in it, it creates the score sheet in that lecturer&rsquo;s name, it opens the attendance register, and it releases the course to the timetable. The second examiner is set now, not at examination time, because the person who enters the marks may not be the person who verifies them.
      </Note>

      {open ? (
        <Modal title={`Assign a lecturer to ${open.course_code}`} sub={`${open.title} · ${open.units} units · ${open.registered} registered`} wide onClose={() => setOpen(null)}
          foot={<><Btn kind="ghost" onClick={() => setOpen(null)}>Cancel</Btn><span style={{ flexGrow: 1 }} />
            {overloaded
              ? <Btn kind="urgent" disabled={busy || !lecturer} onClick={() => void assign(true)}>Assign as an overload ({after} units)</Btn>
              : <Btn kind="go" disabled={busy || !lecturer} onClick={() => void assign(false)}>Assign</Btn>}</>}>
          {err ? <ProblemNotice problem={err} /> : null}
          <div className="sub2" style={{ marginBottom: 8 }}>Ordered by remaining capacity against the approved maximum of {MAX_UNITS} units. A lecturer already at the maximum can still be assigned, but the assignment is recorded as an overload.</div>
          {lecturers.length ? (
            <DTable cols={["Lecturer", "Current load|mid", "After this|mid", "|num"]} rows={lecturers.map((l) => {
              const willBe = l.load + open.units;
              return [
                <Two key="n" a={l.name} b={l.staff_number ?? ""} />,
                <span className="tnum" key="c">{l.load} units</span>,
                <span className="tnum" key="w" style={willBe > MAX_UNITS ? { color: "var(--red-ink)", fontWeight: 700 } : undefined}>{willBe} units</span>,
                <label key="p" style={{ display: "inline-flex", gap: 6, alignItems: "center", cursor: "pointer" }}>
                  <input type="radio" name="al-lec" checked={lecturer === l.id} onChange={() => setLecturer(l.id)} /> {lecturer === l.id ? "Chosen" : "Choose"}
                </label>,
              ];
            })} />
          ) : <Note kind="bad" title="No lecturer is on record for this department">A lecturer appears here once the Registry grants them the lecturer office scoped to this department.</Note>}
          <Field id="al-second" label="Second examiner" hint="Verifies the marks. Cannot be the lecturer. Set now so verification is not blocked later.">
            <select id="al-second" className="ctl" value={second} onChange={(e) => setSecond(e.target.value)}>
              <option value="">Not set yet</option>
              {lecturers.filter((l) => l.id !== lecturer).map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
            </select>
          </Field>
        </Modal>
      ) : null}
    </>
  );
}
