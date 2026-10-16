"use client";
/** V487: whom enforcing prerequisites stops — every student in study whose programme binds a course at their level with a
 *  prerequisite they have not passed, by course (how many, how many registered on it this session), and one course's students
 *  in full; counted on asking, as it reads every such student's results. Printed and downloaded as listed. */
import { useState } from "react";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { brandedXlsx, downloadBlob } from "@/lib/exportbrand";

interface CourseRow { course_code: string; title: string; unmet: string; students: number; registered: number; programmes: string }
interface StudentRow { student_id: string; matric_no: string | null; admission_no: string | null; name: string; programme: string; level: number; course_code: string; title: string; unmet: string; registered: boolean }
interface Impact { mode: string; total: number; students: number; registered: number; courses: CourseRow[]; rows: StudentRow[]; course: string | null }

async function read(course?: string): Promise<Impact | null> {
  const r = await fetch(`/api/bff/api/v1/catalogue/prerequisites/impact${course ? `?course=${encodeURIComponent(course)}` : ""}`, { cache: "no-store" });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem(j && typeof j === "object" && "status" in j ? j : { status: r.status, title: r.statusText }); return null; }
  return j as Impact;
}

export function PrerequisiteImpact({ mode }: { mode: string }) {
  const [busy, setBusy] = useState(false);
  const [all, setAll] = useState<Impact | null>(null);
  const [one, setOne] = useState<Impact | null>(null);
  const enforced = mode === "ENFORCED";

  async function count() {
    setBusy(true); setOne(null);
    try { setAll(await read()); } finally { setBusy(false); }
  }

  async function open(code: string) {
    setBusy(true);
    try { setOne(await read(code)); } finally { setBusy(false); }
  }

  const HEAD = ["Student", "Number", "Programme", "Level", "Course", "Not yet passed", "Registered on it this session"];
  const body = (rows: StudentRow[]) => rows.map((r) => [r.name, r.matric_no ?? r.admission_no ?? "", r.programme, String(r.level), r.course_code, r.unmet, r.registered ? "Yes" : "No"]);

  return (
    <Panel title={enforced ? "Whom enforcing stops" : "Whom enforcing would stop"} right={<Btn kind="secondary" size="sm" disabled={busy} busyLabel="Counting…" onClick={() => void count()}>{all ? "Count again" : "Count who would be stopped"}</Btn>}>
      <PBody>
        <div className="sub2">
          A student in study whose programme binds a course at their level with a prerequisite they have not passed (as registration reads it).
          {enforced ? " Their form locks the course; ICT Support's override sets it aside on a ticket." : " Advisory now: they are shown it and still register it."}
          {" "}A student already registered on it keeps the registration either way.
        </div>
        {all ? (
          <div className="mt-2">
            <Tiles cls="grid--4" items={[
              ["Students", String(all.students), all.students ? "var(--amber-ink)" : null, enforced ? "Stopped on at least one course" : "Would be stopped on at least one course"],
              ["Course places", String(all.total), null, "A student and a course"],
              ["Courses", String(all.courses.length), null, "With a prerequisite someone has not passed"],
              ["Registered on it now", String(all.registered), null, "This session; kept"],
            ]} />
            {!all.total ? <div className="mt-2"><Note kind="ok" title="Nobody would be stopped">Every student whose programme binds a course with a prerequisite has passed it, or entered above it.</Note></div> : null}
          </div>
        ) : null}
      </PBody>
      {all && all.courses.length ? (
        <DTable cols={["Course", "Not yet passed", "Programmes", "Students|num", "Registered now|num", "|num"]} rows={all.courses.map((c) => [
          <span key="c"><b className="tnum">{c.course_code}</b><div className="sub2">{c.title}</div></span>,
          <span key="u" className="tnum">{c.unmet}</span>,
          <span key="p" className="sub2">{c.programmes}</span>,
          <span key="s" className="tnum">{c.students}</span>,
          <span key="r" className="tnum">{c.registered}</span>,
          <Btn key="o" kind="ghost" size="sm" disabled={busy} onClick={() => void open(c.course_code)}>Students</Btn>,
        ])} texts={all.courses.map((c) => `${c.course_code} ${c.title} ${c.unmet} ${c.programmes}`)} />
      ) : null}
      {one ? (
        <PBody>
          <div className="row row--between mt-2">
            <b>{one.course}: {one.total} student{one.total === 1 ? "" : "s"}</b>
            <span className="row row--tight">
              <Btn kind="secondary" size="sm" disabled={!one.rows.length} onClick={async () => downloadBlob(await brandedXlsx(`Prerequisite not passed — ${one.course}`, HEAD, body(one.rows), { sub: `${one.total} students` }), `prerequisite-${(one.course ?? "").replace(/\s+/g, "-")}.xlsx`)}>Excel</Btn>
              <Btn kind="ghost" size="sm" onClick={() => setOne(null)}>Close</Btn>
            </span>
          </div>
          <DTable cols={["S/N|num", "Student", "Number", "Programme", "Level|mid", "Not yet passed", "Registered now|mid"]} rows={one.rows.map((r, i) => [
            <span key="n" className="tnum sub2">{i + 1}</span>, <span key="s">{r.name}</span>, <span key="m" className="tnum sub2">{r.matric_no ?? r.admission_no ?? ""}</span>,
            <span key="p" className="sub2">{r.programme}</span>, <span key="l" className="tnum">{r.level}</span>, <span key="u" className="tnum">{r.unmet}</span>,
            <span key="r" className="sub2">{r.registered ? "Yes" : "No"}</span>,
          ])} texts={one.rows.map((r) => `${r.name} ${r.matric_no ?? ""} ${r.programme}`)} />
        </PBody>
      ) : null}
    </Panel>
  );
}
