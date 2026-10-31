"use client";

/**
 * V651: postgraduate academic management. The stages of each qualification (700, 700 Extension; 800 A–C; 900 A–E), the students
 * of each stage in a session, progression (the calculated stage recorded; an extension only on the Dean's approval), closing a
 * cycle that exhausted its maximum period, the restart workflow (requested and recommended by the department, decided by the
 * Dean: a new cycle at its first stage), the reconciliation of the PG students already on the register (scan, preview, commit),
 * the data-quality list, and the stage setup. The database decides every rule; the screen asks and shows.
 */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, IcoBtn, Note, Panel, PBody, Pil, Spinner, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem, toast } from "@/components/proto/Toast";
import { PgHistoryBody, usePgHistory } from "@/components/pg/PgHistory";
import {
  CYCLE_WORDS, ISSUE_WORDS, RECOMMENDATION_WORDS, RESTART_WORDS, can, outcomeText, restartPath, stageText,
  type Config, type Outcomes, type Quality, type Recommendation, type RestartRow, type Scan, type StageCount, type StageRow, type StudentsPage,
} from "@/lib/pg-academic";

type Tab = "stages" | "students" | "restarts" | "reconcile" | "quality" | "setup";
const API = "/api/bff/api/v1/pg/academic";

async function call<T>(path: string, init?: RequestInit & { reason?: string }): Promise<{ ok: true; data: T } | { ok: false; problem: Problem }> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (init?.reason) headers["X-Reason"] = reasonHeader(init.reason);
  try {
    const r = await fetch(`${API}${path}`, { cache: "no-store", ...init, headers });
    const j = await r.json().catch(() => null);
    if (!r.ok) return { ok: false, problem: j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText } };
    return { ok: true, data: j as T };
  } catch {
    return { ok: false, problem: { status: 0, title: "The portal could not reach the server" } };
  }
}

function useRead<T>(path: string | null, key: number): { data: T | null; problem: Problem | null; loading: boolean } {
  const [st, setSt] = useState<{ path: string; key: number; data: T | null; problem: Problem | null } | null>(null);
  useEffect(() => {
    if (!path) return;
    let alive = true;
    void call<T>(path).then((r) => { if (alive) setSt({ path, key, data: r.ok ? r.data : null, problem: r.ok ? null : r.problem }); });
    return () => { alive = false; };
  }, [path, key]);
  const fresh = st && st.path === path && st.key === key;
  return { data: fresh ? st.data : null, problem: fresh ? st.problem : null, loading: !!path && !fresh };
}

const pct = (n: number, d: number) => (d ? `${Math.round((100 * n) / d)}%` : "—");

export function PgStages({ config, initialTab, initialStage, initialQ = "" }: { config: Config; initialTab: Tab; initialStage: string; initialQ?: string }) {
  const [tab, setTab] = useState<Tab>(initialTab);
  const [session, setSession] = useState(config.session ?? config.sessions[0] ?? "");
  const [reload, setReload] = useState(0);
  // the students list's filters
  const [qual, setQual] = useState("");
  const [stage, setStage] = useState(initialStage);
  const [cat, setCat] = useState("");
  const [rec, setRec] = useState("");
  const [off, setOff] = useState("");
  const [q, setQ] = useState(initialQ);   // V715: opened on a student from the student edit page
  const [page, setPage] = useState(0);
  const [chosen, setChosen] = useState<string[]>([]);
  const [historyOf, setHistoryOf] = useState<StageRow | null>(null);
  const [restartFor, setRestartFor] = useState<StageRow | null>(null);
  const [closing, setClosing] = useState(false);
  const [deciding, setDeciding] = useState<{ row: RestartRow; act: "recommend" | "decide" | "cancel" } | null>(null);
  const [restartState, setRestartState] = useState("OPEN");
  const [conf, setConf] = useState("");
  const [rq, setRq] = useState("");
  const [picked, setPicked] = useState<string[]>([]);
  const [committing, setCommitting] = useState<"selected" | "all" | null>(null);
  const [issue, setIssue] = useState("");
  const [editing, setEditing] = useState<string | null>(null);
  const bump = () => setReload((n) => n + 1);

  const schoolWide = !config.boundDept && !config.boundFaculty;
  const tabs: { id: Tab; label: string }[] = [
    { id: "stages", label: "By stage" }, { id: "students", label: "Students" },
    ...(can(config, "VIEW_PG_RESTART") ? [{ id: "restarts" as Tab, label: "Restarts" }] : []),
    ...(schoolWide && can(config, "VIEW_PG_ACADEMIC_HISTORY") ? [{ id: "reconcile" as Tab, label: "Reconciliation" }] : []),
    { id: "quality", label: "Data quality" }, { id: "setup", label: "Stage setup" },
  ];

  const counts = useRead<{ session: string; rows: StageCount[] }>(tab === "stages" ? `/counts?session=${encodeURIComponent(session)}` : null, reload);
  const params = new URLSearchParams({ session, page: String(page), size: "50" });
  if (qual) params.set("qualification", qual);
  if (stage) params.set("stage", stage);
  if (cat) params.set("category", cat);
  if (rec) params.set("recommendation", rec);
  if (off) params.set("official", off);
  if (q.trim()) params.set("q", q.trim());
  const students = useRead<StudentsPage>(tab === "students" ? `/students?${params}` : null, reload);
  const restarts = useRead<RestartRow[]>(tab === "restarts" ? `/restarts${restartState ? `?state=${restartState}` : ""}` : null, reload);
  const scan = useRead<Scan>(tab === "reconcile" ? `/reconciliation?session=${encodeURIComponent(session)}${conf ? `&confidence=${conf}` : ""}${rq.trim() ? `&q=${encodeURIComponent(rq.trim())}` : ""}&size=200` : null, reload);
  const quality = useRead<Quality>(tab === "quality" ? `/quality?session=${encodeURIComponent(session)}${issue ? `&issue=${issue}` : ""}&size=300` : null, reload);

  const openStudents = (stageCode: string | null, qualification: string, beyond = false) => {
    setQual(qualification); setStage(beyond ? "BEYOND" : stageCode ?? ""); setCat(""); setRec(""); setOff(""); setPage(0); setChosen([]); setTab("students");
  };

  async function progress() {
    const r = await call<Outcomes>("/progress", { method: "POST", body: JSON.stringify({ studentIds: chosen, session }), reason: `Postgraduate stages recorded for ${session}` });
    if (!r.ok) { notifyProblem(r.problem); return; }
    toast.success("Stages recorded.", outcomeText(r.data.outcomes));
    setChosen([]); bump();
  }

  const sessionPick = (
    <Field id="pg-session" label="Session">
      <select id="pg-session" className="ctl" value={session} onChange={(e) => { setSession(e.target.value); setPage(0); setChosen([]); }}>
        {config.sessions.map((s) => <option key={s} value={s}>{s}{s === config.session ? " (the PG School's session)" : ""}</option>)}
      </select>
    </Field>
  );
  const stagesOf = (qc: string) => config.stages.filter((s) => s.qualification === qc && s.active);

  return (
    <>
      <Panel title="Postgraduate stages and cycles" right={config.boundDept ? "Your department" : config.boundFaculty ? "Your faculty" : "The whole School"}>
        <PBody>
          <div className="sub2 mb-2">
            A PG student&rsquo;s level is the qualification; within it they move a stage a year, each with a first and second semester: <b>700 Level</b> and <b>700 Extension</b>;
            {" "}<b>800 A</b>, <b>800 B</b> and <b>800 C</b> (extension); <b>900 A</b> to <b>900 C</b>, then <b>900 D</b> and <b>900 E</b> (extensions). The first stage of a cycle is <b>fresh</b> for
            fees, every later one <b>returning</b>. A stage not yet recorded by the School is calculated from the calendar; nothing moves by itself. After the last extension the cycle
            is exhausted, and a restart is a new cycle — the old one is kept.
          </div>
          <Tabs label="Postgraduate academic management" value={tab} onChange={(t) => setTab(t)} items={tabs} />
        </PBody>
      </Panel>

      {tab === "stages" ? (
        <Panel title={`By stage, ${session}`} right={sessionPick}>
          {counts.loading ? <PBody><div className="row row--tight sub2" role="status"><Spinner /> Counting the students of each stage…</div></PBody>
            : counts.problem ? <PBody><Note kind="bad" title="The counts could not be read">{counts.problem.detail ?? counts.problem.title}</Note></PBody>
            : counts.data ? config.qualifications.map((qq) => {
              const rows = counts.data!.rows.filter((r) => r.qualification === qq.code);
              const total = rows.reduce((n, r) => n + Number(r.students), 0);
              return (
                <PBody key={qq.code}>
                  <div className="row row--tight mb-1"><strong>{qq.label}</strong><span className="sub2">{qq.level} Level · {qq.normal_years} year{qq.normal_years === 1 ? "" : "s"} and {qq.extension_years} extension year{qq.extension_years === 1 ? "" : "s"} · {total.toLocaleString()} students</span></div>
                  <DTable cols={["Stage", "Students|num", "Male|num", "Female|num", "Fresh|num", "Returning|num", "Recorded|num", "Registered|num", "Paid|num"]} rows={rows.map((r) => [
                    <span key="s" className="row row--tight">
                      <Btn kind="ghost" onClick={() => openStudents(r.stage_code, qq.code, r.stage_code === null)}>{r.stage_label}</Btn>
                      {r.is_extension ? <Pil kind="warn">Extension</Pil> : null}{r.stage_code === null ? <Pil kind="bad">Action needed</Pil> : null}
                    </span>,
                    <span key="n" className="tnum">{Number(r.students).toLocaleString()}</span>,
                    <span key="m" className="tnum">{Number(r.male).toLocaleString()}</span>,
                    <span key="f" className="tnum">{Number(r.female).toLocaleString()}</span>,
                    <span key="fr" className="tnum">{Number(r.fresh).toLocaleString()}</span>,
                    <span key="rt" className="tnum">{Number(r.returning).toLocaleString()}</span>,
                    <span key="o" className="tnum">{Number(r.official).toLocaleString()} <span className="sub2">({pct(Number(r.official), Number(r.students))})</span></span>,
                    <span key="g" className="tnum">{Number(r.registered).toLocaleString()}</span>,
                    <span key="p" className="tnum">{Number(r.paid).toLocaleString()}</span>,
                  ])} />
                </PBody>
              );
            }) : null}
        </Panel>
      ) : null}

      {tab === "students" ? (
        <Panel title={`Students, ${session}`} right={students.data ? `${students.data.total.toLocaleString()} students` : undefined}>
          <PBody>
            <div className="row row--end" style={{ flexWrap: "wrap" }}>
              {sessionPick}
              <Field id="pg-qual" label="Qualification">
                <select id="pg-qual" className="ctl" value={qual} onChange={(e) => { setQual(e.target.value); setStage(""); setPage(0); }}>
                  <option value="">Every qualification</option>
                  {config.qualifications.map((x) => <option key={x.code} value={x.code}>{x.label}</option>)}
                </select>
              </Field>
              <Field id="pg-stage" label="Stage">
                <select id="pg-stage" className="ctl" value={stage} onChange={(e) => { setStage(e.target.value); setPage(0); }}>
                  <option value="">Every stage</option>
                  {(qual ? stagesOf(qual) : config.stages.filter((s) => s.active)).map((s) => <option key={s.code} value={s.code}>{s.label}</option>)}
                  <option value="BEYOND">Past the maximum period</option>
                </select>
              </Field>
              <Field id="pg-cat" label="Fee category">
                <select id="pg-cat" className="ctl" value={cat} onChange={(e) => { setCat(e.target.value); setPage(0); }}>
                  <option value="">Fresh and returning</option><option value="FRESH">Fresh</option><option value="RETURNING">Returning</option>
                </select>
              </Field>
              <Field id="pg-rec" label="Recommendation">
                <select id="pg-rec" className="ctl" value={rec} onChange={(e) => { setRec(e.target.value); setPage(0); }}>
                  <option value="">Any</option>
                  {(Object.keys(RECOMMENDATION_WORDS) as Recommendation[]).map((k) => <option key={k} value={k}>{RECOMMENDATION_WORDS[k][0]}</option>)}
                </select>
              </Field>
              <Field id="pg-off" label="Stage">
                <select id="pg-off" className="ctl" value={off} onChange={(e) => { setOff(e.target.value); setPage(0); }}>
                  <option value="">Recorded or calculated</option><option value="true">Recorded by the School</option><option value="false">Calculated only</option>
                </select>
              </Field>
              <Field id="pg-q" label="Search">
                <input id="pg-q" className="ctl" value={q} placeholder="Name or matriculation number" onChange={(e) => { setQ(e.target.value); setPage(0); }} />
              </Field>
            </div>
            {chosen.length ? (
              <div className="row mt-2">
                <span className="sub2">{chosen.length} selected</span>
                {can(config, "MANAGE_PG_PROGRESSION") ? <Btn kind="primary" busyLabel="Recording the stages…" onClick={progress}>Record the stage for {session}</Btn> : null}
                {can(config, "MANAGE_PG_ACADEMIC_CYCLE") ? <Btn kind="secondary" onClick={() => setClosing(true)}>Close as exhausted</Btn> : null}
                <Btn kind="ghost" onClick={() => setChosen([])}>Clear selection</Btn>
              </div>
            ) : null}
          </PBody>
          {students.loading ? <PBody><div className="row row--tight sub2" role="status"><Spinner /> Reading the students…</div></PBody>
            : students.problem ? <PBody><Note kind="bad" title="The students could not be read">{students.problem.detail ?? students.problem.title}</Note></PBody>
            : students.data ? (
              <>
                <DTable cols={["|mid", "S/N|num", "Student", "Programme", "Stage", "Category", "Recommendation", "Cycle", "Registered", "Paid", "|num"]} rows={students.data.rows.map((r, i) => [
                  <input key="c" type="checkbox" className="pchk" aria-label={`Select ${r.surname}, ${r.other_names}`} checked={chosen.includes(r.student_id)}
                    onChange={() => setChosen((cur) => (cur.includes(r.student_id) ? cur.filter((x) => x !== r.student_id) : [...cur, r.student_id]))} />,
                  <span key="n" className="tnum sub2">{page * 50 + i + 1}</span>,
                  <span key="s"><strong>{r.surname}, {r.other_names}</strong><span className="sub2" style={{ display: "block" }}>{r.matric_no ?? r.admission_no ?? "—"}</span></span>,
                  <span key="p" className="sub2">{r.programme}{r.department ? <span style={{ display: "block" }}>{r.department}</span> : null}</span>,
                  <span key="g">{stageText(r)}{r.stage_code && !r.official ? <> <Pil kind="grey" title="Calculated from the calendar; the School has not recorded it">Calculated</Pil></> : null}</span>,
                  <span key="k" className="sub2">{r.category === "FRESH" ? "Fresh" : r.category === "RETURNING" ? "Returning" : "—"}</span>,
                  <Pil key="r" kind={RECOMMENDATION_WORDS[r.recommendation]?.[1] ?? "grey"}>{RECOMMENDATION_WORDS[r.recommendation]?.[0] ?? r.recommendation}</Pil>,
                  <span key="y" className="sub2">{r.cycle_no} · {CYCLE_WORDS[r.cycle_status]?.[0] ?? r.cycle_status}{r.open_restart ? <span style={{ display: "block" }}>{r.open_restart}</span> : null}</span>,
                  <Pil key="re" kind={r.registered ? "ok" : "grey"}>{r.registered ? "Yes" : "No"}</Pil>,
                  <Pil key="pa" kind={r.paid ? "ok" : "grey"}>{r.paid ? "Yes" : "No"}</Pil>,
                  <span key="x" className="row row--tight row--right">
                    <IcoBtn icon="clock" label={`History of ${r.surname}, ${r.other_names}`} onClick={() => setHistoryOf(r)} />
                    {can(config, "REQUEST_PG_RESTART") && !r.open_restart && (r.recommendation === "RESTART_REQUIRED" || r.recommendation === "MAXIMUM_PERIOD_REACHED") && r.cycle_id
                      ? <IcoBtn icon="swap" label={`Request a restart for ${r.surname}, ${r.other_names}`} onClick={() => setRestartFor(r)} /> : null}
                  </span>,
                ])} />
                {students.data.total > 50 ? (
                  <PBody>
                    <div className="row row--right">
                      <Btn kind="ghost" disabled={page <= 0} onClick={() => setPage((p) => p - 1)}>Previous</Btn>
                      <span className="sub2">Page {page + 1} of {Math.ceil(students.data.total / 50)}</span>
                      <Btn kind="ghost" disabled={(page + 1) * 50 >= students.data.total} onClick={() => setPage((p) => p + 1)}>Next</Btn>
                    </div>
                  </PBody>
                ) : null}
                {!students.data.rows.length ? <PBody><div className="sub2">No student matches.</div></PBody> : null}
              </>
            ) : null}
        </Panel>
      ) : null}

      {tab === "restarts" ? (
        <Panel title="Restart requests" right={
          <Field id="pg-rst" label="State">
            <select id="pg-rst" className="ctl" value={restartState} onChange={(e) => setRestartState(e.target.value)}>
              <option value="OPEN">Open</option><option value="">Every request</option>
              {(Object.keys(RESTART_WORDS) as (keyof typeof RESTART_WORDS)[]).map((k) => <option key={k} value={k}>{RESTART_WORDS[k][0]}</option>)}
            </select>
          </Field>}>
          <PBody><div className="sub2">A restart is asked for once a cycle has exhausted its maximum period. The department recommends it, the Dean of the PG School decides; an approval opens the next cycle at its first stage (fresh) and keeps the old one.</div></PBody>
          {restarts.loading ? <PBody><div className="row row--tight sub2" role="status"><Spinner /> Reading the requests…</div></PBody>
            : restarts.problem ? <PBody><Note kind="bad" title="The requests could not be read">{restarts.problem.detail ?? restarts.problem.title}</Note></PBody>
            : restarts.data ? (
              restarts.data.length ? (
                <DTable cols={["Reference", "Student", "Cycle", "New cycle from", "State", "Reason", "|num"]} rows={restarts.data.map((r) => [
                  <span key="r" className="tnum">{r.reference}</span>,
                  <span key="s"><strong>{r.surname}, {r.other_names}</strong><span className="sub2" style={{ display: "block" }}>{r.matric_no ?? "—"} · {r.programme}</span></span>,
                  <span key="c" className="sub2">{r.qualification} cycle {r.cycle_no}{r.new_cycle_no ? ` → ${r.new_cycle_no}` : ""}</span>,
                  <span key="f" className="tnum">{r.start_session}</span>,
                  <Pil key="st" kind={RESTART_WORDS[r.state][1]}>{RESTART_WORDS[r.state][0]}</Pil>,
                  <span key="w" className="sub2">{r.reason}{r.dept_note ? <span style={{ display: "block" }}>Department: {r.dept_note}</span> : null}{r.decision_note ? <span style={{ display: "block" }}>School: {r.decision_note}</span> : null}</span>,
                  <span key="x" className="row row--tight row--right">
                    {r.state === "REQUESTED" && can(config, "RECOMMEND_PG_RESTART") ? <Btn kind="secondary" onClick={() => setDeciding({ row: r, act: "recommend" })}>Recommend…</Btn> : null}
                    {r.state === "UNDER_REVIEW" && can(config, "APPROVE_PG_RESTART") && !r.mine ? <Btn kind="primary" onClick={() => setDeciding({ row: r, act: "decide" })}>Decide…</Btn> : null}
                    {(r.state === "REQUESTED" || r.state === "UNDER_REVIEW") && (can(config, "MANAGE_PG_ACADEMIC_CYCLE") || r.mine) ? <Btn kind="ghost" onClick={() => setDeciding({ row: r, act: "cancel" })}>Withdraw</Btn> : null}
                  </span>,
                ])} />
              ) : <PBody><div className="sub2">No request.</div></PBody>
            ) : null}
        </Panel>
      ) : null}

      {tab === "reconcile" ? (
        <Panel title={`Reconciliation of the PG register, ${session}`} right={sessionPick}>
          <PBody>
            <div className="sub2 mb-2">The PG students with no cycle recorded, read from their admission session and programme. Nothing changes until it is recorded: each becomes cycle 1 — active, with this session&rsquo;s stage recorded; or exhausted, when past the maximum period (then no stage&rsquo;s fee reaches the student until a restart; while the cycle is open they pay the last stage&rsquo;s, V693); or graduated. A reading of low confidence (no qualification or no admission session) is never recorded; put the record right first.</div>
            {scan.data ? (
              <>
                <Tiles items={[
                  ["To reconcile", scan.data.total.toLocaleString(), null, "No cycle recorded"],
                  ["High confidence", String(scan.data.byConfidence.HIGH ?? 0), "var(--green-ink)", "Programme and level agree"],
                  ["Medium", String(scan.data.byConfidence.MEDIUM ?? 0), scan.data.byConfidence.MEDIUM ? "var(--amber-ink)" : null, "The record's level is not the programme's"],
                  ["Low", String(scan.data.byConfidence.LOW ?? 0), scan.data.byConfidence.LOW ? "var(--red-ink)" : null, "Not recorded"],
                ]} />
                <div className="sub2 mt-2">{Object.entries(scan.data.byRecommendation).map(([k, n]) => `${n.toLocaleString()} ${(RECOMMENDATION_WORDS[k as Recommendation]?.[0] ?? k).toLowerCase()}`).join(" · ")}</div>
              </>
            ) : null}
            <div className="row row--end mt-2" style={{ flexWrap: "wrap" }}>
              <Field id="rc-conf" label="Confidence">
                <select id="rc-conf" className="ctl" value={conf} onChange={(e) => setConf(e.target.value)}>
                  <option value="">Every reading</option><option value="HIGH">High</option><option value="MEDIUM">Medium</option><option value="LOW">Low</option>
                </select>
              </Field>
              <Field id="rc-q" label="Search"><input id="rc-q" className="ctl" value={rq} onChange={(e) => setRq(e.target.value)} placeholder="Name, number or programme" /></Field>
              <span className="grow" />
              {can(config, "MANAGE_PG_ACADEMIC_CYCLE") ? (
                <>
                  <Btn kind="secondary" disabled={!picked.length} onClick={() => setCommitting("selected")}>Record the selected ({picked.length})</Btn>
                  <Btn kind="primary" disabled={!scan.data || !((scan.data.byConfidence.HIGH ?? 0) + (scan.data.byConfidence.MEDIUM ?? 0))} onClick={() => setCommitting("all")}>
                    Record every high and medium reading
                  </Btn>
                </>
              ) : null}
            </div>
          </PBody>
          {scan.loading ? <PBody><div className="row row--tight sub2" role="status"><Spinner /> Reading the register…</div></PBody>
            : scan.problem ? <PBody><Note kind="bad" title="The register could not be read">{scan.problem.detail ?? scan.problem.title}</Note></PBody>
            : scan.data && scan.data.rows.length ? (
              <DTable cols={["|mid", "Student", "Programme", "Admitted", "Stage in " + session, "Recommendation", "Confidence", "Notes"]} rows={scan.data.rows.map((r) => [
                r.confidence === "LOW" ? <span key="c" /> : <input key="c" type="checkbox" className="pchk" aria-label={`Select ${r.surname}, ${r.other_names}`} checked={picked.includes(r.student_id)}
                  onChange={() => setPicked((cur) => (cur.includes(r.student_id) ? cur.filter((x) => x !== r.student_id) : [...cur, r.student_id]))} />,
                <span key="s"><strong>{r.surname}, {r.other_names}</strong><span className="sub2" style={{ display: "block" }}>{r.matric_no ?? "—"} · {r.current_level ?? "—"} Level</span></span>,
                <span key="p" className="sub2">{r.programme}</span>,
                <span key="a" className="tnum">{r.entry_session ?? "—"}</span>,
                <span key="g">{stageText(r)}{r.category ? <span className="sub2"> · {r.category === "FRESH" ? "fresh" : "returning"}</span> : null}</span>,
                <Pil key="r" kind={RECOMMENDATION_WORDS[r.recommendation]?.[1] ?? "grey"}>{RECOMMENDATION_WORDS[r.recommendation]?.[0] ?? r.recommendation}</Pil>,
                <Pil key="k" kind={r.confidence === "HIGH" ? "ok" : r.confidence === "MEDIUM" ? "warn" : "bad"}>{r.confidence === "HIGH" ? "High" : r.confidence === "MEDIUM" ? "Medium" : "Low"}</Pil>,
                <span key="n" className="sub2">{r.notes.join("; ") || "—"}</span>,
              ])} />
            ) : scan.data ? <PBody><div className="sub2">Every PG student&rsquo;s cycle is recorded.</div></PBody> : null}
        </Panel>
      ) : null}

      {tab === "quality" ? (
        <Panel title={`Data quality, ${session}`} right={sessionPick}>
          <PBody>
            <div className="sub2 mb-2">What is wrong or unrecorded on the PG register — listed, never put right by itself. Choose an issue to list its students.</div>
            {quality.data ? (
              <div className="row" style={{ flexWrap: "wrap" }}>
                <Btn kind={issue ? "ghost" : "secondary"} onClick={() => setIssue("")}>Every issue ({Object.values(quality.data.byIssue).reduce((a, b) => a + b, 0).toLocaleString()})</Btn>
                {Object.entries(quality.data.byIssue).map(([k, n]) => <Btn key={k} kind={issue === k ? "secondary" : "ghost"} onClick={() => setIssue(k)}>{ISSUE_WORDS[k] ?? k} ({n.toLocaleString()})</Btn>)}
              </div>
            ) : null}
          </PBody>
          {quality.loading ? <PBody><div className="row row--tight sub2" role="status"><Spinner /> Reading the register…</div></PBody>
            : quality.problem ? <PBody><Note kind="bad" title="The register could not be read">{quality.problem.detail ?? quality.problem.title}</Note></PBody>
            : quality.data && quality.data.rows.length ? (
              <DTable cols={["Issue", "Student", "Programme", "Detail"]} rows={quality.data.rows.map((r) => [
                <span key="i">{ISSUE_WORDS[r.issue] ?? r.issue}</span>,
                <span key="s"><strong>{r.surname}, {r.other_names}</strong><span className="sub2" style={{ display: "block" }}>{r.matric_no ?? "—"}</span></span>,
                <span key="p" className="sub2">{r.programme}{r.department ? ` · ${r.department}` : ""}</span>,
                <span key="d" className="sub2">{r.detail}</span>,
              ])} />
            ) : quality.data ? <PBody><div className="sub2">Nothing to put right.</div></PBody> : null}
        </Panel>
      ) : null}

      {tab === "setup" ? (
        <Panel title="Stage setup" right={can(config, "MANAGE_PG_LEVEL_STRUCTURE") ? "The Dean of the PG School changes it" : "Read only"}>
          {config.qualifications.map((qq) => (
            <PBody key={qq.code}>
              <div className="row row--tight mb-1">
                <strong>{qq.label}</strong>
                <span className="sub2">{qq.level} Level · normal {qq.normal_years} year{qq.normal_years === 1 ? "" : "s"} · extension {qq.extension_years} year{qq.extension_years === 1 ? "" : "s"} · maximum {qq.normal_years + qq.extension_years} · {qq.restart_allowed ? "restart allowed after the maximum" : "no restart"}</span>
                <span className="grow" />
                {can(config, "MANAGE_PG_LEVEL_STRUCTURE") ? <Btn kind="ghost" onClick={() => setEditing(qq.code)}>Edit</Btn> : null}
              </div>
              <DTable cols={["Sequence|num", "Stage", "Short label", "Kind", "Semesters", "Next stage"]} rows={stagesOf(qq.code).map((s) => [
                <span key="n" className="tnum">{s.sequence}</span>,
                <strong key="l">{s.label}</strong>,
                <span key="s" className="sub2">{s.short_label}</span>,
                <span key="k">{s.is_extension ? <Pil kind="warn">Extension {s.extension_number}</Pil> : <Pil kind="ok">Year {s.year_number}</Pil>}{s.sequence === 1 ? <span className="sub2"> · fresh</span> : <span className="sub2"> · returning</span>}</span>,
                <span key="m" className="sub2">{s.semesters.map((x) => (x === 1 ? "First" : x === 2 ? "Second" : "Third")).join(", ")}</span>,
                <span key="x" className="sub2">{s.next_label ?? (qq.restart_allowed ? "None — the maximum; a restart after it" : "None — the maximum")}</span>,
              ])} />
            </PBody>
          ))}
        </Panel>
      ) : null}

      {historyOf ? <HistoryModal row={historyOf} session={session} onClose={() => setHistoryOf(null)} /> : null}
      {restartFor ? <RestartModal row={restartFor} config={config} onClose={() => setRestartFor(null)} onDone={() => { setRestartFor(null); bump(); }} /> : null}
      {closing ? <CloseModal ids={chosen} onClose={() => setClosing(false)} onDone={() => { setClosing(false); setChosen([]); bump(); }} /> : null}
      {deciding ? <DecideModal {...deciding} onClose={() => setDeciding(null)} onDone={() => { setDeciding(null); bump(); }} /> : null}
      {committing ? <CommitModal session={session} ids={committing === "all" ? null : picked} count={committing === "all" ? (scan.data?.byConfidence.HIGH ?? 0) + (scan.data?.byConfidence.MEDIUM ?? 0) : picked.length}
        onClose={() => setCommitting(null)} onDone={() => { setCommitting(null); setPicked([]); bump(); }} /> : null}
      {editing ? <SetupModal config={config} code={editing} onClose={() => setEditing(null)} onDone={() => { setEditing(null); notify("Stage setup saved."); window.location.reload(); }} /> : null}
    </>
  );
}

function HistoryModal({ row, session, onClose }: { row: StageRow; session: string; onClose: () => void }) {
  const d = usePgHistory(row.student_id, session);
  return (
    <Modal wide title={`${row.surname}, ${row.other_names}`} sub={`${row.matric_no ?? row.admission_no ?? ""} · ${row.programme}`} onClose={onClose}
      foot={<><span className="grow" /><Btn kind="secondary" onClick={onClose}>Close</Btn></>}>
      {!d ? <div className="row row--tight sub2" role="status"><Spinner /> Reading the history…</div>
        : d.h ? <PgHistoryBody h={d.h} /> : <Note kind="bad" title="The history could not be read">{d.failed}</Note>}
    </Modal>
  );
}

function RestartModal({ row, config, onClose, onDone }: { row: StageRow; config: Config; onClose: () => void; onDone: () => void }) {
  const later = config.sessions.filter((s) => s > (config.session ?? "")).sort();
  const [start, setStart] = useState(later[0] ?? config.session ?? "");
  const [why, setWhy] = useState("");
  async function send() {
    const r = await call<{ reference: string }>("/restarts", { method: "POST", body: JSON.stringify({ studentId: row.student_id, startSession: start, reason: why.trim() }), reason: why.trim() });
    if (!r.ok) { notifyProblem(r.problem); return; }
    toast.success(`Restart ${r.data.reference} requested.`, "The department recommends it; the Dean of the PG School decides.");
    onDone();
  }
  return (
    <Modal title="Request a restart" sub={`${row.surname}, ${row.other_names} · cycle ${row.cycle_no}`} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={why.trim().length < 10 || !start} busyLabel="Requesting…" onClick={send}>Request the restart</Btn></>}>
      <Note kind="info" title="A restart is a new cycle">The student begins again at the first stage of the qualification (fresh), in the session chosen. The old cycle and everything in it — registrations, results, payments, research — is kept.</Note>
      <Field id="rs-start" label="New cycle begins in" hint="A session after the old cycle's last">
        <select id="rs-start" className="ctl" value={start} onChange={(e) => setStart(e.target.value)}>
          {[...(config.session ? [config.session] : []), ...later].filter((v, i, a) => a.indexOf(v) === i).map((s) => <option key={s} value={s}>{s}</option>)}
        </select>
      </Field>
      <Field id="rs-why" label="Reason" hint="Ten characters at least"><textarea id="rs-why" className="ctl" rows={3} value={why} maxLength={1000} onChange={(e) => setWhy(e.target.value)} /></Field>
    </Modal>
  );
}

function CloseModal({ ids, onClose, onDone }: { ids: string[]; onClose: () => void; onDone: () => void }) {
  const [why, setWhy] = useState("");
  async function send() {
    const r = await call<Outcomes>("/close-exhausted", { method: "POST", body: JSON.stringify({ studentIds: ids, reason: why.trim() }), reason: why.trim() });
    if (!r.ok) { notifyProblem(r.problem); return; }
    toast.success(`${(r.data.outcomes.CLOSED ?? 0).toLocaleString()} cycle${r.data.outcomes.CLOSED === 1 ? "" : "s"} closed as exhausted.`,
      r.data.skipped ? `${r.data.skipped} not past the maximum period, or with no active cycle recorded, were left as they are.` : undefined);
    onDone();
  }
  return (
    <Modal title="Close as exhausted" sub={`${ids.length} selected`} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" /><Btn kind="urgent" disabled={why.trim().length < 10} busyLabel="Closing the cycles…" onClick={send}>Close the cycles</Btn></>}>
      <div className="sub2">Only the active cycles past the maximum period are closed, as <b>maximum period exhausted</b>; the others are left as they are. A closed cycle is kept with everything in it; the student may then be restarted in a new cycle. Until then no stage&rsquo;s fee reaches them: while the cycle is open they pay the last stage&rsquo;s (800 C, 900 E, 700 Extension).</div>
      <Field id="cl-why" label="Reason" hint="Ten characters at least"><input id="cl-why" className="ctl" value={why} maxLength={400} onChange={(e) => setWhy(e.target.value)} /></Field>
    </Modal>
  );
}

function DecideModal({ row, act, onClose, onDone }: { row: RestartRow; act: "recommend" | "decide" | "cancel"; onClose: () => void; onDone: () => void }) {
  const [note, setNote] = useState("");
  async function send(yes: boolean) {
    const path = `/restarts/${restartPath(row.reference)}/${act}`;
    const body = act === "recommend" ? { recommend: yes, note: note.trim() || null } : act === "decide" ? { approve: yes, note: note.trim() || null } : { note: note.trim() || null };
    const r = await call<{ state: string }>(path, { method: "POST", body: JSON.stringify(body), reason: note.trim() || `Restart ${row.reference}` });
    if (!r.ok) { notifyProblem(r.problem); return; }
    toast.success(`${row.reference}: ${RESTART_WORDS[r.data.state as keyof typeof RESTART_WORDS]?.[0] ?? r.data.state}.`, act === "decide" && yes ? "The new cycle is open at its first stage." : undefined);
    onDone();
  }
  const title = act === "recommend" ? "The department's recommendation" : act === "decide" ? "The PG School's decision" : "Withdraw the request";
  return (
    <Modal title={title} sub={`${row.reference} · ${row.surname}, ${row.other_names}`} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" />
        {act === "cancel" ? <Btn kind="urgent" busyLabel="Withdrawing…" onClick={() => send(true)}>Withdraw the request</Btn> : (
          <>
            <Btn kind="secondary" disabled={note.trim().length < 10} busyLabel="Saving…" onClick={() => send(false)}>{act === "recommend" ? "Do not recommend" : "Reject"}</Btn>
            <Btn kind="primary" busyLabel="Saving…" onClick={() => send(true)}>{act === "recommend" ? "Recommend" : "Approve the restart"}</Btn>
          </>
        )}</>}>
      <div className="sub2 mb-2">{row.reason}</div>
      {row.dept_note ? <div className="sub2 mb-2">Department: {row.dept_note}</div> : null}
      {act === "decide" ? <Note kind="info" title={`A new cycle from ${row.start_session}`}>Approving opens cycle {row.cycle_no + 1} at the first stage (fresh) and closes cycle {row.cycle_no} as exhausted, everything in it kept.</Note> : null}
      <Field id="dc-note" label="Note" hint={act === "cancel" ? "Optional" : "Required to refuse (ten characters at least)"}><textarea id="dc-note" className="ctl" rows={3} value={note} maxLength={1000} onChange={(e) => setNote(e.target.value)} /></Field>
    </Modal>
  );
}

function CommitModal({ session, ids, count, onClose, onDone }: { session: string; ids: string[] | null; count: number; onClose: () => void; onDone: () => void }) {
  const [why, setWhy] = useState("");
  async function send() {
    const r = await call<Outcomes>("/reconciliation/commit", { method: "POST", body: JSON.stringify({ studentIds: ids, all: ids === null, session, reason: why.trim() || null }),
      reason: why.trim() || `Postgraduate cycles recorded for ${session}` });
    if (!r.ok) { notifyProblem(r.problem); return; }
    toast.success("Cycles recorded.", Object.entries(r.data.byStatus ?? {}).map(([k, n]) => `${n.toLocaleString()} ${(CYCLE_WORDS[k as keyof typeof CYCLE_WORDS]?.[0] ?? k).toLowerCase()}`).join(", ") || outcomeText(r.data.outcomes));
    onDone();
  }
  return (
    <Modal title="Record the cycles" sub={`${count.toLocaleString()} student${count === 1 ? "" : "s"} · ${session}`} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" /><Btn kind="primary" busyLabel="Recording the cycles…" onClick={send}>Record {count.toLocaleString()} cycle{count === 1 ? "" : "s"}</Btn></>}>
      <div className="sub2">Each becomes cycle 1 from its admission session: active with the stage of {session} recorded, or exhausted (past the maximum period), or graduated. The student&rsquo;s record itself does not change.</div>
      <Field id="cm-why" label="Note" hint="Optional; kept with the change"><input id="cm-why" className="ctl" value={why} maxLength={400} onChange={(e) => setWhy(e.target.value)} /></Field>
    </Modal>
  );
}

function SetupModal({ config, code, onClose, onDone }: { config: Config; code: string; onClose: () => void; onDone: () => void }) {
  const q = config.qualifications.find((x) => x.code === code)!;
  const [normal, setNormal] = useState(String(q.normal_years));
  const [ext, setExt] = useState(String(q.extension_years));
  const [restart, setRestart] = useState(q.restart_allowed);
  const current = config.stages.filter((s) => s.qualification === code && s.active);
  const n = (Number(normal) || 0) + (Number(ext) || 0);
  const [labels, setLabels] = useState<string[]>(current.map((s) => s.label));
  async function send() {
    const r = await call<Config>(`/config/${code}`, { method: "PUT", body: JSON.stringify({ normalYears: Number(normal), extensionYears: Number(ext), restartAllowed: restart,
      labels: Array.from({ length: n }, (_, i) => (labels[i] ?? "").trim() || null) }), reason: `Postgraduate stage setup changed for ${q.label}` });
    if (!r.ok) { notifyProblem(r.problem); return; }
    onDone();
  }
  return (
    <Modal title={`Stage setup · ${q.label}`} sub={`${q.level} Level`} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={n < 1 || n > 10} busyLabel="Saving the setup…" onClick={send}>Save the setup</Btn></>}>
      <div className="grid grid--2">
        <Field id="su-n" label="Normal years"><input id="su-n" className="ctl tnum" inputMode="numeric" value={normal} onChange={(e) => setNormal(e.target.value.replace(/[^0-9]/g, ""))} /></Field>
        <Field id="su-e" label="Extension years"><input id="su-e" className="ctl tnum" inputMode="numeric" value={ext} onChange={(e) => setExt(e.target.value.replace(/[^0-9]/g, ""))} /></Field>
      </div>
      <label className="sub2 row row--tight" style={{ gap: 6 }}><input type="checkbox" className="pchk" checked={restart} onChange={(e) => setRestart(e.target.checked)} /> A student past the maximum period may restart in a new cycle</label>
      <div className="sub2 mt-2 mb-1">Labels of the {n} stage{n === 1 ? "" : "s"} (blank for the University&rsquo;s usual wording):</div>
      {Array.from({ length: Math.max(0, Math.min(n, 10)) }, (_, i) => (
        <Field key={i} id={`su-l${i}`} label={`Stage ${i + 1} — ${i < (Number(normal) || 0) ? `year ${i + 1}` : `extension ${i + 1 - (Number(normal) || 0)}`}`}>
          <input id={`su-l${i}`} className="ctl" value={labels[i] ?? ""} maxLength={60} onChange={(e) => setLabels((cur) => { const c = [...cur]; c[i] = e.target.value; return c; })} />
        </Field>
      ))}
      <Note kind="info" title="What changes">Stages past the new total are taken out of use, never deleted; it is refused while students of the running session are recorded at one. Fee lines name a stage, so state the new stage&rsquo;s fees before its students reach it.</Note>
    </Modal>
  );
}
