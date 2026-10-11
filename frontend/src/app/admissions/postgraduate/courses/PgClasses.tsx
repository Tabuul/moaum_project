"use client";

/** V389: the School of Postgraduate Studies' classes in its session — opened by the School on the University's engines, each
 *  with its lecturer (the Head of Department allocates), the students registered on it and where its score sheet stands. */
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";

interface PgClass { id: string; course_code: string; title: string; units: number; dept_code: string | null; department: string | null; lecturer: string | null; registered: number; sheet_stage: string | null }
interface View { session: string; semester: number; gate: string | null; classes: PgClass[]; unmapped: { programme_code: string; code: string; title: string }[] }

export function PgClasses({ mayOpen }: { mayOpen: boolean }) {
  const router = useRouter();
  const [session, setSession] = useState("");
  const [semester, setSemester] = useState(1);
  const [v, setV] = useState<View | null>(null);
  const [busy, setBusy] = useState(false);
  const [course, setCourse] = useState("");

  const load = useCallback(async (s: string, sem: number) => {
    const r = await fetch(`/api/bff/api/v1/pg/coursework/classes?semester=${sem}${s ? `&session=${encodeURIComponent(s)}` : ""}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    setV(j as View);
    if (!s) setSession((j as View).session);
  }, []);
  useEffect(() => { void (async () => { await load(session, semester); })(); }, [load, session, semester]);

  async function post(path: string, body: unknown, reason: string) {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/pg/coursework${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(reason);
      setV(j as View);
      router.refresh();
    } finally { setBusy(false); }
  }

  if (!v) return <Note kind="info" title="Reading the School's classes…">One moment.</Note>;
  return (
    <Panel title="The School's classes" right={<span className="row row--inline row--tight">
      <input className="ctl tnum" style={{ width: 110 }} value={session} onChange={(e) => setSession(e.target.value)} aria-label="Session" />
      <select className="ctl" style={{ width: "auto" }} value={semester} onChange={(e) => setSemester(Number(e.target.value))} aria-label="Semester">
        <option value={1}>First semester</option><option value={2}>Second semester</option><option value={3}>Third semester</option>
      </select></span>}>
      <PBody>
        <Note kind={v.gate ? "info" : "ok"} title={v.gate ? "Postgraduate registration is not open" : "Postgraduate registration is open"}>
          {v.gate ?? `Students register on Course Registration on these classes; their Head of Department approves, and each class's score sheet moves on the results desks.`}
        </Note>
        {mayOpen ? (
          <div className="row row--inline row--tight mt-2" style={{ flexWrap: "wrap" }}>
            <Btn kind="primary" disabled={busy} onClick={() => void post("/classes/open", { session: v.session, semester: v.semester }, `Opened the School's classes for ${v.session} semester ${v.semester}`)}>
              {busy ? "Opening…" : "Open the semester's classes"}</Btn>
            <Field id="pgc-course" label=""><input id="pgc-course" className="ctl tnum" style={{ width: 120 }} placeholder="Course code" value={course} onChange={(e) => setCourse(e.target.value.toUpperCase())} /></Field>
            <Btn kind="ghost" disabled={busy || !course.trim()} onClick={() => void post("/classes", { course: course.trim(), session: v.session, semester: v.semester }, `Added a class of ${course.trim()} for ${v.session}`)}>Add a class</Btn>
          </div>
        ) : null}
      </PBody>
      {v.classes.length ? (
        <DTable cols={["Course", "Department", "Lecturer", "Registered|num", "Score sheet|mid"]} texts={v.classes.map((c) => `${c.course_code} ${c.title} ${c.lecturer ?? ""}`)}
          rows={v.classes.map((c) => [
            <span key="c"><b className="tnum">{c.course_code}</b> {c.title}<div className="sub2">{c.units} units</div></span>, c.department ?? c.dept_code ?? "—",
            c.lecturer ?? <span key="l" className="sub2">Not allocated</span>, c.registered,
            c.sheet_stage ? <Pil key="s" kind={c.sheet_stage === "PUBLISHED" ? "ok" : "info"}>{c.sheet_stage === "PUBLISHED" ? "Published" : c.sheet_stage.replace(/_/g, " ").toLowerCase()}</Pil> : <span key="s" className="sub2">No sheet yet</span>,
          ])} />
      ) : <PBody><div className="sub2">No class is open for {v.session}, semester {v.semester}.</div></PBody>}
      {v.unmapped.length ? (
        <PBody>
          <Note kind="bad" title={`${v.unmapped.length} course row${v.unmapped.length === 1 ? "" : "s"} not yet a course of the University's pool`}>
            {v.unmapped.slice(0, 12).map((u) => `${u.code} (${u.programme_code})`).join(", ")}{v.unmapped.length > 12 ? "…" : ""}. Correct the code below so it can be bound.
          </Note>
        </PBody>
      ) : null}
      <PBody><LinkBtn kind="ghost" href="/allocate">Allocate lecturers</LinkBtn> <LinkBtn kind="ghost" href="/examinations/sessions">Examination sessions</LinkBtn></PBody>
    </Panel>
  );
}
