"use client";
/** The Professional examination desk (V245): for one examination in one session, every candidate at its level
 *  with each subject's CA, examination and (where the subject has one) clinical marks by attempt; the pass is
 *  judged by the rule as the marks are saved, never typed; the rule's recommendation for the candidate's
 *  progression is shown and the College Academic Board's decision recorded; and the reconciliation the crossing
 *  to Senate needs — every candidate accounted for in every subject, or named — stands at the top. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface ExamCatalogue {
  exams: { id: string; code: string; name: string; level: number; papers: string[]; external_examiners: boolean; resit_allowed: boolean; resit_window_months: number; no_resit_if_all_failed: boolean; appeal_to_senate: boolean; min_attendance_pct: number | null; on_failure: string; ordinal: number }[];
  subjects: { id: string; exam_id: string; name: string; departments: string | null; ca_weight: number; exam_weight: number; pass_mark: number; clinical_component_min: number | null; conflict_note: string | null; ordinal: number }[];
  items: { id: string; subject_id: string | null; posting_id: string | null; item_type: string; name: string; weight_within_ca: number | null; max_score: number; eligibility_gate: boolean; note: string | null }[];
}
export interface Result { id: string; subject_id: string; attempt: string; ca: number | null; exam: number | null; clinical: number | null; attendance: number | null; barred: boolean; total: number | null; passed: boolean | null; decided_on: string | null }
export interface Decision { id: string; outcome: string; state: "PROVISIONAL" | "CONFIRMED"; carry_overs: string[]; rule_ref: string | null; minute: string | null; decided_on: string; confirmed_on: string | null; honours: boolean | null; resit_names: string | null }
export interface Enrolment { kind: string; state: string; attempt_no: number; registered_at: string | null }
export interface Candidate { id: string; number: string; surname: string; other_names: string; programme_code: string; entry_mode: string; current_level: number; results: string; decision: string | null; attempt: string; enrolment_kind: string; attempt_no: number; enrolment_state: string; semesters: number; semesters_registered: number; fully_registered: boolean }
export interface Candidates { exam: ExamCatalogue["exams"][number]; subjects: ExamCatalogue["subjects"]; candidates: Candidate[]; yearReached: boolean; calendar: { ordinal: number; length_weeks: number | null; starts_on: string | null; ends_on: string | null }[] }
export interface CaScore { id: string; item_id: string; attempt_no: number; score: number; scored_on: string; item: string; subject: string; max_score: number }
export interface CaItem { id: string; subject_id: string; subject: string; item_type: string; name: string; max_score: number; eligibility_gate: boolean; note: string | null }
export interface Reconciliation {
  exam: ExamCatalogue["exams"][number];
  missing: { number: string; surname: string; other_names: string; subject: string }[];
  undecided: { number: string; surname: string; other_names: string }[];
  unregistered: { number: string; surname: string; other_names: string; semesters: number; semesters_registered: number }[];
  cohort: number; yearReached: boolean;
  counts: { candidates_with_results: number; subject_passes: number; subject_fails: number; distinctions: number };
  decisions: { decided: number; provisional: number; confirmed: number; promoted: number; resits: number; repeats: number; withdrawals: number; appeals: number; honours: number };
  ready: boolean;
}

const ATTEMPTS = ["FIRST", "RESIT", "REPEAT", "SENATE_APPEAL"];
const OUTCOMES: [string, string][] = [["PROMOTE", "Promote"], ["GRADUATE", "Graduate"], ["RESIT", "Resit"], ["REPEAT", "Repeat"], ["WITHDRAW_ADVISED", "Advised to withdraw"], ["WITHDRAW_REQUIRED", "Must withdraw"], ["APPEAL", "Appeal to Senate"]];
type Marks = Record<string, { ca: string; exam: string; clinical: string; attendance: string }>;
const num = (v: number | null | undefined) => (v == null ? "" : String(v));
const word = (s: string) => s.charAt(0) + s.slice(1).toLowerCase().replace(/_/g, " ");
const parse = <T,>(s: string | null, fallback: T): T => { try { return s ? (JSON.parse(s) as T) : fallback; } catch { return fallback; } };

export function Examinations({ catalogue, sessions, session, code, data, reconciliation, problem }: {
  catalogue: ExamCatalogue; sessions: string[]; session: string; code: string; data: Candidates | null; reconciliation: Reconciliation | null; problem: Problem | null;
}) {
  const router = useRouter();
  const go = useQueryNav();
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const [attempt, setAttempt] = useState("FIRST");
  const [marks, setMarks] = useState<Marks>({});
  const [decision, setDecision] = useState({ outcome: "", carry: "", minute: "" });
  const [rec, setRec] = useState<{ recommend: string; failed: number; of: number; latestAttempt: string; onFailure: string; failedNames: string | null; ruleRef: string | null } | null>(null);
  const [boardMinute, setBoardMinute] = useState("");
  const [appealMinute, setAppealMinute] = useState("");
  const [enrol, setEnrol] = useState({ number: "", open: false });
  const [ca, setCa] = useState<{ items: CaItem[]; scores: CaScore[] } | null>(null);
  const [caNew, setCaNew] = useState({ itemId: "", score: "" });

  const exam = catalogue.exams.find((e) => e.code === code) ?? catalogue.exams[0];
  const subjects = data?.subjects ?? catalogue.subjects.filter((s) => s.exam_id === exam?.id);
  const nav = (patch: Partial<{ session: string; exam: string }>) => go(`/college/examinations?session=${encodeURIComponent(patch.session ?? session)}&exam=${encodeURIComponent(patch.exam ?? code)}`);

  async function call(method: "POST", path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true); setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/college${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
      const j = (await r.json().catch(() => null)) as Record<string, unknown> | null;
      if (!r.ok) { setErr(j as unknown as Problem ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j;
    } finally { setBusy(false); }
  }

  function marksAt(results: Result[], at: string): Marks {
    const m: Marks = {};
    for (const s of subjects) {
      const r = results.filter((x) => x.subject_id === s.id).find((x) => x.attempt === at);
      m[s.id] = { ca: num(r?.ca), exam: num(r?.exam), clinical: num(r?.clinical), attendance: num(r?.attendance) };
    }
    return m;
  }

  function openCandidate(c: Candidate) {
    setOpen(c.id);
    setRec(null);
    const results = parse<Result[]>(c.results, []);
    const d = parse<Decision | null>(c.decision, null);
    // the attempt the enrolment puts the candidate at: first, resit, repeat year, or the Senate-approved final
    const at = c.attempt || "FIRST";
    setAttempt(at);
    setMarks(marksAt(results, at));
    setCa(null);
    void fetch(`/api/bff/api/v1/college/assessments?student=${c.id}&exam=${encodeURIComponent(exam.code)}`).then(async (r) => { if (r.ok) setCa(await r.json()); });
    setDecision({ outcome: d?.outcome ?? "", carry: (d?.carry_overs ?? []).join(", "), minute: d?.minute ?? "" });
    void fetch(`/api/bff/api/v1/college/exams/${encodeURIComponent(exam.code)}/recommend?session=${encodeURIComponent(session)}&student=${c.id}`).then(async (r) => { if (r.ok) setRec(await r.json()); });
  }

  async function saveResults(c: Candidate) {
    let saved = 0;
    for (const s of subjects) {
      const m = marks[s.id];
      if (!m || (m.ca === "" && m.exam === "")) continue;
      const j = await call("POST", `/exams/${encodeURIComponent(exam.code)}/results`, {
        session, studentId: c.id, subjectId: s.id, attempt, caScore: m.ca === "" ? null : Number(m.ca), examScore: m.exam === "" ? null : Number(m.exam), clinicalScore: m.clinical === "" ? null : Number(m.clinical),
        attendancePct: m.attendance === "" ? null : Number(m.attendance),
      }, `${c.number}: ${s.name} ${word(attempt)} result — ${exam.code}`);
      if (!j) return;
      saved++;
    }
    if (saved) openCandidate({ ...c });
  }

  async function saveDecision(c: Candidate) {
    if (!decision.outcome) return;
    await call("POST", `/exams/${encodeURIComponent(exam.code)}/decisions`, {
      session, studentId: c.id, outcome: decision.outcome, carryOvers: decision.carry.split(/[,;]/).map((x) => x.trim()).filter(Boolean), ruleRef: rec ? `${exam.code}: ${rec.recommend} recommended (${rec.failed} of ${rec.of} failed at ${word(rec.latestAttempt)})` : null, minute: decision.minute.trim() || null,
    }, `${c.number}: ${OUTCOMES.find((o) => o[0] === decision.outcome)?.[1] ?? decision.outcome} after ${exam.code}`);
  }

  async function enrolStudent() {
    if (!enrol.number.trim()) return;
    const j = await call("POST", "/enrol", { number: enrol.number.trim(), session, level: exam.level }, `${enrol.number.trim()}: ${exam.level} Level year opened for ${session}`);
    if (j) setEnrol({ number: "", open: false });
  }
  async function addCa(c: Candidate) {
    if (!caNew.itemId || caNew.score === "") return;
    const j = await call("POST", "/assessments", { studentId: c.id, itemId: caNew.itemId, score: Number(caNew.score) }, `${c.number}: CA item recorded`);
    if (j) { setCaNew({ itemId: "", score: "" }); const r = await fetch(`/api/bff/api/v1/college/assessments?student=${c.id}&exam=${encodeURIComponent(exam.code)}`); if (r.ok) setCa(await r.json()); }
  }
  async function confirmBoard() {
    if (!boardMinute.trim()) return;
    if (!window.confirm(`Confirm every provisional decision for ${exam.code} in ${session} on minute ${boardMinute.trim()}? Each student is then moved: the next level, the resit, the repeat year, withdrawal, or graduation.`)) return;
    await call("POST", `/exams/${encodeURIComponent(exam.code)}/confirm`, { session, minute: boardMinute.trim() }, `${exam.code} ${session}: the Board's decisions confirmed on ${boardMinute.trim()}`);
  }
  async function grantAppeal(c: Candidate) {
    if (!appealMinute.trim()) return;
    await call("POST", `/exams/${encodeURIComponent(exam.code)}/appeals`, { session, studentId: c.id, minute: appealMinute.trim() }, `${c.number}: Senate's approval of the appeal recorded — a fourth and final attempt`);
  }

  const rows = data?.candidates ?? [];
  const rc = reconciliation;

  return (
    <>
      <div className="scope">
        <div className="scope__f"><label htmlFor="ex-session">Session</label>
          <select id="ex-session" className="ws__select" value={session} onChange={(e) => nav({ session: e.target.value })}>{sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></div>
        <div className="scope__f" style={{ flex: "2 1 320px" }}><label htmlFor="ex-code">Examination</label>
          <select id="ex-code" className="ws__select" value={exam?.code ?? ""} onChange={(e) => nav({ exam: e.target.value })}>
            {catalogue.exams.map((e) => <option key={e.code} value={e.code}>{e.code} — {e.name} · {e.level} Level</option>)}
          </select></div>
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      {exam ? (
        <Note kind="info" title={`${exam.name}: ${exam.papers.map((p) => word(p)).join(", ")}${exam.external_examiners ? " · external examiners" : ""}`}>
          {subjects.map((s) => `${s.name} (CA ${s.ca_weight}, examination ${s.exam_weight}, pass ${s.pass_mark}${s.clinical_component_min ? `, clinical ${s.clinical_component_min}` : ""})`).join(" · ")}. Resit {exam.resit_allowed ? `within ${exam.resit_window_months} months${exam.no_resit_if_all_failed ? ", unless every subject is failed" : ""}` : "not allowed"}{exam.min_attendance_pct ? ` · attendance ${exam.min_attendance_pct}%` : ""}. On failure: {exam.on_failure}
          {subjects.some((s) => s.conflict_note) ? <div style={{ marginTop: 4, color: "var(--red-ink)" }}>{subjects.filter((s) => s.conflict_note).map((s) => `${s.name}: ${s.conflict_note}`).join(" · ")}</div> : null}
        </Note>
      ) : null}

      {data && !data.yearReached ? (
        <Note kind="bad" title={`The ${exam.level} Level year for the ${session} cohort has not reached its final semester`}>
          The College&rsquo;s students sit once, at the end of the year. Results open when the final semester has begun, by the College calendar{data.calendar.length ? `: ${data.calendar.map((c) => `semester ${c.ordinal} ${c.starts_on ?? "undated"} to ${c.ends_on ?? "undated"}`).join(" · ")}` : ""}. CA collected during the year is kept below, graded never.
        </Note>
      ) : null}
      {rc ? (
        <>
          <Tiles items={[
            ["Cohort", String(rc.cohort), null, `${exam.level} Level year begun in ${session} · ${rc.unregistered.length} not fully registered`],
            ["Subject results", `${rc.counts.subject_passes + rc.counts.subject_fails}`, null, `${rc.counts.subject_passes} passed · ${rc.counts.subject_fails} failed · ${rc.counts.distinctions} distinction${rc.counts.distinctions === 1 ? "" : "s"}`],
            ["Decisions", `${rc.decisions.confirmed} of ${rc.decisions.decided}`, rc.decisions.provisional ? "var(--red-ink)" : rc.decisions.decided === rows.length && rows.length ? "var(--green-ink)" : null, `${rc.decisions.provisional} provisional · ${rc.decisions.promoted} promoted · ${rc.decisions.resits} resit · ${rc.decisions.repeats} repeat · ${rc.decisions.withdrawals} withdraw · ${rc.decisions.appeals} appeal${exam.level === 600 ? ` · ${rc.decisions.honours} honours` : ""}`],
            ["Ready for Senate", rc.ready ? "Yes" : "Not yet", rc.ready ? "var(--green-ink)" : "var(--red-ink)", rc.ready ? "Every candidate accounted for in every subject, and every decision confirmed" : `${rc.missing.length} subject result${rc.missing.length === 1 ? "" : "s"} missing · ${rc.undecided.length} undecided · ${rc.decisions.provisional} to confirm`],
          ]} />
          {rc.decisions.provisional > 0 ? (
            <Panel title="The College Academic Board confirms" right={`${rc.decisions.provisional} provisional decision${rc.decisions.provisional === 1 ? "" : "s"}`}>
              <PBody>
                <div className="sub2" style={{ marginBottom: 8 }}>The rule has applied a provisional decision to every candidate whose subjects are all resulted. The Board confirms them in one act on its minute; each student is then moved — to the next level, to the resit, to the repeat year, to withdrawal on the minute as the instrument, or to graduation. A candidate the Board decides differently is changed below before confirming.</div>
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "flex-end" }}>
                  <div className="field" style={{ width: 220 }}><label htmlFor="ex-board">Board minute</label><input id="ex-board" className="ctl" value={boardMinute} onChange={(e) => setBoardMinute(e.target.value)} placeholder="CAB/2026/…" autoComplete="off" /></div>
                  <Btn kind="go" disabled={busy || !boardMinute.trim()} onClick={() => void confirmBoard()}>{busy ? "Confirming…" : `Confirm ${rc.decisions.provisional} decision${rc.decisions.provisional === 1 ? "" : "s"}`}</Btn>
                </div>
              </PBody>
            </Panel>
          ) : null}
          {!rc.ready && rows.length ? (
            <Note kind="bad" title="The crossing to Senate is a reconciliation, not a file drop">
              The set does not leave the College until every registered candidate is accounted for in every subject, and decided. Missing: {rc.missing.slice(0, 8).map((m) => `${m.number} ${m.subject}`).join(" · ")}{rc.missing.length > 8 ? ` · and ${rc.missing.length - 8} more` : ""}{rc.missing.length && rc.undecided.length ? ". " : ""}{rc.undecided.length ? `Undecided: ${rc.undecided.slice(0, 8).map((u) => u.number).join(", ")}${rc.undecided.length > 8 ? ` and ${rc.undecided.length - 8} more` : ""}` : ""}
            </Note>
          ) : null}
        </>
      ) : null}

      <Panel title={`Candidates for ${exam?.code ?? ""} · the ${session} cohort`} right={<span style={{ display: "inline-flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}><span className="sub2">{rows.length} enrolled at {exam?.level ?? ""} Level</span><Btn kind="ghost" onClick={() => setEnrol({ ...enrol, open: !enrol.open })}>{enrol.open ? "Close" : "Enrol a student"}</Btn></span>}>
        {enrol.open ? (
          <PBody>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "flex-end" }}>
              <div className="field" style={{ width: 240 }}><label htmlFor="ex-enrol">Matriculation number</label><input id="ex-enrol" className="ctl" value={enrol.number} onChange={(e) => setEnrol({ ...enrol, number: e.target.value })} placeholder="MOAUM/MED/24/…" autoComplete="off" /></div>
              <Btn kind="primary" disabled={busy || !enrol.number.trim()} onClick={() => void enrolStudent()}>Open the {exam.level} Level year for {session}</Btn>
              <span className="sub2">For a student who registered on paper or arrived by transfer; they must be at {exam.level} Level on the register. The year&rsquo;s semesters are then registered on their fees.</span>
            </div>
          </PBody>
        ) : null}
        {rows.length === 0 ? <PBody><div className="sub2">Nobody has a {exam?.level} Level year begun in {session}. A cohort is the students enrolled at the level in that session: they enrol from their dashboard when the fees are cleared, or the desk opens the year for them above.</div></PBody> : (
          <DTable cols={["Matriculation number", "Name", ...subjects.map((s) => `${s.name}|mid`), "Decision|mid", "|num"]} rows={rows.map((c) => {
            const results = parse<Result[]>(c.results, []);
            const d = parse<Decision | null>(c.decision, null);
            return [
              <span className="tnum" key="n">{c.number}</span>,
              <span key="nm"><strong>{c.surname}, {c.other_names}</strong><div className="sub2">{c.entry_mode === "DIRECT_ENTRY" ? "Direct Entry" : "UTME"}{c.enrolment_kind === "REPEAT" ? ` · repeat year, attempt ${c.attempt_no}` : c.enrolment_kind === "APPEAL" ? " · Senate-approved final attempt" : ""}</div>{c.fully_registered ? null : <Pil kind="bad">{c.semesters ? `Not registered: ${c.semesters_registered} of ${c.semesters} semesters` : "Not registered"}</Pil>}</span>,
              ...subjects.map((s) => {
                const rs = results.filter((r) => r.subject_id === s.id);
                const latest = rs[rs.length - 1];
                return <span key={s.id}>{latest ? <><span className="tnum">{latest.total ?? "—"}</span> <Pil kind={latest.passed ? "ok" : latest.passed === false ? "bad" : "grey"}>{latest.passed ? (Number(latest.total) >= 70 ? "Distinction" : "Pass") : latest.passed === false ? (latest.barred ? "Barred" : "Fail") : "—"}</Pil>{rs.length > 1 ? <div className="sub2">{rs.map((r) => word(r.attempt)).join(" → ")}</div> : latest.attempt !== "FIRST" ? <div className="sub2">{word(latest.attempt)}</div> : null}</> : <span className="sub2">—</span>}</span>;
              }),
              <span key="d">{d ? <><Pil kind={d.outcome === "PROMOTE" || d.outcome === "GRADUATE" ? "ok" : d.outcome.startsWith("WITHDRAW") ? "bad" : "info"}>{OUTCOMES.find((o) => o[0] === d.outcome)?.[1] ?? d.outcome}{d.outcome === "GRADUATE" && d.honours ? " · Honours" : ""}</Pil><div className="sub2">{d.state === "CONFIRMED" ? `Confirmed${d.confirmed_on ? " " + d.confirmed_on : ""}` : "Provisional"}</div></> : <span className="sub2">{c.attempt !== "FIRST" ? word(c.attempt) : "Not yet"}</span>}</span>,
              <Btn key="o" kind={open === c.id ? "ghost" : "primary"} onClick={() => (open === c.id ? setOpen(null) : openCandidate(c))}>{open === c.id ? "Close" : "Open"}</Btn>,
            ];
          })} texts={rows.map((c) => `${c.number} ${c.surname} ${c.other_names}`)} />
        )}
      </Panel>

      {open ? (() => {
        const c = rows.find((x) => x.id === open);
        if (!c) return null;
        const results = parse<Result[]>(c.results, []);
        return (
          <Panel title={`${c.surname}, ${c.other_names} · ${c.number}`} right={<span style={{ display: "inline-flex", gap: 8, alignItems: "center" }}><label htmlFor="ex-attempt" className="sub2">Attempt</label><select id="ex-attempt" className="ctl" value={attempt} onChange={(e) => { setAttempt(e.target.value); setMarks(marksAt(results, e.target.value)); }}>{ATTEMPTS.map((a) => <option key={a} value={a}>{word(a)}</option>)}</select></span>}>
            <div className="tablewrap"><table>
              <thead><tr><th>Subject</th><th className="mid">CA</th><th className="mid">Examination</th><th className="mid">Clinical</th><th className="mid">Attendance %</th><th className="mid">Total</th><th className="mid">Standing</th><th>Earlier attempts</th></tr></thead>
              <tbody>
                {subjects.map((s) => {
                  const m = marks[s.id] ?? { ca: "", exam: "", clinical: "", attendance: "" };
                  const ca = m.ca === "" ? null : Number(m.ca); const ex = m.exam === "" ? null : Number(m.exam); const cl = m.clinical === "" ? null : Number(m.clinical);
                  const at = m.attendance === "" ? null : Number(m.attendance);
                  const total = ca != null && ex != null ? ca + ex : null;
                  const caOver = ca != null && ca > Number(s.ca_weight); const exOver = ex != null && ex > Number(s.exam_weight);
                  const barred = exam.min_attendance_pct != null && at != null && at < exam.min_attendance_pct;
                  const pass = total == null ? null : !barred && total >= s.pass_mark && (s.clinical_component_min == null || (cl != null && cl >= s.clinical_component_min));
                  const earlier = results.filter((r) => r.subject_id === s.id && r.attempt !== attempt);
                  return (
                    <tr key={s.id}>
                      <td><strong>{s.name}</strong><div className="sub2">CA {s.ca_weight} · exam {s.exam_weight} · pass {s.pass_mark}{s.clinical_component_min ? ` · clinical ${s.clinical_component_min}` : ""}</div></td>
                      <td className="mid"><input className="ctl tnum" style={{ width: 70, textAlign: "center", ...(caOver ? { borderColor: "var(--red-ink)", color: "var(--red-ink)", fontWeight: 700 } : {}) }} inputMode="decimal" value={m.ca} onChange={(e) => setMarks({ ...marks, [s.id]: { ...m, ca: e.target.value.replace(/[^0-9.]/g, "") } })} />{caOver ? <div style={{ color: "var(--red-ink)", fontSize: 11 }}>Over {s.ca_weight}</div> : null}</td>
                      <td className="mid"><input className="ctl tnum" style={{ width: 70, textAlign: "center", ...(exOver ? { borderColor: "var(--red-ink)", color: "var(--red-ink)", fontWeight: 700 } : {}) }} inputMode="decimal" value={m.exam} onChange={(e) => setMarks({ ...marks, [s.id]: { ...m, exam: e.target.value.replace(/[^0-9.]/g, "") } })} />{exOver ? <div style={{ color: "var(--red-ink)", fontSize: 11 }}>Over {s.exam_weight}</div> : null}</td>
                      <td className="mid">{s.clinical_component_min ? <input className="ctl tnum" style={{ width: 70, textAlign: "center" }} inputMode="decimal" value={m.clinical} onChange={(e) => setMarks({ ...marks, [s.id]: { ...m, clinical: e.target.value.replace(/[^0-9.]/g, "") } })} placeholder="/100" /> : <span className="sub2">—</span>}</td>
                      <td className="mid"><input className="ctl tnum" style={{ width: 70, textAlign: "center", ...(barred ? { borderColor: "var(--red-ink)", color: "var(--red-ink)", fontWeight: 700 } : {}) }} inputMode="decimal" value={m.attendance} onChange={(e) => setMarks({ ...marks, [s.id]: { ...m, attendance: e.target.value.replace(/[^0-9.]/g, "") } })} placeholder={exam.min_attendance_pct != null ? `≥ ${exam.min_attendance_pct}` : "%"} />{barred ? <div style={{ color: "var(--red-ink)", fontSize: 11 }}>Below {exam.min_attendance_pct}%</div> : null}</td>
                      <td className="mid"><b className="tnum">{total ?? "—"}</b></td>
                      <td className="mid">{pass == null ? <span className="sub2">on save</span> : <Pil kind={pass ? "ok" : "bad"}>{pass ? (total! >= 70 ? "Distinction" : "Pass") : barred ? "Barred" : "Fail"}</Pil>}</td>
                      <td className="sub2">{earlier.length ? earlier.map((r) => `${word(r.attempt)}: ${r.total ?? "—"} ${r.passed ? "pass" : "fail"}`).join(" · ") : "—"}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table></div>
            <PBody>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
                <Btn kind="primary" disabled={busy} onClick={() => void saveResults(c)}>{busy ? "Saving…" : `Save the ${word(attempt).toLowerCase()} results`}</Btn>
                <span className="sub2">The pass is judged by the rule as the marks are saved: {subjects[0]?.pass_mark ?? 50} or more in the subject{subjects.some((s) => s.clinical_component_min) ? ", and in the clinical component where the subject has one" : ""}{exam.min_attendance_pct != null ? `, with attendance of at least ${exam.min_attendance_pct}% or the candidate is barred` : ""}. Once every subject is resulted the rule applies its decision provisionally. A resit or repeat is a new attempt; the earlier one is kept.</span>
              </div>
              <div style={{ marginTop: 14, borderTop: "1px solid var(--line)", paddingTop: 12 }}>
                <div style={{ display: "flex", gap: 10, alignItems: "baseline", flexWrap: "wrap" }}><strong>CA kept during the year</strong><span className="sub2">Course tests and end-of-posting scores as they happen; graded never. The year&rsquo;s CA out of {subjects[0]?.ca_weight ?? 30} is composed from them and entered above at the end of the year.</span></div>
                {ca ? (
                  <>
                    {ca.scores.length ? <div className="sub2" style={{ marginTop: 6 }}>{ca.scores.map((x) => `${x.subject} · ${x.item}: ${x.score} of ${x.max_score}${x.attempt_no > 1 ? ` (attempt ${x.attempt_no})` : ""}`).join(" · ")}</div> : <div className="sub2" style={{ marginTop: 6 }}>Nothing recorded yet.</div>}
                    {ca.items.length ? (
                      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "flex-end", marginTop: 8 }}>
                        <div className="field" style={{ flex: "1 1 260px" }}><label htmlFor="ex-ca-item">Item</label>
                          <select id="ex-ca-item" className="ctl" value={caNew.itemId} onChange={(e) => setCaNew({ ...caNew, itemId: e.target.value })}><option value="">Choose…</option>{ca.items.map((i) => <option key={i.id} value={i.id}>{i.subject} · {i.name} (of {i.max_score})</option>)}</select></div>
                        <div className="field" style={{ width: 110 }}><label htmlFor="ex-ca-score">Score</label><input id="ex-ca-score" className="ctl tnum" inputMode="decimal" value={caNew.score} onChange={(e) => setCaNew({ ...caNew, score: e.target.value.replace(/[^0-9.]/g, "") })} /></div>
                        <Btn kind="ghost" disabled={busy || !caNew.itemId || caNew.score === ""} onClick={() => void addCa(c)}>Record</Btn>
                      </div>
                    ) : <div className="sub2" style={{ marginTop: 6 }}>The prospectus names no CA items for this examination&rsquo;s subjects.</div>}
                  </>
                ) : <div className="sub2" style={{ marginTop: 6 }}>Loading…</div>}
              </div>
              <div style={{ marginTop: 14, borderTop: "1px solid var(--line)", paddingTop: 12 }}>
                <div style={{ display: "flex", gap: 10, alignItems: "baseline", flexWrap: "wrap" }}>
                  <strong>Progression decision</strong>
                  {rec ? <span className="sub2">The rule says <b>{rec.recommend === "INCOMPLETE" ? "nothing yet — results incomplete" : OUTCOMES.find((o) => o[0] === rec.recommend)?.[1] ?? rec.recommend}</b> ({rec.failed} of {rec.of} failed{rec.failedNames ? `: ${rec.failedNames}` : ""}, at {word(rec.latestAttempt).toLowerCase()}). {rec.ruleRef ?? rec.onFailure}</span> : null}
                </div>
                {(() => { const d = parse<Decision | null>(c.decision, null); return d ? (
                  <div style={{ marginTop: 6 }}>
                    <Pil kind={d.state === "CONFIRMED" ? "ok" : "warn"}>{d.state === "CONFIRMED" ? "Confirmed by the Board" : "Provisional"}</Pil> <b>{OUTCOMES.find((o) => o[0] === d.outcome)?.[1] ?? d.outcome}</b>{d.resit_names ? <span className="sub2"> · resit: {d.resit_names}</span> : null}{d.minute ? <span className="sub2"> · minute {d.minute}</span> : null}
                    {d.state === "CONFIRMED" && d.outcome === "APPEAL" && exam.appeal_to_senate ? (
                      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "flex-end", marginTop: 8 }}>
                        <div className="field" style={{ width: 220 }}><label htmlFor="ex-appeal">Senate minute</label><input id="ex-appeal" className="ctl" value={appealMinute} onChange={(e) => setAppealMinute(e.target.value)} placeholder="SEN/2026/…" autoComplete="off" /></div>
                        <Btn kind="urgent" disabled={busy || !appealMinute.trim()} onClick={() => void grantAppeal(c)}>Record Senate&rsquo;s approval of the appeal</Btn>
                        <span className="sub2">Opens the fourth and final attempt at 600 Level for {session}; the student registers it.</span>
                      </div>
                    ) : null}
                  </div>
                ) : null; })()}
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "flex-end", marginTop: 8 }}>
                  <div className="field" style={{ width: 200 }}><label htmlFor="ex-outcome">Decision</label>
                    <select id="ex-outcome" className="ctl" value={decision.outcome} onChange={(e) => setDecision({ ...decision, outcome: e.target.value })}>
                      <option value="">Choose…</option>{OUTCOMES.map((o) => <option key={o[0]} value={o[0]}>{o[1]}</option>)}
                    </select></div>
                  <div className="field" style={{ flex: "1 1 200px" }}><label htmlFor="ex-carry">Carry-overs (GST / EPS only)</label><input id="ex-carry" className="ctl" value={decision.carry} onChange={(e) => setDecision({ ...decision, carry: e.target.value })} placeholder="e.g. GST 111, EPS 201" autoComplete="off" /></div>
                  <div className="field" style={{ flex: "1 1 160px" }}><label htmlFor="ex-minute">Board minute</label><input id="ex-minute" className="ctl" value={decision.minute} onChange={(e) => setDecision({ ...decision, minute: e.target.value })} placeholder="CAB/2026/…" autoComplete="off" /></div>
                  <Btn kind="go" disabled={busy || !decision.outcome} onClick={() => void saveDecision(c)}>Change the provisional decision</Btn>
                </div>
                <div className="sub2" style={{ marginTop: 6 }}>The rule applies its decision provisionally; the Board changes a candidate&rsquo;s here where it decides differently, then confirms the set above on its minute. A confirmed decision is not changed here.</div>
              </div>
            </PBody>
          </Panel>
        );
      })() : null}
    </>
  );
}
