"use client";
import Link from "next/link";

/** tDeptCourses — proto/part…: the department's catalogue, a new course (live at once, on the list and in the
 *  current session's registration), and ending a course with a date rather than deleting it. */
import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { PROPOSAL_STATE, type Directory, type Exists, type Proposal } from "@/lib/catalogue";

export interface Dept { code: string; name: string; faculty_code: string }
export interface Course {
  /** the course's identity (V332): unchanged by an edit of its code, title or units */
  id?: string;
  /** proposals of this course to other departments' programmes still awaiting them (V332) */
  pending?: number;
  code: string; title: string; units: number; semester: number; level: number; kind: string;
  state: string; ended_on: string | null; lecturer: string | null; offered: boolean; curriculum: string | null;
  programmes: string[];
  /** the CA share of the hundred marks (V239); the examination is the rest */
  ca_max?: number;
  /** the programmes the course is bound into, at which level, on what basis, for which track (V013/V235) */
  bindings?: { programme_code: string; programme: string; level: number; basis: string; track: string | null }[];
}
export interface Duplicate { level: number; semester: number; title: string; code: string; keeper: boolean }
/** a code written without the hyphen after its prefix, and the code it should read (V333) */
export interface CodeFix { code: string; proposed: string; title: string; state: string; twin_exists: boolean; offers: number; offerings: number; carried: number }
export interface Programme { code: string; name: string }

const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  LIVE: ["ok", "Live"], BOARD: ["warn", "Not yet live"], SENATE: ["warn", "Not yet live"], ENDED: ["grey", "Ended"],
};
/* the Note's action slot takes the existing-course buttons (V332) */
const KINDS = ["Core", "Required", "Elective", "GST"];
/** how a kind reads on the desk: the Registry's word for Core is "Core Courses" */
const KIND_LABEL: Record<string, string> = { Core: "Core Courses" };
const kindLabel = (k: string) => KIND_LABEL[k] ?? k;
const LEVELS = [100, 200, 300, 400, 500, 600];
/** how a course's hundred marks split: CA share / examination share */
const SPLITS: [number, string][] = [[40, "CA 40 / Exam 60"], [30, "CA 30 / Exam 70"]];
const splitLabel = (caMax: number) => `CA ${caMax} / Exam ${100 - caMax}`;

export function DeptCourses({ depts, dept, courses, duplicates = [], programmes = [], problem, directory = null, proposals = null, codeFixes = [] }: { depts: Dept[]; dept: string; courses: Course[]; duplicates?: Duplicate[]; programmes?: Programme[]; problem: Problem | null; directory?: Directory | null; proposals?: { toDecide: Proposal[]; mine: Proposal[] } | null; codeFixes?: CodeFix[] }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const [add, setAdd] = useState(false);
  const [f, setF] = useState({ code: "", title: "", units: "3", semester: "1", level: "100", kind: "Core" });
  /* V332: the programmes that offer the new course — the department's own bound at once, another department's proposed to it */
  const [own, setOwn] = useState<string[]>([]);
  const [extra, setExtra] = useState<{ programme: string; name: string; dept: string; deptName: string }[]>([]);
  const [pickDept, setPickDept] = useState("");
  const [pickProgs, setPickProgs] = useState<string[]>([]);
  const [why, setWhy] = useState("");
  const [found, setFound] = useState<Exists | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const ownProgs: { code: string; name: string; category?: string | null }[] = directory ? directory.programmes.filter((p) => p.dept_code === dept) : programmes;
  /* the programmes ticked by default: those the level belongs to — postgraduate programmes for 700 Level and above, the rest below */
  const defaultTicked = (level: string) => ownProgs.filter((p) => !p.category || (Number(level) >= 700) === (p.category === "POST GRADUATE")).map((p) => p.code);
  const otherDepts = (directory?.departments ?? []).filter((d) => d.code !== dept);
  const pickable = (directory?.programmes ?? []).filter((p) => p.dept_code === pickDept && !extra.some((x) => x.programme === p.code));
  const direct = Boolean(directory?.central);
  function check(code: string, title: string, level: string) {
    if (timer.current) clearTimeout(timer.current);
    if (code.trim().length < 4 && title.trim().length < 6) { setFound(null); return; }
    timer.current = setTimeout(() => {
      void fetch(`/api/bff/api/v1/catalogue/courses/exists?code=${encodeURIComponent(code.trim() || "-")}&title=${encodeURIComponent(title.trim())}&level=${encodeURIComponent(level)}`).then(async (r) => {
        if (!r.ok) return;
        setFound((await r.json().catch(() => null)) as Exists | null);
      });
    }, 300);
  }
  async function adoptExisting(code: string) {
    let n = 0;
    for (const pr of own) {
      const j = await send(`/courses/${encodeURIComponent(code)}/offers`, { programme: pr, level: Number(f.level) }, `${code} offered to ${pr}`);
      if (!j) break;
      n += 1;
    }
    if (n) { setSaid(`${code} offered to ${n} programme${n === 1 ? "" : "s"} — no second course was made`); setAdd(false); }
  }
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
    queryNav(`/catalogue?dept=${encodeURIComponent(nextDept)}`);
  }

  async function send(path: string, body: unknown, reason: string, method: "POST" | "DELETE" = "POST"): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: method === "DELETE" ? undefined : JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
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
        A course belongs to exactly one department &mdash; the one that teaches it, sets its score sheet and answers a query about a mark in it. A course the department adds is live at once: it appears on this list and in the current session&rsquo;s registration for the programmes it is offered to.
      </Note>

      <div className="scope">
        <div className="scope__row">
          <div className="scope__f"><label htmlFor="dc-dept">Department</label>
            {depts.length > 1 ? (
              <SearchSelect id="dc-dept" value={dept} placeholder="Search a department…"
                options={depts.map((d) => ({ value: d.code, label: d.name }))} onChange={(v) => go(v)} />
            ) : (
              // a Head of Department owns one department — show it, do not ask them to pick it
              <div className="ctl row b600">{depts[0]?.name ?? "—"}</div>
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
              <option value="">All kinds</option>{KINDS.map((k) => <option key={k} value={k}>{kindLabel(k)}</option>)}
            </select></div>
          <div className="scope__f"><label htmlFor="dc-prog">Programme</label>
            <select id="dc-prog" className="ctl" value={fProg} onChange={(e) => setFProg(e.target.value)} disabled={!progOptions.length}>
              <option value="">All programmes</option>{progOptions.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
            </select></div>
        </div>
        <div className="scope__sum">
          <span className="trail">{depts.find((d) => d.code === dept)?.name ?? dept}</span>
          <span className="count"><b>{shown.length}</b> {filtered ? `of ${courses.length}` : `course${courses.length === 1 ? "" : "s"}`} shown</span>
          <div className="row ml-auto">
            {filtered ? <Btn kind="ghost" onClick={() => { setFLevel(""); setFSem(""); setFKind(""); setFProg(""); }}>Clear filters</Btn> : null}
            {waiting ? <Btn kind="ghost" disabled={busy} onClick={() => { if (window.confirm(`Make ${waiting} awaiting course${waiting === 1 ? "" : "s"} Live? They enter the current session's registration.`)) void send(`/courses/live-all?dept=${encodeURIComponent(dept)}`, {}, `Make ${waiting} courses live in ${dept}`).then((j) => { if (j) setSaid(`${String(j.made_live ?? waiting)} course(s) made Live`); }); }}>{busy ? "Working…" : `Make ${waiting} Live`}</Btn> : null}
            <Btn kind="primary" onClick={() => { setF({ code: "", title: "", units: "3", semester: "1", level: "100", kind: "Core" }); setErr(null); setOwn(defaultTicked("100")); setExtra([]); setPickDept(""); setPickProgs([]); setWhy(""); setFound(null); setAdd(true); }}>+ New course</Btn>
          </div>
        </div>
      </div>

      {said ? <Note kind="ok" title={said} /> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}

      {proposals?.toDecide.length ? (
        <Panel title="Courses proposed to your programmes" right={`${proposals.toDecide.length} awaiting your decision · another department asks that your programme offer its course`}>
          <DTable pageSize={0} noPrint cols={["Course", "Owner", "To programme", "Level|mid", "Basis|mid", "Proposed", "|num"]} rows={proposals.toDecide.map((p) => [
            <span key="c"><b className="tnum">{p.course_code}</b> {p.course_title}<div className="sub2">{p.units} units</div></span>,
            <span key="o" className="sub2">{p.course_dept_name ?? p.course_dept}</span>,
            <span key="p">{p.programme}<div className="sub2 tnum">{p.programme_code}</div></span>,
            <span key="l" className="tnum">{p.level}</span>, <span key="b" className="sub2">{p.basis}</span>,
            <span key="w" className="sub2">{p.proposed_by ?? ""}{p.reason ? <div>{p.reason}</div> : null}</span>,
            <span key="a" className="row row--inline row--tight row--right">
              <Btn kind="primary" size="sm" disabled={busy} onClick={() => void send(`/offer-proposals/${p.id}/approve`, { note: window.prompt("A note for the record (optional)") ?? "" }, `${p.course_code} approved for ${p.programme_code}`).then((j) => { if (j) setSaid(`${p.course_code} now offered to ${p.programme_code} at ${p.level} level`); })}>Approve</Btn>
              <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { const n = window.prompt("Why is it rejected?"); if (n !== null) void send(`/offer-proposals/${p.id}/reject`, { note: n }, `${p.course_code} declined for ${p.programme_code}`); }}>Reject</Btn>
              <LinkBtn size="sm" href={`/catalogue/course?code=${encodeURIComponent(p.course_code ?? "")}`}>Course</LinkBtn>
            </span>,
          ])} />
        </Panel>
      ) : null}
      {proposals?.mine.length ? (
        <Panel title="Your proposals to other departments" right="A course of yours offered to another department's programme waits for that department">
          <DTable pageSize={0} noPrint cols={["Course", "To programme", "Department", "Level|mid", "State|mid", "Decision", "|num"]} rows={proposals.mine.map((p) => [
            <span key="c"><b className="tnum">{p.course_code}</b> {p.course_title}</span>,
            <span key="p">{p.programme}<div className="sub2 tnum">{p.programme_code}</div></span>, <span key="d" className="sub2">{p.dept ?? p.dept_code}</span>,
            <span key="l" className="tnum">{p.level}</span>,
            <Pil key="s" kind={PROPOSAL_STATE[p.state]?.[0] ?? "grey"}>{PROPOSAL_STATE[p.state]?.[1] ?? p.state}</Pil>,
            <span key="n" className="sub2">{p.decided_by ?? ""}{p.decision_note ? <div>{p.decision_note}</div> : null}</span>,
            <span key="a" className="row row--inline row--tight row--right">{p.state === "PENDING" ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { if (window.confirm("Withdraw this proposal?")) void send(`/offer-proposals/${p.id}/cancel`, {}, `Proposal of ${p.course_code} to ${p.programme_code} withdrawn`); }}>Withdraw</Btn> : null}</span>,
          ])} />
        </Panel>
      ) : null}

      <Tiles items={[
        ["Courses owned", String(courses.length), null, depts.find((d) => d.code === dept)?.name ?? dept],
        ["Live", String(live), "var(--green-ink)", "Offered and taught"],
        ["Not yet live", String(waiting), waiting ? "var(--chrome)" : null, "Added before courses went live at once"],
        ["Live, no lecturer", String(noLec), noLec ? "var(--red-ink)" : null, noLec ? "No score sheet can open" : "All allocated"],
      ]} />

      {codeFixes.length ? (
        <Panel title="Codes written without the hyphen" right={`${codeFixes.length} to correct · the old portal dropped the hyphen after the prefix`}>
          <PBody>
            <div className="sub2 mb-2">A prefixed code reads <b>MOAU-CHM 101</b>, not MOAUCHM 101. Renaming corrects the code in place: the course keeps its identity, and every registration, result, offering and binding on it follows. Where the corrected code is <b>already another course</b>, the two are the same course under two codes: end or remove the wrong one on the duplicates desk below, or on its details page.</div>
            <DTable pageSize={0} noPrint cols={["Code|mid", "Should read|mid", "Title", "Carries", "|num"]} rows={codeFixes.map((x) => [
              <b key="c" className="tnum ink-red">{x.code}</b>,
              <b key="p" className="tnum">{x.proposed}</b>,
              <span key="t">{x.title}<div className="sub2">{STATE[x.state]?.[1] ?? x.state}</div></span>,
              <span key="k" className="sub2">{x.offers} binding{x.offers === 1 ? "" : "s"} · {x.offerings} offering{x.offerings === 1 ? "" : "s"} · {x.carried} registration{x.carried === 1 ? "" : "s"}/result{x.carried === 1 ? "" : "s"}</span>,
              <span key="a" className="row row--inline row--tight row--right">
                {x.twin_exists ? <Pil kind="warn">{x.proposed} exists — a duplicate</Pil> : <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { if (window.confirm(`Rename ${x.code} to ${x.proposed}? Everything on the course follows the new code.`)) void send(`/courses/${encodeURIComponent(x.code)}/rename`, { code: x.proposed }, `${x.code} renamed to ${x.proposed}`).then((j) => { if (j) setSaid(`${x.code} now reads ${x.proposed}`); }); }}>Rename</Btn>}
                <LinkBtn size="sm" href={`/catalogue/course?code=${encodeURIComponent(x.code)}`}>Details</LinkBtn>
              </span>,
            ])} />
            {codeFixes.some((x) => !x.twin_exists) ? (
              <div className="row row--base mt-3">
                <Btn kind="primary" disabled={busy} onClick={() => { const n = codeFixes.filter((x) => !x.twin_exists).length; if (window.confirm(`Correct ${n} code${n === 1 ? "" : "s"} in one act? Each course keeps its identity and everything on it; a code whose corrected form is already another course is left for the duplicates desk.`)) void send(`/code-fixes/apply?dept=${encodeURIComponent(dept)}`, {}, `Corrected the codes written without the hyphen in ${dept}`).then((j) => { if (j) setSaid(`${String(j.renamed ?? 0)} code(s) corrected${Number(j.twins ?? 0) ? ` · ${String(j.twins)} left as duplicates of a code that already exists` : ""}`); }); }}>{busy ? "Working…" : `Fix ${codeFixes.filter((x) => !x.twin_exists).length} code${codeFixes.filter((x) => !x.twin_exists).length === 1 ? "" : "s"}`}</Btn>
                <span className="sub2">Renames where the corrected code is free; the rest stay listed with the reason.</span>
              </div>
            ) : null}
          </PBody>
        </Panel>
      ) : null}

      {toEnd.length ? (
        <Panel title="Duplicate courses" right={`${toEnd.length} to end or remove · the same course under more than one code`}>
          <PBody>
            <div className="sub2 mb-2">The same course was uploaded under more than one code, so it shows more than once on registration. The cleanest code is kept. A <b>BSU-</b> code and its <b>MOAU-</b> twin are never duplicates: both are kept — students in 300 level and above carry the BSU- code, those in 100 and 200 level the MOAU- code — so they do not appear here. A duplicate code that nothing carries — no registration, result or timetable — can be <b>removed completely</b>; one that a record already carries is <b>ended</b> instead and stays on the transcripts that carry it.</div>
            {dupGroups.map((g, i) => (
              <div key={i} style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)" }}>
                <div className="b600">{g.title} <span className="sub2">· {g.level} Level · {g.semester === 1 ? "First" : g.semester === 2 ? "Second" : "Third"} semester</span></div>
                <div className="row row--base mt-1">
                  {g.codes.map((c) => (
                    <span key={c.code} className="tnum t-sm row row--inline row--tight">
                      {c.keeper ? <Pil kind="ok">Keep {c.code}</Pil> : (
                        <>
                          <span className="ink-red" style={{ textDecoration: "line-through" }}>{c.code}</span>
                          <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { if (window.confirm(`Remove ${c.code} completely? It is deleted from the catalogue, with the programmes it was offered to. The portal refuses if any registration, result or timetable carries it; end it then.`)) void send(`/courses/${encodeURIComponent(c.code)}`, null, `Removed ${c.code} completely`, "DELETE").then((j) => { if (j) setSaid(`${c.code} removed completely`); }); }}>Remove</Btn>
                        </>
                      )}
                    </span>
                  ))}
                </div>
              </div>
            ))}
            <div className="row row--base mt-3">
              <Btn kind="urgent" disabled={busy} onClick={() => { if (window.confirm(`Remove ${toEnd.length} duplicate code${toEnd.length === 1 ? "" : "s"} completely? Each is deleted where nothing carries it, and ended where a registration, result or timetable does. The cleanest code in each group is kept.`)) void send(`/duplicates/remove?dept=${encodeURIComponent(dept)}`, {}, `Removed the duplicate courses in ${dept}`).then((j) => { if (j) setSaid(`${String(j.removed ?? 0)} duplicate code(s) removed completely, ${String(j.ended ?? 0)} ended because a record carries them`); }); }}>{busy ? "Working…" : `Remove ${toEnd.length} duplicate${toEnd.length === 1 ? "" : "s"} completely`}</Btn>
              <Btn kind="secondary" disabled={busy} onClick={() => { if (window.confirm(`End ${toEnd.length} duplicate course${toEnd.length === 1 ? "" : "s"}? The cleanest code in each group is kept. It can be undone by restoring the course.`)) void send(`/duplicates/end?dept=${encodeURIComponent(dept)}`, {}, `Ended ${toEnd.length} duplicate courses in ${dept}`).then((j) => { if (j) setSaid(`${String(j.ended ?? toEnd.length)} duplicate course(s) ended`); }); }}>{busy ? "Ending…" : `End ${toEnd.length} duplicate course${toEnd.length === 1 ? "" : "s"}`}</Btn>
              <span className="sub2">Remove deletes the code outright; End keeps it on the record with a date.</span>
            </div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="The department's catalogue" right={filtered ? `${shown.length} of ${courses.length} · filtered` : "Every course this department owns"}>
        <PBody>
          <div className="sub2 row">
            <span>Curriculum decides which cohort sees a course at registration (CCMAS or BMAS; leave a shared course, e.g. GST, blank). Tag {fLevel ? `${fLevel} Level` : "the department's"} courses:</span>
            {(["CCMAS", "BMAS"] as const).map((cur) => (
              <Btn key={cur} kind="ghost" disabled={busy} onClick={() => {
                if (!window.confirm(`Set ${fLevel ? `every ${fLevel} Level` : "every"} course in this department to ${cur}? You can change any course individually afterwards.`)) return;
                void send(`/curriculum/bulk?dept=${encodeURIComponent(dept)}&curriculum=${cur}${fLevel ? `&level=${fLevel}` : ""}`, {}, `Tagged ${fLevel || "all"} ${dept} courses as ${cur}`).then((j) => { if (j) setSaid(`${String(j.updated ?? "")} course(s) set to ${cur}`); });
              }}>Set to {cur}</Btn>
            ))}
          </div>
          <div className="sub2 row mt-2">
            <span>Assessment split — how a course&rsquo;s hundred marks divide between continuous assessment and the examination; the score sheet holds every mark to it. Set {fLevel ? `${fLevel} Level` : "the department's"} courses:</span>
            {SPLITS.map(([m, label]) => (
              <Btn key={m} kind="ghost" disabled={busy} onClick={() => {
                if (!window.confirm(`Set ${fLevel ? `every ${fLevel} Level` : "every"} course in this department to ${label}? You can change any course individually afterwards.`)) return;
                void send(`/split/bulk?dept=${encodeURIComponent(dept)}&caMax=${m}${fLevel ? `&level=${fLevel}` : ""}`, {}, `${fLevel || "All"} ${dept} courses set to ${label}`).then((j) => { if (j) setSaid(`${String(j.updated ?? "")} course(s) set to ${label}`); });
              }}>{label}</Btn>
            ))}
          </div>
        </PBody>
        {shown.length ? (
          <DTable cols={["Code|mid", "Title", "Units|mid", "Semester|mid", "Level|mid", "Kind", "Curriculum|mid", "CA / Exam|mid", "Lecturer", "State|mid", "Action|num"]} rows={shown.map((c) => [
            <b className="tnum" key="c">{c.code}</b>,
            <span key="t">{c.title}{c.pending ? <span className="sub2 ink-amber"> · {c.pending} proposal{c.pending === 1 ? "" : "s"} awaiting a department</span> : null}{c.bindings && c.bindings.length ? <div className="sub2 row" style={{ marginTop: 2, gap: "var(--s-1)" }}>{c.bindings.map((b) => <Link key={`${b.programme_code}-${b.level}`} href={`/catalogue/structure?prog=${encodeURIComponent(b.programme_code)}`} className="pill t-xs" style={{ textDecoration: "none" }} title={`${b.programme} · ${b.level} level · ${b.basis}${b.track ? ` · ${b.track}` : ""}`}>{b.programme_code} · {b.level}{b.basis !== "Core" ? ` · ${b.basis}` : ""}{b.track ? ` · ${b.track}` : ""}</Link>)}</div> : <div className="sub2 ink-red" style={{ marginTop: 2 }}>Not bound to any programme — no student sees it at registration</div>}</span>,
            <span className="tnum" key="u">{c.units}</span>,
            <span className="tnum" key="s">{c.semester === 1 ? "First" : c.semester === 2 ? "Second" : "Third"}</span>,
            <span className="tnum" key="l">{c.level}</span>,
            <span className="sub2" key="k">{kindLabel(c.kind)}</span>,
            <select key="cur" className="ctl t-sm" style={{ minWidth: 96, padding: "3px 6px" }} value={c.curriculum ?? ""} disabled={busy || c.state === "ENDED"}
              onChange={(e) => void send(`/courses/${encodeURIComponent(c.code)}/curriculum`, { curriculum: e.target.value }, `Curriculum of ${c.code} set to ${e.target.value || "none"}`).then((j) => { if (j) setSaid(`${c.code} → ${e.target.value || "no curriculum"}`); })}>
              <option value="">— (shared)</option>
              <option value="CCMAS">CCMAS</option>
              <option value="BMAS">BMAS</option>
            </select>,
            <select key="split" className="ctl t-sm" style={{ minWidth: 128, padding: "3px 6px" }} value={String(c.ca_max ?? 40)} disabled={busy || c.state === "ENDED"} aria-label={`Assessment split of ${c.code}`}
              onChange={(e) => { const m = Number(e.target.value); void send(`/courses/${encodeURIComponent(c.code)}/split`, { caMax: m }, `${c.code} set to ${splitLabel(m)}`).then((j) => { if (j) setSaid(`${c.code} → ${splitLabel(m)}`); }); }}>
              {SPLITS.some(([m]) => m === (c.ca_max ?? 40)) ? null : <option value={String(c.ca_max ?? 40)}>{splitLabel(c.ca_max ?? 40)}</option>}
              {SPLITS.map(([m, label]) => <option key={m} value={String(m)}>{label}</option>)}
            </select>,
            c.lecturer ? <span className="sub2" key="lec">{c.lecturer}</span> : c.state === "LIVE" && c.offered ? <span className="sub2 ink-red" key="lec">Not allocated</span> : <span className="sub2" key="lec">&mdash;</span>,
            <Pil kind={STATE[c.state]?.[0] ?? "grey"} key="st">{STATE[c.state]?.[1] ?? c.state}</Pil>,
            <div key="a" className="row row--tight row--right">
              <LinkBtn size="sm" href={`/catalogue/course?code=${encodeURIComponent(c.code)}`}>Details</LinkBtn>
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
              <Btn kind="ghost" disabled={busy} title="Delete the course outright; only possible when no registration, result or timetable carries it" onClick={() => { if (window.confirm(`Remove ${c.code} completely? It is deleted from the catalogue with the programmes it was offered to. The portal refuses if any registration, result or timetable carries it; end it then.`)) void send(`/courses/${encodeURIComponent(c.code)}`, null, `Removed ${c.code} completely`, "DELETE").then((j) => { if (j) setSaid(`${c.code} removed completely`); }); }}>Remove</Btn>
            </div>,
          ])} texts={shown.map((c) => `${c.code} ${c.title} ${kindLabel(c.kind)}`)} />
        ) : <PBody><div className="sub2">{filtered ? "No course in this department matches these filters. Clear them to see all." : "This department owns no course yet. A course appears here, live, as soon as it is created."}</div></PBody>}
      </Panel>

      {add ? (
        <Modal title="New course" sub={`For ${depts.find((d) => d.code === dept)?.name ?? dept} — one course, offered to the programmes you tick`} wide onClose={() => setAdd(false)}
          foot={<><Btn kind="ghost" onClick={() => setAdd(false)}>Cancel</Btn><span className="grow" />
            <Btn kind="primary" disabled={busy || !f.code.trim() || !f.title.trim() || Boolean(found?.byCode)} onClick={async () => {
              const offers = [...own.map((p) => ({ programme: p, level: Number(f.level) })), ...extra.map((x) => ({ programme: x.programme, level: Number(f.level), reason: why.trim() || null }))];
              const j = await send("/courses", { code: f.code.toUpperCase(), title: f.title, units: Number(f.units), semester: Number(f.semester), level: Number(f.level), dept, kind: f.kind, offers }, `New course ${f.code}`);
              if (j) { setSaid(`${String(j.code)} created and live · offered to ${String(j.bound ?? 0)} programme(s)${Number(j.proposed ?? 0) ? ` · proposed to ${String(j.proposed)} of another department` : ""} · it is on the course list below`); setAdd(false); }
            }}>Create</Btn></>}>
          {err ? <ProblemNotice problem={err} /> : null}
          <div className="grid grid--2">
            <Field id="nc-code" label="Code" hint="Three letters, a space, three digits — e.g. CSC 311"><input id="nc-code" className="ctl tnum" value={f.code} onChange={(e) => { setF({ ...f, code: e.target.value }); check(e.target.value, f.title, f.level); }} placeholder="CSC 311" autoComplete="off" /></Field>
            <Field id="nc-units" label="Units"><input id="nc-units" className="ctl tnum" value={f.units} inputMode="numeric" onChange={(e) => setF({ ...f, units: e.target.value })} /></Field>
          </div>
          <Field id="nc-title" label="Title"><input id="nc-title" className="ctl" value={f.title} onChange={(e) => { setF({ ...f, title: e.target.value }); check(f.code, e.target.value, f.level); }} placeholder="Algorithms and Complexity" autoComplete="off" /></Field>
          <div className="grid grid--3">
            <Field id="nc-level" label="Level"><select id="nc-level" className="ctl" value={f.level} onChange={(e) => { setF({ ...f, level: e.target.value }); setOwn(defaultTicked(e.target.value)); check(f.code, f.title, e.target.value); }}>{LEVELS.map((l) => <option key={l} value={l}>{l}</option>)}</select></Field>
            <Field id="nc-sem" label="Semester"><select id="nc-sem" className="ctl" value={f.semester} onChange={(e) => setF({ ...f, semester: e.target.value })}><option value="1">First</option><option value="2">Second</option></select></Field>
            <Field id="nc-kind" label="Kind"><select id="nc-kind" className="ctl" value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value })}>{KINDS.map((k) => <option key={k} value={k}>{kindLabel(k)}</option>)}</select></Field>
          </div>
          {found?.byCode ? (
            <Note kind="bad" title={`${found.byCode.code} already exists`} action={<span className="row row--inline row--tight"><LinkBtn size="sm" href={`/catalogue/course?code=${encodeURIComponent(found.byCode.code)}`}>Open the course</LinkBtn>{own.length ? <Btn kind="primary" size="sm" disabled={busy} onClick={() => void adoptExisting(found.byCode!.code)}>Offer it to my programme{own.length === 1 ? "" : "s"} instead</Btn> : null}</span>}>
              {found.byCode.title} · {found.byCode.dept_name ?? found.byCode.dept_code} · {found.byCode.level} Level · {STATE[found.byCode.state]?.[1] ?? found.byCode.state} · offered to {found.byCode.programmes ?? 0} programme{found.byCode.programmes === 1 ? "" : "s"}. A code is one course across the University: use the existing course and add your programme as an offering rather than creating a second record.
            </Note>
          ) : found?.byTitle.length ? (
            <Note kind="info" title="A course with this title already exists">
              {found.byTitle.map((c) => `${c.code} (${c.dept_name ?? c.dept_code}, ${c.level} Level)`).join("; ")}. If it is the same course, open it and add your programme as an offering instead of creating another; a different course with the same title is allowed.
            </Note>
          ) : null}
          <div className="eyebrow mt-3">Course owner</div>
          <div className="sub2 mb-2">{depts.find((d) => d.code === dept)?.name ?? dept} — sets the score sheet and answers a query on a mark. Another department offering the course does not change its owner.</div>
          <div className="eyebrow">Programmes offering this course</div>
          {ownProgs.length ? ownProgs.map((p) => (
            <label key={p.code} className="row row--inline row--tight" style={{ marginRight: 16 }}>
              <input type="checkbox" checked={own.includes(p.code)} onChange={(e) => setOwn(e.target.checked ? [...own, p.code] : own.filter((x) => x !== p.code))} /> {p.name} <span className="sub2 tnum">{p.code}</span>
            </label>
          )) : <div className="sub2">No active programme in this department; bind the course from a programme&rsquo;s structure later.</div>}
          {extra.length ? (
            <div className="mt-2">
              {extra.map((x) => (
                <span key={x.programme} className="chip row row--inline" style={{ border: "1px solid var(--line)", borderRadius: "var(--r-pill)", padding: "3px 6px 3px 12px", marginRight: 8 }}>
                  {x.name} <span className="sub2">· {x.deptName}{direct ? "" : " · awaits that department"}</span>
                  <button className="btn btn--ghost btn--sm" onClick={() => setExtra(extra.filter((y) => y.programme !== x.programme))} aria-label={`Remove ${x.name}`}>Remove</button>
                </span>
              ))}
            </div>
          ) : null}
          <div className="row row--end mt-2">
            <Field id="nc-dept" label="+ Add Department / Programme" style={{ flex: "2 1 260px" }} hint={direct ? "Bound at once" : "Another department's programme: its Head, its Dean or the Academic Office approves before students see it"}>
              <SearchSelect id="nc-dept" value={pickDept} placeholder="Search a department…" options={otherDepts.map((d) => ({ value: d.code, label: d.name }))} onChange={(v) => { setPickDept(v); setPickProgs([]); }} />
            </Field>
            {pickDept ? (
              <div style={{ flex: "3 1 320px" }}>
                {pickable.length ? pickable.map((p) => (
                  <label key={p.code} className="row row--inline row--tight" style={{ marginRight: 12 }}>
                    <input type="checkbox" checked={pickProgs.includes(p.code)} onChange={(e) => setPickProgs(e.target.checked ? [...pickProgs, p.code] : pickProgs.filter((x) => x !== p.code))} /> {p.name}
                  </label>
                )) : <div className="sub2">No further active programme in this department.</div>}
              </div>
            ) : null}
            {pickDept && pickProgs.length ? <Btn kind="secondary" onClick={() => { const dn = otherDepts.find((d) => d.code === pickDept)?.name ?? pickDept; setExtra([...extra, ...pickProgs.map((c) => ({ programme: c, name: pickable.find((p) => p.code === c)?.name ?? c, dept: pickDept, deptName: dn }))]); setPickDept(""); setPickProgs([]); }}>Add {pickProgs.length}</Btn> : null}
          </div>
          {extra.length && !direct ? <Field id="nc-why" label="Why those programmes should offer it" hint="Goes to each department's Head"><input id="nc-why" className="ctl" value={why} onChange={(e) => setWhy(e.target.value)} maxLength={2000} /></Field> : null}
        </Modal>
      ) : null}
    </>
  );
}
