"use client";
/** Programme structure: what a programme offers at each level and semester (catalogue.course_offer), the
 *  units each semester carries against the level's limits, and — for the programme's own department —
 *  the binding of a course into the structure and its removal. Registration reads these rows, so a
 *  course missing here is a course no student of the programme sees. V460: each binding may carry the programme's own units
 *  (one programme takes a course at 2, another at 3); registration, course forms and results follow them. V465: a change of
 *  units is counted before it is saved, and the examined classes it leaves as they are are listed with their sheets.
 *  V471: a postgraduate programme's structure is worked here too — at 700, 800 or 900 level, a course taken as Core,
 *  Elective, Borrowed, Deficiency or Research — by the School of Postgraduate Studies and, within their postings, the ICT
 *  Support Desk, who may name the ticket a change answers; a course the pool does not hold yet is created here, once an
 *  existing course of that code or title has been ruled out. V483: a postgraduate programme's specialisations, the students who
 *  read them, and for each bound course the specialisations it is for (none: every student). */
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";
import { UnitsChangeModal, type UnitsTarget } from "../UnitsChange";
import { ForSpecialisations, Specialisations, type SpecData } from "./Specialisations";

export interface ProgrammeOption { code: string; name: string; dept_code: string | null; department_name: string | null; faculty_name: string; archived: boolean; category?: string | null }
export interface StructureRow { level: number; semester: number | null; both_semesters?: boolean; code: string; title: string; units: number; own_units?: number | null; course_units?: number; kind: string; state: string; dept_code: string; dept_name: string | null; basis: string; track: string | null; ca_max: number; offered_now?: boolean;
  /** V483: the specialisations the binding is for (codes, and ids comma-separated); none is every student */
  specialisations?: string | null; specialisation_ids?: string | null }
export interface StructureData {
  programme: { code: string; name: string; dept_code: string | null; dept_name: string | null; faculty_code: string; faculty_name?: string | null; category?: string | null; pg_award?: string | null; award_level?: number | null };
  rows: StructureRow[];
  limits: { level: number; min_units: number; max_units: number }[];
  tracks: { code: string; name: string }[];
  /** V471: the levels and bases this programme takes, the session its students register in now, and what the acting office may do */
  levels?: number[];
  bases?: string[];
  session?: string;
  may?: { change: boolean; ticket: boolean };
}
interface Found { code: string; title: string; units: number; semester: number | null; both_semesters?: boolean; level: number; kind: string; dept_code: string; dept_name: string | null }
interface Existing { byCode: (Found & { faculty_name?: string | null; state: string; programmes: number }) | null; byTitle: (Found & { faculty_name?: string | null; state: string; programmes: number })[] }

const UG_BASES = ["Core", "Elective", "Borrowed", "GST"];
const UG_LEVELS = [100, 200, 300, 400, 500, 600];
const semName = (n: number | null) => (n === 1 ? "First semester" : n === 2 ? "Second semester" : n === 3 ? "Third semester" : "Semester not set");
const PG_AWARD_LEVEL: Record<number, string> = { 700: "postgraduate diploma", 800: "masters", 900: "doctorate" };

export function Structure({ programmes, prog, data, problem, may, canCreate = false, ticketRef = "", pgOffice = false }: {
  programmes: ProgrammeOption[]; prog: string; data: StructureData | null; problem: Problem | null; may: boolean;
  /** V471: the acting office is the School of Postgraduate Studies' (it keeps the postgraduate programmes only) */
  pgOffice?: boolean;
  /** V471: the acting office may create a course for this programme (the School, an agent with EDIT_COURSES) */
  canCreate?: boolean;
  /** V471: the ticket the support desk opened this screen from */
  ticketRef?: string;
}) {
  const router = useRouter();
  const go = useQueryNav();
  const [track, setTrack] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  // the picker: a course anywhere in the University, by code or title
  const [q, setQ] = useState("");
  const [found, setFound] = useState<Found[]>([]);
  const [pick, setPick] = useState<Found | null>(null);
  const [f, setF] = useState({ level: "", basis: "", track: "", units: "" });
  const [unitsEdit, setUnitsEdit] = useState<UnitsTarget | null>(null);
  const [ticket, setTicket] = useState(ticketRef);
  // V471: a new course, created only once the pool is seen not to hold it
  const [creating, setCreating] = useState(false);
  const [nc, setNc] = useState({ code: "", title: "", units: "3", semester: "1", level: "", basis: "" });
  const [existing, setExisting] = useState<Existing | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  // V483: a postgraduate programme's specialisations, and the binding whose specialisations are being chosen
  const [spec, setSpec] = useState<SpecData | null>(null);
  const [forRow, setForRow] = useState<StructureRow | null>(null);

  const LV = data?.levels?.length ? data.levels : UG_LEVELS;
  const BS = data?.bases?.length ? data.bases : UG_BASES;
  const pgp = data?.programme.category === "POST GRADUATE";
  const mayChange = may && (data?.may?.change ?? true);
  const mayTicket = !!data?.may?.ticket;
  const defaultLevel = String(pgp && data?.programme.award_level && LV.includes(data.programme.award_level) ? data.programme.award_level : LV[0]);
  // a level or basis chosen for another programme does not carry over to this one
  const level = LV.includes(Number(f.level)) ? f.level : defaultLevel;
  const basis = BS.includes(f.basis) ? f.basis : BS[0];
  const ncLevel = LV.includes(Number(nc.level)) ? nc.level : defaultLevel;
  const ncBasis = BS.includes(nc.basis) ? nc.basis : BS[0];
  const progCode = data?.programme.code ?? "";
  const [specTick, setSpecTick] = useState(0);
  useEffect(() => {
    if (!pgp || !progCode) return;
    let live = true;
    void fetch(`/api/bff/api/v1/catalogue/structure/specialisations?prog=${encodeURIComponent(progCode)}`, { cache: "no-store" }).then(async (r) => {
      const j = r.ok ? ((await r.json().catch(() => null)) as SpecData | null) : null;
      if (live) setSpec(j);
    });
    return () => { live = false; };
  }, [pgp, progCode, specTick, data]);
  const loadSpec = () => setSpecTick((n) => n + 1);
  // the specialisations of the programme in view (a list fetched for another programme is not shown)
  const specNow = pgp && spec?.programme.code === progCode ? spec : null;
  const hasSpec = !!specNow?.specialisations.length;

  const rows = data ? data.rows.filter((r) => !track || !r.track || r.track === track) : [];
  const levels = [...new Set(rows.map((r) => Number(r.level)))].sort((a, b) => a - b);
  const limitOf = (lv: number) => data?.limits.find((l) => Number(l.level) === lv);
  const ownDept = data?.programme.dept_code ?? null;

  /** the ticket on the request and in the reason, so the change is on the ticket's timeline and in the course's history */
  const withTicket = (path: string) => (mayTicket && ticket.trim() ? `${path}${path.includes("?") ? "&" : "?"}ticket=${encodeURIComponent(ticket.trim())}` : path);
  const why = (text: string) => (mayTicket && ticket.trim() ? `Ticket ${ticket.trim().toUpperCase()}: ${text}` : text);

  function search(text: string) {
    setQ(text);
    setPick(null);
    if (timer.current) clearTimeout(timer.current);
    if (text.trim().length < 2) { setFound([]); return; }
    timer.current = setTimeout(() => {
      void fetch(`/api/bff/api/v1/catalogue/courses/search?q=${encodeURIComponent(text.trim())}`).then(async (r) => {
        if (!r.ok) return;
        const j = (await r.json().catch(() => [])) as Found[];
        setFound(Array.isArray(j) ? j : []);
      });
    }, 250);
  }

  async function call(method: "POST" | "DELETE", path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue${withTicket(path)}`, {
        method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why(reason)) }, body: method === "DELETE" ? undefined : JSON.stringify(body),
      });
      if (!r.ok) { { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setErr(p); notifyProblem(p); } return false; }
      notify(reason);
      router.refresh();
      return true;
    } finally {
      setBusy(false);
    }
  }

  function choose(c: Found) {
    const lv = LV.includes(c.level) ? String(c.level) : level;
    const b = c.kind === "GST" && BS.includes("GST") ? "GST" : ownDept && c.dept_code !== ownDept ? "Borrowed" : c.kind === "Elective" ? "Elective" : "Core";
    setPick(c);
    setF({ ...f, level: lv, basis: b });
  }

  async function bind() {
    if (!pick || !data) return;
    const units = f.units.trim() ? Number(f.units) : null;
    const ok = await call("POST", "/structure/bind", { programme: data.programme.code, course: pick.code, level: Number(level), basis, track: f.track || null, units },
      `${pick.code} bound into ${data.programme.code} at ${level} level as ${basis}${f.track ? ` (${f.track})` : ""}${units != null ? ` at ${units} units` : ""}`);
    if (ok) { setPick(null); setQ(""); setFound([]); setF({ ...f, units: "" }); }
  }

  /** V471: before a course is created, the pool is asked for the code and the title; one found is bound instead */
  async function checkExisting(): Promise<Existing | null> {
    const qs = new URLSearchParams({ code: nc.code.trim(), title: nc.title.trim(), level: ncLevel, semester: nc.semester });
    const r = await fetch(`/api/bff/api/v1/catalogue/courses/exists?${qs.toString()}`, { cache: "no-store" });
    const j = (await r.json().catch(() => null)) as Existing | null;
    if (!r.ok || !j) { notifyProblem((j as unknown as Problem) ?? { status: r.status, title: r.statusText }); return null; }
    setExisting(j);
    return j;
  }

  async function create() {
    if (!data || !nc.code.trim() || !nc.title.trim()) return;
    const ex = await checkExisting();
    if (!ex || ex.byCode || ex.byTitle.length) return;   // shown; the user binds the existing course or changes the new one
    const ok = await call("POST", "/courses", {
      code: nc.code.trim(), title: nc.title.trim(), units: Number(nc.units) || 0, semester: Number(nc.semester) || 1, level: Number(ncLevel),
      dept: data.programme.dept_code, kind: ncBasis === "Elective" ? "Elective" : "Core",
      offers: [{ programme: data.programme.code, level: Number(ncLevel), basis: ncBasis }],
    }, `${nc.code.trim().toUpperCase()} created and bound into ${data.programme.code} at ${ncLevel} level as ${ncBasis}`);
    if (ok) { setCreating(false); setExisting(null); setNc({ code: "", title: "", units: "3", semester: "1", level: "", basis: "" }); }
  }

  /** V460, V465: the units this programme takes a bound course at — counted before it is saved; the course's own number takes
   *  the course's units again */
  function changeUnits(r: StructureRow) {
    if (!data) return;
    setUnitsEdit({ course: r.code, courseUnits: r.course_units ?? r.units, programme: data.programme.code, programmeName: data.programme.name, level: r.level, units: r.units });
  }

  function unbind(r: StructureRow) {
    if (!data) return;
    if (!window.confirm(`Remove ${r.code} from ${data.programme.code} at ${r.level} level? Students of the programme at that level will no longer see it at registration. The course itself stays in the University's course list, and every registration and result that carries it stays as it is.`)) return;
    void call("DELETE", `/structure/bind?programme=${encodeURIComponent(data.programme.code)}&course=${encodeURIComponent(r.code)}&level=${r.level}`, null,
      `${r.code} removed from ${data.programme.code} at ${r.level} level`);
  }

  const total = rows.length;
  const borrowed = rows.filter((r) => ownDept && r.dept_code !== ownDept).length;
  const unplaced = rows.filter((r) => r.semester == null).length;
  const noClass = rows.filter((r) => r.offered_now === false && r.state !== "ENDED").length;
  const ended = rows.filter((r) => r.state === "ENDED").length;
  const programmeLink = (p: string) => `/catalogue/structure?prog=${encodeURIComponent(p)}${mayTicket && ticket.trim() ? `&ticket=${encodeURIComponent(ticket.trim())}` : ""}`;
  const existingRows = existing ? [...(existing.byCode ? [existing.byCode] : []), ...existing.byTitle.filter((t) => t.code !== existing.byCode?.code)] : [];

  return (
    <>
      <div className="scope">
        <div className="scope__f" style={{ flex: "2 1 320px" }}><label htmlFor="st-prog">Programme</label>
          <SearchSelect id="st-prog" value={prog} placeholder="Search a programme…" options={programmes.map((p) => ({ value: p.code, label: `${p.name} · ${p.code}${p.department_name ? ` · ${p.department_name}` : ""}${p.category === "POST GRADUATE" ? " · Postgraduate" : ""}` }))}
            onChange={(v: string) => go(programmeLink(v))} /></div>
        <div className="scope__f"><label htmlFor="st-track">Track</label>
          <select id="st-track" className="ws__select" value={track} onChange={(e) => setTrack(e.target.value)}>
            <option value="">Every track</option>
            {(data?.tracks ?? []).map((t) => <option key={t.code} value={t.code}>{t.code} — {t.name}</option>)}
          </select></div>
        {mayTicket ? (
          <div className="scope__f"><label htmlFor="st-ticket">Support ticket (optional)</label>
            <input id="st-ticket" className="ctl tnum" style={{ width: 190 }} value={ticket} onChange={(e) => setTicket(e.target.value)} placeholder="ICT-2026-001245" autoComplete="off" maxLength={40} /></div>
        ) : null}
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      {!data ? (
        <Note kind="info" title="Choose a programme" />
      ) : (
        <>
          <Tiles items={[
            ["Courses bound", String(total), null, `${data.programme.name}`],
            ["Programme type", pgp ? "Postgraduate" : "Undergraduate", null, pgp ? `${data.programme.pg_award ?? "Award not stated"} · courses at ${LV.join(", ")} level` : `Courses at ${LV[0]} to ${LV[LV.length - 1]} level`],
            ["Levels", String(levels.length), null, levels.length ? levels.join(", ") + " level" : "Nothing bound yet"],
            ["Borrowed", String(borrowed), borrowed ? "var(--chrome)" : null, "Owned by another department"],
            ["Without a semester", String(unplaced), unplaced ? "var(--red-ink)" : null, unplaced ? "Fix the course's semester on its department's desk" : "Every course says which semester"],
            ["No class this session", String(noClass), noClass ? "var(--amber-ink)" : null, data.session ? `No class of the course in ${data.session} yet` : "No current session"],
            ["Ended but bound", String(ended), ended ? "var(--red-ink)" : null, ended ? "Ended courses are not registered" : "Every bound course is live"],
            ["Faculty", data.programme.faculty_name ?? data.programme.faculty_code ?? "—", null, data.programme.dept_name ?? ""],
          ]} />
          <Note kind="info" title="Registration reads this structure">
            A course missing here cannot be registered by students of {data.programme.code}. A course bound here is on their registration menu once it has a class in the session{data.session ? ` (${data.session})` : ""}{pgp ? ", opened by the School on Classes & course upload" : ""}. <Link className="lnk" href="/catalogue/structure/checks">Structure checks</Link>
          </Note>
          {mayChange ? (
            <Panel title="Bind a course into the structure" right={`${data.programme.name} · ${data.programme.dept_name ?? ""}`}>
              <PBody>
                <div className="row row--end">
                  <div className="field" style={{ flex: "2 1 280px", position: "relative" }}><label htmlFor="st-find">Course — any department, by code or title</label>
                    <input id="st-find" className="ctl" value={pick ? `${pick.code} — ${pick.title}` : q} onChange={(e) => search(e.target.value)} placeholder={pgp ? "e.g. CSC 801, or Research Methodology" : "e.g. GST 111, or Use of English"} autoComplete="off" />
                    {found.length && !pick ? (
                      <div style={{ position: "absolute", zIndex: 5, left: 0, right: 0, top: "100%", background: "var(--bg)", border: "1px solid var(--line)", borderRadius: "var(--r-md)", maxHeight: 260, overflowY: "auto", boxShadow: "var(--sh-3)" }}>
                        {found.map((c) => (
                          <button key={c.code} type="button" style={{ display: "block", width: "100%", textAlign: "left", padding: "var(--s-2) var(--s-3)", border: 0, background: "transparent", cursor: "pointer" }}
                            onClick={() => choose(c)}>
                            <strong className="tnum">{c.code}</strong> <span>{c.title}</span> <span className="sub2">· {c.units} units · {c.level} level · {c.both_semesters ? "First and second semesters" : semName(c.semester)} · {c.dept_name ?? c.dept_code}</span>
                          </button>
                        ))}
                      </div>
                    ) : null}
                    {q.trim().length >= 2 && !found.length && !pick ? <div className="sub2 mt-1">No course of the University has that code or title{canCreate ? " — create it below" : ""}.</div> : null}
                  </div>
                  <Field id="st-level" label="Level">
                    <select id="st-level" className="ctl" style={{ width: 110 }} value={level} onChange={(e) => setF({ ...f, level: e.target.value })}>{LV.map((l) => <option key={l} value={String(l)}>{l}</option>)}</select></Field>
                  <Field id="st-basis" label="Basis">
                    <select id="st-basis" className="ctl" style={{ width: 130 }} value={basis} onChange={(e) => setF({ ...f, basis: e.target.value })}>{BS.map((b) => <option key={b} value={b}>{b}</option>)}</select></Field>
                  <Field id="st-units" label="Units" hint={pick ? `Blank: the course's ${pick.units}` : "Blank: the course's own"}>
                    <input id="st-units" className="ctl tnum" style={{ width: 90 }} inputMode="numeric" value={f.units} placeholder={pick ? String(pick.units) : ""}
                      onChange={(e) => setF({ ...f, units: e.target.value.replace(/[^0-9]/g, "").slice(0, 2) })} /></Field>
                  <Field id="st-btrack" label="Track">
                    <select id="st-btrack" className="ctl" style={{ width: 170 }} value={f.track} onChange={(e) => setF({ ...f, track: e.target.value })}>
                      <option value="">Every track</option>
                      {data.tracks.map((t) => <option key={t.code} value={t.code}>{t.code}</option>)}
                    </select></Field>
                  <Btn kind="primary" disabled={busy || !pick} onClick={() => bind()}>Bind the course</Btn>
                </div>
                <div className="sub2 mt-2">
                  Basis: <b>Core</b> the programme requires it; <b>Elective</b> the student chooses it and a failure is not carried; <b>Borrowed</b> another department owns it;{" "}
                  {pgp ? <><b>Deficiency</b> a course a candidate makes up, earning no credit; <b>Research</b> the project, thesis or dissertation.</> : <><b>GST</b> a University requirement.</>}{" "}
                  <b>Units</b>: what this programme takes the course at, where it differs from the course&rsquo;s own &mdash; another programme keeps its own. A binding for a track is seen by that track&rsquo;s students only.
                  {pgp ? <> Levels: {LV.map((l) => `${l} ${PG_AWARD_LEVEL[l] ?? ""}`.trim()).join(", ")}.</> : null}
                </div>
                {canCreate ? (
                  <div className="mt-3">
                    {!creating ? <Btn kind="ghost" size="sm" onClick={() => { setCreating(true); setExisting(null); }}>+ New course for this programme</Btn> : (
                      <div className="stack">
                        <div className="eyebrow">A course the University does not hold yet — one record, bound here at once</div>
                        <div className="row row--end">
                          <Field id="nc-code" label="Code" hint="Three letters and three digits"><input id="nc-code" className="ctl tnum" style={{ width: 120 }} value={nc.code} maxLength={20} onChange={(e) => { setNc({ ...nc, code: e.target.value.toUpperCase() }); setExisting(null); }} placeholder={pgp ? "CSC 801" : "CSC 101"} /></Field>
                          <Field id="nc-title" label="Title" style={{ flex: "2 1 240px" }}><input id="nc-title" className="ctl" value={nc.title} maxLength={120} onChange={(e) => { setNc({ ...nc, title: e.target.value }); setExisting(null); }} /></Field>
                          <Field id="nc-units" label="Units"><input id="nc-units" className="ctl tnum" style={{ width: 70 }} inputMode="numeric" value={nc.units} onChange={(e) => setNc({ ...nc, units: e.target.value.replace(/[^0-9]/g, "").slice(0, 2) })} /></Field>
                          <Field id="nc-sem" label="Semester"><select id="nc-sem" className="ctl" value={nc.semester} onChange={(e) => setNc({ ...nc, semester: e.target.value })}><option value="1">First</option><option value="2">Second</option><option value="3">Third</option></select></Field>
                          <Field id="nc-level" label="Level"><select id="nc-level" className="ctl" style={{ width: 100 }} value={ncLevel} onChange={(e) => setNc({ ...nc, level: e.target.value })}>{LV.map((l) => <option key={l} value={String(l)}>{l}</option>)}</select></Field>
                          <Field id="nc-basis" label="Basis"><select id="nc-basis" className="ctl" style={{ width: 120 }} value={ncBasis} onChange={(e) => setNc({ ...nc, basis: e.target.value })}>{BS.map((b) => <option key={b} value={b}>{b}</option>)}</select></Field>
                        </div>
                        {existingRows.length ? (
                          <Note kind="bad" title="Existing course found">
                            The University already holds {existingRows.length === 1 ? "this course" : "courses like this"}; bind {existingRows.length === 1 ? "it" : "the right one"} instead of creating a second record.
                            <div className="stack mt-2">
                              {existingRows.map((e) => (
                                <div key={e.code} className="row row--inline row--tight">
                                  <b className="tnum">{e.code}</b> {e.title} <span className="sub2">· {e.units} units · {e.level} level · {e.dept_name ?? e.dept_code}{e.state === "ENDED" ? " · ended" : ""}</span>
                                  {e.state !== "ENDED" ? <Btn kind="secondary" size="sm" onClick={() => { choose(e); setCreating(false); setExisting(null); }}>Use this course</Btn> : null}
                                </div>
                              ))}
                            </div>
                          </Note>
                        ) : existing ? <div className="sub2">No course of the University has this code or title.</div> : null}
                        <div className="row row--tight">
                          <Btn kind="primary" disabled={busy || !nc.code.trim() || !nc.title.trim() || existingRows.length > 0} onClick={() => create()}>Create and bind</Btn>
                          <Btn kind="ghost" onClick={() => { setCreating(false); setExisting(null); }}>Cancel</Btn>
                          <span className="sub2">Owned by {data.programme.dept_name ?? "the programme's department"}; it is live at once and on the registration menu once its class is opened.</span>
                        </div>
                      </div>
                    )}
                  </div>
                ) : null}
              </PBody>
            </Panel>
          ) : data.may && !data.may.change ? (
            <Note kind="info" title="You may read this structure">
              {pgOffice ? "The School of Postgraduate Studies keeps the postgraduate programmes' structures; an undergraduate programme's is its department's."
                : "Your support posting does not carry binding courses for this programme's faculty or department; the Head of the ICT Support Desk grants it with a posting."}
            </Note>
          ) : null}
          {specNow ? <Specialisations data={specNow} ticket={mayTicket ? ticket : ""} onChanged={() => { loadSpec(); router.refresh(); }} /> : null}
          {levels.length === 0 ? (
            <Note kind="bad" title="Nothing is bound to this programme">No student of {data.programme.code} sees any course at registration.</Note>
          ) : levels.map((lv) => {
            const lim = limitOf(lv);
            const sems = [1, 2, 3, null].filter((s) => rows.some((r) => r.level === lv && (r.semester ?? null) === s));
            return (
              <Panel key={lv} title={`${lv} Level${pgp && PG_AWARD_LEVEL[lv] ? ` · ${PG_AWARD_LEVEL[lv]}` : ""}`} right={lim ? `Limits ${lim.min_units}–${lim.max_units} units a semester` : "No unit limit set for this level"}>
                {sems.map((s) => {
                  const list = rows.filter((r) => r.level === lv && (r.semester ?? null) === s);
                  const units = list.reduce((n, r) => n + Number(r.units), 0);
                  const coreUnits = list.filter((r) => r.basis === "Core" || r.basis === "GST").reduce((n, r) => n + Number(r.units), 0);
                  const over = lim && coreUnits > lim.max_units;
                  const under = lim && units < lim.min_units;
                  return (
                    <div key={String(s)} style={{ padding: "0 0 var(--s-2)" }}>
                      <div className="row row--between row--base" style={{ padding: "var(--s-3) var(--s-4) var(--s-1)" }}>
                        <strong>{semName(s)}</strong>
                        <span className={`sub2 tnum${over || under ? " ink-red b600" : ""}`}>
                          {units} units bound · {coreUnits} core/GST{lim ? over ? ` — core alone exceeds the ${lim.max_units}-unit maximum` : under ? ` — under the ${lim.min_units}-unit minimum even with every course` : "" : ""}
                        </span>
                      </div>
                      <DTable cols={["Code|mid", "Title", "Units|mid", "Basis|mid", "Track|mid", ...(hasSpec ? ["For|mid"] : []), "Owner", "State|mid", "This session|mid", ...(mayChange ? ["|num"] : [])]} rows={list.map((r) => [
                        <Link className="lnk" key="c" href={`/catalogue/course?code=${encodeURIComponent(r.code)}`}><strong className="tnum">{r.code}</strong></Link>,
                        <span key="t">{r.title}{r.both_semesters ? <span className="sub2"> · both semesters</span> : null}</span>,
                        <span key="u"><span className="tnum">{r.units}</span>{r.own_units != null && r.course_units != null && r.own_units !== r.course_units ? <span className="sub2"> · this programme (course {r.course_units})</span> : null}</span>,
                        <Pil key="b" kind={r.basis === "Core" ? "info" : r.basis === "GST" || r.basis === "Research" ? "ok" : r.basis === "Deficiency" ? "warn" : "grey"}>{r.basis}</Pil>,
                        <span className="sub2 tnum" key="tr">{r.track ?? "every track"}</span>,
                        ...(hasSpec ? [r.specialisations ? <span key="sp" className="tnum b600">{r.specialisations}</span> : <span key="sp" className="sub2">every student</span>] : []),
                        <span className={`sub2${ownDept && r.dept_code !== ownDept ? " ink-chrome" : ""}`} key="o">{r.dept_name ?? r.dept_code}</span>,
                        <Pil key="s" kind={r.state === "LIVE" ? "ok" : r.state === "ENDED" ? "bad" : "warn"}>{r.state === "LIVE" ? "Live" : r.state === "BOARD" || r.state === "SENATE" ? "Not yet live" : r.state === "ENDED" ? "Ended" : r.state}</Pil>,
                        r.offered_now == null ? <span key="n" /> : r.offered_now ? <Pil key="n" kind="ok">Class open</Pil> : <span key="n" className="sub2 ink-amber">No class yet</span>,
                        ...(mayChange ? [<span key="x" className="row row--tight row--right">{hasSpec ? <Btn kind="ghost" disabled={busy} onClick={() => setForRow(r)}>For</Btn> : null}<Btn kind="ghost" disabled={busy} onClick={() => changeUnits(r)}>Units</Btn><Btn kind="ghost" disabled={busy} onClick={() => unbind(r)}>Remove</Btn></span>] : []),
                      ])} texts={list.map((r) => `${r.code} ${r.title} ${r.basis} ${r.track ?? ""} ${r.specialisations ?? ""} ${r.dept_name ?? ""}`)} />
                    </div>
                  );
                })}
              </Panel>
            );
          })}
        </>
      )}
      {forRow && specNow ? (
        <ForSpecialisations data={specNow} course={forRow.code} level={forRow.level} chosen={(forRow.specialisation_ids ?? "").split(",").filter(Boolean)} ticket={mayTicket ? ticket : ""}
          onClose={() => setForRow(null)} onSaved={() => { setForRow(null); loadSpec(); router.refresh(); }} />
      ) : null}
      {unitsEdit ? <UnitsChangeModal target={unitsEdit} ticket={mayTicket ? ticket.trim() : ""} onClose={() => setUnitsEdit(null)} onSaved={() => { setUnitsEdit(null); router.refresh(); }} /> : null}
    </>
  );
}
