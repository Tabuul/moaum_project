"use client";

/** The postgraduate student's home — the central workspace after admission. It answers, from the register and
 *  nothing else: who I am, what I study, the School's session and semester in progress, what I am registered for,
 *  what I owe, how my coursework stands, who supervises me, where my research is, what is due, and whether I am
 *  on the way to graduation. Every figure is read live; where the register holds nothing yet it says so. */
import Link from "next/link";
import type { Me } from "@/lib/student-portal";
import { KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Passport } from "@/components/proto/blocks";
import { naira } from "./common";
import { RESEARCH_WORD, awardWord, eligibility, fmtDay, nextStep, type PgSummary } from "./pg-common";

const SEM = ["", "First semester", "Second semester", "Third semester"];

export type { PgSummary };

export function PgDashboard({ s, pg }: { s: Me; pg?: PgSummary | null }) {
  const f = s.fees;
  const reg = pg?.registration ?? null;
  const registered = !!reg && (reg.state === "SUBMITTED" || reg.state === "ENDORSED");
  const cgpaShown = pg && pg.standing !== "NEW" && pg.cgpa != null;
  const research = pg?.research ?? null;
  const step = research ? nextStep(research.stage, research.degree_kind, research.supervisor ?? null) : null;
  const regWord = !reg ? "Not started" : reg.state === "ENDORSED" ? "Endorsed" : reg.state === "SUBMITTED" ? "Submitted" : reg.state.charAt(0) + reg.state.slice(1).toLowerCase();
  const modeWord = reg ? (reg.mode === "PART_TIME" ? "Part-time" : "Full-time") : null;
  const feeLine = f.paidInFull ? `School fees settled in full for ${f.session}.`
    : f.balance > 0 ? `${naira(f.balance)} outstanding for ${f.session}.`
    : f.due > 0 ? `Fully paid for ${f.session}.` : `No charge stated yet for ${f.session}.`;
  const sem = pg?.semester ?? null;
  const cw = pg?.coursework ?? null;
  const elig = pg ? eligibility(pg, f) : null;
  const met = elig ? elig.filter((e) => e.state === "MET").length : 0;
  const supervisors = pg?.supervisors ?? [];
  const graduated = s.status === "GRADUATED" || !!pg?.graduand;

  /* what is due: the registration window, corrections, the semester's dates */
  const deadlines: [string, string, "bad" | "warn" | "grey"][] = [];
  if (sem?.registration_closes && !registered) deadlines.push(["Course registration closes", fmtDay(sem.registration_closes), new Date(sem.registration_closes) < new Date() ? "bad" : "warn"]);
  if (pg?.researchDates?.corrections_due && research?.stage === "CORRECTIONS") deadlines.push(["Corrections due", fmtDay(pg.researchDates.corrections_due), new Date(pg.researchDates.corrections_due) < new Date() ? "bad" : "warn"]);
  if (sem?.exams_from) deadlines.push(["Examinations", `${fmtDay(sem.exams_from)}${sem.exams_to ? ` to ${fmtDay(sem.exams_to)}` : ""}`, "grey"]);
  if (f.balance > 0) deadlines.push(["School fees outstanding", naira(f.balance), "bad"]);

  return (
    <>
      <Panel title="Postgraduate student" right="Your record on the register">
        <PBody>
          <div className="row row--top" style={{ gap: "var(--s-4)" }}>
            <Passport w={96} h={118} radius={6} src={s.hasPhoto ? `/api/bff/api/v1/me/passport?v=${encodeURIComponent(s.matricNo ?? s.admissionNo ?? s.id)}` : null} />
            <div className="grow" style={{ minWidth: 240 }}>
              <div className="phead__t">{s.name}</div>
              <div className="sub2 tnum mt-1">{s.matricNo ?? s.admissionNo}{s.matricNo ? "" : " · admission number, matriculation follows registration"}</div>
              <div className="sub2 mt-1">{s.programme} &middot; {s.department}</div>
              <div className="sub2">{s.faculty}</div>
              <div className="row mt-2">
                <span className={`pill ${s.status === "ACTIVE" ? "pill--ok" : graduated ? "pill--ok" : "pill--info"}`}><span className="dot" style={{ background: s.status === "ACTIVE" || graduated ? "var(--green)" : "var(--chrome)" }} />{s.status.charAt(0) + s.status.slice(1).toLowerCase().replace(/_/g, " ")}</span>
                <Pil kind="info">{awardWord(s.entryLevel)}</Pil>
                <Pil kind="grey">Entered {s.entrySession}</Pil>
              </div>
            </div>
            <KvGrid cls="grid--1" pairs={[
              ["Current PG session", <strong key="s" className="tnum">{pg?.session ?? s.session}</strong>],
              ["Current semester", <span key="m">{sem ? <Pil kind="ok">{SEM[Number(sem.number)] ?? `Semester ${sem.number}`}</Pil> : <Pil kind="grey">No semester open</Pil>}</span>],
            ]} />
          </div>
        </PBody>
      </Panel>

      <Tiles items={[
        ["Programme", awardWord(s.entryLevel), null, s.programme],
        ["Registered courses", reg ? String(reg.courses) : "0", registered ? "var(--green-ink)" : null, reg ? `${SEM[reg.semester] ?? `Semester ${reg.semester}`} · ${regWord}` : "Not yet registered", "/student/pg-courses"],
        ["CGPA", cgpaShown ? Number(pg!.cgpa).toFixed(2) : "—", pg?.standing === "PROBATION" ? "var(--red-ink)" : cgpaShown ? "var(--green-ink)" : null, pg?.standing === "PROBATION" ? "Probation · below 2.50" : cgpaShown ? "of 5.00 · good standing" : "No results yet", "/student/pg-courses"],
        ["Outstanding fees", f.balance > 0 ? naira(f.balance) : f.due > 0 ? "₦0" : "—", f.balance > 0 ? "var(--red-ink)" : f.paidInFull ? "var(--green-ink)" : null, f.paidInFull ? `Paid in full · ${f.session}` : f.due > 0 ? f.session : "No charge stated yet", "/student/fees"],
        ["Research", research ? (RESEARCH_WORD[research.stage] ?? research.stage) : "—", research && research.stage !== "WITHDRAWN" ? "var(--chrome)" : null, research ? (step ? step[0] : "") : "Not started", "/student/research"],
        ["Supervisor", supervisors[0]?.name ?? "—", null, supervisors.length > 1 ? `and ${supervisors.length - 1} more` : supervisors.length ? (supervisors[0].role === "FIRST" ? "Main supervisor" : supervisors[0].role.toLowerCase()) : "Not yet assigned", "/student/research"],
        ["Pending tasks", String(deadlines.filter((d) => d[2] !== "grey").length), deadlines.some((d) => d[2] === "bad") ? "var(--red-ink)" : deadlines.some((d) => d[2] === "warn") ? "var(--amber-ink)" : null, deadlines.length ? deadlines.filter((d) => d[2] !== "grey").map((d) => d[0]).join(" · ") || "Nothing overdue" : "Nothing due"],
        ["Deferment", s.status === "DEFERRED" ? "Active" : "None", s.status === "DEFERRED" ? "var(--amber-ink)" : null, s.status === "DEFERRED" ? "See your expected return" : "Defer a semester or session", "/student/deferment"],
        ["Graduation", graduated ? "Graduated" : elig ? `${met} / ${elig.length}` : "—", graduated ? "var(--green-ink)" : elig && met === elig.length ? "var(--green-ink)" : null, graduated ? (pg?.graduand?.award ? `${pg.graduand.award} · ${pg.graduand.session}` : "Award recorded") : "Requirements met", "/student/pg-progress"],
      ]} />

      {graduated ? (
        <Note kind="ok" title={`Your award of ${pg?.graduand?.award ?? awardWord(s.entryLevel)} is recorded`} action={<LinkBtn kind="primary" href="/student/graduation">Graduation and Certificate</LinkBtn>}>
          Senate approved the award{pg?.graduand?.senate_minute ? ` under minute ${pg.graduand.senate_minute}` : ""}. The Graduation screen shows convocation clearance and your certificate.
        </Note>
      ) : pg?.standing === "PROBATION" ? (
        <Note kind="bad" title="On academic probation" action={<LinkBtn kind="primary" href="/student/pg-courses">My Results</LinkBtn>}>
          Your CGPA is below 2.50. You are on probation for a semester and are advised to withdraw if it does not improve (Policy 15.5 / 20).
        </Note>
      ) : !registered && sem ? (
        <Note kind="info" title={reg ? `Complete your registration for ${pg?.session ?? s.session}` : `Register your courses for ${SEM[Number(sem.number)]?.toLowerCase() ?? "this semester"}`} action={<LinkBtn kind="primary" href="/student/pg-courses">Course Registration</LinkBtn>}>
          Register the courses your programme carries this semester; the department endorses the form.{sem.registration_closes ? ` Registration closes ${fmtDay(sem.registration_closes)}.` : ""} {feeLine}
        </Note>
      ) : step ? (
        <Note kind={step[2]} title={step[0]} action={<LinkBtn kind="ghost" href="/student/research">Research &amp; Thesis</LinkBtn>}>
          {step[1]}
        </Note>
      ) : reg ? (
        <Note kind="ok" title={`Registered for ${reg.session} · ${SEM[reg.semester] ?? `semester ${reg.semester}`}`} action={<LinkBtn kind="ghost" href="/student/pg-courses">Registration &amp; Results</LinkBtn>}>
          {reg.courses} course{reg.courses === 1 ? "" : "s"} registered ({modeWord!.toLowerCase()}){reg.state === "ENDORSED" ? ", endorsed by the department" : ""}. {feeLine}
        </Note>
      ) : (
        <Note kind="info" title="No semester is open for registration yet">
          The School opens the semester on its calendar; you are told by email when registration opens. {feeLine}
        </Note>
      )}

      <div className="grid grid--2">
        <Panel title="Deadlines" right={deadlines.length ? `${deadlines.length} on your calendar` : "Nothing due"}>
          {deadlines.length ? (
            <ul className="plain">
              {deadlines.map(([what, when, kind], i) => (
                <li key={i} className="row row--between" style={{ padding: "8px var(--s-4)", borderBottom: "1px solid var(--line)" }}>
                  <span>{what}</span><Pil kind={kind}>{when}</Pil>
                </li>
              ))}
            </ul>
          ) : <PBody><div className="sub2">Registration windows, examination dates and corrections due appear here from the School&rsquo;s calendar and your research record.</div></PBody>}
        </Panel>
        <Panel title="Supervision" right={supervisors.length ? `${supervisors.length} assigned` : "Awaiting assignment"}>
          <PBody>
            {supervisors.length ? (
              <KvGrid cls="grid--1" pairs={supervisors.map((x) => [x.role === "FIRST" ? "Main supervisor" : x.role === "SECOND" ? "Second supervisor" : "Co-supervisor",
                <span key={x.name}><strong>{x.name}</strong>{x.is_external ? " (external)" : ""}<div className="sub2">{[x.department, x.email].filter(Boolean).join(" · ") || `Assigned ${fmtDay(x.assigned_at)}`}</div></span>])} />
            ) : <div className="sub2">The department assigns a supervisor after registration (Policy 14). Their name appears here and on your research desk once assigned.</div>}
            {research?.topic ? <div className="sub2 mt-3">Topic: {research.topic}</div> : null}
          </PBody>
        </Panel>
      </div>

      <div className="grid grid--2">
        <Panel title="Academic progress" right={<Link className="lnk" href="/student/pg-progress">Full progress and eligibility</Link>}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["Courses registered", cw ? String(cw.courses) : "0"],
              ["Courses passed", cw ? `${cw.passed} of ${cw.graded} graded` : "—"],
              ["Units earned", cw ? `${cw.units_passed} of ${cw.units_registered} registered` : "—"],
              ["Registrations endorsed", cw ? `${cw.endorsed} of ${cw.registrations}` : "—"],
              ["CGPA", cgpaShown ? Number(pg!.cgpa).toFixed(2) : "No results yet"],
              ["Standing", pg?.standing === "PROBATION" ? "Probation" : cgpaShown ? "Good standing" : "No results yet"],
            ]} />
          </PBody>
        </Panel>
        <Panel title="This session" right={reg ? `${reg.session} · ${SEM[reg.semester] ?? `semester ${reg.semester}`}` : pg?.session ?? s.session}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["Programme", s.programme],
              ["Level / mode", `${s.level}${modeWord ? ` · ${modeWord}` : ""}`],
              ["Registration", reg ? `${regWord} · ${reg.courses} course${reg.courses === 1 ? "" : "s"}${reg.units != null ? `, ${reg.units} units` : ""}` : "Not started"],
              ["Research", research ? `${RESEARCH_WORD[research.stage] ?? research.stage} · ${(research.degree_kind ?? "").toLowerCase()}` : "Not started"],
              ["School fees", feeLine.replace(/\.$/, "")],
              ["Semester dates", sem?.lectures_from ? `${fmtDay(sem.lectures_from)}${sem.lectures_to ? ` to ${fmtDay(sem.lectures_to)}` : ""}` : "Not stated"],
            ]} />
          </PBody>
        </Panel>
      </div>
    </>
  );
}
