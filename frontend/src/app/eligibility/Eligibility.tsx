"use client";

/** tEligibility — proto/part…: who may register a course. The eligible set is part of the
 *  course, assigned at creation and amended only by a curriculum change; this screen reads it. */
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Dept { code: string; name: string; faculty_code: string }
export interface CourseRow { code: string; title: string }
export interface Offer { programme_code: string; programme: string; dept_code: string; dept: string; faculty: string; level: number; basis: string; registered: number }
export interface EligibilityView { code: string; title: string; dept_code: string; dept_name: string; units: number; level: number; semester: number; offers: Offer[] }

export function Eligibility({ depts, dept, courses, code, view, problem }: {
  depts: Dept[]; dept: string; courses: CourseRow[]; code: string; view: EligibilityView | null; problem: Problem | null;
}) {
  const queryNav = useQueryNav();
  function go(next: { dept?: string; course?: string }) {
    const q = new URLSearchParams();
    q.set("dept", next.dept ?? dept);
    if (next.course ?? (next.dept ? "" : code)) q.set("course", next.course ?? code);
    queryNav(`/eligibility?${q.toString()}`);
  }

  const all = view ? view.offers.reduce((n, o) => n + o.registered, 0) : 0;
  const borrowed = view ? view.offers.filter((o) => o.dept_code !== view.dept_code).reduce((n, o) => n + o.registered, 0) : 0;
  const relation = (o: Offer) => o.dept_code === view?.dept_code ? <Pil kind="ok">Same department</Pil> : <span className="sub2">Borrows it</span>;

  return (
    <>
      <Note kind="info" title="Who may offer a course is decided when the course is created">
        The eligible set is part of the course, like its units and its semester. It is assigned at creation, goes to the Faculty Board with the course, and Senate approves it. Nothing here is an exception granted to a named student &mdash; an exception is how a course quietly acquires a cohort nobody accredited.
      </Note>

      <div className="card"><div className="card__body row row--end">
        <div style={{ minWidth: 220 }}><Field id="el-dept" label="Department">
          <SearchSelect id="el-dept" value={dept} placeholder="Search a department…"
            options={depts.map((d) => ({ value: d.code, label: d.name }))} onChange={(v) => go({ dept: v, course: "" })} /></Field></div>
        <div style={{ minWidth: 260 }}><Field id="el-course" label="Course">
          <SearchSelect id="el-course" value={code} placeholder={courses.length ? "Search a course…" : "No course in this department"}
            options={courses.map((c) => ({ value: c.code, label: `${c.code} — ${c.title}` }))} onChange={(v) => go({ course: v })} /></Field></div>
      </div></div>

      {problem ? <ProblemNotice problem={problem} /> : null}

      {view ? (
        <>
          <Tiles items={[
            ["Owning department", view.dept_name, null, "Opens the sheet, holds the board"],
            ["Eligible cohorts", String(view.offers.length), null, "Programme and level pairs"],
            ["Registered", String(all), null, "Approved registrations, all programmes"],
            ["From other departments", String(borrowed), borrowed ? "var(--chrome)" : null, "They sat the same paper"],
          ]} />

          <Panel title={`${view.code} — who may register it`} right="Assigned at course creation · amended only by a curriculum change">
            {view.offers.length ? (
              <DTable cols={["Programme", "Department", "Faculty", "Level|mid", "Basis|mid", "Registered|mid", "Relation|mid"]} rows={view.offers.map((o) => [
                <strong key="p">{o.programme}</strong>,
                <span className="sub2" key="d">{o.dept}</span>,
                <span className="sub2" key="f">{o.faculty}</span>,
                <span className="tnum" key="l">{o.level}</span>,
                o.basis === "Core" ? <Pil kind="ok" key="b">Core</Pil> : <Pil kind="info" key="b">{o.basis}</Pil>,
                <span className="tnum" key="r">{o.registered}</span>,
                <span key="rel">{relation(o)}</span>,
              ])} texts={view.offers.map((o) => `${o.programme} ${o.dept} ${o.faculty}`)} />
            ) : <PBody><div className="sub2">No programme is on this course&rsquo;s eligible set. Until a programme and level are added at a curriculum change, no student can register it and it appears on no course form.</div></PBody>}
          </Panel>

          <div className="grid grid--2">
            <Panel title="What a student sees" right="On the course registration form">
              <PBody>
                <p className="sub2 m-0" style={{ lineHeight: 1.6 }}>If a student&rsquo;s programme and level are on the set, the course is offered on their form, beside their own department&rsquo;s courses. If they are not, the course is not on the form at all. Nobody writes to a Head of Department and nobody carries a paper form between offices.</p>
                <Note kind="ok" title="Eligibility is checked when the registration is made, not when the mark is entered">A registration outside the eligible set is refused at the form &mdash; the only place refusing it is cheap. Refusing it at the score sheet means a student has already sat an examination they were never registered for.</Note>
              </PBody>
            </Panel>
            <Panel title="What the lecturer sees" right="On the score sheet">
              <PBody>
                <p className="sub2 m-0" style={{ lineHeight: 1.6 }}>All {all} registered candidates in one list, ordered by matriculation number. The programme is a column, not a filter. {borrowed} of them are from other departments, and they are marked exactly like the rest, because they sat exactly the same paper.</p>
              </PBody>
            </Panel>
          </div>
        </>
      ) : courses.length ? null : <Note kind="info" title="This department owns no course yet">A course appears here once the department creates it.</Note>}
    </>
  );
}
