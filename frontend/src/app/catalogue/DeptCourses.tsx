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
import { notify } from "@/components/proto/Toast";

export interface Dept { code: string; name: string; faculty_code: string }
export interface Course {
  code: string; title: string; units: number; semester: number; level: number; kind: string;
  state: string; ended_on: string | null; lecturer: string | null; offered: boolean; curriculum: string | null;
  programmes: string[];
}
export interface Duplicate { level: number; semester: number; title: string; code: string; keeper: boolean }
export interface Programme { code: string; name: string }

const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  LIVE: ["ok", "Live"], BOARD: ["warn", "At the Faculty Board"], SENATE: ["info", "At Senate"], ENDED: ["grey", "Ended"],
};
const KINDS = ["Compulsory", "Required", "Elective", "GST"];
const LEVELS = [100, 200, 300, 400, 500, 600];

export function DeptCourses({ depts, dept, courses, duplicates = [], programmes = [], problem }: { depts: Dept[]; dept: string; courses: Course[]; duplicates?: Duplicate[]; programmes?: Programme[]; problem: Problem | null }) {
  const router = useRouter();
  const [add, setAdd] = useState(false);
  const [f, setF] = useState({ code: "", title: "", units: "3", semester: "1", level: "100", kind: "Compulsory" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [fLevel, setFLevel] = useState("");
  const [fSem, setFSem] = useState("");
  const [fKind, setFKind] = useState("");
  const [fProg, setFProg] = useState("");

  // the programmes to offer in the filter: those that actually offer any of this department's courses,
  // named from the programmes list where it has the name, otherwise the code
  const progName = new Map(programmes.map((p) => [p.code, p.name]));
  const progOptions = Array.from(new Set(courses.flatMap((c) => c.programmes ?? [])))
    .map((code) => ({ code, name: progName.get(code) ?? code }))
    .sort((a, b) => a.name.localeCompare(b.name));

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

  /* level, semester, kind and programme filter the already-loaded department list, client-side */
  const shown = courses.filter((c) =>
    (!fLevel || c.level === Number(fLevel)) &&
    (!fSem || c.semester === Number(fSem)) &&
    (!fKind || c.kind === fKind) &&
    (!fProg || (c.programmes ?? []).includes(fProg)));
  const filtered = Boolean(fLevel || fSem || fKind || fProg);

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
      notify(reason);
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

      <div className="scope">
        <div className="scope__row">
          <div className="scope__f"><label htmlFor="dc-dept">Department</label>
            {depts.length > 1 ? (
              <SearchSelect id="dc-dept" value={dept} placeholder="Search a department…"
                options={depts.map((d) => ({ value: d.code, label: d.name }))} onChange={(v) => go(v)} />
            ) : (
              // a Head of Department owns one department — show it, do not ask them to pick it
              <div className="ctl" style={{ display: "flex", alignItems: "center", fontWeight: 600 }}>{depts[0]?.name ?? "—"}</div>
            )}
          </div>
          <div className="scope__f"><label htmlFor="dc-level">Level</label>
            <select id="dc-level" className="ctl" value={fLevel} onChange={(e) => setFLevel(e.target.value)}>
              <option value="">All levels</option>{LEVELS.map((l) => <option key={l} value={l}>{l} Level</option>)}
            </select></div>
          <div className="scope__f"><label htmlFor="dc-sem">Semester</label>
            <select id="dc-sem" className="ctl" value={fSem} onChange={(e) => setFSem(e.target.value)}>
              <option value="">All semesters</option><option value="1">First</option><option value="2">Second</option><option value="3">Third</option>
            </select></div>
          <div className="scope__f"><label htmlFor="dc-kind">Kind</label>
            <select id="dc-kind" className="ctl" value={fKind} onChange={(e) => setFKind(e.target.value)}>
              <option value="">All kinds</option>{KINDS.map((k) => <option key={k} value={k}>{k}</option>)}
            </select></div>
          <div className="scope__f"><label htmlFor="dc-prog">Programme</label>
            <select id="dc-prog" className="ctl" value={fProg} onChange={(e) => setFProg(e.target.value)} disabled={!progOptions.length}>
              <option value="">All programmes</option>{progOptions.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
            </select></div>
        </div>
        <div className="scope__sum">
          <span className="trail">{depts.find((d) => d.code === dept)?.name ?? dept}</span>
          <span className="count"><b>{shown.length}</b> {filtered ? `of ${courses.length}` : `course${courses.length === 1 ? "" : "s"}`} shown</span>
          <div style={{ marginLeft: "auto", display: "flex", gap: 8, alignItems: "center" }}>
            {filtered ? <button className="btn btn--ghost btn--sm" onClick={() => { setFLevel(""); setFSem(""); setFKind(""); setFProg(""); }}>Clear filters</button> : null}
            {waiting ? <button className="btn btn--ghost btn--sm" disabled={busy} onClick={() => { if (window.confirm(`Make ${waiting} awaiting course${waiting === 1 ? "" : "s"} Live? They enter the current session's registration.`)) void send(`/courses/live-all?dept=${encodeURIComponent(dept)}`, {}, `Make ${waiting} courses live in ${dept}`).then((j) => { if (j) setSaid(`${String(j.made_live ?? waiting)} course(s) made Live`); }); }}>{busy ? "Working…" : `Make ${waiting} Live`}</button> : null}
            <button className="btn btn--primary btn--sm" onClick={() => { setF({ code: "", title: "", units: "3", semester: "1", level: "100", kind: "Compulsory" }); setErr(null); setAdd(true); }}>+ New course</button>
          </div>
        </div>
      </div>

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
        <PBody>
          <div className="sub2" style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
            <span>Curriculum decides which cohort sees a course at registration (CCMAS or BMAS; leave a shared course, e.g. GST, blank). Tag {fLevel ? `${fLevel} Level` : "the department's"} courses:</span>
            {(["CCMAS", "BMAS"] as const).map((cur) => (
              <Btn key={cur} kind="ghost" disabled={busy} onClick={() => {
                if (!window.confirm(`Set ${fLevel ? `every ${fLevel} Level` : "every"} course in this department to ${cur}? You can change any course individually afterwards.`)) return;
                void send(`/curriculum/bulk?dept=${encodeURIComponent(dept)}&curriculum=${cur}${fLevel ? `&level=${fLevel}` : ""}`, {}, `Tagged ${fLevel || "all"} ${dept} courses as ${cur}`).then((j) => { if (j) setSaid(`${String(j.updated ?? "")} course(s) set to ${cur}`); });
              }}>Set to {cur}</Btn>
            ))}
          </div>
        </PBody>
        {shown.length ? (
          <DTable cols={["Code|mid", "Title", "Units|mid", "Semester|mid", "Level|mid", "Kind", "Curriculum|mid", "Lecturer", "State|mid", "Action|num"]} rows={shown.map((c) => [
            <b className="tnum" key="c">{c.code}</b>,
            <span key="t">{c.title}</span>,
            <span className="tnum" key="u">{c.units}</span>,
            <span className="tnum" key="s">{c.semester === 1 ? "First" : c.semester === 2 ? "Second" : "Third"}</span>,
            <span className="tnum" key="l">{c.level}</span>,
            <span className="sub2" key="k">{c.kind}</span>,
            <select key="cur" className="ctl" style={{ minWidth: 96, padding: "3px 6px", fontSize: 12.5 }} value={c.curriculum ?? ""} disabled={busy || c.state === "ENDED"}
              onChange={(e) => void send(`/courses/${encodeURIComponent(c.code)}/curriculum`, { curriculum: e.target.value }, `Curriculum of ${c.code} set to ${e.target.value || "none"}`).then((j) => { if (j) setSaid(`${c.code} → ${e.target.value || "no curriculum"}`); })}>
              <option value="">— (shared)</option>
              <option value="CCMAS">CCMAS</option>
              <option value="BMAS">BMAS</option>
            </select>,
            c.lecturer ? <span className="sub2" key="lec">{c.lecturer}</span> : c.state === "LIVE" && c.offered ? <span className="sub2" key="lec" style={{ color: "var(--red-ink)" }}>Not allocated</span> : <span className="sub2" key="lec">&mdash;</span>,
            <Pil kind={STATE[c.state]?.[0] ?? "grey"} key="st">{STATE[c.state]?.[1] ?? c.state}</Pil>,
            <div key="a" style={{ display: "flex", gap: 6, justifyContent: "flex-end", flexWrap: "wrap" }}>
              {c.state === "ENDED" ? (
                <Btn kind="ghost" disabled={busy} onClick={() => { if (window.confirm(`Restore ${c.code}? It returns to Live and re-enters registration.`)) void send(`/courses/${encodeURIComponent(c.code)}/restore`, {}, `Restore course ${c.code}`).then((j) => { if (j) setSaid(`${c.code} restored — Live again`); }); }}>Restore</Btn>
              ) : (
                <>
                  {c.state === "BOARD" || c.state === "SENATE" ? (
                    <Btn kind="ghost" disabled={busy} onClick={() => { if (window.confirm(`Make ${c.code} Live? It enters the current session's registration.`)) void send(`/courses/${encodeURIComponent(c.code)}/live`, {}, `Make course ${c.code} live`).then((j) => { if (j) setSaid(`${c.code} is now Live`); }); }}>Make live</Btn>
                  ) : null}
                  <Btn kind="ghost" disabled={busy} onClick={() => { if (window.confirm(`End ${c.code}? It leaves next session's registration and stays on every transcript that carries it. It is not deleted.`)) void send(`/courses/${encodeURIComponent(c.code)}/end`, {}, `End course ${c.code}`).then((j) => { if (j) setSaid(`${c.code} ended`); }); }}>End</Btn>
                </>
              )}
            </div>,
          ])} texts={shown.map((c) => `${c.code} ${c.title} ${c.kind}`)} />
        ) : <PBody><div className="sub2">{filtered ? "No course in this department matches these filters. Clear them to see all." : "This department owns no course yet. A course appears here once it is created; it starts at the Faculty Board."}</div></PBody>}
      </Panel>

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
