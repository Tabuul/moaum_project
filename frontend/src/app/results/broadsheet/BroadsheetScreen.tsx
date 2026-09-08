"use client";

/** tBroadsheet — proto/part26.html: every candidate in one programme at one level, across all their courses. */
import type { Scope } from "@/lib/scope";
import { STAGE_LABEL, csv, download, type Broadsheet } from "@/lib/results";
import { ScopeBar, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Note, Panel, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

const COLOUR = (points: number | null) => (points === null ? "var(--muted)" : points >= 4 ? "var(--green-ink)" : points >= 1 ? "var(--chrome)" : "var(--red-ink)");

export function BroadsheetScreen({ scope, structure, sessions, sheet }: { scope: Scope; structure: ScopeStructure; sessions: string[]; sheet: Broadsheet | null }) {
  const programme = structure.faculties.flatMap((f) => f.departments).flatMap((d) => d.programmes).find((p) => p.code === scope.prog);
  const semester = (scope.sem || "1") === "1" ? "First" : "Second";
  return (
    <>
      <Note kind="info" title="The broadsheet is computed, not typed">
        Every figure on this sheet comes from the score sheets and the grading scheme in force for the session. Nobody keys a GPA. A mark counts here once its set has passed the Faculty Board; a set still in the chain shows as pending, and the GPA is computed over what is approved so far.
      </Note>
      <Note kind="info" title="A broadsheet is by programme and level. A score sheet is by course.">
        A score sheet carries every candidate registered for one course, from every programme the course was made available to. A broadsheet carries every candidate in one programme at one level, across all their courses, because a GPA belongs to a student in a programme.
      </Note>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} what="the broadsheet" count={sheet?.rows.length ?? 0} of={sheet?.rows.length ?? 0}
        onExport={sheet ? () => download(`broadsheet-${sheet.programme}-${sheet.level}-${sheet.session.replace("/", "-")}-${sheet.semester}.csv`, csv([
          ["Matriculation number", "Name", ...sheet.courses.map((c) => c.courseCode), "Units", "Points", "GPA", "Standing"],
          ...sheet.rows.map((r) => [r.number, r.name, ...r.marks.map((m) => (m.counted ? `${m.total} ${m.grade}` : m.stage === "NOT_REGISTERED" ? "" : "pending")), r.units, r.points, r.gpa ?? "", r.standing]),
        ])) : undefined} />
      {!sheet ? (
        <Note kind="info" title="Choose a programme and a level">The broadsheet is one programme at one level in one semester. Pick them in the bar above; the session and semester are the ones the bar holds.</Note>
      ) : (
        <>
          <Tiles items={[
            ["Candidates", String(sheet.rows.length), null, `${sheet.level} Level · ${semester} semester`],
            ["Mean GPA", sheet.meanGpa === null ? "—" : sheet.meanGpa.toFixed(2), null, sheet.meanGpa === null ? "No approved set yet" : "Unweighted, this level"],
            ["Passed every course", String(sheet.passed), "var(--green-ink)", sheet.rows.length ? `${Math.round((100 * sheet.passed) / sheet.rows.length)}% of the level` : "—"],
            ["Carrying over", String(sheet.carrying), sheet.carrying ? "var(--red-ink)" : null, sheet.pendingSets ? `${sheet.pendingSets} set${sheet.pendingSets === 1 ? "" : "s"} still in the chain` : "One or more F grades"],
          ]} />
          <Panel title={`Broadsheet — ${programme?.name ?? sheet.programme}, ${sheet.level} Level, ${semester} semester`} right={sheet.gradingInstrument ? `Grading scheme ${sheet.gradingInstrument}` : "No grading scheme in force"}>
            {sheet.rows.length === 0 ? (
              <div className="card__body sub2">No approved registration at this level in {sheet.session} semester {sheet.semester} for this programme. The broadsheet has nobody to compute.</div>
            ) : (
              <DTable
                cols={["Matriculation number", "Name", ...sheet.courses.map((c) => `${c.courseCode}|mid`), "Units|mid", "Points|mid", "GPA|mid", "Standing|num"]}
                rows={sheet.rows.map((r) => [
                  <span className="tnum" key="n">{r.number}</span>,
                  <strong key="s">{r.name}</strong>,
                  ...r.marks.map((m) => m.stage === "NOT_REGISTERED" ? <span className="sub2" key={m.courseCode}>—</span> : m.counted ? (
                    <span key={m.courseCode}><span className="tnum">{m.total}</span><div className="sub2" style={{ color: COLOUR(m.points), fontWeight: 700 }}>{m.grade}</div></span>
                  ) : (
                    <span key={m.courseCode} className="sub2" title={STAGE_LABEL[m.stage]?.[0] ?? m.stage}>{m.outcome && m.outcome !== "GRADED" ? m.outcome.toLowerCase() : "pending"}</span>
                  )),
                  <span className="tnum" key="u">{r.units}</span>,
                  <span className="tnum" key="p">{r.points}</span>,
                  <span className="tnum" key="g" style={{ fontWeight: 700 }}>{r.gpa === null ? "—" : r.gpa.toFixed(2)}</span>,
                  <Pil key="st" kind={r.standing === "Pass" ? "ok" : r.standing === "Carryover" ? "bad" : "info"}>{r.standing}</Pil>,
                ])}
                texts={sheet.rows.map((r) => `${r.number} ${r.name}`)}
              />
            )}
          </Panel>
          <Panel title="The grading scheme this sheet used" right="Effective-dated: a 2019 result is graded by the 2019 scheme">
            <DTable cols={["Grade|mid", "From|mid", "To|mid", "Points|mid", "Meaning"]}
              rows={sheet.bands.map((b) => [
                <b key="g" style={{ color: COLOUR(b.points) }}>{b.grade}</b>,
                <span className="tnum" key="l">{b.low}</span>, <span className="tnum" key="h">{b.high}</span>, <span className="tnum" key="p">{b.points}</span>,
                <span key="m">{b.points >= 1 ? "Pass" : "Fail — the course is carried over"}</span>,
              ])} />
          </Panel>
          <Panel title="Classification" right="From the table in force">
            <DTable cols={["Class", "CGPA from|mid", "to|mid"]} rows={sheet.classes.map((c) => [<span key="c">{c.clazz}</span>, <span className="tnum" key="l">{c.low.toFixed(2)}</span>, <span className="tnum" key="h">{c.high.toFixed(2)}</span>])} />
          </Panel>
        </>
      )}
    </>
  );
}
