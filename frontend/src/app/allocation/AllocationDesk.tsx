"use client";

/**
 * The course allocation desk (V408) of the Director of ICT and the ICT Support Desk: the classes of a semester within the office's
 * reach, with who teaches each; the figures the desk opens with, each opening its list; a class allocated, reassigned (with a
 * reason), given a co-lecturer or a second examiner through the one allocation engine — after the checks, on a ticket where one
 * is named; a lecturer's load; the history; what needs a look; the bulk import. The server decides every reach and every act;
 * the buttons here only follow the capabilities it reports.
 */
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { roleLabel } from "@/lib/offices";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, PageHead, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { SearchSelect, type Opt } from "@/components/proto/SearchSelect";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { BulkUpload, type ImportRecord } from "../allocate/BulkUpload";
import { ACTION_WORD, ROLE_WORD, SOURCE_WORD, CheckList, HistoryTable, whenText as when, type AllocationChecks as Checks, type AllocationEvent as HistoryRow } from "@/components/allocation/AllocationParts";

export interface DeskOptions {
  sessions: { name: string; state: string; semesters: number | null }[];
  currentSession: string; currentSemester: number;
  faculties: { code: string; name: string }[];
  departments: { code: string; name: string; faculty_code: string }[];
  programmes: { code: string; name: string; dept_code: string | null }[];
  capabilities: string[]; scope: string;
}
interface Initial { session: string; semester: number; faculty: string; dept: string; programme: string; level: number; status: string; q: string; ticket: string }
interface Overview { classes: number; allocated: number; unallocated: number; several: number; allocations: number; teaching: number; conflicts: number; lecturers: number; session: string; semester: number; scope: string }
/** V443: a course taught this semester in reach, with its class in the session if one exists — `id` null until the desk opens it */
interface ClassRow {
  id: string | null; no_class?: boolean; course_code: string; title: string; units: number; level: number; dept_code: string; department: string | null; faculty_code: string | null; faculty: string | null;
  programmes: string | null; lecturer_id: string | null; lecturer: string | null; lecturer_staff_number: string | null; co_lecturers: string | null; second_examiner: string | null;
  registered: number; stage: string | null; allocated_on: string | null; updated_at: string | null;
}
interface Person { id: string; name: string; staff_number: string | null; email: string | null; ended_on: string | null; departments: string | null }
interface ClassView {
  id: string; course_code: string; title: string; units: number; level: number; session: string; semester: number; stream: string; dept_code: string; department: string | null;
  faculty_code: string | null; faculty: string | null; programmes: { code: string; name: string; level: number | null }[]; lecturer: Person | null; second_examiner: Person | null;
  co_lecturers: { id: string; name: string; staff_number: string | null; programme_code: string | null; programme: string | null; added_at: string }[];
  registered: number; stage: string | null; twin: string | null; conflicts: { kind: string; words: string }[]; history: HistoryRow[];
}
interface LecturerHit { id: string; name: string; staff_number: string | null; email: string | null; department: string | null; faculty: string | null; load: number }
interface LecturerView extends Person {
  faculty: string | null; session: string; semester: number | null; load: number | null; maxUnits: number; outside: number;
  classes: { id: string; course_code: string; title: string; units: number; level: number; session: string; semester: number; department: string | null; programmes: string | null; role: string; stage: string | null }[];
}
interface Conflict { offering_id: string; course_code: string; title: string; dept_code: string; department: string | null; kind: string; words: string }

type Tab = "classes" | "lecturers" | "history" | "conflicts" | "bulk";
type Status = "" | "UNALLOCATED" | "ALLOCATED" | "SEVERAL" | "CONFLICT";

const SEM = (n: number | null | undefined) => (n === 1 ? "First" : n === 2 ? "Second" : n === 3 ? "Third" : "—");
const CONFLICT_WORD: Record<string, string> = {
  LECTURER_LEFT: "Lecturer has left", NO_TEACHING_OFFICE: "No lecturer office", COURSE_ENDED: "Course ended", LEAD_ALSO_CO_LECTURER: "Lead also co-lecturer",
  OVERLOAD: "Over 12 units", TIMETABLE_CLASH: "Timetable clash",
};
const stageWord = (s: string | null) => (s ? s.charAt(0) + s.slice(1).toLowerCase().replace(/_/g, " ") : "—");
const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

type Result<T> = { ok: true; data: T } | { ok: false; problem: Problem };
async function call<T>(path: string, method = "GET", body?: unknown, reason?: string): Promise<Result<T>> {
  const headers: Record<string, string> = { Accept: "application/json" };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (reason) headers["X-Reason"] = reasonHeader(reason);
  try {
    const r = await fetch(`/api/bff/api/v1/allocation/desk${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), cache: "no-store" });
    const j = await r.json().catch(() => null);
    return r.ok ? { ok: true, data: j as T } : { ok: false, problem: (j as Problem) ?? { status: r.status, title: r.statusText } };
  } catch {
    return { ok: false, problem: { status: 0, title: "The portal could not be reached. Check the connection and try again." } };
  }
}

/** a lecturer found on the server as the name, staff number, email or department is typed (debounced) */
function LecturerPick({ id, value, label, onPick, session, semester, placeholder }: {
  id: string; value: string; label: string; onPick: (v: LecturerHit | null) => void; session: string; semester: number; placeholder?: string;
}) {
  const [hits, setHits] = useState<LecturerHit[]>([]);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const search = useCallback((q: string) => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(async () => {
      const r = await call<LecturerHit[]>(`/lecturers?q=${encodeURIComponent(q)}&session=${encodeURIComponent(session)}&semester=${semester}&limit=25`);
      if (r.ok) setHits(r.data);
    }, 250);
  }, [session, semester]);
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);
  const opts: Opt[] = hits.map((h) => ({ value: h.id, label: h.name, sub: [h.staff_number ? `Staff No: ${h.staff_number}` : null, h.department, `${h.load} units led this semester`].filter(Boolean).join(" · ") }));
  return (
    <SearchSelect id={id} value={value} valueLabel={label} options={opts} onQuery={search} placeholder={placeholder ?? "Type a name, staff number, email or department"}
      onChange={(v) => onPick(hits.find((h) => h.id === v) ?? null)} />
  );
}

export function AllocationDesk({ options, imports, initial }: { options: DeskOptions; imports: ImportRecord[]; initial: Initial }) {
  const caps = new Set(options.capabilities);
  const canAllocate = caps.has("ALLOCATE_COURSES");
  const [tab, setTab] = useState<Tab>("classes");
  const [session, setSession] = useState(initial.session || options.currentSession);
  const [semester, setSemester] = useState(initial.semester || options.currentSemester || 1);
  const [faculty, setFaculty] = useState(initial.faculty);
  const [dept, setDept] = useState(initial.dept);
  const [programme, setProgramme] = useState(initial.programme);
  const [level, setLevel] = useState(initial.level ? String(initial.level) : "");
  const [status, setStatus] = useState<Status>((["UNALLOCATED", "ALLOCATED", "SEVERAL", "CONFLICT"].includes(initial.status) ? initial.status : "") as Status);
  const [q, setQ] = useState(initial.q);
  const [qLive, setQLive] = useState(initial.q);
  const [page, setPage] = useState(1);
  const [overview, setOverview] = useState<Overview | null>(null);
  const [list, setList] = useState<{ rows: ClassRow[]; total: number } | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const [opening, setOpening] = useState<string | null>(null);
  const [version, setVersion] = useState(0);
  const SIZE = 50;

  // the search typed waits for a pause before the server is asked
  useEffect(() => { const t = setTimeout(() => { setQLive(q); setPage(1); }, 350); return () => clearTimeout(t); }, [q]);

  const qs = useMemo(() => {
    const p = new URLSearchParams({ session, semester: String(semester) });
    if (faculty) p.set("faculty", faculty);
    if (dept) p.set("dept", dept);
    if (programme) p.set("programme", programme);
    if (level) p.set("level", level);
    return p;
  }, [session, semester, faculty, dept, programme, level]);

  useEffect(() => {
    let live = true;
    void call<Overview>(`/overview?${qs.toString()}`).then((r) => { if (!live) return; if (r.ok) setOverview(r.data); else setProblem(r.problem); });
    return () => { live = false; };
  }, [qs, version]);
  useEffect(() => {
    let live = true;
    const p = new URLSearchParams(qs);
    if (status) p.set("status", status);
    if (qLive.trim()) p.set("q", qLive.trim());
    p.set("page", String(page));
    p.set("size", String(SIZE));
    void call<{ rows: ClassRow[]; total: number }>(`/classes?${p.toString()}`).then((r) => { if (!live) return; if (r.ok) { setList(r.data); setProblem(null); } else setProblem(r.problem); });
    return () => { live = false; };
  }, [qs, status, qLive, page, version]);
  const refresh = useCallback(() => setVersion((v) => v + 1), []);

  /** V443: the class of a course the session holds none for yet, opened by the desk within its reach, then shown for allocation */
  async function openClass(courseCode: string) {
    setOpening(courseCode);
    try {
      const r = await call<{ offering: string }>("/classes/open", "POST", { courseCode, session, semester }, `Class opened for ${courseCode} in ${session}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      refresh();
      setOpen(r.data.offering);
    } finally {
      setOpening(null);
    }
  }

  const facOpts: Opt[] = options.faculties.map((f) => ({ value: f.code, label: f.name }));
  const deptOpts: Opt[] = options.departments.filter((d) => !faculty || d.faculty_code === faculty).map((d) => ({ value: d.code, label: d.name }));
  const deptCodes = new Set(options.departments.filter((d) => !faculty || d.faculty_code === faculty).map((d) => d.code));
  const progOpts: Opt[] = options.programmes.filter((p) => (dept ? p.dept_code === dept : !faculty || deptCodes.has(p.dept_code ?? ""))).map((p) => ({ value: p.code, label: `${p.name} (${p.code})` }));
  const sessOpts: Opt[] = options.sessions.map((s) => ({ value: s.name, label: `${s.name}${s.state === "CURRENT" ? " (current)" : s.state === "PLANNED" ? " (planned)" : ""}` }));
  const semCount = options.sessions.find((s) => s.name === session)?.semesters ?? 2;
  const semOpts: Opt[] = Array.from({ length: Math.max(2, semCount) }, (_, i) => ({ value: String(i + 1), label: `${SEM(i + 1)} semester` }));
  const levelOpts: Opt[] = [100, 200, 300, 400, 500, 600, 700, 800, 900].map((l) => ({ value: String(l), label: `${l} level` }));

  const pick = (s: Status) => { setStatus(s); setPage(1); setTab("classes"); };
  const figure = (label: string, n: ReactNode, note: string, s: Status | null, colour?: string): ReactNode => (
    <button type="button" className="tile" style={{ textAlign: "left", cursor: s === null ? "default" : "pointer", font: "inherit" }}
      onClick={s === null ? undefined : () => pick(s)} aria-pressed={s !== null && status === s}>
      <span className="eyebrow">{label}</span>
      <span className="n tnum" style={colour ? { color: colour } : undefined}>{n ?? "…"}</span>
      <span className="c">{note}</span>
    </button>
  );

  async function exportClasses() {
    const p = new URLSearchParams(qs);
    if (status) p.set("status", status);
    if (qLive.trim()) p.set("q", qLive.trim());
    p.set("size", "5000");
    const r = await call<{ rows: ClassRow[] }>(`/classes?${p.toString()}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    const title = status === "UNALLOCATED" ? "Unallocated courses" : "Course allocations";
    downloadBlob(await brandedXlsx(title, ["Course Code", "Course Title", "Units", "Faculty", "Department", "Programmes", "Level", "Lecturer", "Staff Number", "Co-lecturers", "Second Examiner", "Registered", "Score Sheet", "Status", "Last Updated"],
      r.data.rows.map((c) => [c.course_code, c.title, c.units, c.faculty ?? "", c.department ?? c.dept_code, c.programmes ?? "", c.level, c.lecturer ?? "", c.lecturer_staff_number ?? "", c.co_lecturers ?? "",
        c.second_examiner ?? "", c.registered, stageWord(c.stage), c.lecturer_id ? "Allocated" : "Unallocated", day(c.updated_at)]),
      { sheetName: title, serial: docSerial("ALLOC"), meta: [["Session", session], ["Semester", `${SEM(semester)} semester`], ["Scope", options.scope]] }),
      `${title.toLowerCase().replace(/ /g, "-")}-${session.replace("/", "-")}-sem${semester}.xlsx`);
  }

  const rows = list?.rows ?? [];
  const total = list?.total ?? 0;
  const from = total ? (page - 1) * SIZE + 1 : 0;
  const to = Math.min(total, page * SIZE);
  const deptName = options.departments.find((d) => d.code === dept)?.name ?? "";

  return (
    <>
      <PageHead description={`${options.scope} · ${session}, ${SEM(semester)} semester`}
        actions={<Btn kind="ghost" onClick={() => void exportClasses()}>Export (Excel)</Btn>} />
      {problem ? <Note kind="bad" title={problem.title ?? "The request was refused"}>{problem.detail}</Note> : null}

      <Panel title="Filters">
        <PBody>
          <div className="grid grid--4">
            <Field id="al-session" label="Session"><SearchSelect id="al-session" value={session} options={sessOpts} onChange={(v) => { setSession(v || options.currentSession); setPage(1); }} /></Field>
            <Field id="al-sem" label="Semester"><SearchSelect id="al-sem" value={String(semester)} options={semOpts} onChange={(v) => { setSemester(Number(v) || 1); setPage(1); }} /></Field>
            <Field id="al-fac" label="Faculty"><SearchSelect id="al-fac" value={faculty} allLabel="All faculties" options={facOpts} onChange={(v) => { setFaculty(v); setDept(""); setProgramme(""); setPage(1); }} /></Field>
            <Field id="al-dept" label="Department"><SearchSelect id="al-dept" value={dept} allLabel="All departments" options={deptOpts} onChange={(v) => { setDept(v); setProgramme(""); setPage(1); }} /></Field>
            <Field id="al-prog" label="Programme"><SearchSelect id="al-prog" value={programme} allLabel="All programmes" options={progOpts} onChange={(v) => { setProgramme(v); setPage(1); }} /></Field>
            <Field id="al-level" label="Level"><SearchSelect id="al-level" value={level} allLabel="All levels" options={levelOpts} onChange={(v) => { setLevel(v); setPage(1); }} /></Field>
            <Field id="al-q" label="Search" style={{ gridColumn: "1 / -1" }}><input id="al-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Course code, title, lecturer or staff number" /></Field>
          </div>
        </PBody>
      </Panel>

      <div className="grid grid--4 mt-2">
        {figure("Courses", overview?.classes, "classes this semester", "")}
        {figure("Allocated", overview?.allocated, "with a lead lecturer", "ALLOCATED", "var(--green, #1d7a46)")}
        {figure("Unallocated", overview?.unallocated, "waiting for a lecturer", "UNALLOCATED", overview?.unallocated ? "var(--crimson, #c51e28)" : undefined)}
        {figure("Several lecturers", overview?.several, "with co-lecturers", "SEVERAL")}
        {figure("Allocations", overview?.allocations, "leads and co-lecturers", null)}
        {figure("Lecturers", overview?.lecturers, `${overview?.teaching ?? 0} teaching this semester`, null)}
        {figure("Conflicts", overview?.conflicts, "need a look", "CONFLICT", overview?.conflicts ? "var(--amber, #a15c00)" : undefined)}
        {figure("Current session", options.currentSession, `${SEM(options.currentSemester)} semester`, null)}
      </div>

      <div className="mt-2">
        <Tabs<Tab> label="Course allocation" value={tab} onChange={setTab} items={[
          { id: "classes", label: "Courses", count: total },
          { id: "lecturers", label: "Lecturers" },
          { id: "history", label: "History" },
          { id: "conflicts", label: "Conflicts", count: overview?.conflicts },
          ...(caps.has("BULK_ALLOCATE") ? [{ id: "bulk" as Tab, label: "Bulk allocate" }] : []),
        ]} />
      </div>

      {tab === "classes" ? (
        <Panel title={status === "UNALLOCATED" ? "Unallocated courses" : status === "ALLOCATED" ? "Allocated courses" : status === "SEVERAL" ? "Courses with several lecturers" : status === "CONFLICT" ? "Courses with a conflict" : "Course allocations"}
          right={<span className="row row--inline">
            <Tabs<Status> look="line" label="Status" value={status} onChange={(s) => { setStatus(s); setPage(1); }} items={[
              { id: "", label: "All" }, { id: "UNALLOCATED", label: "Unallocated" }, { id: "ALLOCATED", label: "Allocated" }, { id: "SEVERAL", label: "Several" }, { id: "CONFLICT", label: "Conflicts" }]} />
          </span>}>
          <PBody>
            {!list ? <p className="sub2">Loading…</p> : rows.length === 0 ? <p className="sub2">No course matches these filters.</p> : (
              <>
                <DTable pageSize={0} cols={["S/N|num", "Course Code", "Course Title", "Units|num", "Department", "Programmes", "Level|num", "Lecturer", "Co-lecturers", "Status|mid", "Last Updated", "|mid"]}
                  rows={rows.map((c, i) => [from + i, <b key="c">{c.course_code}</b>, c.title, c.units, c.department ?? c.dept_code, c.programmes ?? "—", c.level,
                    c.lecturer ? <span key="l">{c.lecturer}{c.lecturer_staff_number ? <span className="sub2"> · {c.lecturer_staff_number}</span> : null}</span> : <span key="l" className="sub2">—</span>,
                    c.co_lecturers ?? "—",
                    <Pil key="s" kind={c.lecturer_id ? "ok" : "warn"}>{c.lecturer_id ? "Allocated" : "Unallocated"}</Pil>,
                    day(c.updated_at),
                    c.id
                      ? <Btn key="a" kind={c.lecturer_id ? "ghost" : "primary"} onClick={() => setOpen(c.id as string)}>{c.lecturer_id ? "View" : canAllocate ? "Allocate" : "View"}</Btn>
                      // V443: a course is never tied to a session — a course the session holds no class for yet is opened by the desk, then allocated
                      : canAllocate
                        ? <Btn key="a" kind="primary" disabled={opening === c.course_code} onClick={() => void openClass(c.course_code)}>{opening === c.course_code ? "Opening…" : "Open & allocate"}</Btn>
                        : <span key="a" className="sub2">No class yet</span>])} />
                <div className="row mt-2" style={{ justifyContent: "space-between", flexWrap: "wrap" }}>
                  <span className="sub2">Showing {from}–{to} of {total}</span>
                  <span className="row row--inline">
                    <Btn kind="ghost" disabled={page <= 1} onClick={() => setPage((p) => Math.max(1, p - 1))}>Previous</Btn>
                    <Btn kind="ghost" disabled={to >= total} onClick={() => setPage((p) => p + 1)}>Next</Btn>
                  </span>
                </div>
              </>
            )}
          </PBody>
        </Panel>
      ) : null}

      {tab === "lecturers" ? <LecturerLoad session={session} semester={semester} onOpen={setOpen} scope={options.scope} /> : null}
      {tab === "history" ? <History session={session} semester={semester} dept={dept} initialTicket={initial.ticket} onOpen={setOpen} scope={options.scope} /> : null}
      {tab === "conflicts" ? <Conflicts session={session} semester={semester} dept={dept} onOpen={setOpen} /> : null}
      {tab === "bulk" ? (
        <BulkUpload dept={dept} deptName={deptName || "All departments in reach"} session={session} semester={semester} imports={imports} canImport={caps.has("BULK_ALLOCATE")} />
      ) : null}

      {open ? <ClassDialog id={open} caps={caps} initialTicket={initial.ticket} onClose={() => setOpen(null)} onChanged={refresh} /> : null}
    </>
  );
}

/* ── one class: who teaches it, the act, the checks, the history ── */

type Act = "LECTURER" | "CO_LECTURER" | "SECOND_EXAMINER";

function ClassDialog({ id, caps, initialTicket, onClose, onChanged }: {
  id: string; caps: Set<string>; initialTicket: string; onClose: () => void; onChanged: () => void;
}) {
  const [view, setView] = useState<ClassView | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [act, setAct] = useState<Act>("LECTURER");
  const [person, setPerson] = useState<LecturerHit | null>(null);
  const [checks, setChecks] = useState<Checks | null>(null);
  const [overload, setOverload] = useState(false);
  const [reason, setReason] = useState("");
  const [ticket, setTicket] = useState(initialTicket);
  const [review, setReview] = useState(false);
  const [busy, setBusy] = useState(false);
  const [removing, setRemoving] = useState<{ id: string; name: string } | null>(null);
  const canAllocate = caps.has("ALLOCATE_COURSES");

  const [version, setVersion] = useState(0);
  useEffect(() => {
    let live = true;
    void call<ClassView>(`/classes/${id}`).then((r) => { if (!live) return; if (r.ok) setView(r.data); else setProblem(r.problem); });
    return () => { live = false; };
  }, [id, version]);
  useEffect(() => {
    if (!person || act === "SECOND_EXAMINER") return;
    let live = true;
    void call<Checks>(`/check?offering=${id}&lecturer=${person.id}&role=${act}`).then((r) => { if (live && r.ok) setChecks(r.data); });
    return () => { live = false; };
  }, [person, act, id]);
  /* a new choice of person or role: its own checks, nothing carried over */
  const choose = (p: LecturerHit | null, a: Act = act) => { setChecks(null); setOverload(false); setReview(false); setPerson(p); setAct(a); };

  if (problem) return <Modal title="Course" onClose={onClose}><Note kind="bad" title={problem.title ?? "Refused"}>{problem.detail}</Note></Modal>;
  if (!view) return <Modal title="Course" onClose={onClose}><p className="sub2">Loading…</p></Modal>;

  const reassign = act === "LECTURER" && !!view.lecturer;
  const changingSecond = act === "SECOND_EXAMINER" && !!view.second_examiner;
  const needReason = reassign || changingSecond;
  const blocked = act !== "SECOND_EXAMINER" && (!checks || !checks.ok || (checks.overload && !overload));
  const verb = act === "LECTURER" ? (reassign ? "Reassign course" : "Allocate course") : act === "CO_LECTURER" ? "Add co-lecturer" : "Name second examiner";
  const programmes = view.programmes.map((p) => p.name).filter((n, i, a) => a.indexOf(n) === i).join("; ") || "—";

  async function commit() {
    if (!person || !view) return;
    setBusy(true);
    const body = { lecturer: person.id, person: person.id, overload, reason: reason.trim() || undefined, ticket: ticket.trim() || undefined };
    const path = act === "LECTURER" ? `/classes/${id}/lecturer` : act === "CO_LECTURER" ? `/classes/${id}/co-lecturers` : `/classes/${id}/second-examiner`;
    const r = await call<{ message: string }>(path, "POST", body, reason.trim() || `${verb}: ${view.course_code}`);
    setBusy(false);
    if (!r.ok) { notifyProblem(r.problem); setProblem(null); return; }
    notify(r.data.message);
    choose(null); setReason("");
    setVersion((v) => v + 1);
    onChanged();
  }
  async function remove() {
    if (!removing || !view) return;
    setBusy(true);
    const r = await call<{ message: string }>(`/classes/${id}/co-lecturers/${removing.id}/remove`, "POST", { reason: reason.trim(), ticket: ticket.trim() || undefined }, reason.trim());
    setBusy(false);
    if (!r.ok) { notifyProblem(r.problem); return; }
    notify(r.data.message);
    setRemoving(null); setReason("");
    setVersion((v) => v + 1);
    onChanged();
  }


  return (
    <Modal wide title={`${view.course_code} — ${view.title}`} sub={`${view.session}, ${SEM(view.semester)} semester · ${view.units} units · ${view.level} level`} onClose={onClose}
      foot={removing ? (
        <><Btn kind="ghost" onClick={() => setRemoving(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || reason.trim().length < 5} onClick={() => void remove()}>Remove allocation</Btn></>
      ) : review ? (
        <><Btn kind="ghost" onClick={() => setReview(false)}>Cancel</Btn><Btn kind="go" disabled={busy} onClick={() => void commit()}>{busy ? "Saving…" : verb}</Btn></>
      ) : canAllocate ? (
        <><Btn kind="ghost" onClick={onClose}>Close</Btn><Btn kind="primary" disabled={!person || blocked || (needReason && reason.trim().length < 5)} onClick={() => setReview(true)}>Review</Btn></>
      ) : <Btn kind="ghost" onClick={onClose}>Close</Btn>}>
      <KvGrid cls="grid--3" pairs={[
        ["Faculty", view.faculty ?? "—"], ["Department", view.department ?? view.dept_code], ["Programmes", programmes],
        ["Lead lecturer", view.lecturer ? `${view.lecturer.name}${view.lecturer.staff_number ? ` · ${view.lecturer.staff_number}` : ""}` : "Not allocated"],
        ["Second examiner", view.second_examiner?.name ?? "—"], ["Registered", String(view.registered)],
        ["Score sheet", stageWord(view.stage)], ["Taught with", view.twin ?? "—"], ["Stream", view.stream === "PG" ? "Postgraduate" : "Full-time"],
      ]} />
      {view.conflicts.length ? <Note kind="bad" title="Needs a look">{view.conflicts.map((c) => c.words).join(" ")}</Note> : null}

      {view.co_lecturers.length ? (
        <div className="mt-2">
          <b>Co-lecturers</b>
          <DTable noPrint pageSize={0} cols={["S/N|num", "Lecturer", "Staff Number", "Group", "Added", "|mid"]} rows={view.co_lecturers.map((c, i) => [i + 1, c.name, c.staff_number ?? "—", c.programme ?? "Every programme", day(c.added_at),
            caps.has("REMOVE_ALLOCATIONS") ? <Btn key="r" kind="ghost" onClick={() => { setRemoving({ id: c.id, name: c.name }); setReview(false); }}>Remove</Btn> : ""])} />
        </div>
      ) : null}

      {removing ? (
        <div className="mt-2">
          <Note kind="info" title={`Remove ${removing.name} as a co-lecturer of ${view.course_code}?`}>The history keeps that they taught the class; they are told.</Note>
          <Field id="al-rm-reason" label="Reason" required><textarea id="al-rm-reason" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
          <Field id="al-rm-ticket" label="Support ticket" hint="Optional: TICK-2026-00145"><input id="al-rm-ticket" className="ctl" value={ticket} onChange={(e) => setTicket(e.target.value)} /></Field>
        </div>
      ) : canAllocate && !review ? (
        <div className="mt-2">
          <div className="grid grid--3">
            <Field id="al-act" label="Allocate as">
              <SearchSelect id="al-act" value={act} onChange={(v) => choose(null, (v || "LECTURER") as Act)}
                options={[{ value: "LECTURER", label: view.lecturer ? "Lead lecturer (reassign)" : "Lead lecturer" }, { value: "CO_LECTURER", label: "Co-lecturer" }, ...(view.lecturer ? [{ value: "SECOND_EXAMINER", label: "Second examiner" }] : [])]} />
            </Field>
            <Field id="al-who" label="Lecturer" style={{ gridColumn: "1 / -1" }}>
              <LecturerPick id="al-who" value={person?.id ?? ""} label={person?.name ?? ""} onPick={(p) => choose(p)} session={view.session} semester={view.semester} />
            </Field>
          </div>
          {person && act !== "SECOND_EXAMINER" ? <CheckList checks={checks} /> : null}
          {checks?.overload ? (
            <label className="row mt-2" style={{ gap: 6 }}><input type="checkbox" checked={overload} onChange={(e) => setOverload(e.target.checked)} /> Allocate as an overload (reported to the Dean)</label>
          ) : null}
          <div className="grid grid--2 mt-2">
            <Field id="al-reason" label={needReason ? "Reason for reassignment" : "Reason"} required={needReason} hint={needReason ? undefined : "Optional for a first allocation"}>
              <textarea id="al-reason" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} />
            </Field>
            <Field id="al-ticket" label="Support ticket" hint="Optional: the ticket this resolves, e.g. TICK-2026-00145">
              <input id="al-ticket" className="ctl" value={ticket} onChange={(e) => setTicket(e.target.value)} />
            </Field>
          </div>
        </div>
      ) : null}

      {review && person ? (
        <div className="mt-2" style={{ border: "1px solid var(--line, #d9dde4)", borderRadius: 8, padding: 12, background: "var(--sky-bg, #eef5fb)" }}>
          <b>{verb}</b>
          <KvGrid cls="grid--2" pairs={[
              ["Course", `${view.course_code} — ${view.title}`], ["Faculty", view.faculty ?? "—"], ["Department", view.department ?? view.dept_code], ["Programme", programmes],
              ["Session", view.session], ["Semester", `${SEM(view.semester)} semester`],
              ...(reassign ? [["Current lecturer", view.lecturer?.name ?? "—"] as [ReactNode, ReactNode], ["New lecturer", person.name] as [ReactNode, ReactNode]]
                : [[act === "SECOND_EXAMINER" ? "Second examiner" : act === "CO_LECTURER" ? "Co-lecturer" : "Lecturer", person.name] as [ReactNode, ReactNode]]),
              ...(reason.trim() ? [["Reason", reason.trim()] as [ReactNode, ReactNode]] : []),
              ...(ticket.trim() ? [["Ticket", ticket.trim()] as [ReactNode, ReactNode]] : []),
          ]} />
        </div>
      ) : null}

      <div className="mt-2">
        <b>History</b>
        <HistoryTable rows={view.history} />
      </div>
    </Modal>
  );
}

/* ── a lecturer and their load ── */

function LecturerLoad({ session, semester, onOpen, scope }: { session: string; semester: number; onOpen: (id: string) => void; scope: string }) {
  const [hit, setHit] = useState<LecturerHit | null>(null);
  const [view, setView] = useState<LecturerView | null>(null);
  const [allSemesters, setAllSemesters] = useState(false);
  useEffect(() => {
    if (!hit) return;
    let live = true;
    void call<LecturerView>(`/lecturers/${hit.id}?session=${encodeURIComponent(session)}${allSemesters ? "" : `&semester=${semester}`}`).then((r) => { if (live) { if (r.ok) setView(r.data); else notifyProblem(r.problem); } });
    return () => { live = false; };
  }, [hit, session, semester, allSemesters]);
  const units = view?.classes.filter((c) => c.role === "LECTURER").reduce((n, c) => n + Number(c.units), 0) ?? 0;
  async function exportLoad() {
    if (!view) return;
    downloadBlob(await brandedXlsx(`Lecturer course load — ${view.name}`, ["Course Code", "Course Title", "Units", "Department", "Programmes", "Level", "Session", "Semester", "Role", "Score Sheet"],
      view.classes.map((c) => [c.course_code, c.title, c.units, c.department ?? "", c.programmes ?? "", c.level, c.session, `${SEM(c.semester)}`, ROLE_WORD[c.role] ?? c.role, stageWord(c.stage)]),
      { sheetName: "Course load", serial: docSerial("ALLOCLOAD"), meta: [["Lecturer", view.name], ["Staff number", view.staff_number ?? ""], ["Department", view.departments ?? ""], ["Session", session], ["Units led", String(units)]] }),
      `course-load-${(view.staff_number ?? view.name).replace(/[^A-Za-z0-9]+/g, "-")}-${session.replace("/", "-")}.xlsx`);
  }
  return (
    <Panel title="Lecturer allocations" right={view ? <Btn kind="ghost" onClick={() => void exportLoad()}>Export (Excel)</Btn> : undefined}>
      <PBody>
        <div className="grid grid--2">
          <Field id="al-lec" label="Search lecturer"><LecturerPick id="al-lec" value={hit?.id ?? ""} label={hit?.name ?? ""} onPick={(h) => { setView(null); setHit(h); }} session={session} semester={semester} /></Field>
          <Field id="al-lec-all" label="Semesters"><label className="row" style={{ gap: 6 }}><input id="al-lec-all" type="checkbox" checked={allSemesters} onChange={(e) => setAllSemesters(e.target.checked)} /> every semester of {session}</label></Field>
        </div>
        {view ? (
          <>
            <KvGrid cls="grid--3" pairs={[["Name", view.name], ["Staff number", view.staff_number ?? "—"], ["Department", view.departments ?? "—"], ["Faculty", view.faculty ?? "—"], ["Email", view.email ?? "—"],
              ["Units led", allSemesters ? `${units} in ${session}` : `${view.load ?? units} of ${view.maxUnits}`]]} />
            {view.outside ? <Note kind="info" title={`${view.outside} more class${view.outside === 1 ? "" : "es"} outside your scope`}>Your allocation scope is {scope}.</Note> : null}
            {view.classes.length ? (
              <DTable pageSize={0} cols={["S/N|num", "Course Code", "Course Title", "Units|num", "Department", "Programmes", "Level|num", "Session", "Semester", "Role", "Score Sheet", "|mid"]}
                rows={view.classes.map((c, i) => [i + 1, <b key="c">{c.course_code}</b>, c.title, c.units, c.department ?? "—", c.programmes ?? "—", c.level, c.session, SEM(c.semester), ROLE_WORD[c.role] ?? c.role, stageWord(c.stage),
                  <Btn key="o" kind="ghost" onClick={() => onOpen(c.id)}>View</Btn>])} />
            ) : <p className="sub2 mt-2">No class allocated to {view.name} in {session}{allSemesters ? "" : `, ${SEM(semester)} semester`}.</p>}
          </>
        ) : <p className="sub2 mt-2">Find a lecturer by name, staff number, email or department.</p>}
      </PBody>
    </Panel>
  );
}

/* ── the history ── */

function History({ session, semester, dept, initialTicket, onOpen, scope }: { session: string; semester: number; dept: string; initialTicket: string; onOpen: (id: string) => void; scope: string }) {
  const [ticket, setTicket] = useState(initialTicket);
  const [ticketLive, setTicketLive] = useState(initialTicket);
  const [rows, setRows] = useState<HistoryRow[] | null>(null);
  useEffect(() => { const t = setTimeout(() => setTicketLive(ticket), 400); return () => clearTimeout(t); }, [ticket]);
  useEffect(() => {
    let live = true;
    const p = new URLSearchParams({ session, semester: String(semester), limit: "1000" });
    if (dept) p.set("dept", dept);
    if (ticketLive.trim()) p.set("ticket", ticketLive.trim());
    void call<HistoryRow[]>(`/history?${p.toString()}`).then((r) => { if (live) { if (r.ok) setRows(r.data); else notifyProblem(r.problem); } });
    return () => { live = false; };
  }, [session, semester, dept, ticketLive]);
  async function exportHistory() {
    if (!rows) return;
    downloadBlob(await brandedXlsx("Allocation history", ["When", "Course Code", "Department", "Action", "Role", "Lecturer", "Staff Number", "Previous Lecturer", "Reason", "Performed By", "Office", "Source", "Ticket"],
      rows.map((h) => [when(h.at), h.course_code, h.department ?? "", ACTION_WORD[h.action] ?? h.action, ROLE_WORD[h.role] ?? h.role, h.lecturer ?? "", h.lecturer_staff_number ?? "", h.previous_lecturer ?? "",
        h.reason ?? "", h.performed_by ?? "", h.actor_office ? roleLabel(h.actor_office) : "", SOURCE_WORD[h.source] ?? h.source, h.ticket ?? ""]),
      { sheetName: "History", serial: docSerial("ALLOCHIST"), meta: [["Session", session], ["Semester", `${SEM(semester)} semester`], ["Scope", scope]] }), `allocation-history-${session.replace("/", "-")}-sem${semester}.xlsx`);
  }
  return (
    <Panel title="Allocation history" right={rows?.length ? <Btn kind="ghost" onClick={() => void exportHistory()}>Export (Excel)</Btn> : undefined}>
      <PBody>
        <div className="grid grid--3"><Field id="al-h-ticket" label="Support ticket" hint="Only the acts made on this ticket"><input id="al-h-ticket" className="ctl" value={ticket} onChange={(e) => setTicket(e.target.value)} placeholder="TICK-2026-00145" /></Field></div>
        {rows === null ? <p className="sub2">Loading…</p> : rows.length === 0 ? <p className="sub2">No allocation recorded for these filters.</p> : (
          <HistoryTable rows={rows} showCourse onOpen={onOpen} pageSize={50} />
        )}
      </PBody>
    </Panel>
  );
}

/* ── what needs a look ── */

function Conflicts({ session, semester, dept, onOpen }: { session: string; semester: number; dept: string; onOpen: (id: string) => void }) {
  const [rows, setRows] = useState<Conflict[] | null>(null);
  useEffect(() => {
    let live = true;
    void call<Conflict[]>(`/conflicts?session=${encodeURIComponent(session)}&semester=${semester}`).then((r) => { if (live) { if (r.ok) setRows(r.data); else notifyProblem(r.problem); } });
    return () => { live = false; };
  }, [session, semester]);
  const shown = (rows ?? []).filter((c) => !dept || c.dept_code === dept);
  return (
    <Panel title="Allocation conflicts" right={rows ? `${shown.length} to look at` : undefined}>
      <PBody>
        {rows === null ? <p className="sub2">Loading…</p> : shown.length === 0 ? <p className="sub2">Nothing needs a look in {session}, {SEM(semester)} semester.</p> : (
          <DTable pageSize={50} cols={["S/N|num", "Course Code", "Course Title", "Department", "Conflict", "What", "|mid"]} texts={shown.map((c) => `${c.course_code} ${c.title} ${c.department ?? ""} ${c.words}`)}
            rows={shown.map((c, i) => [i + 1, <b key="c">{c.course_code}</b>, c.title, c.department ?? c.dept_code, <Pil key="k" kind={c.kind === "OVERLOAD" || c.kind === "TIMETABLE_CLASH" ? "warn" : "bad"}>{CONFLICT_WORD[c.kind] ?? c.kind}</Pil>, c.words,
              <Btn key="o" kind="ghost" onClick={() => onOpen(c.offering_id)}>View</Btn>])} />
        )}
      </PBody>
    </Panel>
  );
}
