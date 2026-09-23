"use client";

/** t/overview — the session so far, in figures (proto _ac.html instOverview). Every chart is drawn
 *  from the same record the desks work on and carries its table beneath it, because a chart is for
 *  seeing the shape and a table for quoting the number. Nothing here is entered by hand — the marks,
 *  the chain stages, the collections are read once and counted, so this cannot drift from the desks. */
import { Note, Panel, PBody, Tiles, Tick, WarnIcon, Ico } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { money } from "@/components/proto/blocks";
import { Donut, HBars, Stack, Line, VBars, Legend, VZ, vzNum, type LegendKey } from "@/components/proto/vz";
import { PeriodPicker } from "@/components/proto/PeriodPicker";

export interface OverviewData {
  session: string;
  semester: number;
  uni?: { students: number; faculties: number; departments: number };
  students: { total: number; byFaculty: { code: string; name: string; students: number }[]; byLevel: { level: number; students: number }[] };
  results: { code: string; name: string; expected: number; submitted?: number; approved?: number; published: number; in_progress: number }[];
  grades?: { grade: string; count: number }[];
  weeks?: { week: number; label: string; submitted: number; approved: number }[];
  collection: { faculty_code: string; faculty_name: string; students: number; paid_students: number; collected: number; due: number }[];
}

const N = (x: unknown) => Number(x ?? 0);
const LEVEL_COLS = [VZ.s1, VZ.s2, VZ.s3, VZ.s4, VZ.s5];
function niceMax(v: number) {
  if (v <= 0) return 1;
  const mag = Math.pow(10, Math.floor(Math.log10(v)));
  return Math.ceil((v * 1.12) / mag) * mag;
}

export function Overview({ d, semester, session, sessions }: { d: OverviewData; semester: number; session: string; sessions: string[] }) {
  const res = d.results.map((r) => {
    const expected = N(r.expected);
    const submitted = r.submitted != null ? N(r.submitted) : N(r.published) + N(r.in_progress);
    const approved = r.approved != null ? N(r.approved) : N(r.published);
    return { code: r.code, name: r.name, expected, submitted, approved, pending: Math.max(0, submitted - approved), never: Math.max(0, expected - submitted) };
  });
  const expected = res.reduce((a, r) => a + r.expected, 0);
  const subm = res.reduce((a, r) => a + r.submitted, 0);
  const appr = res.reduce((a, r) => a + r.approved, 0);
  const pend = Math.max(0, subm - appr), miss = Math.max(0, expected - subm);
  const pastPct = expected ? Math.round((appr / expected) * 100) : 0;
  const uniStudents = N(d.uni?.students ?? d.students.total);
  const collected = d.collection.reduce((a, c) => a + N(c.collected), 0);

  const statusKeys: LegendKey[] = [
    { l: "Approved", c: VZ.good, i: <Tick size={12} colour={VZ.good} /> },
    { l: "Pending in the chain", c: VZ.warn, i: <Ico name="clock" size={12} stroke="#8a6300" w={2.2} /> },
    { l: "Never submitted", c: VZ.crit, i: <WarnIcon size={12} /> },
  ];

  /* the faculty furthest behind, named from the record rather than asserted */
  const ranked = res.filter((r) => r.expected > 0).map((r) => ({ ...r, pct: Math.round((r.approved / r.expected) * 100) })).sort((a, b) => a.pct - b.pct);
  const worst = ranked[0];

  const facStudents = [...d.students.byFaculty].map((f) => ({ l: f.name, v: N(f.students) })).sort((a, b) => b.v - a.v);
  const gradeOrder = ["A", "B", "C", "D", "E", "F"];
  const gradeTotal = (d.grades ?? []).reduce((a, g) => a + N(g.count), 0);
  const grades = gradeOrder.map((g) => ({ grade: g, count: N((d.grades ?? []).find((x) => x.grade === g)?.count) }));
  const fPct = gradeTotal ? Math.round((N(grades.find((g) => g.grade === "F")?.count) / gradeTotal) * 100) : 0;

  const weeks = d.weeks ?? [];
  const wMax = niceMax(Math.max(1, ...weeks.map((w) => Math.max(N(w.submitted), N(w.approved)))));

  return (
    <>
      <PeriodPicker base="/overview" sessions={sessions} session={session} semester={semester} />
      <Note kind="info" title="The session so far, in figures">
        Every chart on this screen is drawn from the same record the desks work on, and each carries its table beneath it &mdash; because a chart is for seeing the shape and a table is for quoting the number, and an institutional paper needs both.
      </Note>

      <Tiles items={[
        ["Students on the register", vzNum(uniStudents), null, `${N(d.uni?.faculties ?? d.students.byFaculty.length)} faculties · ${N(d.uni?.departments)} departments`, "/reports/students"],
        ["Result sets expected", vzNum(expected), null, `${d.session} · ${semester === 1 ? "first" : "second"} semester`],
        ["Past Senate", expected ? `${pastPct}%` : "—", appr ? "var(--green-ink)" : null, `${vzNum(appr)} sets`],
        ["Never submitted", vzNum(miss), miss ? "var(--red-ink)" : "var(--green-ink)", miss ? "sets with no desk yet" : "every set is on a desk"],
      ]} />

      <div className="grid grid--2">
        <Panel title={`Where the ${vzNum(expected)} result sets stand`} right="Approved, pending, never submitted">
          <PBody>
            {expected ? (
              <>
                <Donut capLabel="approved" capValue={`${pastPct}%`} items={[
                  { l: "Approved by Senate", v: appr, c: VZ.good, i: <Tick size={13} colour="#0a7a3b" /> },
                  { l: "Pending in the chain", v: pend, c: VZ.warn, i: <Ico name="clock" size={13} stroke="#8a6300" w={2.2} /> },
                  { l: "Never submitted", v: miss, c: VZ.crit, i: <WarnIcon size={13} /> },
                ]} />
              </>
            ) : <div className="sub2">No score sheet exists for {d.session}, {semester === 1 ? "first" : "second"} semester yet. A sheet appears when a lecturer is allocated and the examination session is open.</div>}
          </PBody>
        </Panel>
        <Panel title="Students by level" right="All modes, all faculties">
          <PBody>
            {d.students.byLevel.length ? (
              <>
                <Donut capLabel="students" capValue={vzNum(uniStudents)} items={d.students.byLevel.map((r, i) => ({ l: `${N(r.level)} Level`, v: N(r.students), c: LEVEL_COLS[i % LEVEL_COLS.length] }))} />
                <Note kind="info" title="Every student on the register sits in exactly one level">
                  The shape is the intake history &mdash; four or five years of it &mdash; as admission, progression and graduation have left it. Only the programmes with a five-year run (MBBS, the LL.B, Pharm.D and Engineering) reach 500 Level.
                </Note>
              </>
            ) : <div className="sub2">No enrolment recorded yet.</div>}
          </PBody>
        </Panel>
      </div>

      <Panel title="Results by faculty" right="Each bar is that faculty&rsquo;s expected sets, split three ways">
        <PBody>
          {res.length ? (
            <>
              <Stack keys={statusKeys} rows={res.map((f) => ({ l: f.name, parts: [f.approved, f.pending, f.never] }))} />
              {worst ? (
                <Note kind="bad" title={`${worst.name} is furthest behind`}>
                  {vzNum(worst.approved)} set{worst.approved === 1 ? "" : "s"} approved of {vzNum(worst.expected)} expected &mdash; {worst.pct} per cent, against a University average of {pastPct}. {worst.never ? <>{vzNum(worst.never)} have never been submitted, which is where a Vice-Chancellor&rsquo;s question belongs.</> : "The rest are pending on a named desk and can be chased there."}
                </Note>
              ) : null}
            </>
          ) : <div className="sub2">No score sheet exists for this session and semester yet.</div>}
        </PBody>
      </Panel>

      <Panel title="Results by faculty, in figures" right="The chart above, as numbers">
        {res.length ? (
          <DTable cols={["Faculty", "Expected|mid", "Submitted|mid", "Approved|mid", "Pending|mid", "Never submitted|mid", "Approved %|num"]} rows={res.map((f) => {
            const pct = f.expected ? Math.round((f.approved / f.expected) * 100) : 0;
            return [
              <strong key="f">{f.name}</strong>,
              <span className="tnum" key="e">{f.expected}</span>,
              <span className="tnum" key="s">{f.submitted}</span>,
              <span className="tnum" key="a" style={{ color: "var(--green-ink)", fontWeight: 700 }}>{f.approved}</span>,
              <span className="tnum" key="p">{f.pending}</span>,
              <span className="tnum" key="n" style={f.never > 30 ? { color: "var(--red-ink)", fontWeight: 700 } : undefined}>{f.never}</span>,
              <b className="tnum" key="r" style={pct < 55 ? { color: "var(--red-ink)" } : undefined}>{pct}%</b>,
            ];
          })} />
        ) : <PBody><div className="sub2">No score sheet exists for {d.session}, {semester === 1 ? "first" : "second"} semester yet.</div></PBody>}
      </Panel>

      <Panel title="The semester week by week" right="Cumulative sets, submitted and approved">
        <PBody>
          {weeks.length ? (
            <>
              <Line yMax={wMax} yLabel="Cumulative result sets submitted and approved" xs={weeks.map((w) => w.label)} series={[
                { l: "Submitted", v: weeks.map((w) => N(w.submitted)), c: VZ.s1 },
                { l: "Approved", v: weeks.map((w) => N(w.approved)), c: VZ.s2 },
              ]} />
              <Legend keys={[{ l: "Submitted by the lecturer", c: VZ.s1 }, { l: "Approved by Senate", c: VZ.s2 }]} />
              <Note kind="info" title="The gap between the two lines is the workflow">
                It is the width of the approval chain: work arriving and work clearing. A gap that stays roughly constant is a chain in good health; a widening gap means a desk has stopped, and it shows here before anybody reports it.
              </Note>
            </>
          ) : <div className="sub2">No sheet has been submitted for {d.session}, {semester === 1 ? "first" : "second"} semester yet, so there is no week-by-week line to draw.</div>}
        </PBody>
      </Panel>

      <div className="grid grid--2">
        <Panel title="Students by faculty" right="On the register, all levels">
          <PBody>
            {facStudents.length ? <HBars items={facStudents} /> : <div className="sub2">Nobody is on the register yet.</div>}
          </PBody>
        </Panel>
        <Panel title="Grades across the University" right="Every published, graded entry this semester">
          <PBody>
            {gradeTotal ? (
              <>
                <VBars items={grades.map((g) => ({ l: g.grade, v: gradeTotal ? Math.round((g.count / gradeTotal) * 100) : 0, c: g.grade === "F" ? VZ.crit : VZ.seq }))} />
                <Note kind={fPct >= 15 ? "bad" : "info"} title={`${fPct} per cent of every graded entry is an F`}>
                  That is roughly one entry in {fPct ? Math.max(1, Math.round(100 / fPct)) : "—"} becoming a carryover, and a carryover consumes units in a later semester that a student then cannot spend on new courses. The portal can say which courses carry the failures, but not whether the cause is the examination, the teaching or the entry standard.
                </Note>
              </>
            ) : <div className="sub2">No result has been published for {d.session}, {semester === 1 ? "first" : "second"} semester yet, so there is no grade spread to show.</div>}
          </PBody>
        </Panel>
      </div>

      <Note kind="info" title="A number here and a number on a desk are one number read twice">
        The students are the rows the Registry works; the result sets are the sheets the lecturers own and the chain approves; the grades are the marks the examiners entered; the {money(collected)} collected is the day book the Bursary confirms. This screen counts them, it does not keep a second copy.
      </Note>
    </>
  );
}
