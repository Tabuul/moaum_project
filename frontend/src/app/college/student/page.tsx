import Link from "next/link";
import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { loadStudent } from "../../student/load";
import { BLOCKS, COMMON_RULES, MBBS, PHASES, PROGRESSION, phaseOf, SEMESTERS } from "@/lib/mbbs";

export const dynamic = "force-dynamic";

/**
 * /college/student — where the login gate sends a College of Health Sciences student: a student whose
 * programme sits under the College (faculty.college_code = 'CHS') and who is at 200 level or above.
 * They sign in through the one University login; the gate routes them here.
 *
 * The College's own academic system (postings, professional examinations, College results) is
 * separate. What this page can say with certainty is what the CHS Prospectus 2023–2025 says about the
 * student's own level — the phase they are in, how they are enrolled, the examination ahead and what
 * passing and failing it means — read from lib/mbbs.ts, the same file the College overview reads.
 */
export default async function CollegeStudentPage() {
  const loaded = await loadStudent();
  if (!loaded.student) {
    return <Shell route="s/dashboard" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  }
  const s = loaded.student;
  const level = Number(s.level);
  const phase = PHASES.find((p) => p.phase === phaseOf(level));
  const step = PROGRESSION.find((r) => r.from === level);
  const semesters = SEMESTERS.filter((x) => x.period.startsWith(`${level} Level`));
  // a posting is at the student's level when its level text names it ("400", "400 or 500") or spans it ("300–400")
  const atLevel = (text: string) => {
    const range = text.match(/(\d{3})–(\d{3})/);
    if (range) { const a = Number(range[1]); const z = Number(range[2]); if (level >= a && level <= z) return true; }
    return (text.match(/\d{3}/g) ?? []).some((n) => Number(n) === level);
  };
  const blocks = BLOCKS.map((b) => ({ block: b.block, total: b.total, postings: b.postings.filter((p) => atLevel(p.level)) })).filter((b) => b.postings.length);
  const de = s.entryMode === "DIRECT_ENTRY";
  return (
    <Shell route="s/dashboard" me={loaded.me}>
      <Note kind="info" title={`Welcome, ${s.name} — College of Health Sciences`}>
        You are a College of Health Sciences student at {level} Level, in the <b>{phase?.name ?? "—"}</b> phase of the {MBBS.degree}. Your fees, your record and your transcript are in the University portal; the College&rsquo;s own system holds your postings and professional examinations. Below is what the College&rsquo;s prospectus says about your level.
      </Note>
      <Tiles items={[
        ["Level", String(level), null, phase?.name ?? ""],
        ["Minimum duration", `${de ? MBBS.minYears.directEntry : MBBS.minYears.utme} years`, null, de ? "Direct Entry" : "UTME entry"],
        ["Credit units to graduate", String(MBBS.minCreditUnits), null, "All courses compulsory"],
        ["CGPA", s.cgpa != null ? String(s.cgpa) : "—", null, "The degree itself is unclassified"],
      ]} />
      {phase ? (
        <Panel title={`${phase.name}: how you are enrolled`} right={`Levels ${phase.levels.join(", ")}`}>
          <PBody><div>{phase.how}</div></PBody>
        </Panel>
      ) : null}
      {semesters.length ? (
        <Panel title="Your semesters this level" right="Lengths from the prospectus; the College sets the dates">
          <DTable cols={["Period", "Weeks|mid", "Subjects"]} rows={semesters.map((x) => [<strong key="p">{x.period}</strong>, <span className="tnum" key="w">{x.weeks}</span>, <span className="tnum" key="s">{x.subjects}</span>])} />
        </Panel>
      ) : null}
      {blocks.length ? (
        <Panel title="Postings at your level" right="Durations and sequence; the College allocates you to each">
          {blocks.map((b) => (
            <div key={b.block}>
              <div style={{ display: "flex", justifyContent: "space-between", gap: 10, padding: "8px 14px 2px", flexWrap: "wrap", alignItems: "baseline" }}><strong>{b.block}</strong><span className="sub2">{b.total}</span></div>
              <DTable cols={["Posting|mid", "Name", "Courses", "Weeks|mid"]} rows={b.postings.map((p) => [<strong className="tnum" key="c">{p.code}</strong>, <span key="n">{p.name}</span>, <span className="sub2" key="k">{p.courses}</span>, <span className="tnum" key="w">{p.weeks}</span>])} />
            </div>
          ))}
        </Panel>
      ) : null}
      {step ? (
        <Panel title={`The examination ahead: ${step.exam}`} right={`${level} → ${step.to}`}>
          <DTable cols={["Item", "Rule"]} rows={[
            ["Subjects", step.subjects], ["CA / Examination", step.weights], ["To pass", step.pass], ["Minimum attendance", step.attendance],
            ["Resit", step.resit], ["On failure", step.onFailure],
          ].map(([k, v]) => [<strong key="k">{k}</strong>, <span key="v">{v}</span>])} />
          <PBody><ul className="sub2" style={{ margin: 0, paddingLeft: 18 }}>{COMMON_RULES.map((c) => <li key={c}>{c}</li>)}</ul></PBody>
        </Panel>
      ) : null}
      <Panel title="Carry-over and the degree">
        <PBody>
          <div>{MBBS.carryOver}</div>
          <div style={{ marginTop: 6 }}>{MBBS.classification}</div>
          <div style={{ marginTop: 10 }}><Link href="/student" className="btn btn--primary btn--sm">Open my student record</Link></div>
        </PBody>
      </Panel>
    </Shell>
  );
}
