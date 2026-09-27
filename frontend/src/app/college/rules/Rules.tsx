"use client";
/** The College's rules (V285): the regulations as the tables hold them — each Professional examination's attendance, resit and
 *  appeal rule; each subject's pass mark, weights and clinical minimum, with the attendance it effectively needs; the attendance
 *  rules by phase and by block; the programme rule (distinction, minimum years, carry-over, resit window); the assessment items
 *  that gate a candidate's sitting — read by every officer, set by the Provost's desk on the audit spine. Below them the two acts
 *  the rules call for: the Board's act on the 100 Level rule for a session's entrants, and the carry-overs a decision left owing. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface ExamRule { id: string; code: string; name: string; level: number; papers: string[]; resit_allowed: boolean; resit_window_months: number; no_resit_if_all_failed: boolean; appeal_to_senate: boolean; min_attendance_pct: number | null; on_failure: string; ordinal: number }
export interface SubjectRule { id: string; exam: string; level: number; name: string; departments: string | null; ca_weight: number; exam_weight: number; pass_mark: number; clinical_component_min: number | null; ordinal: number; min_attendance: number | null }
export interface AttendanceRule { id: string; scope: string; phase: string | null; block_id: string | null; block_code: string | null; block: string | null; min_pct: number; applies_to: string; note: string | null }
export interface ProgrammeRule { programme_code: string; programme: string; degree: string; min_years_utme: number; min_years_de: number; min_total_cu: number; classified: boolean; distinction_mark: number; resit_window_months: number; carry_over_note: string | null; honours_rule: string | null }
export interface GateItem { id: string; name: string; item_type: string; weight_within_ca: number; max_score: number; eligibility_gate: boolean; subject: string; exam: string }
export interface RulesData { exams: ExamRule[]; subjects: SubjectRule[]; attendance: AttendanceRule[]; programme: ProgrammeRule[]; gates: GateItem[] }
export interface Level100 { session: string; rows: { id: string; surname: string; other_names: string; number: string; status: string; current_level: number; outcome: string | null; failed: string | null; carried: string | null; published: number; registered: number; minute: string | null }[]; promoted?: number; withdrawn?: number; waiting?: number }
export interface CarryOvers { rows: { student_id: string; code: string; from_session: string; note: string | null; cleared_on: string | null; surname: string; other_names: string; number: string; current_level: number; status: string }[] }

const OUT: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = { PROMOTE: ["Promote to 200 Level", "ok"], WITHDRAW_ADVISED: ["Advise withdrawal", "bad"], INCOMPLETE: ["Results not all published", "warn"] };
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

export function Rules({ data, sessions, session, level100, carry, mayEdit, mayAct }: { data: RulesData; sessions: string[]; session: string; level100: Level100; carry: CarryOvers; mayEdit: boolean; mayAct: boolean }) {
  const router = useRouter();
  const go = useQueryNav();
  const [d, setD] = useState<RulesData>(data);
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [edits, setEdits] = useState<Record<string, string>>({});
  const [minute, setMinute] = useState("");
  const [clearing, setClearing] = useState<CarryOvers["rows"][number] | null>(null);
  const [clearMinute, setClearMinute] = useState("");
  const [carryQ, setCarryQ] = useState("");
  const [carryRows, setCarryRows] = useState(carry.rows);
  const [l100, setL100] = useState<Level100>(level100);
  const v = (key: string, current: unknown) => (key in edits ? edits[key] : current == null ? "" : String(current));
  const num = (s: string) => (s.trim() === "" ? null : Number(s));

  async function call<T>(path: string, method: "PUT" | "POST", body: unknown, label: string, key: string): Promise<T | null> {
    setBusy(key); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/college${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(label) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return null; }
      notify(label); return j as T;
    } finally { setBusy(null); }
  }
  const saveExam = async (e: ExamRule) => {
    const r = await call<RulesData>(`/rules/exams/${e.code}`, "PUT", { minAttendancePct: num(v(`ex-att-${e.code}`, e.min_attendance_pct)), resitAllowed: v(`ex-ra-${e.code}`, e.resit_allowed) === "true", resitWindowMonths: num(v(`ex-rw-${e.code}`, e.resit_window_months)), noResitIfAllFailed: v(`ex-nr-${e.code}`, e.no_resit_if_all_failed) === "true", appealToSenate: v(`ex-ap-${e.code}`, e.appeal_to_senate) === "true", onFailure: v(`ex-of-${e.code}`, e.on_failure) }, `${e.code} rule set`, e.code);
    if (r) { setD(r); setEdits({}); router.refresh(); }
  };
  const saveSubject = async (s: SubjectRule) => {
    const r = await call<RulesData>(`/rules/subjects/${s.id}`, "PUT", { passMark: num(v(`sb-pm-${s.id}`, s.pass_mark)), caWeight: num(v(`sb-ca-${s.id}`, s.ca_weight)), examWeight: num(v(`sb-ex-${s.id}`, s.exam_weight)), clinicalComponentMin: num(v(`sb-cl-${s.id}`, s.clinical_component_min)) }, `${s.exam} ${s.name}: rule set`, s.id);
    if (r) { setD(r); setEdits({}); router.refresh(); }
  };
  const saveAttendance = async (a: AttendanceRule) => {
    const r = await call<RulesData>(`/rules/attendance/${a.id}`, "PUT", { minPct: num(v(`at-${a.id}`, a.min_pct)), appliesTo: v(`at-ap-${a.id}`, a.applies_to), note: null }, `Attendance rule set: ${a.scope === "BLOCK" ? a.block : a.phase} ${v(`at-${a.id}`, a.min_pct)}%`, a.id);
    if (r) { setD(r); setEdits({}); router.refresh(); }
  };
  const saveProgramme = async (p: ProgrammeRule) => {
    const r = await call<RulesData>(`/rules/programme/${p.programme_code}`, "PUT", { distinctionMark: num(v(`pr-d-${p.programme_code}`, p.distinction_mark)), minYearsUtme: num(v(`pr-u-${p.programme_code}`, p.min_years_utme)), minYearsDe: num(v(`pr-de-${p.programme_code}`, p.min_years_de)), minTotalCu: num(v(`pr-cu-${p.programme_code}`, p.min_total_cu)), resitWindowMonths: num(v(`pr-rw-${p.programme_code}`, p.resit_window_months)), honoursRule: v(`pr-h-${p.programme_code}`, p.honours_rule), carryOverNote: v(`pr-c-${p.programme_code}`, p.carry_over_note) }, `${p.programme} rule set`, p.programme_code);
    if (r) { setD(r); setEdits({}); router.refresh(); }
  };
  const toggleGate = async (g: GateItem) => { const r = await call<RulesData>(`/rules/gates/${g.id}`, "PUT", { eligibilityGate: !g.eligibility_gate }, `${g.subject}: ${g.name} ${g.eligibility_gate ? "no longer gates" : "gates"} the sitting`, g.id); if (r) setD(r); };
  const confirm100 = async () => {
    if (!minute.trim()) { const pr: Problem = { status: 422, title: "The Board acts on a minute; cite it." }; setProblem(pr); return; }
    const r = await call<Level100>("/level100/confirm", "POST", { session, minute: minute.trim() }, `100 Level rule confirmed for ${session} on minute ${minute.trim()}`, "l100");
    if (r) { setL100(r); setMinute(""); router.refresh(); }
  };
  const clearCarry = async () => {
    if (!clearing) return;
    if (!clearMinute.trim()) { const pr: Problem = { status: 422, title: "A carry-over is cleared on the Board's minute; cite it." }; setProblem(pr); return; }
    const r = await call<CarryOvers>("/carry-overs/clear", "POST", { studentId: clearing.student_id, code: clearing.code, minute: clearMinute.trim() }, `${clearing.code} cleared for ${clearing.surname}`, "clear");
    if (r) { setCarryRows(r.rows); setClearing(null); setClearMinute(""); router.refresh(); }
  };
  const searchCarry = async () => {
    const r = await fetch(`/api/bff/api/v1/college/carry-overs?q=${encodeURIComponent(carryQ)}`, { cache: "no-store" }); const j = await r.json().catch(() => null);
    if (r.ok && j) setCarryRows((j as CarryOvers).rows);
  };
  const inp = (key: string, current: unknown, width = 70, disabled = !mayEdit) => <input className="ctl tnum" style={{ width }} value={v(key, current)} disabled={disabled} onChange={(e) => setEdits({ ...edits, [key]: e.target.value })} />;
  const sel = (key: string, current: boolean) => <select className="ctl" value={v(key, current)} disabled={!mayEdit} onChange={(e) => setEdits({ ...edits, [key]: e.target.value })}><option value="true">Yes</option><option value="false">No</option></select>;
  const open = carryRows.filter((c) => !c.cleared_on);

  return (
    <>
      <PageHead title="College Rules" description="The regulations as the College's tables hold them, and as the portal applies them: attendance bars the sitting, the pass mark and weights judge the subject, the resit window and the programme rule govern the decision, the Board acts on the 100 Level rule and clears the carry-overs. Every change is on the audit spine." />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!mayEdit ? <Note kind="info" title="Read only">The rules are set by the Provost&rsquo;s desk, the College Secretary and the Academic Office.</Note> : null}

      <Panel title="Professional examinations" right="Attendance to sit · resit · appeal">
        <DTable pageSize={0} cols={["Examination", "Level|mid", "Min. attendance %|mid", "Resit allowed|mid", "Resit window (months)|mid", "No resit if all failed|mid", "Appeal to Senate|mid", "On failure", "|num"]} rows={d.exams.map((e) => [
          <span key="n"><b>{e.code}</b><div className="sub2">{e.name}</div></span>, <span key="l" className="tnum">{e.level}</span>,
          <span key="a">{inp(`ex-att-${e.code}`, e.min_attendance_pct)}</span>, <span key="r">{sel(`ex-ra-${e.code}`, e.resit_allowed)}</span>, <span key="w">{inp(`ex-rw-${e.code}`, e.resit_window_months, 60)}</span>,
          <span key="x">{sel(`ex-nr-${e.code}`, e.no_resit_if_all_failed)}</span>, <span key="p">{sel(`ex-ap-${e.code}`, e.appeal_to_senate)}</span>,
          <textarea key="o" className="ctl" rows={2} style={{ minWidth: 260 }} value={v(`ex-of-${e.code}`, e.on_failure)} disabled={!mayEdit} onChange={(ev) => setEdits({ ...edits, [`ex-of-${e.code}`]: ev.target.value })} />,
          mayEdit ? <Btn key="s" kind="primary" size="sm" disabled={busy !== null} onClick={() => void saveExam(e)}>Save</Btn> : null,
        ])} />
      </Panel>

      <Panel title="Subjects" right="Pass mark · CA and examination weights · clinical minimum · the attendance the subject effectively needs">
        <DTable pageSize={0} cols={["Examination|mid", "Subject", "Pass mark|mid", "CA weight|mid", "Exam weight|mid", "Clinical min.|mid", "Attendance needed|mid", "|num"]} rows={d.subjects.map((s) => [
          <span key="e" className="tnum">{s.exam}</span>, <span key="n"><b>{s.name}</b>{s.departments ? <div className="sub2">{s.departments}</div> : null}</span>,
          <span key="p">{inp(`sb-pm-${s.id}`, s.pass_mark, 60)}</span>, <span key="c">{inp(`sb-ca-${s.id}`, s.ca_weight, 60)}</span>, <span key="x">{inp(`sb-ex-${s.id}`, s.exam_weight, 60)}</span>, <span key="l">{inp(`sb-cl-${s.id}`, s.clinical_component_min, 60)}</span>,
          <span key="a" className="tnum">{s.min_attendance != null ? `${s.min_attendance}%` : "—"}</span>,
          mayEdit ? <Btn key="s" kind="primary" size="sm" disabled={busy !== null} onClick={() => void saveSubject(s)}>Save</Btn> : null,
        ])} />
      </Panel>

      <div className="grid grid--2">
        <Panel title="Attendance rules" right="The strictest rule that reaches a subject bars the sitting">
          <DTable pageSize={0} cols={["Scope", "Applies to", "Min. %|mid", "|num"]} rows={d.attendance.map((a) => [
            <span key="s"><b>{a.scope === "BLOCK" ? `${a.block} block` : `${(a.phase ?? "").toLowerCase()} phase`}</b>{a.note ? <div className="sub2">{a.note}</div> : null}</span>,
            <select key="ap" className="ctl" value={v(`at-ap-${a.id}`, a.applies_to)} disabled={!mayEdit} onChange={(e) => setEdits({ ...edits, [`at-ap-${a.id}`]: e.target.value })}><option value="OVERALL">Overall</option><option value="EACH_ACTIVITY_AND_OVERALL">Each activity and overall</option></select>,
            <span key="m">{inp(`at-${a.id}`, a.min_pct, 60)}</span>,
            mayEdit ? <Btn key="b" kind="primary" size="sm" disabled={busy !== null} onClick={() => void saveAttendance(a)}>Save</Btn> : null,
          ])} />
        </Panel>
        <Panel title="Programme rule" right="Graduation, distinction, resit window">
          <PBody>
            {d.programme.map((p) => (
              <div key={p.programme_code} className="stack" style={{ gap: 8 }}>
                <b>{p.programme} · {p.degree}</b>
                <KvGrid cls="grid--2" pairs={[
                  ["Distinction mark", inp(`pr-d-${p.programme_code}`, p.distinction_mark, 60)], ["Resit window (months)", inp(`pr-rw-${p.programme_code}`, p.resit_window_months, 60)],
                  ["Minimum years · UTME", inp(`pr-u-${p.programme_code}`, p.min_years_utme, 60)], ["Minimum years · Direct Entry", inp(`pr-de-${p.programme_code}`, p.min_years_de, 60)],
                  ["Minimum credit units", inp(`pr-cu-${p.programme_code}`, p.min_total_cu, 70)], ["Classified", p.classified ? "Yes" : "No, unclassified"],
                ]} />
                <Field id={`pr-h-${p.programme_code}`} label="Honours rule"><textarea id={`pr-h-${p.programme_code}`} className="ctl" rows={2} value={v(`pr-h-${p.programme_code}`, p.honours_rule)} disabled={!mayEdit} onChange={(e) => setEdits({ ...edits, [`pr-h-${p.programme_code}`]: e.target.value })} /></Field>
                <Field id={`pr-c-${p.programme_code}`} label="Carry-over rule"><textarea id={`pr-c-${p.programme_code}`} className="ctl" rows={2} value={v(`pr-c-${p.programme_code}`, p.carry_over_note)} disabled={!mayEdit} onChange={(e) => setEdits({ ...edits, [`pr-c-${p.programme_code}`]: e.target.value })} /></Field>
                {mayEdit ? <div><Btn kind="primary" size="sm" disabled={busy !== null} onClick={() => void saveProgramme(p)}>Save</Btn></div> : null}
              </div>
            ))}
          </PBody>
        </Panel>
      </div>

      <Panel title="Assessment items that gate the sitting" right="An item marked as a gate must carry a score before the candidate sits the subject">
        {d.gates.length ? <DTable pageSize={0} cols={["Examination|mid", "Subject", "Item", "Type|mid", "Weight in CA|mid", "Gates the sitting|mid"]} rows={d.gates.map((g) => [
          <span key="e" className="tnum">{g.exam}</span>, g.subject, <b key="n">{g.name}</b>, <span key="t" className="sub2">{g.item_type}</span>, <span key="w" className="tnum">{g.weight_within_ca}</span>,
          mayEdit ? <Btn key="g" kind={g.eligibility_gate ? "secondary" : "ghost"} size="sm" disabled={busy !== null} onClick={() => void toggleGate(g)}>{g.eligibility_gate ? "Yes · gate" : "No"}</Btn> : <Pil key="g" kind={g.eligibility_gate ? "info" : "grey"}>{g.eligibility_gate ? "Gate" : "No"}</Pil>,
        ])} /> : <PBody><div className="sub2">No assessment item is configured under a subject.</div></PBody>}
      </Panel>

      <Panel title={`The 100 Level rule · entrants of ${session}`} right={<span className="row row--inline row--tight"><label htmlFor="rl-session" className="sub2">Session</label><select id="rl-session" className="ctl" value={session} onChange={(e) => go(`/college/rules?session=${encodeURIComponent(e.target.value)}`)}>{sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></span>}>
        <PBody>
          <div className="sub2">Every C-group course at 50 or more on the University&rsquo;s published results, no resit; GST below 50 is carried. The Board confirms the reading on its minute: those who met it move to 200 Level, those who did not are advised to withdraw; a student whose results are not all published waits.</div>
          {l100.promoted != null ? <Note kind="ok" title="The Board's act was recorded">{l100.promoted} promoted to 200 Level · {l100.withdrawn} advised to withdraw · {l100.waiting} waiting on unpublished results.</Note> : null}
          {l100.rows.length ? <DTable pageSize={0} cols={["Student", "Number|mid", "Published|mid", "Reading", "Below 50", "GST carried", "Minute"]} rows={l100.rows.map((r) => [
            <b key="n">{r.surname}, {r.other_names}</b>, <span key="m" className="tnum">{r.number}</span>, <span key="p" className="tnum">{r.published}/{r.registered}</span>,
            <Pil key="o" kind={OUT[r.outcome ?? ""]?.[1] ?? "grey"}>{OUT[r.outcome ?? ""]?.[0] ?? (r.minute ? (r.current_level >= 200 ? "Promoted" : r.status) : "No results yet")}</Pil>,
            <span key="f" className="ink-red">{r.failed ?? ""}</span>, <span key="c" className="sub2">{r.carried ?? ""}</span>, <span key="mi" className="sub2 tnum">{r.minute ?? ""}</span>,
          ])} /> : <div className="sub2 mt-2">No MBBS entrant of {session} stands at 100 Level.</div>}
          {mayAct && l100.rows.some((r) => r.outcome === "PROMOTE" || r.outcome === "WITHDRAW_ADVISED") ? (
            <div className="row row--tight mt-2" style={{ gap: 8, alignItems: "flex-end" }}>
              <Field id="rl-minute" label="College Academic Board minute" required><input id="rl-minute" className="ctl" value={minute} onChange={(e) => setMinute(e.target.value)} placeholder="e.g. CAB/2026/03/07" /></Field>
              <Btn kind="go" disabled={busy !== null} onClick={() => void confirm100()}>Confirm the Board&rsquo;s act on the 100 Level rule</Btn>
            </div>
          ) : null}
        </PBody>
      </Panel>

      <Panel title="Carry-overs" right={`${open.length} open`}>
        <PBody>
          <div className="row row--tight" style={{ gap: 8 }}><input className="ctl" style={{ width: 280 }} placeholder="Search by name, number or course" value={carryQ} onChange={(e) => setCarryQ(e.target.value)} /><Btn kind="ghost" onClick={() => void searchCarry()}>Search</Btn></div>
          {carryRows.length ? <DTable pageSize={30} cols={["Student", "Number|mid", "Course|mid", "From|mid", "Note", "State|mid", "|num"]} rows={carryRows.map((c) => [
            <b key="n">{c.surname}, {c.other_names}</b>, <span key="m" className="tnum">{c.number}</span>, <b key="c" className="tnum">{c.code}</b>, <span key="f" className="tnum">{c.from_session}</span>,
            <span key="t" className="sub2">{c.note ?? ""}</span>, <Pil key="s" kind={c.cleared_on ? "ok" : "warn"}>{c.cleared_on ? `Cleared ${day(c.cleared_on)}` : "Owed"}</Pil>,
            mayAct && !c.cleared_on ? <Btn key="b" kind="secondary" size="sm" onClick={() => { setClearing(c); setClearMinute(""); }}>Clear</Btn> : null,
          ])} /> : <div className="sub2 mt-2">No carry-over on the register. Graduation from the Final MBBS waits while one is owed.</div>}
        </PBody>
      </Panel>

      {clearing ? (
        <Modal title={`Clear ${clearing.code} · ${clearing.surname}, ${clearing.other_names}`} sub="The course was passed; the Board's minute records it. A Final held on this carry-over is decided again at once." onClose={() => setClearing(null)}
          foot={<><Btn kind="ghost" onClick={() => setClearing(null)}>Back</Btn><Btn kind="go" disabled={busy !== null} onClick={() => void clearCarry()}>Clear the carry-over</Btn></>}>
          <Field id="cl-minute" label="College Academic Board minute" required><input id="cl-minute" className="ctl" value={clearMinute} onChange={(e) => setClearMinute(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
