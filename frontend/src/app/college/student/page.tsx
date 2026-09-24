import Link from "next/link";
import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { loadStudent } from "../../student/load";
import { api } from "@/lib/api";
import { BLOCKS, COMMON_RULES, MBBS, PHASES, PROGRESSION, phaseOf, SEMESTERS } from "@/lib/mbbs";
import { RegisterButton } from "./RegisterButton";

export const dynamic = "force-dynamic";

/**
 * /college/student — the College of Health Sciences student's journey (V248): the levels 100 to 600 as a ladder, and
 * at the level in hand the three steps — pay the level's fees, register the fixed curriculum, sit the examination and
 * see the decision. Four views: the dashboard, fees, registration, the results history. 100 Level runs on the
 * University's courses and GPA sheet; the College's own 100 Level rule (every C-group course at 50, no resit) decides
 * promotion to 200, read from those results. From 200 Level the Professional examinations decide: the rule applies
 * provisionally, the College Academic Board confirms.
 */
interface Exam { id: string; code: string; name: string; level: number; papers: string[]; resit_allowed: boolean; resit_window_months: number; no_resit_if_all_failed: boolean; appeal_to_senate: boolean; min_attendance_pct: number | null; on_failure: string }
interface Enrolment { id: string; level: number; session: string; attempt_no: number; kind: string; state: string; registered_at: string | null; registered_items: number | null; first_cleared: boolean; second_cleared: boolean; resit_names: string | null; semesters: string; year_ends_on: string | null; year_reached_final: boolean }
interface YearSemester { ordinal: number; name: string; length_weeks: number | null; subjects: string | null; registered_at: string | null; cleared: boolean; starts_on: string | null; ends_on: string | null }
interface Next { kind: "semester" | "year"; ordinal: number; name: string; session: string; cleared: boolean }
interface Result { session: string; level: number; exam: string; subject: string; ordinal: number; attempt: string; ca: number | null; exam_score: number | null; clinical: number | null; attendance: number | null; barred: boolean; total: number | null; passed: boolean | null; distinction: boolean | null }
interface Decision { level: number; session: string; outcome: string; state: string; rule_ref: string | null; minute: string | null; decided_on: string; confirmed_on: string | null; honours: boolean | null; carry_overs: string[]; resit_names: string | null }
interface MyRecord {
  student: { id: string; number: string; surname: string; other_names: string; programme: string; entry_mode: string; entry_session: string; entry_level: number; current_level: number; status: string };
  session: string; exams: Exam[]; enrolments: Enrolment[]; results: Result[]; decisions: Decision[];
  level100: { outcome: string | null; failed: string | null; carried: string | null; published: number; registered: number };
  carryOvers: { code: string; from_session: string; note: string | null; cleared_on: string | null }[];
  fees: { session: string; first_cleared: boolean; second_cleared: boolean }; current: Enrolment | null; canRegister: boolean; nextSession: string; next: Next | null;
}
const parseSem = (s: string | undefined): YearSemester[] => { try { return s ? (JSON.parse(s) as YearSemester[]) : []; } catch { return []; } };

const OUTCOME: Record<string, [string, "ok" | "bad" | "info" | "warn" | "grey"]> = {
  PROMOTE: ["Promoted", "ok"], GRADUATE: ["Passed the Final MBBS", "ok"], RESIT: ["Resit required", "warn"], REPEAT: ["Repeat the level", "warn"],
  WITHDRAW_ADVISED: ["Advised to withdraw", "bad"], WITHDRAW_REQUIRED: ["Required to withdraw", "bad"], APPEAL: ["Advised to withdraw · Senate appeal possible", "bad"],
};
const word = (s: string) => s.charAt(0) + s.slice(1).toLowerCase().replace(/_/g, " ");
const dayOf = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const VIEWS: [string, string][] = [["overview", "Dashboard"], ["fees", "Fees & payments"], ["registration", "Course registration"], ["results", "Results history"]];

export default async function CollegeStudentPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const view = typeof p.view === "string" && VIEWS.some((v) => v[0] === p.view) ? p.view : "overview";
  const loaded = await loadStudent();
  if (!loaded.student) {
    return <Shell route="s/dashboard" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  }
  const s = loaded.student;
  const level = Number(s.level);
  const [rec, mine] = await Promise.all([
    api<MyRecord>("/api/v1/college/my-record"),
    api<{ id: string; session: string; state: string; starts_on: string | null; ends_on: string | null; posting: string; posting_name: string; tier: string; duration_weeks: number | null; block_code: string; block: string; group_label: string | null; supervisor: string | null; requirements: number; requirements_met: number }[]>("/api/v1/college/my-postings"),
  ]);
  if (!rec.ok) {
    return <Shell route="s/dashboard" me={loaded.me}><ProblemNotice problem={rec.problem} /></Shell>;
  }
  const r = rec.data;
  const myPostings = mine.ok ? mine.data : [];
  const phase = PHASES.find((x) => x.phase === phaseOf(level));
  const step = PROGRESSION.find((x) => x.from === level);
  const examAt = r.exams.find((e) => e.level === level) ?? null;
  const cur = r.current;
  const yearSession = cur?.session ?? r.nextSession;   // the College year's session, not the University's
  const sems = parseSem(cur?.semesters);
  const semNow = sems.find((x) => x.starts_on && x.starts_on <= new Date().toISOString().slice(0, 10) && (!x.ends_on || x.ends_on >= new Date().toISOString().slice(0, 10))) ?? null;
  const de = s.entryMode === "DIRECT_ENTRY";
  const status = r.student.status;
  const active = ["ACTIVE", "PROBATION", "ADMITTED"].includes(status);

  // ── the journey: a level is passed when a confirmed decision promoted from it (100 by the College's rule from the University's results) ──
  const passedAt = (L: number) => (L === 100 ? r.level100.outcome === "PROMOTE" || (level > 100 && !de) : r.decisions.some((d) => d.level === L && d.state === "CONFIRMED" && (d.outcome === "PROMOTE" || d.outcome === "GRADUATE")));
  const attemptsAt = (L: number) => r.enrolments.filter((e) => e.level === L).length;
  const ladder = [100, 200, 300, 400, 500, 600].map((L) => {
    const passed = passedAt(L);
    const skipped = de && L === 100;
    const isCur = level === L && !passed;
    const st: "done" | "cur" | "stop" | "todo" | "skip" = skipped ? "skip" : passed ? "done" : isCur ? (active ? "cur" : "stop") : "todo";
    const ex = L === 100 ? "Sessional examinations" : (r.exams.find((e) => e.level === L)?.code ?? "");
    const sub = skipped ? "Direct Entry" : passed ? (attemptsAt(L) > 1 ? `Passed · ${attemptsAt(L)} attempts` : "Passed") : isCur ? (active ? (attemptsAt(L) > 1 ? `In progress · attempt ${attemptsAt(L)}` : "In progress") : word(status)) : "Upcoming";
    return { L, st, ex, sub };
  });
  const dot = (st: string) => ({
    width: 44, height: 44, borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center", fontWeight: 700, fontSize: 13, boxSizing: "border-box" as const,
    ...(st === "done" ? { background: "var(--green-ink)", color: "#fff" } : st === "cur" ? { background: "var(--panel)", color: "var(--green-ink)", border: "2px solid var(--green-ink)" }
      : st === "stop" ? { background: "var(--red-soft, #fbe7e4)", color: "var(--red-ink)", border: "2px solid var(--red-ink)" } : { background: "var(--panel-2, var(--line-2))", color: "var(--chrome-dim)", border: "1px solid var(--line)" }),
  });

  // ── the three steps at the level in hand ──
  const paidFirst = r.fees.first_cleared;
  const paidAll = r.fees.second_cleared;
  const registered = !!cur?.registered_at;
  const next = r.next;
  const latestDecision = [...r.decisions].reverse()[0] ?? null;
  const decisionHere = cur ? r.decisions.find((d) => d.level === cur.level && d.session === cur.session) ?? null : null;
  const stageIdx = next && !next.cleared ? 0 : next ? 1 : 2;
  const semWord = sems.length ? `semester ${semNow ? semNow.ordinal : sems.filter((x) => x.registered_at).length || 1} of ${sems.length}` : "";
  const stageLabel = !active ? word(status) : level === 100 ? "100 Level runs on the University's form" : next && !next.cleared ? `Awaiting fee payment · ${next.name}` : next ? `Awaiting registration · ${next.name}` : cur?.state === "RESIT" ? `Resit pending: ${cur.resit_names ?? ""}` : decisionHere ? (decisionHere.state === "CONFIRMED" ? "Decided" : "Provisional decision · awaiting the Board") : `Registered${semWord ? " · " + semWord : ""} · awaiting the ${examAt?.code ?? "examination"} at the end of the year`;
  const steps = [
    { label: next ? `Pay ${next.name} fees` : `Pay ${level} Level fees`, sub: paidAll ? `Paid in full · ${yearSession}` : paidFirst ? `First semester cleared · the second is due before its registration` : "Pending", done: next ? next.cleared : paidFirst },
    { label: sems.length ? "Register each semester's courses" : "Register courses and postings", sub: registered ? `${cur?.registered_items ?? 0} items registered · ${dayOf(cur?.registered_at ?? null)}` : sems.length ? `${sems.filter((x) => x.registered_at).length} of ${sems.length} semesters registered${next && next.cleared ? " · open now" : ""}` : next && next.cleared ? "Open now" : "Opens after payment", done: registered },
    { label: examAt ? `${examAt.name} · once, at the end of the year` : "Sessional examinations", sub: cur?.state === "RESIT" ? `Resit pending: ${cur.resit_names ?? ""}` : decisionHere ? (OUTCOME[decisionHere.outcome]?.[0] ?? decisionHere.outcome) + (decisionHere.state === "CONFIRMED" ? "" : " (provisional)") : registered ? (cur?.year_ends_on ? `The year runs to ${dayOf(cur.year_ends_on)}` : "Awaiting the examiners") : "After registration", done: !!decisionHere && decisionHere.state === "CONFIRMED" },
  ];
  const registerLabel = next ? (next.kind === "semester" ? `Register ${next.name}` : `Register ${level} Level · ${yearSession}`) : undefined;
  const items = (r.current?.registered_items ?? 0) || (BLOCKS.flatMap((b) => b.postings).filter((x) => (x.level.match(/\d{3}/g) ?? []).some((n) => Number(n) === level)).length + SEMESTERS.filter((x) => x.period.startsWith(`${level} Level`)).length + r.carryOvers.filter((c) => !c.cleared_on).length);

  const nav = (
    <div style={{ display: "flex", gap: 6, flexWrap: "wrap", margin: "0 0 12px" }}>
      {VIEWS.map((v) => <Link key={v[0]} href={`/college/student?view=${v[0]}`} className={`btn btn--sm ${view === v[0] ? "btn--primary" : "btn--ghost"}`}>{v[1]}</Link>)}
      <Link href="/student" className="btn btn--sm btn--ghost">University record</Link>
    </div>
  );

  // the history: every enrolment (level, session, attempt) with its results, main then resit, and the decision
  const sessionsSeen = Array.from(new Set([...r.enrolments.map((e) => `${e.level}|${e.session}`), ...r.results.map((x) => `${x.level}|${x.session}`), ...r.decisions.map((d) => `${d.level}|${d.session}`)]));
  const history = sessionsSeen.map((k) => { const [L, ses] = k.split("|"); return { level: Number(L), session: ses }; }).sort((a, b) => a.session.localeCompare(b.session) || a.level - b.level).reverse();

  return (
    <Shell route="s/dashboard" me={loaded.me}>
      <Note kind={active ? "info" : "bad"} title={`${s.name} · ${r.student.number} · ${MBBS.degree}`}>
        {level} Level, <b>{phase?.name ?? "—"}</b> phase · {cur ? `${cur.kind === "REPEAT" ? `Repeat year, attempt ${cur.attempt_no}` : cur.kind === "APPEAL" ? "Senate-approved final attempt" : "First attempt"}` : "First attempt"} · {stageLabel}.
        {!active ? <> Your record stands <b>{word(status)}</b>; the College Secretary&rsquo;s office holds the decision.</> : null}
      </Note>
      {nav}

      {view === "overview" ? (
        <>
          <Panel title="Your journey to the MB.BS" right={`${de ? "Direct Entry · " : ""}${r.student.entry_session} entry`}>
            <PBody>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(6, 1fr)", gap: 6 }}>
                {ladder.map((x) => (
                  <div key={x.L} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 6, textAlign: "center" }}>
                    <div style={dot(x.st)}>{x.st === "done" ? "✓" : x.L}</div>
                    <div style={{ fontWeight: 600, fontSize: 13 }}>{x.L} Level</div>
                    <div className="sub2">{x.ex}</div>
                    <div style={{ fontSize: 12, fontWeight: 600, color: x.st === "done" ? "var(--green-ink)" : x.st === "stop" ? "var(--red-ink)" : x.st === "cur" ? "var(--chrome)" : "var(--chrome-dim)" }}>{x.sub}</div>
                  </div>
                ))}
              </div>
            </PBody>
          </Panel>
          {level >= 200 ? (
            <Panel title={`${level} Level · ${r.session}`} right={stageLabel}>
              <PBody>
                <div style={{ display: "grid", gap: 10 }}>
                  {steps.map((x, i) => (
                    <div key={x.label} style={{ display: "flex", gap: 12, alignItems: "flex-start" }}>
                      <div style={{ width: 32, height: 32, flexShrink: 0, borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center", fontWeight: 700, fontSize: 14, boxSizing: "border-box", ...(x.done ? { background: "var(--green-ink)", color: "#fff" } : i === stageIdx && active ? { border: "2px solid var(--green-ink)", color: "var(--green-ink)" } : { border: "1px solid var(--line)", color: "var(--chrome-dim)" }) }}>{x.done ? "✓" : i + 1}</div>
                      <div><div className="b600">{x.label}</div><div className="sub2">{x.sub}</div></div>
                    </div>
                  ))}
                </div>
                {active && next && !next.cleared ? <div className="mt-3"><Link href="/student/fees" className="btn btn--primary btn--sm">Pay {next.name} fees · {next.session}</Link></div> : null}
                {active && r.canRegister ? <div className="mt-3"><RegisterButton session={yearSession} level={level} items={items} label={registerLabel} /></div> : null}
              </PBody>
            </Panel>
          ) : (
            <Panel title="100 Level · Pre-Medical, on the University's form" right={r.level100.outcome ? (OUTCOME[r.level100.outcome]?.[0] ?? word(r.level100.outcome)) : "No results yet"}>
              <PBody>
                <div>You register by semester on the University&rsquo;s form and your results stand on the University&rsquo;s GPA sheet. Promotion to 200 Level follows the College&rsquo;s rule: every C-group course (Mathematics, Physics, Chemistry, Biology) passed at 50 or more, with no resit; a GST course failed is carried over.</div>
                <div className="mt-2">{r.level100.published} of {r.level100.registered} courses published{r.level100.failed ? <> · <b className="ink-red">below 50: {r.level100.failed}</b></> : null}{r.level100.carried ? <> · GST carried: {r.level100.carried}</> : null}</div>
                <div className="mt-3"><Link href="/student/results" className="btn btn--ghost btn--sm">Your University results</Link></div>
              </PBody>
            </Panel>
          )}
          {latestDecision ? (
            <Note kind={OUTCOME[latestDecision.outcome]?.[1] === "ok" ? "ok" : OUTCOME[latestDecision.outcome]?.[1] === "bad" ? "bad" : "info"} title={`Latest decision: ${OUTCOME[latestDecision.outcome]?.[0] ?? latestDecision.outcome}${latestDecision.honours ? " with MBBS Honours" : ""} · ${latestDecision.level} Level · ${latestDecision.session}${latestDecision.state === "CONFIRMED" ? "" : " (provisional, awaiting the College Academic Board)"}`}>
              {latestDecision.rule_ref ?? ""}{latestDecision.resit_names ? ` Resit: ${latestDecision.resit_names}, within ${examAt?.resit_window_months ?? 3} months, with fresh CA.` : ""}{latestDecision.minute ? ` Minute ${latestDecision.minute}.` : ""}
            </Note>
          ) : null}
          {r.carryOvers.filter((c) => !c.cleared_on).length ? <Note kind="bad" title={`Carried over: ${r.carryOvers.filter((c) => !c.cleared_on).map((c) => c.code).join(", ")}`}>Registered again with each level until passed; must be passed before graduation.</Note> : null}
          {step ? (
            <Panel title={`The examination ahead: ${step.exam}`} right={`${level} → ${step.to}`}>
              <DTable cols={["Item", "Rule"]} rows={[
                ["Subjects", step.subjects], ["CA / Examination", step.weights], ["To pass", step.pass], ["Minimum attendance", step.attendance],
                ["Resit", step.resit], ["On failure", step.onFailure],
              ].map(([k, v]) => [<strong key="k">{k}</strong>, <span key="v">{v}</span>])} />
              <PBody><ul className="sub2" style={{ margin: 0, paddingLeft: 18 }}>{COMMON_RULES.map((c) => <li key={c}>{c}</li>)}</ul></PBody>
            </Panel>
          ) : null}
          {myPostings.length ? (
            <Panel title="Your postings" right="As the College has allocated you">
              <DTable cols={["Session|mid", "Block", "Posting", "Group|mid", "Supervisor", "From|mid", "To|mid", "Logbook|mid", "Standing|mid"]} rows={myPostings.map((a) => [
                <span className="tnum" key="s">{a.session}</span>, <strong key="b">{a.block}</strong>,
                <span key="p"><strong className="tnum">{a.posting}</strong> <span className="sub2">{a.posting_name}{a.duration_weeks ? ` · ${a.duration_weeks} wk` : ""}</span></span>,
                <span className="tnum" key="g">{a.group_label ?? "—"}</span>, <span className="sub2" key="sv">{a.supervisor ?? "Not yet assigned"}</span>,
                <span className="tnum" key="f">{dayOf(a.starts_on)}</span>, <span className="tnum" key="t">{dayOf(a.ends_on)}</span>,
                <span className="tnum" key="l">{a.requirements ? `${a.requirements_met} of ${a.requirements}` : "—"}</span>, <span key="st">{word(a.state)}</span>,
              ])} />
            </Panel>
          ) : null}
        </>
      ) : null}

      {view === "fees" ? (
        <>
          <Tiles items={[
            ["Your College year", yearSession, null, `${level} Level${yearSession !== r.session ? ` · the University's session is ${r.session}` : ""}`],
            ["First semester fees", paidFirst ? "Cleared" : "Due", paidFirst ? "var(--green-ink)" : "var(--red-ink)", "Opens the first semester's registration"],
            ["Second semester fees", paidAll ? "Cleared" : "Due", paidAll ? "var(--green-ink)" : null, "Opens the second semester's registration"],
            ["Status", word(status), active ? "var(--green-ink)" : "var(--red-ink)", cur ? word(cur.kind) : ""],
          ]} />
          <Panel title="Fees by session" right="The University's one ledger; the College charges through it">
            <DTable cols={["Session|mid", "Level|mid", "Attempt", "First semester|mid", "Second semester|mid"]} rows={(r.enrolments.length ? r.enrolments : cur ? [cur] : []).slice().reverse().map((e) => [
              <span className="tnum" key="s">{e.session}</span>, <span className="tnum" key="l">{e.level}</span>,
              <span key="k">{e.kind === "REPEAT" ? `Repeat · attempt ${e.attempt_no}` : e.kind === "APPEAL" ? "Senate appeal" : "First attempt"}</span>,
              <Pil key="f" kind={e.first_cleared ? "ok" : "bad"}>{e.first_cleared ? "Paid" : "Due"}</Pil>, <Pil key="g" kind={e.second_cleared ? "ok" : "warn"}>{e.second_cleared ? "Paid" : "Due"}</Pil>,
            ])} />
            <PBody><div className="sub2">The level&rsquo;s fees are set by the Bursary and paid on the University&rsquo;s Fees &amp; payments page; the position here updates the moment a payment is confirmed. The whole session may be paid at once, or by semester as on the main portal.</div>
              <div className="mt-2"><Link href="/student/fees" className="btn btn--primary btn--sm">Fees &amp; payments</Link></div></PBody>
          </Panel>
        </>
      ) : null}

      {view === "registration" ? (
        <>
          {level < 200 ? <Note kind="info" title="100 Level registers on the University's form">Courses are chosen by semester under the Faculty of Science. <Link href="/student/registration">Open the registration form</Link>.</Note> : (
            <Panel title={`${level} Level registration · ${yearSession}`} right={registered ? `Registered · ${dayOf(cur?.registered_at ?? null)}` : next ? (next.cleared ? `Open: ${next.name}` : `${next.name} opens after its fees`) : "—"}>
              <PBody>
                <div>The curriculum is fixed by the prospectus: there is nothing to choose. {sems.length ? "Each semester's courses are registered in turn, on that semester's fees; the whole session paid at once clears every semester. Nothing is graded at a semester's end: the one examination sits at the end of the year." : "Every posting at the level is registered together, on the first semester's fees."} {r.carryOvers.filter((c) => !c.cleared_on).length ? `Carried over and registered again: ${r.carryOvers.filter((c) => !c.cleared_on).map((c) => c.code).join(", ")}.` : ""}</div>
                {sems.length ? (
                  <div className="mt-3">
                    <DTable cols={["Semester", "Weeks|mid", "Courses", "Runs|mid", "Fees|mid", "Registered|mid"]} rows={sems.map((x) => [
                      <strong key="n">{x.name}</strong>, <span className="tnum" key="w">{x.length_weeks ?? "—"}</span>, <span className="sub2 tnum" key="s">{x.subjects ?? "—"}</span>,
                      <span className="sub2" key="r">{x.starts_on ? `${dayOf(x.starts_on)} to ${dayOf(x.ends_on)}` : "Not yet dated"}</span>,
                      <Pil key="f" kind={x.cleared ? "ok" : "bad"}>{x.cleared ? "Cleared" : "Due"}</Pil>,
                      <span key="g">{x.registered_at ? <Pil kind="ok">{dayOf(x.registered_at)}</Pil> : <span className="sub2">Not yet</span>}</span>,
                    ])} />
                  </div>
                ) : null}
                {!active ? <div className="sub2 mt-2">Registration is closed: {word(status)}.</div>
                  : next && !next.cleared ? <div className="mt-3"><span className="sub2">{next.name} opens after its fees are paid for {next.session}. </span><Link href="/student/fees" className="btn btn--primary btn--sm">Pay fees</Link></div>
                  : next ? <div className="mt-3"><RegisterButton session={yearSession} level={level} items={items} disabled={!r.canRegister} label={registerLabel} /></div>
                  : registered ? <div className="sub2 mt-2">{cur?.registered_items ?? 0} items registered. {cur?.state === "RESIT" ? `Resit pending: ${cur.resit_names ?? ""}.` : ""}</div>
                  : null}
              </PBody>
            </Panel>
          )}
          {SEMESTERS.filter((x) => x.period.startsWith(`${level} Level`)).length ? (
            <Panel title="Semesters at your level" right="Lengths from the prospectus; the College sets the dates">
              <DTable cols={["Period", "Weeks|mid", "Subjects"]} rows={SEMESTERS.filter((x) => x.period.startsWith(`${level} Level`)).map((x) => [<strong key="p">{x.period}</strong>, <span className="tnum" key="w">{x.weeks}</span>, <span className="tnum" key="s">{x.subjects}</span>])} />
            </Panel>
          ) : null}
          {BLOCKS.map((b) => ({ block: b.block, total: b.total, postings: b.postings.filter((x) => { const range = x.level.match(/(\d{3})–(\d{3})/); if (range && level >= Number(range[1]) && level <= Number(range[2])) return true; return (x.level.match(/\d{3}/g) ?? []).some((n) => Number(n) === level); }) })).filter((b) => b.postings.length).map((b) => (
            <Panel key={b.block} title={`${b.block} postings`} right={b.total}>
              <DTable cols={["Posting|mid", "Name", "Courses", "Weeks|mid"]} rows={b.postings.map((x) => [<strong className="tnum" key="c">{x.code}</strong>, <span key="n">{x.name}</span>, <span className="sub2" key="k">{x.courses}</span>, <span className="tnum" key="w">{x.weeks}</span>])} />
            </Panel>
          ))}
        </>
      ) : null}

      {view === "results" ? (
        <>
          {history.length === 0 ? <Note kind="info" title="No College results yet">Your 100 Level results stand on the University&rsquo;s sheet. <Link href="/student/results">Your University results</Link>.</Note> : null}
          {history.map((h) => {
            const en = r.enrolments.find((e) => e.level === h.level && e.session === h.session) ?? null;
            const ex = r.exams.find((e) => e.level === h.level);
            const main = r.results.filter((x) => x.level === h.level && x.session === h.session && (x.attempt === "FIRST" || x.attempt === "REPEAT" || x.attempt === "SENATE_APPEAL"));
            const resit = r.results.filter((x) => x.level === h.level && x.session === h.session && x.attempt === "RESIT");
            const d = r.decisions.find((x) => x.level === h.level && x.session === h.session) ?? null;
            const row = (x: Result) => [
              <strong key="s">{x.subject}</strong>, <span className="tnum" key="c">{x.ca ?? "—"}</span>, <span className="tnum" key="e">{x.exam_score ?? "—"}</span>,
              <span className="tnum" key="cl">{x.clinical != null ? `${x.clinical}%` : "—"}</span>, <span className="tnum" key="a">{x.attendance != null ? `${x.attendance}%` : "—"}</span>,
              <b className="tnum" key="t">{x.total ?? "—"}</b>,
              <Pil key="p" kind={x.passed ? "ok" : x.passed === false ? "bad" : "grey"}>{x.passed ? (x.distinction ? "Pass · Distinction" : "Pass") : x.passed === false ? (x.barred ? `Barred: attendance below ${ex?.min_attendance_pct ?? ""}%` : "Fail") : "Pending"}</Pil>,
            ];
            return (
              <Panel key={`${h.level}-${h.session}`} title={`${h.level} Level · ${h.session}`} right={`${en ? (en.kind === "REPEAT" ? `Repeat year, attempt ${en.attempt_no}` : en.kind === "APPEAL" ? "Senate-approved final attempt" : "First attempt") : "First attempt"} · ${ex?.name ?? ""}`}>
                {main.length ? <DTable cols={["Subject", "CA|mid", "Exam|mid", "Clinical|mid", "Attend.|mid", "Total|mid", "Remark"]} rows={main.map(row)} /> : <PBody><div className="sub2">{en?.registered_at ? `Registered. Awaiting the ${ex?.name ?? "examination"}.` : en ? "Not yet registered." : "No results."}</div></PBody>}
                {resit.length ? <><div className="sub2" style={{ padding: "8px 14px 0", fontWeight: 600 }}>Resit · fresh CA</div><DTable cols={["Subject", "CA|mid", "Exam|mid", "Clinical|mid", "Attend.|mid", "Total|mid", "Remark"]} rows={resit.map(row)} /></> : null}
                {d ? (
                  <PBody>
                    <Note kind={OUTCOME[d.outcome]?.[1] === "ok" ? "ok" : OUTCOME[d.outcome]?.[1] === "bad" ? "bad" : "info"} title={`${OUTCOME[d.outcome]?.[0] ?? d.outcome}${d.honours ? " with MBBS Honours" : ""}${d.state === "CONFIRMED" ? "" : " (provisional)"}`}>
                      {d.rule_ref ?? ""}{d.resit_names ? ` Resit: ${d.resit_names}.` : ""}{d.carry_overs?.length ? ` Carried over: ${d.carry_overs.join(", ")}.` : ""}{d.minute ? ` Minute ${d.minute}.` : ""}
                    </Note>
                  </PBody>
                ) : null}
              </Panel>
            );
          })}
          {level === 100 || r.level100.outcome ? (
            <Panel title="100 Level · by the College's rule" right={r.level100.outcome ? (OUTCOME[r.level100.outcome]?.[0] ?? word(r.level100.outcome)) : "No results yet"}>
              <PBody><div className="sub2">{r.level100.published} of {r.level100.registered} courses published{r.level100.failed ? ` · below 50: ${r.level100.failed}` : ""}{r.level100.carried ? ` · GST carried: ${r.level100.carried}` : ""}. The figures stand on the University&rsquo;s GPA sheet: <Link href="/student/results">your University results</Link>.</div></PBody>
            </Panel>
          ) : null}
        </>
      ) : null}
    </Shell>
  );
}
