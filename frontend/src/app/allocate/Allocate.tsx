"use client";

/** rAllocate — the department's offerings for a session, semester and level, and assigning teaching:
 *  a lead lecturer (who owns the score sheet), co-lecturers who also teach and enter scores, and the
 *  second examiner who verifies. V408: the checks the ICT desk reads, before saving; a reason when a lead is
 *  replaced or a co-lecturer removed; the class's and the department's allocation history. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedXlsx, downloadBlob } from "@/lib/exportbrand";
import { BulkUpload, type ImportRecord } from "./BulkUpload";
import { CheckList, HistoryTable, firmError, ACTION_WORD, ROLE_WORD, byText, whenText, type AllocationChecks, type AllocationEvent } from "@/components/allocation/AllocationParts";

export interface Dept { code: string; name: string; faculty_code: string }
export interface Lecturer { id: string; name: string; staff_number: string | null; load: number; department?: string | null }
export interface CoLecturer { id: string; name: string; programme_code?: string | null; programme?: string | null }
/** V443: a course of the department taught this semester, with its class in the session if one exists — `id` is null until the course
 *  is allocated (the allocation opens the class); a course is never tied to a session */
export interface Offering {
  id: string | null; course_code: string; title: string; units: number; level: number; allocated_on: string | null; registered: number;
  no_class?: boolean; not_in_structure?: boolean;
  lecturer_id: string | null; lecturer: string | null; second_examiner_id: string | null; second_examiner: string | null;
  co_lecturers: CoLecturer[]; sheet: boolean;
  /** the programmes that offer the course (V332): a co-lecturer may be posted to one programme's group */
  programmes?: { code: string; name: string }[];
}

const MAX_UNITS = 12;
const LEVELS = [100, 200, 300, 400, 500, 600];
const semName = (n: number) => (n === 1 ? "First" : n === 2 ? "Second" : "Third");

export function Allocate({ depts, sessions, dept, session, semester, level, offerings, lecturers, problem, imports = [], canImport = false, events = [] }: {
  depts: Dept[]; sessions: string[]; dept: string; session: string; semester: number; level: number | null;
  offerings: Offering[]; lecturers: Lecturer[]; problem: Problem | null; imports?: ImportRecord[]; canImport?: boolean;
  /** V408: the department's allocation history for the session and semester */
  events?: AllocationEvent[];
}) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const [open, setOpen] = useState<Offering | null>(null);
  const [lecturer, setLecturer] = useState("");
  const [second, setSecond] = useState("");
  const [co, setCo] = useState<CoLecturer[]>([]);
  const [addCoId, setAddCoId] = useState("");
  const [addCoProg, setAddCoProg] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  // cross-department: the department can assign its course to a lecturer from another department
  const [pool, setPool] = useState<Lecturer[] | null>(null);
  const [loadingPool, setLoadingPool] = useState(false);
  // the Head of Department finds a lecturer by name, staff number or department rather than scroll the register
  const [lecQ, setLecQ] = useState("");
  // V408: the checks of the lead and of the co-lecturer chosen, the reason a change needs, the class's history
  const [leadChecks, setLeadChecks] = useState<AllocationChecks | null>(null);
  const [coChecks, setCoChecks] = useState<AllocationChecks | null>(null);
  const [reason, setReason] = useState("");
  const [removing, setRemoving] = useState<CoLecturer | null>(null);
  const [removeReason, setRemoveReason] = useState("");
  const [history, setHistory] = useState<AllocationEvent[] | null>(null);
  const [historyVersion, setHistoryVersion] = useState(0);
  const openId = open?.id ?? null;
  const openLead = open?.lecturer_id ?? null;
  const replacing = !!openLead && !!lecturer && lecturer !== openLead;
  useEffect(() => {
    if (!openId || !lecturer || lecturer === openLead) return;
    let live = true;
    void fetch(`/api/bff/api/v1/allocation/${openId}/check?lecturer=${lecturer}&role=LECTURER`).then((r) => (r.ok ? r.json() : null)).then((j) => { if (live && j) setLeadChecks(j as AllocationChecks); });
    return () => { live = false; };
  }, [openId, lecturer, openLead]);
  useEffect(() => {
    if (!openId || !addCoId) return;
    let live = true;
    void fetch(`/api/bff/api/v1/allocation/${openId}/check?lecturer=${addCoId}&role=CO_LECTURER`).then((r) => (r.ok ? r.json() : null)).then((j) => { if (live && j) setCoChecks(j as AllocationChecks); });
    return () => { live = false; };
  }, [openId, addCoId]);
  useEffect(() => {
    if (!openId) return;
    let live = true;
    void fetch(`/api/bff/api/v1/allocation/${openId}/history`).then((r) => (r.ok ? r.json() : null)).then((j) => { if (live && Array.isArray(j)) setHistory(j as AllocationEvent[]); });
    return () => { live = false; };
  }, [openId, historyVersion]);
  /* a new choice: its own checks; the lead is never also the second examiner */
  function chooseLead(id: string) {
    setLecturer(id); setLeadChecks(null);
    if (second === id) setSecond("");
  }
  function chooseCo(id: string) {
    setAddCoId(id); setCoChecks(null);
  }

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
    setLecQ("");
    setSecond(o.second_examiner_id ?? "");
    setCo(o.co_lecturers ?? []);
    setAddCoId("");
    setErr(null);
    setLeadChecks(null); setCoChecks(null); setReason(""); setRemoving(null); setRemoveReason(""); setHistory(null);
  }

  async function call(path: string, method: string, body: unknown, reason: string, toast?: string): Promise<Record<string, unknown> | null> {
    // a request the portal never answers (an API restarting mid-deploy) must not lock the dialog for ever
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 30_000);
    let r: Response;
    try {
      r = await fetch(`/api/bff/api/v1/allocation${path}`, {
        method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) },
        body: method === "DELETE" ? undefined : JSON.stringify(body ?? {}), signal: ctl.signal,
      });
    } catch {
      setErr({ status: 0, title: ctl.signal.aborted ? "The portal did not answer within 30 seconds" : "The portal could not be reached",
        detail: "Nothing was saved. Try again in a moment; if the portal has just been updated, sign in again first." } as Problem); notifyProblem({ status: 0, title: ctl.signal.aborted ? "The portal did not answer within 30 seconds" : "The portal could not be reached",
        detail: "Nothing was saved. Try again in a moment; if the portal has just been updated, sign in again first." } as Problem);
      return null;
    } finally { clearTimeout(timer); }
    const j = await r.json().catch(() => null);
    if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
    notify(toast ?? reason);
    setHistoryVersion((v) => v + 1);
    return (j ?? {}) as Record<string, unknown>;
  }

  async function assign(overload: boolean) {
    if (!open || !lecturer) return;
    setBusy(true);
    setErr(null);
    try {
      // V443: a course the session holds no class for yet — the allocation opens the class first, as part of the same act
      let id = open.id;
      if (!id) {
        const opened = await call("/open", "POST", { courseCode: open.course_code, session, semester }, `Class opened for ${open.course_code} in ${session}`);
        if (!opened) return;
        id = String(opened.id);
      }
      const ok = await call(`/${id}`, "POST", { lecturer, secondExaminer: second || null, overload, reason: replacing ? reason.trim() : undefined },
        replacing ? reason.trim() : `Allocate ${open.course_code}`, replacing ? `${open.course_code} reassigned` : `Allocate ${open.course_code}`);
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
    if (!open || !addCoId || !open.id) return;   // V443: co-lecturers join a class; the lead's allocation opens it first
    setBusy(true);
    try {
      const group = (open.programmes ?? []).find((p) => p.code === addCoProg) ?? null;
      const ok = await call(`/${open.id}/teachers`, "POST", { lecturer: addCoId, programme: addCoProg || null }, `Co-lecturer added to ${open.course_code}${group ? ` for ${group.name}` : ""}`);
      setCoChecks(null);
      if (!ok) return;
      const who = list.find((l) => l.id === addCoId);
      if (who && !co.some((c) => c.id === who.id)) setCo([...co, { id: who.id, name: who.name, programme_code: group?.code ?? null, programme: group?.name ?? null }]);
      setAddCoId("");
      setAddCoProg("");
      router.refresh();
    } finally { setBusy(false); }
  }

  async function removeCoLecturer(id: string) {
    if (!open || removeReason.trim().length < 5) return;
    setBusy(true);
    try {
      const why = removeReason.trim();
      const ok = await call(`/${open.id}/teachers/${id}?reason=${encodeURIComponent(why)}`, "DELETE", null, why, `Co-lecturer removed from ${open.course_code}`);
      if (!ok) return;
      setCo(co.filter((c) => c.id !== id));
      setRemoving(null); setRemoveReason("");
      router.refresh();
    } finally { setBusy(false); }
  }

  const chosenLoad = list.find((l) => l.id === lecturer)?.load ?? 0;
  const lecTerms = lecQ.toLowerCase().trim().split(/s+/).filter(Boolean);
  const shownLecturers = lecTerms.length
    ? list.filter((l) => { const hay = `${l.name} ${l.staff_number ?? ""} ${l.department ?? ""}`.toLowerCase(); return lecTerms.every((t) => hay.includes(t)); })
    : list;
  const after = open ? chosenLoad + open.units : 0;
  const overloaded = after > MAX_UNITS;
  const coCandidates = list.filter((l) => l.id !== lecturer && !co.some((c) => c.id === l.id));
  // a new lead waits for the checks; a firm refusal, or a replacement without its reason, cannot be saved
  // V443: a course the session holds no class for yet has no class to pre-check against; the server checks the lecturer when the
  // class is opened and allocated (V408's refuseIneligible), so the save is not held for checks that cannot be fetched
  const blockedLead = !!lecturer && lecturer !== openLead && ((!!openId && !leadChecks) || (leadChecks != null && firmError(leadChecks)) || (replacing && reason.trim().length < 5));

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
              <div className="ws__select row b600">{deptName}</div>
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

      {said ? <Note kind="ok" title={said} /> : null}
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
                  <div className="row row--tight mt-1">
                    {cos(o).map((c) => <Pil kind="info" key={c.id}>{c.name}</Pil>)}
                  </div>
                ) : null}
              </span>
            ) : (
              <span key="l">
                <span className="ink-red b700">Unassigned</span>
                {/* V443: a course the session holds no class for yet — allocating it opens the class */}
                {!o.id ? <div className="sub2">No class in {session} yet · opens on allocation{o.not_in_structure ? " · in no programme's structure" : ""}</div> : null}
              </span>
            ),
            o.second_examiner ? <Pil kind="ok" key="s">{o.second_examiner}</Pil> : o.lecturer_id ? <Pil kind="bad" key="s">Not set</Pil> : <span className="sub2" key="s">&mdash;</span>,
            <Btn key="a" kind={o.lecturer_id ? "ghost" : "urgent"} onClick={() => openAssign(o)}>{o.lecturer_id ? "Manage" : "Assign"}</Btn>,
          ])} texts={offerings.map((o) => `${o.course_code} ${o.title} ${o.lecturer ?? ""} ${cos(o).map((c) => c.name).join(" ")}`)} />
        ) : <PBody><div className="sub2">No course is offered for {deptName} in {session}, {semName(semester).toLowerCase()} semester{level ? `, ${level} level` : ""}.</div></PBody>}
      </Panel>

      <div className="row mt-1">
        <Btn kind="ghost" onClick={() => void brandedXlsx("Teaching allocation", ["Course code", "Course", "Level", "Units", "Registered", "Lead lecturer", "Co-lecturers", "Second examiner"],
          offerings.map((o) => [o.course_code, o.title, o.level, o.units, o.registered, o.lecturer ?? "", cos(o).map((c) => c.name).join("; "), o.second_examiner ?? ""]),
          { sheetName: "Allocation", sub: `${deptName} · ${session} · ${semName(semester)} semester${level ? ` · ${level} level` : ""}`, meta: [["Department", deptName], ["Session", session], ["Semester", `${semName(semester)} semester`]] })
          .then((b) => downloadBlob(b, `allocation-${dept}-${session.replace("/", "-")}-${semester}.xlsx`))}>Download Excel</Btn>
      </div>

      <BulkUpload dept={dept} deptName={deptName} session={session} semester={semester} imports={imports} canImport={canImport} />

      <Panel title="Allocation history" right={events.length ? (
        <Btn kind="ghost" onClick={() => void brandedXlsx("Allocation history", ["When", "Course code", "Action", "Role", "Lecturer", "Previous lecturer", "Reason", "By", "Ticket"],
          events.map((h) => [whenText(h.at), h.course_code, ACTION_WORD[h.action] ?? h.action, ROLE_WORD[h.role] ?? h.role, h.lecturer ?? "", h.previous_lecturer ?? "", h.reason ?? "", byText(h), h.ticket ?? ""]),
          { sheetName: "History", sub: `${deptName} · ${session} · ${semName(semester)} semester`, meta: [["Department", deptName], ["Session", session], ["Semester", `${semName(semester)} semester`]] })
          .then((b) => downloadBlob(b, `allocation-history-${dept}-${session.replace("/", "-")}-${semester}.xlsx`))}>Download Excel</Btn>
      ) : `${deptName} · ${session} · ${semName(semester).toLowerCase()} semester`}>
        <PBody><HistoryTable rows={events} showCourse pageSize={20} onOpen={(id) => { const o = offerings.find((x) => x.id === id); if (o) openAssign(o); }} /></PBody>
      </Panel>


      {open ? (
        <Modal title={`${open.lecturer_id ? "Manage" : "Assign"} teaching for ${open.course_code}`} sub={`${open.title} · ${open.level} level · ${open.units} units · ${open.registered} registered`} wide onClose={() => setOpen(null)}
          foot={<><Btn kind="ghost" onClick={() => setOpen(null)}>Close</Btn>
            <span className={`sub2 grow${err ? " ink-red" : ""}`}>
              {err ? `Not saved — ${err.title}` : busy ? "Saving…" : !lecturer ? "Choose the lead lecturer to save"
                : firmError(leadChecks) ? "This lecturer cannot take the class — see the checks" : replacing && reason.trim().length < 5 ? "Give the reason for replacing the lead" : ""}
            </span>
            {overloaded
              ? <Btn kind="urgent" disabled={busy || !lecturer || blockedLead} onClick={() => void assign(true)}>{busy ? "Saving…" : `Save as an overload (${after} units)`}</Btn>
              : <Btn kind="go" disabled={busy || !lecturer || blockedLead} onClick={() => void assign(false)}>{busy ? "Saving…" : replacing ? "Reassign the lead" : "Save the lead & second examiner"}</Btn>}</>}>
          {err ? <ProblemNotice problem={err} /> : null}

          <div className="eyebrow mt-1">Lead lecturer</div>
          <div className="row row--between mt-1 mb-2">
            <div className="sub2">Ordered by remaining capacity against the {MAX_UNITS}-unit maximum; a full lecturer can still be assigned as an overload.</div>
            <label className="row row--inline row--tight" style={{ cursor: "pointer", whiteSpace: "nowrap" }}>
              <input type="checkbox" checked={pool !== null} disabled={loadingPool} onChange={(e) => void toggleAllDepartments(e.target.checked)} />
              {loadingPool ? "Loading…" : "Lecturers from other departments"}
            </label>
          </div>
          {list.length ? (<>
            <div className="row mb-2">
              <input id="al-find" className="ctl" type="search" value={lecQ} onChange={(e) => setLecQ(e.target.value)} autoComplete="off"
                placeholder={pool !== null ? "Search a lecturer by name, staff number or department…" : "Search a lecturer by name or staff number…"} aria-label="Search a lecturer" style={{ flex: "1 1 260px" }} />
              <span className="sub2 tnum" style={{ whiteSpace: "nowrap" }}>{lecTerms.length ? `${shownLecturers.length} of ${list.length} lecturers` : `${list.length} lecturers`}</span>
            </div>
            {shownLecturers.length ? (
            <DTable noPrint cols={pool !== null ? ["Lecturer", "Department", "Current load|mid", "After this|mid", "|num"] : ["Lecturer", "Current load|mid", "After this|mid", "|num"]} rows={shownLecturers.map((l) => {
              const willBe = l.load + open.units;
              return [
                <Two key="n" a={l.name} b={l.staff_number ?? ""} />,
                ...(pool !== null ? [<span className="sub2" key="d">{l.department ?? "—"}</span>] : []),
                <span className="tnum" key="c">{l.load} units</span>,
                <span className={`tnum${willBe > MAX_UNITS ? " ink-red b700" : ""}`} key="w">{willBe} units</span>,
                <label key="p" className="row row--inline row--tight" style={{ cursor: "pointer" }}>
                  <input type="radio" name="al-lec" checked={lecturer === l.id} onChange={() => chooseLead(l.id)} /> {lecturer === l.id ? "Lead" : "Choose"}
                </label>,
              ];
            })} />
            ) : <div className="sub2" style={{ padding: "var(--s-2) 0" }}>No lecturer matches &ldquo;{lecQ}&rdquo;{pool === null ? " in this department — tick “Lecturers from other departments” to look further" : ""}.</div>}
          </>) : <Note kind="bad" title="No lecturer is on record for this department">Tick &ldquo;Lecturers from other departments&rdquo; to assign from elsewhere.</Note>}

          {lecturer && lecturer !== open.lecturer_id ? <CheckList checks={leadChecks} title={`Checks for ${list.find((l) => l.id === lecturer)?.name ?? "the lecturer"}`} /> : null}
          {replacing ? (
            <Field id="al-reason" label={`Reason for replacing ${open.lecturer ?? "the lead"}`} required hint="Kept on the allocation history">
              <textarea id="al-reason" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} />
            </Field>
          ) : null}

          <Field id="al-second" label="Second examiner" hint="Verifies the marks. Cannot be the lead. Set now so verification is not blocked later.">
            <SearchSelect id="al-second" value={second} allLabel="Not set yet" placeholder="Search a lecturer…"
              options={list.filter((l) => l.id !== lecturer).map((l) => ({ value: l.id, label: pool !== null && l.department ? `${l.name} · ${l.department}` : l.name }))} onChange={setSecond} />
          </Field>

          {/* co-teaching: additional lecturers who teach the course and enter scores on the same sheet */}
          <div className="eyebrow mt-4">Co-lecturers</div>
          <div className="sub2 mb-2">Co-lecturers enter scores on the shared sheet; the lead submits it.{!open.id ? " Save the lead first: the class opens with that, and co-lecturers join it after." : ""}</div>
          {!open.id ? null : co.length ? (
            <div className="row mb-2">
              {co.map((c) => (
                <span key={c.id} className="chip row row--inline" style={{ border: "1px solid var(--line)", borderRadius: "var(--r-pill)", padding: "3px 6px 3px 12px" }}>
                  {c.name}{c.programme ? <span className="sub2"> · {c.programme}</span> : null}
                  <button className="btn btn--ghost btn--sm" disabled={busy} onClick={() => { setRemoving(c); setRemoveReason(""); }} aria-label={`Remove ${c.name}`}>Remove</button>
                </span>
              ))}
            </div>
          ) : <div className="sub2 mb-2">No co-lecturer yet — this course is taught by the lead alone.</div>}
          {removing ? (
            <div className="row row--end mb-2">
              <div style={{ flex: "1 1 280px" }}><Field id="al-rm" label={`Reason for removing ${removing.name}`} required hint="Kept on the allocation history">
                <input id="al-rm" className="ctl" value={removeReason} onChange={(e) => setRemoveReason(e.target.value)} /></Field></div>
              <Btn kind="ghost" disabled={busy} onClick={() => setRemoving(null)}>Cancel</Btn>
              <Btn kind="urgent" disabled={busy || removeReason.trim().length < 5} onClick={() => void removeCoLecturer(removing.id)}>{busy ? "Removing…" : "Remove co-lecturer"}</Btn>
            </div>
          ) : null}
          <div className="row row--end">
            <div style={{ flex: "1 1 240px" }}><Field id="al-co" label="Add a co-lecturer">
              <SearchSelect id="al-co" value={addCoId} placeholder="Search a lecturer…"
                options={coCandidates.map((l) => ({ value: l.id, label: pool !== null && l.department ? `${l.name} · ${l.department}` : l.name }))} onChange={chooseCo} /></Field></div>
            {(open.programmes ?? []).length > 1 ? (
              <div style={{ flex: "1 1 200px" }}><Field id="al-co-prog" label="Teaches" hint="One programme's group, or every programme">
                <select id="al-co-prog" className="ctl" value={addCoProg} onChange={(e) => setAddCoProg(e.target.value)}>
                  <option value="">Every programme</option>
                  {(open.programmes ?? []).map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
                </select></Field></div>
            ) : null}
            <Btn kind="primary" disabled={busy || !addCoId || !coChecks || !coChecks.ok} onClick={() => void addCoLecturer()}>{busy ? "Adding…" : "Add co-lecturer"}</Btn>
          </div>
          {addCoId ? <CheckList checks={coChecks} title={`Checks for ${list.find((l) => l.id === addCoId)?.name ?? "the co-lecturer"}`} /> : null}
          {!open.lecturer_id ? <div className="sub2 ink-muted mt-2">Tip: save the lead first, then co-lecturers are added to the same course.</div> : null}

          <div className="eyebrow mt-4">History</div>
          {history === null ? <div className="sub2">Loading…</div> : <HistoryTable rows={history} />}
        </Modal>
      ) : null}
    </>
  );
}
