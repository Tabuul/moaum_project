"use client";

/** tBroadsheet — proto/part26.html: every candidate in one programme at one level, across all their courses. */
import type { Scope } from "@/lib/scope";
import { STAGE_LABEL, csv, download, type Broadsheet } from "@/lib/results";
import { ScopeBar, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Note, Panel, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

const COLOUR = (points: number | null) => (points === null ? "var(--muted)" : points >= 4 ? "var(--green-ink)" : points >= 1 ? "var(--chrome)" : "var(--red-ink)");

export function BroadsheetScreen({ scope, structure, sessions, sheet }: { scope: Scope; structure: ScopeStructure; sessions: string[]; sheet: Broadsheet | null }) {
  const programme = structure.faculties.flatMap((f) => f.departments).flatMap((d) => d.programmes).find((p) => p.code === scope.prog);
  const semester = (scope.sem || "1") === "1" ? "First" : "Second";
  const core = sheet ? sheet.courses.filter((c) => c.kind !== "Elective") : [];
  const elec = sheet ? sheet.courses.filter((c) => c.kind === "Elective") : [];
  const markOf = (r: Broadsheet["rows"][number], code: string) => r.marks.find((m) => m.courseCode === code);
  const fx = (n: number | null) => (n === null || n === undefined ? "—" : Number(n).toFixed(2));
  const cell = (m: ReturnType<typeof markOf>) =>
    !m || m.stage === "NOT_REGISTERED" ? <span className="sub2">—</span>
      : m.counted ? <span><span className="tnum">{m.total}</span><div className="sub2" style={{ color: COLOUR(m.points), fontWeight: 700 }}>{m.grade}</div></span>
      : <span className="sub2" title={STAGE_LABEL[m.stage]?.[0] ?? m.stage}>{m.outcome && m.outcome !== "GRADED" ? m.outcome.toLowerCase() : "•"}</span>;
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
          ["S/N", "Matriculation number", "Name", "Carryover",
            ...core.map((c) => `${c.courseCode} (${c.units})`), ...elec.map((c) => `${c.courseCode} (${c.units})`),
            "CUE", "WGP", "GPA", "TCR", "TCE", "TWGP", "LCGPA", "CGPA", "Remarks"],
          ...sheet.rows.map((r, i) => [i + 1, r.number, r.name, r.carryovers.join(" "),
            ...[...core, ...elec].map((c) => { const m = markOf(r, c.courseCode); return m && m.counted ? `${m.total} ${m.grade}` : m && m.stage !== "NOT_REGISTERED" ? "pending" : ""; }),
            r.units, r.points, r.gpa ?? "", r.tcr, r.tce, r.twgp, r.lcgpa ?? "", r.cgpa ?? "", r.remarks]),
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
          <Panel title={`Broadsheet — ${programme?.name ?? sheet.programme}, ${sheet.level} Level, ${semester} semester`} right={sheet.gradingInstrument ? `Grading scheme ${sheet.gradingInstrument} · score over grade` : "No grading scheme in force"}>
            {sheet.rows.length === 0 ? (
              <div className="card__body sub2">No approved registration at this level in {sheet.session} semester {sheet.semester} for this programme. The broadsheet has nobody to compute.</div>
            ) : (
              <div style={{ overflowX: "auto" }}>
                <table className="bsheet">
                  <thead>
                    <tr className="grp">
                      <th rowSpan={2} className="sn">S/N</th>
                      <th rowSpan={2} className="l">Matric no.</th>
                      <th rowSpan={2} className="l">Name of candidate</th>
                      <th rowSpan={2}>Carryover</th>
                      {core.length ? <th colSpan={core.length} className="band">Core courses</th> : null}
                      {elec.length ? <th colSpan={elec.length} className="band">Elective courses</th> : null}
                      <th colSpan={3} className="band">This semester</th>
                      <th colSpan={5} className="band">Cumulative to date</th>
                      <th rowSpan={2} className="l">Remarks</th>
                    </tr>
                    <tr className="sub">
                      {[...core, ...elec].map((c) => <th key={c.courseCode} className="course"><span className="mono">{c.courseCode}</span><span className="u">{c.units}</span></th>)}
                      <th>CUE</th><th>WGP</th><th>GPA</th>
                      <th>TCR</th><th>TCE</th><th>TWGP</th><th>LCGPA</th><th>CGPA</th>
                    </tr>
                  </thead>
                  <tbody>
                    {sheet.rows.map((r, i) => (
                      <tr key={r.studentId}>
                        <td className="sn tnum">{i + 1}</td>
                        <td className="l tnum">{r.number}</td>
                        <td className="l nm">{r.name}</td>
                        <td className="co sub2">{r.carryovers.length ? r.carryovers.join(", ") : "—"}</td>
                        {[...core, ...elec].map((c) => <td key={c.courseCode} className="mk">{cell(markOf(r, c.courseCode))}</td>)}
                        <td className="tnum">{r.units}</td>
                        <td className="tnum">{Number(r.points)}</td>
                        <td className="tnum b">{fx(r.gpa)}</td>
                        <td className="tnum">{r.tcr}</td>
                        <td className="tnum">{r.tce}</td>
                        <td className="tnum">{Number(r.twgp)}</td>
                        <td className="tnum">{fx(r.lcgpa)}</td>
                        <td className="tnum b">{fx(r.cgpa)}</td>
                        <td className="rm sub2">{r.remarks}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Panel>
          <style>{`
            .bsheet{border-collapse:collapse;font-size:12px;width:100%}
            .bsheet th,.bsheet td{border:1px solid var(--line);padding:4px 6px;text-align:center;vertical-align:middle}
            .bsheet thead th{background:var(--panel-2,var(--line-2));font-size:10.5px;letter-spacing:.03em;text-transform:uppercase;color:var(--chrome-dim)}
            .bsheet th.band{color:var(--chrome);font-weight:700}
            .bsheet th.l,.bsheet td.l{text-align:left;white-space:nowrap}
            .bsheet td.nm{white-space:normal;min-width:150px;font-weight:600}
            .bsheet th.course .mono{display:block;font-family:ui-monospace,monospace;font-weight:700}
            .bsheet th.course .u{display:block;font-size:10px;color:var(--chrome-dim)}
            .bsheet td.mk{min-width:44px}
            .bsheet td.b{font-weight:700}
            .bsheet td.co,.bsheet td.rm{text-align:left;min-width:120px;max-width:220px}
            .bsheet tbody tr:nth-child(even) td{background:var(--line-2)}
          `}</style>
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
