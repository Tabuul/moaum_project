"use client";

/** tDeptCourses — proto/part…: the department's catalogue, a new course (into BOARD state,
 *  the Board and Senate make it live), and ending a course with a date rather than deleting it. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Dept { code: string; name: string; faculty_code: string }
export interface Course {
  code: string; title: string; units: number; semester: number; level: number; kind: string;
  state: string; ended_on: string | null; lecturer: string | null; offered: boolean;
}

const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  LIVE: ["ok", "Live"], BOARD: ["warn", "At the Faculty Board"], SENATE: ["info", "At Senate"], ENDED: ["grey", "Ended"],
};
const KINDS = ["Compulsory", "Required", "Elective", "GST"];
const LEVELS = [100, 200, 300, 400, 500, 600];

export function DeptCourses({ depts, dept, courses, problem }: { depts: Dept[]; dept: string; courses: Course[]; problem: Problem | null }) {
  const router = useRouter();
  const [add, setAdd] = useState(false);
  const [f, setF] = useState({ code: "", title: "", units: "3", semester: "1", level: "100", kind: "Compulsory" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const live = courses.filter((c) => c.state === "LIVE").length;
  const waiting = courses.filter((c) => c.state === "BOARD" || c.state === "SENATE").length;
  const noLec = courses.filter((c) => c.state === "LIVE" && c.offered && !c.lecturer).length;

  function go(nextDept: string) {
    router.push(`/catalogue?dept=${encodeURIComponent(nextDept)}`);
  }

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return null; }
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="The department owns its courses, and creates them">
        A course belongs to exactly one department &mdash; the one that teaches it, sets its score sheet and answers a query about a mark in it. What the department cannot do is make it live on its own: a new course is a curriculum change the Faculty Board sees and Senate approves, because the NUC accredits a programme on the courses it says it teaches.
      </Note>

      <div className="card"><div className="card__body" style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "flex-end" }}>
        <div className="field" style={{ minWidth: 240 }}><label htmlFor="dc-dept">Department</label>
          <select id="dc-dept" className="ctl" value={dept} onChange={(e) => go(e.target.value)}>
            {depts.map((d) => <option key={d.code} value={d.code}>{d.name}</option>)}
          </select></div>
        <div style={{ flexGrow: 1 }} />
        <button className="btn btn--primary" onClick={() => { setF({ code: "", title: "", units: "3", semester: "1", level: "100", kind: "Compulsory" }); setErr(null); setAdd(true); }}>+ New course</button>
      </div></div>

      {said ? <Note kind="ok" title={said}>It goes to the Faculty Board, then to Senate &mdash; the department cannot make it live. Until Senate resolves it, no student can register for it and no score sheet exists.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Tiles items={[
        ["Courses owned", String(courses.length), null, depts.find((d) => d.code === dept)?.name ?? dept],
        ["Live", String(live), "var(--green-ink)", "Offered and taught"],
        ["Awaiting approval", String(waiting), waiting ? "var(--chrome)" : null, "Board or Senate"],
        ["Live, no lecturer", String(noLec), noLec ? "var(--red-ink)" : null, noLec ? "No score sheet can open" : "All allocated"],
      ]} />

      <Panel title="The department's catalogue" right="Every course this department owns">
        {courses.length ? (
          <DTable cols={["Code|mid", "Title", "Units|mid", "Semester|mid", "Level|mid", "Kind", "Lecturer", "State|mid", "Action|num"]} rows={courses.map((c) => [
            <b className="tnum" key="c">{c.code}</b>,
            <span key="t">{c.title}</span>,
            <span className="tnum" key="u">{c.units}</span>,
            <span className="tnum" key="s">{c.semester === 1 ? "First" : c.semester === 2 ? "Second" : "Third"}</span>,
            <span className="tnum" key="l">{c.level}</span>,
            <span className="sub2" key="k">{c.kind}</span>,
            c.lecturer ? <span className="sub2" key="lec">{c.lecturer}</span> : c.state === "LIVE" && c.offered ? <span className="sub2" key="lec" style={{ color: "var(--red-ink)" }}>Not allocated</span> : <span className="sub2" key="lec">&mdash;</span>,
            <Pil kind={STATE[c.state]?.[0] ?? "grey"} key="st">{STATE[c.state]?.[1] ?? c.state}</Pil>,
            c.state === "ENDED" ? <span className="sub2" key="a">On old records</span> : <Btn key="a" kind="ghost" disabled={busy} onClick={() => { if (window.confirm(`End ${c.code}? It leaves next session's registration and stays on every transcript that carries it. It is not deleted.`)) void send(`/courses/${encodeURIComponent(c.code)}/end`, {}, `End course ${c.code}`).then((j) => { if (j) setSaid(`${c.code} ended`); }); }}>End</Btn>,
          ])} texts={courses.map((c) => `${c.code} ${c.title} ${c.kind}`)} />
        ) : <PBody><div className="sub2">This department owns no course yet. A course appears here once it is created; it starts at the Faculty Board.</div></PBody>}
      </Panel>

      <Note kind="bad" title="Ending a course is not deleting it">
        A course that is no longer taught is ended with a date. It disappears from next session&rsquo;s registration and stays on every transcript that carries it, because a degree earned in one year was earned on the courses that existed that year. Nothing in this catalogue is ever removed.
      </Note>

      {add ? (
        <Modal title="New course" sub={`For ${depts.find((d) => d.code === dept)?.name ?? dept}`} onClose={() => setAdd(false)}
          foot={<><Btn kind="ghost" onClick={() => setAdd(false)}>Cancel</Btn><span style={{ flexGrow: 1 }} />
            <Btn kind="primary" disabled={busy || !f.code.trim() || !f.title.trim()} onClick={async () => { const j = await send("/courses", { code: f.code.toUpperCase(), title: f.title, units: Number(f.units), semester: Number(f.semester), level: Number(f.level), dept, kind: f.kind }, `New course ${f.code}`); if (j) { setSaid(`${j.code} created — at the Faculty Board`); setAdd(false); } }}>Create</Btn></>}>
          {err ? <ProblemNotice problem={err} /> : null}
          <div className="grid grid--2">
            <Field id="nc-code" label="Code" hint="Three letters, a space, three digits — e.g. CSC 311"><input id="nc-code" className="ctl tnum" value={f.code} onChange={(e) => setF({ ...f, code: e.target.value })} placeholder="CSC 311" autoComplete="off" /></Field>
            <Field id="nc-units" label="Units"><input id="nc-units" className="ctl tnum" value={f.units} inputMode="numeric" onChange={(e) => setF({ ...f, units: e.target.value })} /></Field>
          </div>
          <Field id="nc-title" label="Title"><input id="nc-title" className="ctl" value={f.title} onChange={(e) => setF({ ...f, title: e.target.value })} placeholder="Algorithms and Complexity" autoComplete="off" /></Field>
          <div className="grid grid--3">
            <Field id="nc-level" label="Level"><select id="nc-level" className="ctl" value={f.level} onChange={(e) => setF({ ...f, level: e.target.value })}>{LEVELS.map((l) => <option key={l} value={l}>{l}</option>)}</select></Field>
            <Field id="nc-sem" label="Semester"><select id="nc-sem" className="ctl" value={f.semester} onChange={(e) => setF({ ...f, semester: e.target.value })}><option value="1">First</option><option value="2">Second</option></select></Field>
            <Field id="nc-kind" label="Kind"><select id="nc-kind" className="ctl" value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value })}>{KINDS.map((k) => <option key={k} value={k}>{k}</option>)}</select></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
