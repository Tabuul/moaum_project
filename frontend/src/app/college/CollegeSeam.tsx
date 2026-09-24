/**
 * The College of Health Sciences — proto/part41.html tCollege, word for word, as rewritten from the
 * CHS Prospectus 2023–2025 extraction of 24 September 2026 (lib/mbbs.ts holds the document's tables).
 * The only figures that come from the database are the College's address (ref.college.url — the link
 * is disabled until one is recorded) and the number of students on its register.
 */
import type { ReactNode } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ASSESSMENT_RULE, BLOCKS, COMMON_RULES, CONFLICTS, DEPARTMENT_CA, LOGBOOKS, MBBS, MODEL, PHASES, PROGRESSION, PSYCHIATRY_DAY, PSYCHIATRY_WEEKS, RULES_TO_IMPLEMENT, SEMESTERS, TO_CONFIRM, YEAR_VIEW } from "@/lib/mbbs";

export interface CollegeData {
  college: { code: string; name: string; system: string | null; url: string | null };
  faculties: { code: string; name: string; students: number }[];
  students: number;
  byLevel: { level: number; students: number }[];
}

const OWN: [ReactNode, string][] = [
  ["Person, identity, credentials", "One person, one identity, however many systems"],
  ["Admission, and the admission number", "Admissions is JAMB-facing and University-wide; the College's entry routes are checked here"],
  [<b key="m">The matriculation number</b>, "Permanent, never reused. Two minting systems make two students out of one person"],
  ["Fees, invoices, the ledger, clearance", "Money is audited centrally and the Bursary is one office"],
  ["The identity card", "One photograph, one record, one card"],
  [<b key="s">Senate approval of a result</b>, "The College Academic Board decides, subject to Senate; the Registrar signs one transcript from one record"],
  ["The transcript and the certificate", "A degree is the University's award — unclassified for MBBS, distinctions and Honours shown on it"],
];

function OpenLink({ url, name, small }: { url: string | null; name: string; small?: boolean }) {
  const label = `Open ${name} →`;
  const cls = `btn btn--primary${small ? " btn--sm" : ""}`;
  return url ? (
    <a className={cls} href={url} target="_blank" rel="noopener">{label}</a>
  ) : (
    <Btn kind="primary" size={small ? "sm" : "md"} disabled title={`No address recorded for ${name} yet`}>{label}</Btn>
  );
}

export function CollegeSeam({ college, problem }: { college: CollegeData | null; problem: Problem | null }) {
  const system = college?.college.system ?? "CHS-AMS";
  const url = college?.college.url ?? null;
  const students = college?.students ?? 0;
  const faculties = college?.faculties ?? [];
  const levels = college?.byLevel.length ?? 0;

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Note kind="info" title="The College of Health Sciences runs a separate system, and this is the seam" action={<OpenLink url={url} name={system} small />}>
        The MBBS programme does not fit a two-semester calendar, and not marginally. The prospectus says so in figures: 200 Level runs two semesters of seventeen weeks and 300 Level a twenty-week Third Semester; from 400 Level the student is not registered on courses but allocated to Blocks and Postings — Internal Medicine thirty-four weeks, Surgery thirty, Paediatrics sixteen, Obstetrics sixteen, three Pharmacology postings, four Pathology disciplines of twenty-four weeks each — and clinical clerkship runs 152 to 156 weeks in all, with a level split into rotation groups mid-session. A <code>semester</code> column cannot hold any of that. The College therefore has <b>{system}</b>, integrated with this portal for identity, fees and transcripts. What follows is the programme as the CHS Prospectus 2023–2025 states it (pages 24–154, extracted 24 September 2026), which is what {system} must hold.
      </Note>

      <Tiles items={[
        ["Held by this portal", "7 concerns", null, "Everything that outlives the College"],
        [`Held by ${system}`, "9 concerns", "var(--chrome)", "The programme's own machinery, from the prospectus"],
        ["Professional examinations", "4 + CPE", null, "Resit within three months; fresh CA every attempt"],
        ["Students in the College", students.toLocaleString("en-NG"), null,
          students === 0 ? "Nobody is on the College register yet" : `Across ${levels} ${levels === 1 ? "level" : "levels"} and ${faculties.length} ${faculties.length === 1 ? "faculty" : "faculties"}`],
      ]} />

      <Panel title="The programme" right={`${MBBS.degree} · regulations effective ${MBBS.regulationsEffective}`}>
        <DTable cols={["Item", "As the prospectus states it"]} rows={[
          ["Duration", `${MBBS.minYears.utme} years (${MBBS.minSemesters.utme} semesters) for UTME entrants; ${MBBS.minYears.directEntry} years (${MBBS.minSemesters.directEntry} semesters) for Direct Entry`],
          ["Graduation", `At least ${MBBS.minCreditUnits} credit units. All courses compulsory. ${MBBS.carryOver}`],
          ["Classification", MBBS.classification],
          ["Governance", MBBS.governance.join(" ")],
          ["Entry — O'Level", MBBS.entry.olevel],
          ["Entry — UTME", MBBS.entry.utme],
          ["Entry — Direct Entry", MBBS.entry.directEntry],
          ["Entry — Special", MBBS.entry.special],
        ].map(([k, v]) => [<strong key="k">{k}</strong>, <span key="v">{v}</span>])} />
      </Panel>

      <Panel title="Three phases, three ways of registering" right="Pre-Medical · Pre-clinical · Clinical">
        <DTable cols={["Phase", "Levels|mid", "How the student is enrolled"]} rows={PHASES.map((p) => [
          <strong key="p">{p.name}</strong>, <span className="tnum" key="l">{p.levels.join(", ")}</span>, <span key="h">{p.how}</span>,
        ])} />
        <PBody><div className="sub2">The prospectus pages read contain no section on registration — no portal, no deadlines, no add and drop. To confirm with the College: {TO_CONFIRM.join(" ")}</div></PBody>
      </Panel>

      <Panel title="The pre-clinical calendar" right="Lengths, not dates — the prospectus gives no calendar dates anywhere">
        <DTable cols={["Period", "Weeks|mid", "Subjects"]} rows={SEMESTERS.map((s) => [<strong key="p">{s.period}</strong>, <span className="tnum" key="w">{s.weeks}</span>, <span className="tnum" key="s">{s.subjects}</span>])} />
      </Panel>

      <Panel title="Progression, 100 Level to graduation" right="Promotion and progression are one rule">
        <DTable cols={["From|mid", "Examination", "Subjects", "CA / Exam|mid", "Pass", "Attendance|mid", "Resit", "On failure"]} rows={PROGRESSION.map((r) => [
          <strong className="tnum" key="f">{r.from} → {r.to}</strong>, <span key="e">{r.exam}</span>, <span className="sub2" key="s">{r.subjects}</span>,
          <span className="tnum" key="w">{r.weights}</span>, <span key="p">{r.pass}</span>, <span className="tnum" key="a">{r.attendance}</span>,
          <span key="r">{r.resit}</span>, <span className="sub2" key="o">{r.onFailure}</span>,
        ])} />
        <PBody><ul className="sub2 m-0" style={{ paddingLeft: "var(--s-5)" }}>{COMMON_RULES.map((c) => <li key={c}>{c}</li>)}</ul></PBody>
      </Panel>

      <Panel title="Blocks and postings" right="Durations, sequence and level; Psychiatry alone has a weekly timetable">
        {BLOCKS.map((b) => (
          <div key={b.block} style={{ padding: "6px 0 var(--s-1)" }}>
            <div className="row row--between row--base" style={{ padding: "var(--s-2) var(--s-4) 2px" }}>
              <strong>{b.block}</strong><span className="sub2">{b.total}</span>
            </div>
            <DTable cols={["Posting|mid", "Name", "Level|mid", "Courses", "Weeks|mid"]} rows={b.postings.map((p) => [
              <strong className="tnum" key="c">{p.code}</strong>, <span key="n">{p.name}</span>, <span className="tnum" key="l">{p.level}</span>, <span className="sub2" key="k">{p.courses}</span>, <span className="tnum" key="w">{p.weeks}</span>,
            ])} />
            {b.note ? <PBody><div className="sub2">{b.note}</div></PBody> : null}
          </div>
        ))}
      </Panel>

      <div className="grid grid--2">
        <Panel title="The Psychiatry week" right="Eight weeks; each weekday follows this template">
          <DTable cols={["Slot|mid", "Activity"]} rows={PSYCHIATRY_DAY.map((s) => [<span className="tnum" key="s">{s[0]}</span>, <span key="a">{s[1]}</span>])} />
          <DTable cols={["Week|mid", "Lecture themes"]} rows={PSYCHIATRY_WEEKS.map((w) => [<span className="tnum" key="w">{w[0]}</span>, <span className="sub2" key="t">{w[1]}</span>])} />
        </Panel>
        <Panel title="Year by year" right="A reconstruction from the postings — to confirm with the College">
          <DTable cols={["Level|mid", "Blocks and postings (weeks)"]} rows={YEAR_VIEW.map((y) => [<strong className="tnum" key="l">{y[0]}</strong>, <span key="b">{y[1]}</span>])} />
        </Panel>
      </div>

      <Panel title="Assessment: CA and the Professional examinations" right="CA 30, examination 70, at every stage">
        <PBody><div>{ASSESSMENT_RULE.general}</div></PBody>
        <DTable cols={["Department", "CA components", "Stated weight", "Examination"]} rows={DEPARTMENT_CA.map((d) => [
          <strong key="d">{d.department}</strong>, <span key="c">{d.components}</span>,
          <span key="w" className={/conflict|against/.test(d.weight) ? "ink-red b600" : "sub2"}>{d.weight}</span>,
          <span className="sub2" key="e">{d.exam}</span>,
        ])} />
        <PBody>
          <div><strong>Paediatrics minimum procedures</strong> <span className="sub2">{LOGBOOKS.paediatrics}</span></div>
          <div className="mt-2"><strong>Family Medicine skills checklist</strong> <span className="sub2">{LOGBOOKS.familyMedicine}</span></div>
        </PBody>
      </Panel>

      <div className="grid grid--2">
        <Panel title="This portal is the system of record for" right="Anything that outlives the College">
          <DTable cols={["Concern", "Why it sits here|num"]} rows={OWN.map((r) => [r[0], <span className="sub2" key="w">{r[1]}</span>])} />
        </Panel>
        <Panel title={`${system} holds`} right="The document's data model — ◊ marks a value the prospectus does not give">
          <DTable cols={["Concern", "What it carries|num"]} rows={MODEL.map((r) => [<strong key="c" className="tnum t-sm">{r[0]}</strong>, <span className="sub2" key="w">{r[1]}</span>])} />
        </Panel>
      </div>

      <Panel title="Rules the College's system must implement" right="From the regulations, as extracted">
        <PBody><ol className="m-0" style={{ paddingLeft: "var(--s-5)" }}>{RULES_TO_IMPLEMENT.map((r) => <li key={r}>{r}</li>)}</ol></PBody>
      </Panel>

      <Note kind="bad" title="Conflicts and gaps to resolve with the College before any of this is built">
        <ol style={{ margin: "var(--s-1) 0 0", paddingLeft: "var(--s-5)" }}>{CONFLICTS.map((c) => <li key={c}>{c}</li>)}</ol>
      </Note>

      <Panel title="Where the two systems touch" right="Each with what happens when it fails">
        <DTable cols={["Ref|mid", "What it is", "Direction|mid", "On failure|num"]} rows={[
          ["I-1", <><strong>Identity, at sign-in</strong><div className="sub2">OIDC. The token carries the identifier, the matriculation number and the offices held.</div></>, "CHS → here", <>New sign-ins stop. <b>No fallback to a local password store</b> — a fallback is a permanent second door</>],
          ["I-2", <><strong>Clearance, before registration or a posting allocation</strong><div className="sub2">Asked synchronously and never cached.</div></>, "CHS → here", "Refused, never allowed provisionally. A provisional registration is an unpaid student holding a place"],
          ["I-3", <><strong>Matriculation</strong><div className="sub2"><code>StudentMatriculated</code>. The College creates its record on receipt and never before — at 200 Level, since 100 Level is the Faculty of Science&rsquo;s.</div></>, "here → CHS", "Redelivered from the outbox; handlers are idempotent"],
          ["I-4", <><strong>Results crossing to Senate</strong><div className="sub2">A reconciliation, not a file drop: each Professional&rsquo;s subjects by attempt, with the distinction and the progression decision.</div></>, "CHS → here", <>The set does not reach Exams &amp; Records until every registered candidate is accounted for</>],
          ["I-5", <><strong>Enrolment reconciliation</strong><div className="sub2">Nightly, both directions.</div></>, "Both ways", <>Discrepancies go to the College Secretary <b>and</b> the Registrar — a divergence is a records question before it is a technical one</>],
        ].map((r) => [<b className="tnum" key="r">{r[0]}</b>, r[1], <span className="sub2" key="d">{r[2]}</span>, <span className="sub2" key="f">{r[3]}</span>])} />
      </Panel>

      <div className="row">
        <OpenLink url={url} name={system} />
        <span className="sub2">Opens in a new tab. It is a separate system and it looks like one.</span>
        <Pil kind="grey">Source: CHS Prospectus 2023–2025, pp. 24–154, extraction v2</Pil>
      </div>
    </>
  );
}
