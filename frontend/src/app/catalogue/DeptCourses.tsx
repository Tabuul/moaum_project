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
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Dept { code: string; name: string; faculty_code: string }
export interface Course {
  code: string; title: string; units: number; semester: number; level: number; kind: string;
  state: string; ended_on: string | null; lecturer: string | null; offered: boolean;
}
export interface Duplicate { level: number; semester: number; title: string; code: string; keeper: boolean }

const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  LIVE: ["ok", "Live"], BOARD: ["warn", "At the Faculty Board"], SENATE: ["info", "At Senate"], ENDED: ["grey", "Ended"],
};
const KINDS = ["Compulsory", "Required", "Elective", "GST"];
const LEVELS = [100, 200, 300, 400, 500, 600];

export function DeptCourses({ depts, dept, courses, duplicates = [], problem }: { depts: Dept[]; dept: string; courses: Course[]; duplicates?: Duplicate[]; problem: Problem | null }) {
  const router = useRouter();
  const [add, setAdd] = useState(false);
  const [f, setF] = useState({ code: "", title: "", units: "3", semester: "1", level: "100", kind: "Compulsory" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [fLevel, setFLevel] = useState("");
  const [fSem, setFSem] = useState("");
  const [fKind, setFKind] = useState("");

  const live = courses.filter((c) => c.state === "LIVE").length;
  const waiting = courses.filter((c) => c.state === "BOARD" || c.state === "SENATE").length;
  const noLec = courses.filter((c) => c.state === "LIVE" && c.offered && !c.lecturer).length;

  /* the same course under more than one code — the cleanest is kept, the rest end */
  const toEnd = duplicates.filter((d) => !d.keeper);
  const dupGroups = Object.values(duplicates.reduce((acc, d) => {
    const k = `${d.level}-${d.semester}-${d.title}`;
    (acc[k] ??= { level: d.level, semester: d.semester, title: d.title, codes: [] as Duplicate[] }).codes.push(d);
    return acc;
  }, {} as Record<string, { level: number; semester: number; title: string; codes: Duplicate[] }>));

  /* level, semester and kind filter the already-loaded department list, client-side */
  const shown = courses.filter((c) =>
    (!fLevel || c.level === Number(fLevel)) &&
    (!fSem || c.semester === Number(fSem)) &&
    (!fKind || c.kind === fKind));
  const filtered = Boolean(fLevel || fSem || fKind);

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
        {depts.length > 1 ? (
          <div className="field" style={{ minWidth: 240 }}><label htmlFor="dc-dept">Department</label>
            <SearchSelect id="dc-dept" value={dept} placeholder="Search a department…"
              options={depts.map((d) => ({ value: d.code, label: d.name }))} onChange={(v) => go(v)} /></div>
        ) : (
          // a Head of Department owns one department — show it, do not ask them to pick it
          <div className="field" style={{ minWidth: 240 }}><label>Department</label>
            <div className="ctl" style={{ display: "flex", alignItems: "center", fontWeight: 600 }}>{depts[0]?.name ?? "—"}</div></div>
        )}
        <div className="field" style={{ minWidth: 120 }}><label htmlFor="dc-level">Level</label>
          <select id="dc-level" className="ctl" value={fLevel} onChange={(e) => setFLevel(e.target.value)}>
            <option value="">All levels</option>{LEVELS.map((l) => <option key={l} value={l}>{l} Level</option>)}
          </select></div>
        <div className="field" style={{ minWidth: 130 }}><label htmlFor="dc-sem">Semester</label>
          <select id="dc-sem" className="ctl" value={fSem} onChange={(e) => setFSem(e.target.value)}>
            <option value="">All semesters</option><option value="1">First</option><option value="2">Second</option><option value="3">Third</option>
          </select></div>
        <div className="field" style={{ minWidth: 140 }}><label htmlFor="dc-kind">Kind</label>
          <select id="dc-kind" className="ctl" value={fKind} onChange={(e) => setFKind(e.target.value)}>
            <option value="">All kinds</option>{KINDS.map((k) => <option key={k} value={k}>{k}</option>)}
          </select></div>
        {filtered ? <Btn kind="ghost" onClick={() => { setFLevel(""); setFSem(""); setFKind(""); }}>Clear</Btn> : null}
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

      {toEnd.length ? (
        <Panel title="Duplicate courses" right={`${toEnd.length} to end · the same course under more than one code`}>
          <PBody>
            <div className="sub2" style={{ marginBottom: 8 }}>The same course was uploaded under more than one code, so it shows more than once on registration. The cleanest code is kept; ending the others removes them from future registration (they stay on any transcript that already carries them).</div>
            {dupGroups.map((g, i) => (
              <div key={i} style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)" }}>
                <div style={{ fontWeight: 600 }}>{g.title} <span className="sub2">· {g.level} Level · {g.semester === 1 ? "First" : g.semester === 2 ? "Second" : "Third"} semester</span></div>
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 4 }}>
                  {g.codes.map((c) => (
                    <span key={c.code} className="tnum" style={{ fontSize: 12.5 }}>
                      {c.keeper ? <Pil kind="ok">Keep {c.code}</Pil> : <span style={{ color: "var(--red-ink)", textDecoration: "line-through" }}>{c.code}</span>}
                    </span>
                  ))}
                </div>
              </div>
            ))}
            <div style={{ marginTop: 12 }}>
              <Btn kind="urgent" disabled={busy} onClick={() => { if (window.confirm(`End ${toEnd.length} duplicate course${toEnd.length === 1 ? "" : "s"}? The cleanest code in each group is kept. This can be undone by the Board/Senate if needed.`)) void send(`/duplicates/end?dept=${encodeURIComponent(dept)}`, {}, `Ended ${toEnd.length} duplicate courses in ${dept}`).then((j) => { if (j) setSaid(`${String(j.ended ?? toEnd.length)} duplicate course(s) ended`); }); }}>{busy ? "Ending…" : `End ${toEnd.length} duplicate course${toEnd.length === 1 ? "" : "s"}`}</Btn>
            </div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="The department's catalogue" right={filtered ? `${shown.length} of ${courses.length} · filtered` : "Every course this department owns"}>
        {shown.length ? (
          <DTable cols={["Code|mid", "Title", "Units|mid", "Semester|mid", "Level|mid", "Kind", "Lecturer", "State|mid", "Action|num"]} rows={shown.map((c) => [
            <b className="tnum" key="c">{c.code}</b>,
            <span key="t">{c.title}</span>,
            <span className="tnum" key="u">{c.units}</span>,
            <span className="tnum" key="s">{c.semester === 1 ? "First" : c.semester === 2 ? "Second" : "Third"}</span>,
            <span className="tnum" key="l">{c.level}</span>,
            <span className="sub2" key="k">{c.kind}</span>,
            c.lecturer ? <span className="sub2" key="lec">{c.lecturer}</span> : c.state === "LIVE" && c.offered ? <span className="sub2" key="lec" style={{ color: "var(--red-ink)" }}>Not allocated</span> : <span className="sub2" key="lec">&mdash;</span>,
            <Pil kind={STATE[c.state]?.[0] ?? "grey"} key="st">{STATE[c.state]?.[1] ?? c.state}</Pil>,
            c.state === "ENDED" ? <span className="sub2" key="a">On old records</span> : <Btn key="a" kind="ghost" disabled={busy} onClick={() => { if (window.confirm(`End ${c.code}? It leaves next session's registration and stays on every transcript that carries it. It is not deleted.`)) void send(`/courses/${encodeURIComponent(c.code)}/end`, {}, `End course ${c.code}`).then((j) => { if (j) setSaid(`${c.code} ended`); }); }}>End</Btn>,
          ])} texts={shown.map((c) => `${c.code} ${c.title} ${c.kind}`)} />
        ) : <PBody><div className="sub2">{filtered ? "No course in this department matches these filters. Clear them to see all." : "This department owns no course yet. A course appears here once it is created; it starts at the Faculty Board."}</div></PBody>}
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
