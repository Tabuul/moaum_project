"use client";

/**
 * The CCE examinations and progression (V381). Exams: the CCE examination sessions the Directorate of ICT set for the CCE
 * session, and where each CCE class's score sheet stands on the one results chain — the same desks as every sheet, read here
 * for the Centre. Progression: each CCE student's entry, programme length, current level, expected completion, spillover and
 * graduation, from the one academic position the database keeps; six years passing graduates nobody.
 */
import { useEffect, useState } from "react";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { buildXlsx } from "@/lib/xlsx";
import { downloadBlob } from "@/lib/exportbrand";
import { ccall, day, semesterWord, type CceExamsView, type CceProgressionView } from "@/lib/cce";
import type { TabProps } from "./CceList";

const q = (s: string) => encodeURIComponent(s);

function useLoad<T>(url: string): T | null {
  const [data, setData] = useState<T | null>(null);
  useEffect(() => {
    let live = true;
    void ccall<T>(url).then((r) => { if (!live) return; if (r.ok) setData(r.data); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [url]);
  return data;
}

const KIND: Record<string, string> = { MAIN: "Main", RESIT: "Re-sit", SPECIAL: "Special" };
const STATE: Record<string, [string, "ok" | "info" | "grey"]> = { OPEN: ["Open", "ok"], DRAFT: ["Draft", "info"], CLOSED: ["Closed", "grey"] };

/* ── the CCE examinations ───────────────────────────────────────────────────────────────────────────────────────── */

export function CceExams({ session, pick }: TabProps) {
  const [semester, setSemester] = useState<number | null>(null);
  const v = useLoad<CceExamsView>(`/api/v1/cce/exams?session=${q(session)}${semester ? `&semester=${semester}` : ""}`);
  if (!v) return <Note kind="info" title="Reading the CCE examinations…">One moment.</Note>;
  const withSheet = v.sheets.filter((s) => s.sheet_id);
  const published = withSheet.filter((s) => s.stage === "PUBLISHED").length;
  const noLecturer = v.sheets.filter((s) => !s.lecturer).length;
  const p = v.policy;
  const exportXlsx = () => downloadBlob(buildXlsx(["Course", "Title", "Semester", "Department", "Lecturer", "Candidates", "Sitting", "Stage", "Desk", "Due", "Submitted", "Published"],
    v.sheets.map((s) => [s.course_code, s.title, s.semester, s.dept ?? "", s.lecturer ?? "", s.candidates, s.sitting ? KIND[s.sitting] ?? s.sitting : "", s.stage ?? "No sheet yet", s.desk ?? "",
      s.due_on ? day(s.due_on) : "", s.submitted_at ? day(s.submitted_at) : "", s.published_at ? day(s.published_at) : ""]), "CCE examinations"), `cce-examinations-${session.replace("/", "-")}.xlsx`);
  return (
    <>
      <PageHead title="CCE examinations" description={`${session}: the Centre's classes are examined in the CCE session, on the same results desks as every other class.`}
        actions={<span className="row row--inline row--tight">{pick}
          <select className="ctl" style={{ width: 170 }} aria-label="Semester" value={semester ?? ""} onChange={(e) => setSemester(e.target.value ? Number(e.target.value) : null)}>
            <option value="">Every semester</option><option value="1">First semester</option><option value="2">Second semester</option><option value="3">Third semester</option>
          </select></span>} />
      {!v.examSessions.length ? (
        <Note kind="info" title={`No CCE examination session for ${session} yet`}>
          The Directorate of ICT sets examination sessions on Portal Management; one marked <b>CCE (part-time)</b> examines the Centre&rsquo;s classes only. Until it exists and its score sheets are released, the Centre&rsquo;s classes have no sheets.
        </Note>
      ) : null}
      <Tiles cls="grid--4" items={[
        ["CCE CLASSES", v.sheets.filter((s, i, all) => all.findIndex((x) => x.offering_id === s.offering_id) === i).length, null, `${noLecturer} without a lecturer`],
        ["SCORE SHEETS", withSheet.length, null, "Released to the lecturers"],
        ["PUBLISHED", published, published ? "var(--green-ink)" : null, "Released on a Senate minute"],
        ["ATTENDANCE BAR", p?.bars_exams ? "On" : "Off", p?.bars_exams ? "var(--chrome)" : null, p?.bars_exams && p.min_percent != null ? `Below ${p.min_percent}% bars the paper` : "Nobody is barred for attendance"],
      ]} />
      <Panel title="CCE examination sessions" right={<LinkBtn kind="ghost" href="/examinations/sessions">All examination sessions</LinkBtn>}>
        {v.examSessions.length ? (
          <DTable cols={["Semester|mid", "Type|mid", "Examinations|mid", "Sheets due|mid", "Sheets|num", "State|mid", "Cards|mid"]} rows={v.examSessions.map((e) => {
            const [w, k] = STATE[e.state] ?? [e.state, "grey" as const];
            return [semesterWord(e.semester), KIND[e.kind] ?? e.kind, <span key="x" className="tnum">{day(e.exams_from)} – {day(e.exams_to)}</span>, day(e.sheets_due), e.sheets,
              <Pil key="s" kind={k}>{w}</Pil>, e.cards_released_at ? <Pil key="c" kind="ok">Released {day(e.cards_released_at)}</Pil> : <Pil key="c" kind="grey">Not released</Pil>];
          })} />
        ) : <PBody><div className="sub2">None in this selection.</div></PBody>}
      </Panel>
      {v.stages.length ? (
        <Panel title="Where the sheets are">
          <DTable cols={["Stage", "Desk", "Sheets|num"]} rows={v.stages.map((s) => [s.stage === "PUBLISHED" ? "Published" : s.stage.replace(/_/g, " ").toLowerCase().replace(/^./, (c) => c.toUpperCase()), s.desk, s.sheets])} />
        </Panel>
      ) : null}
      <Panel title="By class" right={<Btn kind="secondary" disabled={!v.sheets.length} onClick={exportXlsx}>Excel</Btn>}>
        {v.sheets.length ? (
          <DTable cols={["Course", "Lecturer", "Candidates|num", "Sitting|mid", "Stage", "Due|mid"]} texts={v.sheets.map((s) => `${s.course_code} ${s.title} ${s.lecturer ?? ""} ${s.dept ?? ""}`)}
            rows={v.sheets.map((s) => [
              <span key="c"><b className="tnum">{s.course_code}</b> {s.title}<div className="sub2">{semesterWord(s.semester).toLowerCase()}{s.dept ? ` · ${s.dept}` : ""}</div></span>,
              s.lecturer ?? <span key="l" className="ink-red">No lecturer</span>, s.candidates, s.sitting ? KIND[s.sitting] ?? s.sitting : "—",
              s.sheet_id ? <span key="s">{s.stage === "PUBLISHED" ? <Pil kind="ok">Published</Pil> : <Pil kind="info">With {s.desk}</Pil>}</span> : <span key="s" className="sub2">No sheet yet</span>,
              s.due_on ? day(s.due_on) : "—",
            ])} />
        ) : <PBody><div className="sub2">No CCE class in {session} yet.</div></PBody>}
      </Panel>
      <div className="sub2">The broadsheet and the Senate schedule read the Centre&rsquo;s students on their own: choose <b>CCE (part-time)</b> on those screens.</div>
    </>
  );
}

/* ── the CCE students' progression ──────────────────────────────────────────────────────────────────────────────── */

const SPILL: Record<string, [string, "ok" | "info" | "bad" | "warn" | "grey"]> = {
  NORMAL: ["Within the programme length", "ok"], SPILLOVER_YEAR_1: ["Spillover, year 1", "warn"], SPILLOVER_YEAR_2: ["Spillover, year 2", "warn"],
  SPILLOVER_YEAR_3: ["Spillover, year 3", "bad"], SPILLOVER_LIMIT_REACHED: ["Spillover limit reached", "bad"], NOT_APPLICABLE: ["Not applicable", "grey"],
};

export function CceProgression({ pick }: TabProps) {
  const [f, setF] = useState({ programme: "", state: "", q: "" });
  const [typed, setTyped] = useState("");
  const qs = [f.programme ? `programme=${q(f.programme)}` : "", f.state ? `state=${f.state}` : "", f.q ? `q=${q(f.q)}` : ""].filter(Boolean).join("&");
  const v = useLoad<CceProgressionView>(`/api/v1/cce/progression${qs ? `?${qs}` : ""}`);
  if (!v) return <Note kind="info" title="Reading the CCE students' progression…">One moment.</Note>;
  const c = v.counts;
  const exportXlsx = () => downloadBlob(buildXlsx(["Number", "Surname", "Other names", "Programme", "Entry session", "Current session", "Level", "Final level", "Length (years)",
    "Expected completion", "Deferred sessions", "Spillover years", "Standing", "Registered now", "Graduation"],
    v.rows.map((r) => [r.matric_no ?? "", r.surname, r.other_names, r.programme ?? r.programme_code, r.entry_session ?? "", r.current_session ?? "", r.current_level ?? "", r.final_level ?? "",
      r.duration_years ?? "", r.expected_completion ?? "", r.deferred_sessions, r.spillover_years, (SPILL[r.spillover_state] ?? [r.spillover_state])[0], r.registered_current ? "Yes" : "No",
      r.graduation_state ?? ""]), "CCE progression"), `cce-progression-${v.session.replace("/", "-")}.xlsx`);
  return (
    <>
      <PageHead title="CCE progression" description={`The CCE session is ${v.session}: each student's place is counted on the CCE programme length, never the full-time one.`} actions={pick} />
      <Note kind="info" title="Six years passing graduates nobody">
        Expected completion is the entry session plus the programme&rsquo;s CCE length, moved on by any approved deferment. A student past it is in spillover until the results chain and the Senate graduate them; the count is the database&rsquo;s, recomputed whenever a registration, a result or a deferment changes.
      </Note>
      <Tiles cls="grid--5" items={[
        ["CCE STUDENTS", c.students ?? 0, null, `${c.registered ?? 0} registered in ${v.session}`],
        ["FINAL SESSION", c.final_session ?? 0, null, "Expected to complete this session"],
        ["IN SPILLOVER", c.spillover ?? 0, (c.spillover ?? 0) ? "var(--amber-ink)" : null, "Past the programme length"],
        ["LIMIT REACHED", c.limit_reached ?? 0, (c.limit_reached ?? 0) ? "var(--red-ink)" : null, "Spillover limit reached"],
        ["TO REVIEW", c.review ?? 0, (c.review ?? 0) ? "var(--chrome)" : null, "The record does not settle the place"],
      ]} />
      <Panel title="Filter">
        <PBody>
          <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
            <Field id="pg-p" label="Programme"><select id="pg-p" className="ctl" value={f.programme} onChange={(e) => setF({ ...f, programme: e.target.value })}><option value="">Every CCE programme</option>{v.programmes.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field>
            <Field id="pg-s" label="Standing"><select id="pg-s" className="ctl" value={f.state} onChange={(e) => setF({ ...f, state: e.target.value })}>
              <option value="">Every standing</option><option value="NORMAL">Within the programme length</option><option value="SPILLOVER">In spillover</option><option value="SPILLOVER_LIMIT_REACHED">Spillover limit reached</option>
            </select></Field>
            <Field id="pg-q" label="Number or surname"><input id="pg-q" className="ctl" value={typed} onChange={(e) => setTyped(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") setF({ ...f, q: typed.trim() }); }} /></Field>
            <Btn kind="ghost" onClick={() => setF({ ...f, q: typed.trim() })}>Search</Btn>
          </div>
        </PBody>
      </Panel>
      <Panel title={`${v.rows.length} student${v.rows.length === 1 ? "" : "s"}`} right={<Btn kind="secondary" disabled={!v.rows.length} onClick={exportXlsx}>Excel</Btn>}>
        {v.rows.length ? (
          <DTable cols={["Student", "Entry|mid", "Now|mid", "Length|num", "Expected completion|mid", "Standing", "Registered|mid"]} texts={v.rows.map((r) => `${r.surname} ${r.other_names} ${r.matric_no ?? ""} ${r.programme ?? ""}`)}
            rows={v.rows.map((r) => {
              const [w, k] = SPILL[r.spillover_state] ?? [r.spillover_state, "grey" as const];
              return [
                <span key="n">{r.surname}, {r.other_names}<div className="sub2 tnum">{r.matric_no ?? "Not yet matriculated"} · {r.programme ?? r.programme_code}</div></span>,
                <span key="e" className="tnum">{r.entry_session ?? "—"}<div className="sub2">{r.entry_level ? `${r.entry_level} level` : ""}</div></span>,
                <span key="c" className="tnum">{r.current_session ?? "—"}<div className="sub2">{r.current_level ? `${r.current_level} level` : ""}</div></span>,
                r.duration_years ? `${r.duration_years} yrs` : "—",
                <span key="x" className="tnum">{r.expected_completion ?? "—"}{r.deferred_sessions ? <div className="sub2">{r.deferred_sessions} deferred</div> : null}</span>,
                <span key="s"><Pil kind={k}>{w}</Pil>{r.graduation_state ? <div className="sub2">{r.graduation_state.replace(/_/g, " ").toLowerCase()}</div> : null}</span>,
                r.registered_current ? <Pil key="r" kind="ok">Yes</Pil> : <Pil key="r" kind="grey">No</Pil>,
              ];
            })} />
        ) : <PBody><div className="sub2">No CCE student in this selection.</div></PBody>}
      </Panel>
    </>
  );
}
