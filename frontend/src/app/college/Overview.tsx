import Link from "next/link";
import type { Problem } from "@/lib/api";
import { LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { COMMON_RULES, MBBS, PHASES, PROGRESSION, TO_CONFIRM } from "@/lib/mbbs";

/**
 * The College of Health Sciences overview (t/college): the live picture of the MBBS programme inside the portal —
 * every level with its students, open years and cohorts, its Professional examination and where the Board's
 * decisions stand; the session's postings by block; the calendar; and the doors to each desk. The prospectus's
 * rules stand beneath as the reference they are.
 */
export interface OverviewData {
  session: string;
  levels: { level: number; phase: string; enrolment: string; students: number; open_years: number; cohorts: string | null; exam_code: string | null; exam_name: string | null; provisional: number; confirmed: number; dated: number }[];
  totals: { students: number; open_years: number; provisional: number; allocations: number; blocks: number; postings: number; coordinators: number };
  blocks: { code: string; name: string; total_weeks: number | null; ordinal: number; postings: number; posting_codes: string | null; allocated: number }[];
}
const PHASE: Record<string, string> = { PREMEDICAL: "Pre-Medical", PRECLINICAL: "Pre-clinical", CLINICAL: "Clinical" };

export function Overview({ data, problem, office }: { data: OverviewData | null; problem: Problem | null; office: string | null }) {
  if (!data) return problem ? <ProblemNotice problem={problem} /> : null;
  const t = data.totals;
  const desk = ["provost", "collegesecretary", "academic", "registrar", "dregistrar", "admin", "super"].includes(office ?? "");
  return (
    <>
      <PageHead
        title="College of Health Sciences"
        description={`${MBBS.degree} · the College's students from 200 Level run on the College's own years, postings and Professional examinations inside this portal; 100 Level runs on the University's courses and GPA sheet.`}
        actions={<>
          <LinkBtn kind="primary" href="/college/examinations">Professional Examinations</LinkBtn>
          <LinkBtn href="/college/postings">Postings</LinkBtn>
          <LinkBtn href="/college/calendar">College Calendar</LinkBtn>
          <LinkBtn href="/college/supervision">Logbooks</LinkBtn>
          {desk ? <LinkBtn href="/college/scoresheets">Score Sheets</LinkBtn> : null}
        </>}
      />
      <Tiles items={[
        ["Students", String(t.students), null, "On the register, 200 to 600 Level and Pre-Medical"],
        ["Years open", String(t.open_years), null, "College years running or at a resit"],
        ["Awaiting the Board", String(t.provisional), t.provisional ? "var(--red-ink)" : null, "Provisional decisions to confirm"],
        ["Postings this session", String(t.allocations), null, `${data.session} · ${t.postings} postings in ${t.blocks} blocks`],
      ]} />

      <Panel title="The levels" right={`${data.session} · ${t.coordinators} MBBS coordinator${t.coordinators === 1 ? "" : "s"} appointed`}>
        <DTable cols={["Level|mid", "Phase", "Students|mid", "Years open|mid", "Cohorts", "Examination", "Decisions|mid", "Calendar|mid", ""]} rows={data.levels.map((l) => [
          <strong className="tnum" key="l">{l.level}</strong>,
          <span key="p">{PHASE[l.phase] ?? l.phase}<div className="sub2">{l.enrolment}</div></span>,
          <span className="tnum" key="s">{l.students}</span>,
          <span className="tnum" key="y">{l.level >= 200 ? l.open_years : "—"}</span>,
          <span className="sub2 tnum" key="c">{l.level >= 200 ? (l.cohorts ?? "None open") : "The University's session"}</span>,
          <span key="e">{l.exam_code ? <><strong className="tnum">{l.exam_code}</strong> <span className="sub2">{l.exam_name}</span></> : <span className="sub2">Sessional examinations, GPA</span>}</span>,
          <span key="d">{l.level >= 200 ? <>{l.provisional ? <Pil kind="warn">{l.provisional} provisional</Pil> : null}{l.provisional && l.confirmed ? " " : null}{l.confirmed ? <Pil kind="ok">{l.confirmed} confirmed</Pil> : null}{!l.provisional && !l.confirmed ? <span className="sub2">None yet</span> : null}</> : <span className="sub2">—</span>}</span>,
          <span key="k">{l.level >= 200 ? (l.dated ? <Pil kind="ok">Dated</Pil> : <Pil kind="grey">Undated</Pil>) : <span className="sub2">—</span>}</span>,
          <span key="o">{l.exam_code ? <LinkBtn href={`/college/examinations?exam=${encodeURIComponent(l.exam_code)}`}>Open</LinkBtn> : <LinkBtn href="/results/broadsheet">Broadsheet</LinkBtn>}</span>,
        ])} />
        <PBody><div className="sub2">A year opens when a student registers it from their dashboard, or when the desk opens it for them; a cohort is the year begun in a session. The examination sits once, at the end of the year; the rule applies its decision provisionally and the College Academic Board confirms.</div></PBody>
      </Panel>

      <Panel title="Blocks and postings" right={`${data.session} · ${t.allocations} allocation${t.allocations === 1 ? "" : "s"}`}>
        <DTable cols={["Block", "Postings", "Weeks|mid", "Allocated|mid"]} rows={data.blocks.map((b) => [
          <span key="b"><strong>{b.name}</strong> <span className="sub2 tnum">{b.code}</span></span>,
          <span className="sub2 tnum" key="p">{b.posting_codes ?? "—"}</span>,
          <span className="tnum" key="w">{b.total_weeks ?? "—"}</span>,
          <span className="tnum" key="a">{b.allocated}</span>,
        ])} />
        <PBody><div className="row"><span className="sub2">The College allocates students to a block&rsquo;s postings for a session, with a rotation group, a supervisor and dates; the supervisor keeps the logbook.</span><span className="grow" /><LinkBtn href="/college/postings">Postings desk</LinkBtn></div></PBody>
      </Panel>

      <Panel title="The programme, from the prospectus" right={`Regulations effective ${MBBS.regulationsEffective}`}>
        <DTable cols={["Phase", "Levels|mid", "How the student is enrolled"]} rows={PHASES.map((p) => [<strong key="n">{p.name}</strong>, <span className="tnum" key="l">{p.levels.join(", ")}</span>, <span key="h">{p.how}</span>])} />
      </Panel>
      <Panel title="Progression, as the rule applies it" right="Promotion and progression are one rule">
        <DTable cols={["From|mid", "Examination", "To pass", "Resit", "On failure"]} rows={PROGRESSION.map((r) => [
          <strong className="tnum" key="f">{r.from}</strong>, <span key="e">{r.exam}</span>, <span key="p">{r.pass}</span>, <span key="r">{r.resit}</span>, <span key="o">{r.onFailure}</span>,
        ])} />
        <PBody><ul className="list sub2">{COMMON_RULES.map((c) => <li key={c}>{c}</li>)}</ul></PBody>
      </Panel>
      {TO_CONFIRM.length ? (
        <Note kind="info" title="Still to confirm with the College">
          {TO_CONFIRM.join(" · ")} — the portal holds each as the prospectus states it until the College says otherwise. The prospectus&rsquo;s eleven conflicts stand on the examinations desk beside the subject they touch.
        </Note>
      ) : null}
      <Note kind="info" title="Students of the College">
        A College student signs in through the one University login and lands on the College dashboard: the journey from 100 to 600 Level, the year in hand with its fees and registration, and the results history. <Link href="/students">The register</Link> lists them with everyone else.
      </Note>
    </>
  );
}
