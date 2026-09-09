"use client";

/** instOverview — the session so far, in figures: each chart carries its table, because a
 *  chart is for seeing the shape and a table is for quoting the number. Every figure is from
 *  the same record the desks work on; nothing here is entered. */
import { Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Bar, money } from "@/components/proto/blocks";

export interface OverviewData {
  session: string;
  semester: number;
  students: { total: number; byFaculty: { code: string; name: string; students: number }[]; byLevel: { level: number; students: number }[] };
  results: { code: string; name: string; expected: number; published: number; in_progress: number }[];
  collection: { faculty_code: string; faculty_name: string; students: number; paid_students: number; collected: number; due: number }[];
}

export function Overview({ d, semester }: { d: OverviewData; semester: number }) {
  const expected = d.results.reduce((a, r) => a + Number(r.expected), 0);
  const published = d.results.reduce((a, r) => a + Number(r.published), 0);
  const collected = d.collection.reduce((a, c) => a + Number(c.collected), 0);
  const maxFac = Math.max(1, ...d.students.byFaculty.map((f) => f.students));

  return (
    <>
      <Note kind="info" title="The session so far, in figures">
        Every figure on this screen is drawn from the same record the desks work on, and each chart carries its table &mdash; because a chart is for seeing the shape and a table is for quoting the number, and an institutional paper needs both. Nothing here is entered by hand.
      </Note>

      <Tiles items={[
        ["Students on the register", d.students.total.toLocaleString(), null, `${d.students.byFaculty.length} facult${d.students.byFaculty.length === 1 ? "y" : "ies"}`],
        ["Result sets expected", String(expected), null, `${d.session} · ${semester === 1 ? "first" : "second"} semester`],
        ["Past Senate", expected ? `${Math.round((100 * published) / expected)}%` : "—", published ? "var(--green-ink)" : null, `${published} of ${expected} published`],
        ["Collected this session", money(collected), collected ? "var(--green-ink)" : null, "School fees confirmed"],
      ]} />

      <div className="grid grid--2">
        <Panel title="Students by faculty" right="On the register, all levels">
          {d.students.byFaculty.length ? (
            <DTable cols={["Faculty", "Students|num", "Share|num"]} rows={d.students.byFaculty.map((f) => [
              <span key="f">{f.name}</span>,
              <span className="tnum" key="n">{f.students.toLocaleString()}</span>,
              <span key="b" style={{ display: "flex", alignItems: "center", gap: 8 }}><Bar pct={Math.round((100 * f.students) / maxFac)} /></span>,
            ])} />
          ) : <PBody><div className="sub2">Nobody is on the register yet, so there is nothing to chart.</div></PBody>}
        </Panel>
        <Panel title="Students by level" right="All modes, all faculties">
          {d.students.byLevel.length ? (
            <DTable cols={["Level", "Students|num", "Share|num"]} rows={d.students.byLevel.map((l) => [
              <span className="tnum" key="l">{l.level} Level</span>,
              <span className="tnum" key="n">{l.students.toLocaleString()}</span>,
              <span key="b" style={{ display: "flex", alignItems: "center", gap: 8 }}><Bar pct={Math.round((100 * l.students) / Math.max(1, ...d.students.byLevel.map((x) => x.students)))} /></span>,
            ])} />
          ) : <PBody><div className="sub2">No enrolment recorded yet.</div></PBody>}
        </Panel>
      </div>

      <Panel title="Results by faculty" right={`${d.session} · ${semester === 1 ? "first" : "second"} semester · expected, published, in progress`}>
        {d.results.length ? (
          <DTable cols={["Faculty", "Expected|mid", "Published|mid", "In progress|mid", "Published %|num"]} rows={d.results.map((r) => {
            const pct = Number(r.expected) ? Math.round((100 * Number(r.published)) / Number(r.expected)) : 0;
            return [
              <strong key="f">{r.name}</strong>,
              <span className="tnum" key="e">{r.expected}</span>,
              <span className="tnum" key="p" style={{ color: "var(--green-ink)", fontWeight: 700 }}>{r.published}</span>,
              <span className="tnum" key="i">{r.in_progress}</span>,
              <span key="r" style={{ display: "flex", alignItems: "center", gap: 8 }}><Bar pct={pct} colour={pct < 55 ? "var(--red)" : "var(--green)"} /><span className="tnum sub2">{pct}%</span></span>,
            ];
          })} />
        ) : <PBody><div className="sub2">No score sheet exists for {d.session}, {semester === 1 ? "first" : "second"} semester yet. A sheet appears when a lecturer is allocated and the examination session is open.</div></PBody>}
      </Panel>

      <Panel title="Collection by faculty" right={`${d.session} · from the register`}>
        {d.collection.length ? (
          <DTable cols={["Faculty", "Collected|mid", "Students paid|mid", "Rate|num"]} rows={d.collection.map((c) => {
            const rate = Number(c.due) ? Math.min(100, Math.round((100 * Number(c.collected)) / Number(c.due))) : 0;
            return [
              <span key="f">{c.faculty_name}</span>,
              <span className="tnum" key="c">{money(Number(c.collected))}</span>,
              <span className="tnum" key="s">{c.paid_students} of {c.students}</span>,
              <span key="r" style={{ display: "flex", alignItems: "center", gap: 8 }}><Bar pct={rate} colour={rate < 60 ? "var(--red)" : "var(--green)"} /><span className="tnum sub2">{Number(c.due) ? `${rate}%` : "no charge"}</span></span>,
            ];
          })} />
        ) : <PBody><div className="sub2">Nothing is charged for {d.session} yet, so there is nothing to collect against.</div></PBody>}
      </Panel>

      <Note kind="info" title="A number here and a number on a desk are one number read twice">
        The students on the register are the rows the Registry works; the result sets are the sheets the lecturers own; the collection is the day book the Bursary confirms. This screen counts them, it does not keep a second copy, so it cannot drift from what the desks see.
      </Note>
    </>
  );
}
