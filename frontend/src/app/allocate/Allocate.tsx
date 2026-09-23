"use client";

/** rAllocate — the department's offerings for a session, semester and level, and assigning teaching:
 *  a lead lecturer (who owns the score sheet), co-lecturers who also teach and enter scores, and the
 *  second examiner who verifies. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Dept { code: string; name: string; faculty_code: string }
export interface Lecturer { id: string; name: string; staff_number: string | null; load: number; department?: string | null }
export interface CoLecturer { id: string; name: string }
export interface Offering {
  id: string; course_code: string; title: string; units: number; level: number; allocated_on: string | null; registered: number;
  lecturer_id: string | null; lecturer: string | null; second_examiner_id: string | null; second_examiner: string | null;
  co_lecturers: CoLecturer[]; sheet: boolean;
}

const MAX_UNITS = 12;
const LEVELS = [100, 200, 300, 400, 500, 600];
const semName = (n: number) => (n === 1 ? "First" : n === 2 ? "Second" : "Third");

export function Allocate({ depts, sessions, dept, session, semester, level, offerings, lecturers, problem }: {
  depts: Dept[]; sessions: string[]; dept: string; session: string; semester: number; level: number | null;
  offerings: Offering[]; lecturers: Lecturer[]; problem: Problem | null;
}) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const [open, setOpen] = useState<Offering | null>(null);
  const [lecturer, setLecturer] = useState("");
  const [second, setSecond] = useState("");
  const [co, setCo] = useState<CoLecturer[]>([]);
  const [addCoId, setAddCoId] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  // cross-department: the department can assign its course to a lecturer from another department
  const [pool, setPool] = useState<Lecturer[] | null>(null);
  const [loadingPool, setLoadingPool] = useState(false);

  async function toggleAllDepartments(on: boolean) {
    if (!on) { setPool(null); return; }
    setLoadingPool(true);
    try {
      const r = await fetch(`/api/bff/api/v1/allocation/lecturers?dept=${encodeURIComponent(dept)}&session=${encodeURIComponent(session)}&semester=${semester}&all=true`);
      const j = await r.json().catch(() => null);
      if (r.ok && Array.isArray(j)) setPool(j as Lecturer[]);
    } finally { setLoadingPool(false); }
  }
  const list = pool ?? lecturers;
  // co_lecturers should be an array; coerce defensively so a bad shape never crashes the render
  const cos = (o: Offering): CoLecturer[] => (Array.isArray(o.co_lecturers) ? o.co_lecturers : []);

  const unassigned = offerings.filter((o) => !o.lecturer_id).length;
  const noSecond = offerings.filter((o) => o.lecturer_id && !o.second_examiner_id).length;
  const deptName = depts.find((d) => d.code === dept)?.name ?? dept;

  function go(next: { dept?: string; session?: string; sem?: number; level?: number | null }) {
    const q = new URLSearchParams();
    q.set("dept", next.dept ?? dept);
    q.set("session", next.session ?? session);
    q.set("sem", String(next.sem ?? semester));
    const lv = next.level !== undefined ? next.level : level;
    if (lv) q.set("level", String(lv));
    queryNav(`/allocate?${q.toString()}`);
  }

  function openAssign(o: Offering) {
    setOpen(o);
    setLecturer(o.lecturer_id ?? "");
    setSecond(o.second_examiner_id ?? "");
    setCo(o.co_lecturers ?? []);
    setAddCoId("");
    setErr(null);
  }

  async function call(path: string, method: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    // a request the portal never answers (an API restarting mid-deploy) must not lock the dialog for ever
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 30_000);
    let r: Response;
    try {
      r = await fetch(`/api/bff/api/v1/allocation${path}`, {
        method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) },
        body: method === "DELETE" ? undefined : JSON.stringify(body ?? {}), signal: ctl.signal,
      });
    } catch (e) {
      setErr({ status: 0, title: ctl.signal.aborted ? "The portal did not answer within 30 seconds" : "The portal could not be reached",
        detail: "Nothing was saved. Try again in a moment; if the portal has just been updated, sign in again first." } as Problem);
      return null;
    } finally { clearTimeout(timer); }
    const j = await r.json().catch(() => null);
    if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return null; }
    notify(reason);
    return (j ?? {}) as Record<string, unknown>;
  }

  async function assign(overload: boolean) {
    if (!open || !lecturer) return;
    setBusy(true);
    setErr(null);
    try {
      const ok = await call(`/${open.id}`, "POST", { lecturer, secondExaminer: second || null, overload }, `Allocate ${open.course_code}`);
      if (!ok) return;
      const who = list.find((l) => l.id === lecturer)?.name ?? "the lecturer";
      setSaid(`${open.course_code} assigned to ${who}${co.length ? ` with ${co.length} co-lecturer${co.length === 1 ? "" : "s"}` : ""}`);
      setOpen(null);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  async function addCoLecturer() {
    if (!open || !addCoId) return;
    setBusy(true);
    try {
      const ok = await call(`/${open.id}/teachers`, "POST", { lecturer: addCoId }, `Co-lecturer added to ${open.course_code}`);
      if (!ok) return;
      const who = list.find((l) => l.id === addCoId);
      if (who && !co.some((c) => c.id === who.id)) setCo([...co, { id: who.id, name: who.name }]);
      setAddCoId("");
      router.refresh();
    } finally { setBusy(false); }
  }

  async function removeCoLecturer(id: string) {
    if (!open) return;
    setBusy(true);
    try {
      const ok = await call(`/${open.id}/teachers/${id}`, "DELETE", null, `Co-lecturer removed from ${open.course_code}`);
      if (!ok) return;
      setCo(co.filter((c) => c.id !== id));
      router.refresh();
    } finally { setBusy(false); }
  }

  const chosenLoad = list.find((l) => l.id === lecturer)?.load ?? 0;
  const after = open ? chosenLoad + open.units : 0;
  const overloaded = after > MAX_UNITS;
  const coCandidates = list.filter((l) => l.id !== lecturer && !co.some((c) => c.id === l.id));

  return (
    <>
      {/* the scope bar: a department office is bound to its own department, then session, semester, level */}
      <div className="scope">
        <div className="scope__row">
          <div className="scope__f"><label htmlFor="al-dept">Department</label>
            {depts.length > 1 ? (
              <SearchSelect id="al-dept" value={dept} placeholder="Search a department…"
                options={depts.map((d) => ({ value: d.code, label: d.name }))} onChange={(v) => go({ dept: v })} />
            ) : (
              <div className="ws__select" style={{ display: "flex", alignItems: "center", fontWeight: 600 }}>{deptName}</div>
            )}
          </div>
          <div className="scope__f"><label htmlFor="al-session">Session</label>
            <select id="al-session" className="ws__select" value={session} onChange={(e) => go({ session: e.target.value })}>
              {(sessions.includes(session) ? sessions : [session, ...sessions]).map((s) => <option key={s} value={s}>{s}</option>)}
            </select></div>
          <div className="scope__f"><label htmlFor="al-sem">Semester</label>
            <select id="al-sem" className="ws__select" value={semester} onChange={(e) => go({ sem: Number(e.target.value) })}>
              <option value={1}>First semester</option><option value={2}>Second semester</option>
            </select></div>
          <div className="scope__f"><label htmlFor="al-level">Level</label>
            <select id="al-level" className="ws__select" value={level ?? ""} onChange={(e) => go({ level: e.target.value ? Number(e.target.value) : null })}>
              <option value="">All levels</option>
              {LEVELS.map((l) => <option key={l} value={l}>{l} Level</option>)}
            </select></div>
        </div>
        <div className="scope__sum">
          <span className="trail">{deptName}{level ? ` › ${level} Level` : ""} › {session} › {semester === 1 ? "First" : "Second"} semester</span>
          <span className="count">Showing <b className="tnum">{offerings.length.toLocaleString()}</b> course{offerings.length === 1 ? "" : "s"}</span>
        </div>
      </div>

      {said ? <Note kind="ok" title={said}>The score sheet opens in the lead lecturer&rsquo;s name once the examination session is open; co-lecturers enter scores on the same sheet, and the second examiner verifies.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Tiles items={[
        ["Courses", String(offerings.length), null, `${session} · ${semName(semester).toLowerCase()} semester${level ? ` · ${level} level` : ""}`],
        ["Unassigned", String(unassigned), unassigned ? "var(--red-ink)" : "var(--green-ink)", unassigned ? "No lead lecturer yet" : "All have a lead"],
        ["No second examiner", String(noSecond), noSecond ? "var(--red-ink)" : null, "Blocks verification"],
        ["Lecturers", String(lecturers.length), null, "In this department"],
      ]} />

      <Panel title="Teaching allocation" right={`${deptName} · ${session} · ${semName(semester).toLowerCase()} semester${level ? ` · ${level} level` : ""}`}>
        {offerings.length ? (
          <DTable cols={["Course", "Level|mid", "Units|mid", "Registered|mid", "Lecturers", "Second examiner", "Action|num"]} rows={offerings.map((o) => [
            <span key="c"><strong className="tnum">{o.course_code}</strong><div className="sub2">{o.title}</div></span>,
            <span className="tnum" key="lv">{o.level}</span>,
            <span className="tnum" key="u">{o.units}</span>,
            <span className="tnum" key="r">{o.registered}</span>,
            o.lecturer ? (
              <span key="l">
                <strong>{o.lecturer}</strong>
                {cos(o).length ? (
                  <div style={{ display: "flex", gap: 4, flexWrap: "wrap", marginTop: 3 }}>
                    {cos(o).map((c) => <Pil kind="info" key={c.id}>{c.name}</Pil>)}
                  </div>
                ) : null}
              </span>
            ) : <span key="l" style={{ color: "var(--red-ink)", fontWeight: 700 }}>Unassigned</span>,
            o.second_examiner ? <Pil kind="ok" key="s">{o.second_examiner}</Pil> : o.lecturer_id ? <Pil kind="bad" key="s">Not set</Pil> : <span className="sub2" key="s">&mdash;</span>,
            <Btn key="a" kind={o.lecturer_id ? "ghost" : "urgent"} onClick={() => openAssign(o)}>{o.lecturer_id ? "Manage" : "Assign"}</Btn>,
          ])} texts={offerings.map((o) => `${o.course_code} ${o.title} ${o.lecturer ?? ""} ${cos(o).map((c) => c.name).join(" ")}`)} />
        ) : <PBody><div className="sub2">No course is offered for {deptName} in {session}, {semName(semester).toLowerCase()} semester{level ? `, ${level} level` : ""}. A course appears here once it is offered to the programme for the session and its registration is opened.</div></PBody>}
      </Panel>

      <Note kind="info" title="Assigning the lead lecturer does four things at once">
        It opens the course space and enrols the registered students, creates the score sheet in the lead lecturer&rsquo;s name, opens the attendance register, and releases the course to the timetable. A co-lecturer teaches the same course and enters scores on that sheet. The second examiner is set now, not at examination time, because the person who enters the marks may not be the one who verifies them.
      </Note>

      {open ? (
        <Modal title={`${open.lecturer_id ? "Manage" : "Assign"} teaching for ${open.course_code}`} sub={`${open.title} · ${open.level} level · ${open.units} units · ${open.registered} registered`} wide onClose={() => setOpen(null)}
          foot={<><Btn kind="ghost" onClick={() => setOpen(null)}>Close</Btn>
            <span className="sub2" style={{ flexGrow: 1, color: err ? "var(--red-ink)" : undefined }}>
              {err ? `Not saved — ${err.title}` : busy ? "Saving…" : !lecturer ? "Choose the lead lecturer to save" : ""}
            </span>
            {overloaded
              ? <Btn kind="urgent" disabled={busy || !lecturer} onClick={() => void assign(true)}>{busy ? "Saving…" : `Save as an overload (${after} units)`}</Btn>
              : <Btn kind="go" disabled={busy || !lecturer} onClick={() => void assign(false)}>{busy ? "Saving…" : "Save the lead & second examiner"}</Btn>}</>}>
          {err ? <ProblemNotice problem={err} /> : null}

          <div className="eyebrow" style={{ marginTop: 2 }}>Lead lecturer</div>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, flexWrap: "wrap", margin: "4px 0 8px" }}>
            <div className="sub2">The lead owns the score sheet and submits it up the chain. Ordered by remaining capacity against the {MAX_UNITS}-unit maximum; a full lecturer can still be assigned as an overload.</div>
            <label style={{ display: "inline-flex", gap: 6, alignItems: "center", cursor: "pointer", whiteSpace: "nowrap" }}>
              <input type="checkbox" checked={pool !== null} disabled={loadingPool} onChange={(e) => void toggleAllDepartments(e.target.checked)} />
              {loadingPool ? "Loading…" : "Lecturers from other departments"}
            </label>
          </div>
          {list.length ? (
            <DTable noPrint cols={pool !== null ? ["Lecturer", "Department", "Current load|mid", "After this|mid", "|num"] : ["Lecturer", "Current load|mid", "After this|mid", "|num"]} rows={list.map((l) => {
              const willBe = l.load + open.units;
              return [
                <Two key="n" a={l.name} b={l.staff_number ?? ""} />,
                ...(pool !== null ? [<span className="sub2" key="d">{l.department ?? "—"}</span>] : []),
                <span className="tnum" key="c">{l.load} units</span>,
                <span className="tnum" key="w" style={willBe > MAX_UNITS ? { color: "var(--red-ink)", fontWeight: 700 } : undefined}>{willBe} units</span>,
                <label key="p" style={{ display: "inline-flex", gap: 6, alignItems: "center", cursor: "pointer" }}>
                  <input type="radio" name="al-lec" checked={lecturer === l.id} onChange={() => setLecturer(l.id)} /> {lecturer === l.id ? "Lead" : "Choose"}
                </label>,
              ];
            })} />
          ) : <Note kind="bad" title="No lecturer is on record for this department">A lecturer appears here once the Registry grants them the lecturer office scoped to this department. Tick &ldquo;Lecturers from other departments&rdquo; to assign from elsewhere.</Note>}

          <Field id="al-second" label="Second examiner" hint="Verifies the marks. Cannot be the lead. Set now so verification is not blocked later.">
            <SearchSelect id="al-second" value={second} allLabel="Not set yet" placeholder="Search a lecturer…"
              options={list.filter((l) => l.id !== lecturer).map((l) => ({ value: l.id, label: pool !== null && l.department ? `${l.name} · ${l.department}` : l.name }))} onChange={setSecond} />
          </Field>

          {/* co-teaching: additional lecturers who teach the course and enter scores on the same sheet */}
          <div className="eyebrow" style={{ marginTop: 14 }}>Co-lecturers</div>
          <div className="sub2" style={{ margin: "2px 0 8px" }}>A course can be taught by more than one lecturer. A co-lecturer sees the course on their dashboard and enters scores on the shared sheet; the lead still submits it.</div>
          {co.length ? (
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 8 }}>
              {co.map((c) => (
                <span key={c.id} className="chip" style={{ display: "inline-flex", alignItems: "center", gap: 8, border: "1px solid var(--line)", borderRadius: 999, padding: "3px 6px 3px 12px" }}>
                  {c.name}
                  <button className="btn btn--ghost btn--sm" disabled={busy} onClick={() => void removeCoLecturer(c.id)} aria-label={`Remove ${c.name}`}>Remove</button>
                </span>
              ))}
            </div>
          ) : <div className="sub2" style={{ marginBottom: 8 }}>No co-lecturer yet — this course is taught by the lead alone.</div>}
          <div style={{ display: "flex", gap: 8, alignItems: "flex-end", flexWrap: "wrap" }}>
            <div className="field" style={{ flex: "1 1 240px" }}><label htmlFor="al-co">Add a co-lecturer</label>
              <SearchSelect id="al-co" value={addCoId} placeholder="Search a lecturer…"
                options={coCandidates.map((l) => ({ value: l.id, label: pool !== null && l.department ? `${l.name} · ${l.department}` : l.name }))} onChange={setAddCoId} /></div>
            <Btn kind="primary" disabled={busy || !addCoId} onClick={() => void addCoLecturer()}>{busy ? "Adding…" : "Add co-lecturer"}</Btn>
          </div>
          {!open.lecturer_id ? <div className="sub2" style={{ marginTop: 6, color: "var(--muted)" }}>Tip: save the lead first, then co-lecturers are added to the same course.</div> : null}
        </Modal>
      ) : null}
    </>
  );
}
