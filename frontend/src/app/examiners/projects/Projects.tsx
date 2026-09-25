"use client";
/** The project register for external examination (V254): a finalist's or postgraduate's project registered with its
 *  title, abstract, supervisor and submission date; then assigned to an active examiner by a deadline. */
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { dayOf, type ExaminerRow, type ProjectRow, type Rubric } from "@/lib/examiners";

interface Student { id: string; name: string; number: string; level: number; programme: string; department: string; postgraduate: boolean; pg_research_id: string | null; pg_topic: string | null; degree_kind: string | null }
interface Supervisor { id: string; name: string; staff_number: string | null; department: string | null }

export function Projects({ rows, session, current, sessions, examiners, rubrics, assignFor }: { rows: ProjectRow[]; session: string; current: string; sessions: string[]; examiners: ExaminerRow[]; rubrics: Rubric[]; assignFor: string }) {
  const router = useRouter();
  const go = useQueryNav();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [q, setQ] = useState("");
  const [open, setOpen] = useState(false);
  const [assign, setAssign] = useState<ProjectRow | null>(null);
  const [sq, setSq] = useState(""); const [students, setStudents] = useState<Student[]>([]); const [student, setStudent] = useState<Student | null>(null);
  const [vq, setVq] = useState(""); const [supers, setSupers] = useState<Supervisor[]>([]); const [supervisor, setSupervisor] = useState<Supervisor | null>(null);
  const [f, setF] = useState({ session: session || current, title: "", abstractText: "", keywords: "", projectType: "", submittedOn: "", supervisorName: "", coSupervisor: "", courseCode: "" });
  const [a, setA] = useState({ examinerId: assignFor, rubricId: "", deadline: "", examDate: "" });
  const shown = rows.filter((r) => !q.trim() || `${r.title} ${r.student} ${r.number} ${r.programme} ${r.department} ${r.examiner_names ?? ""}`.toLowerCase().includes(q.trim().toLowerCase()));

  async function search(kind: "students" | "supervisors", text: string) {
    if (text.trim().length < 2) { if (kind === "students") setStudents([]); else setSupers([]); return; }
    const r = await fetch(`/api/bff/api/v1/examiners/${kind}?q=${encodeURIComponent(text.trim())}`);
    if (r.ok) { const j = await r.json(); if (kind === "students") setStudents(j); else setSupers(j); }
  }
  async function post(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/examiners${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
      const j = (await r.json().catch(() => null)) as Record<string, unknown> | null;
      if (!r.ok) { const p = (j as unknown as Problem) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return null; }
      notify(reason); router.refresh(); return j;
    } finally { setBusy(false); }
  }
  async function create() {
    if (!student || !f.title.trim() || !f.session) return;
    const j = await post("/projects", { studentId: student.id, session: f.session, title: f.title.trim(), abstractText: f.abstractText || null, keywords: f.keywords || null, projectType: f.projectType || null, submittedOn: f.submittedOn || null, supervisorId: supervisor?.id ?? null, supervisorName: supervisor ? null : f.supervisorName || null, coSupervisor: f.coSupervisor || null, courseCode: f.courseCode || null }, `Project registered for ${student.name}`);
    if (j) { setOpen(false); router.push(`/examiners/projects/${j.id}`); }
  }
  async function doAssign() {
    if (!assign || !a.examinerId || !a.deadline) return;
    const ex = examiners.find((e) => e.id === a.examinerId);
    const j = await post("/assignments", { projectId: assign.id, examinerId: a.examinerId, rubricId: a.rubricId || null, deadline: a.deadline, examDate: a.examDate || null }, `${assign.student}'s project assigned to ${ex?.name ?? "the examiner"}`);
    if (j) { setAssign(null); setA({ examinerId: assignFor, rubricId: "", deadline: "", examDate: "" }); }
  }
  const openAssign = (r: ProjectRow) => { setProblem(null); setA({ examinerId: assignFor, rubricId: rubrics.find((x) => x.kind === r.kind)?.id ?? "", deadline: "", examDate: "" }); setAssign(r); };

  return (
    <>
      <PageHead title="Project Assignments" description="Final-year projects registered for external examination, the examiners each is with, and where every review stands."
        actions={<><Btn kind="primary" onClick={() => { setProblem(null); setStudent(null); setSupervisor(null); setOpen(true); }}>Register a Project</Btn><LinkBtn href="/examiners/assignments">Every Assignment</LinkBtn><LinkBtn href="/examiners/rubrics">Assessment Criteria</LinkBtn></>} />
      {assignFor ? <Note kind="info" title={`Assigning to ${examiners.find((e) => e.id === assignFor)?.name ?? "the chosen examiner"}`}>Choose a project below and click Assign; the examiner is already picked.</Note> : null}
      {problem && !open && !assign ? <ProblemNotice problem={problem} /> : null}
      <div className="scope">
        <div className="scope__f"><label htmlFor="pj-session">Session</label>
          <select id="pj-session" className="ws__select" value={session} onChange={(e) => go(`/examiners/projects${e.target.value ? `?session=${encodeURIComponent(e.target.value)}` : ""}${assignFor ? `${e.target.value ? "&" : "?"}assign=${assignFor}` : ""}`)}>
            <option value="">Every session</option>{sessions.map((s) => <option key={s} value={s}>{s}</option>)}
          </select></div>
        <div className="scope__f grow"><label htmlFor="pj-q">Search</label><input id="pj-q" className="ws__select" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Title, candidate, matric number, programme, examiner" /></div>
      </div>
      <Panel title="Projects" right={`${shown.length} of ${rows.length}`}>
        {shown.length ? (
          <DTable pageSize={0} cols={["Candidate", "Project", "Programme", "Supervisor", "Session|mid", "Documents|mid", "Examiners", "|num"]} rows={shown.map((r) => [
            <span key="c"><strong>{r.student}</strong><div className="sub2 tnum">{r.number} · {r.level} Level</div></span>,
            <span key="t"><Link className="lnk" href={`/examiners/projects/${r.id}`}>{r.title}</Link><div className="sub2">{r.kind === "POSTGRADUATE" ? "Postgraduate" : "Undergraduate"}{r.project_type ? ` · ${r.project_type}` : ""}{r.submitted_on ? ` · submitted ${dayOf(r.submitted_on)}` : ""}</div></span>,
            <span key="p" className="sub2">{r.programme}<div>{r.department}</div></span>,
            <span key="s" className="sub2">{r.supervisor ?? "—"}</span>,
            <span key="se" className="tnum">{r.session}</span>,
            <span key="d" className={`tnum${Number(r.documents) ? "" : " ink-red"}`}>{Number(r.documents)}</span>,
            <span key="e">{r.examiner_names ? <span className="sub2">{r.examiner_names}</span> : <Pil kind="warn">Not assigned</Pil>}{Number(r.submitted) ? <div><Pil kind="ok">{Number(r.submitted)} submitted</Pil></div> : null}</span>,
            <span key="o" className="row row--inline row--tight row--right"><Btn kind={Number(r.examiners) ? "ghost" : "primary"} size="sm" onClick={() => openAssign(r)}>Assign</Btn><LinkBtn href={`/examiners/projects/${r.id}`} size="sm">Open</LinkBtn></span>,
          ])} />
        ) : <PBody><div className="sub2">{rows.length ? "Nothing matches." : "No project registered yet. Register one, release its documents, and assign an examiner."}</div></PBody>}
      </Panel>

      {open ? (
        <Modal title="Register a Project" sub="A finalist's or a postgraduate's project, for external examination" onClose={() => setOpen(false)} wide
          foot={<><Btn kind="ghost" onClick={() => setOpen(false)}>Cancel</Btn><Btn kind="primary" disabled={busy || !student || !f.title.trim() || !f.session} onClick={() => void create()}>Register</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="stack">
            <Field id="np-student" label="Candidate" required hint="Finalists and postgraduates within your reach">
              {student ? <div className="row row--base"><strong>{student.name}</strong><span className="sub2 tnum">{student.number} · {student.programme} · {student.level} Level{student.postgraduate ? " · postgraduate" : ""}</span><Btn kind="ghost" size="sm" onClick={() => setStudent(null)}>Change</Btn></div> : (
                <>
                  <input id="np-student" className="ctl" value={sq} onChange={(e) => { setSq(e.target.value); void search("students", e.target.value); }} placeholder="Type a name or matriculation number" autoComplete="off" />
                  {students.length ? <ul className="plain stack mt-2">{students.map((s) => <li key={s.id}><button type="button" className="lnk" onClick={() => { setStudent(s); setStudents([]); if (s.pg_topic && !f.title) setF({ ...f, title: s.pg_topic }); }}>{s.name}</button> <span className="sub2 tnum">{s.number} · {s.programme}{s.pg_topic ? ` · research: ${s.pg_topic}` : ""}</span></li>)}</ul> : null}
                </>
              )}
            </Field>
            <div className="grid grid--3">
              <Field id="np-session" label="Academic session" required><select id="np-session" className="ctl" value={f.session} onChange={(e) => setF({ ...f, session: e.target.value })}>{sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></Field>
              <Field id="np-type" label="Project type"><input id="np-type" className="ctl" value={f.projectType} onChange={(e) => setF({ ...f, projectType: e.target.value })} placeholder="e.g. Software, Field study, Thesis" /></Field>
              <Field id="np-sub" label="Submission date"><input id="np-sub" className="ctl" type="date" value={f.submittedOn} onChange={(e) => setF({ ...f, submittedOn: e.target.value })} /></Field>
            </div>
            <Field id="np-title" label="Project title" required><input id="np-title" className="ctl" value={f.title} onChange={(e) => setF({ ...f, title: e.target.value })} maxLength={400} /></Field>
            <Field id="np-abs" label="Abstract"><textarea id="np-abs" className="ctl" rows={4} value={f.abstractText} onChange={(e) => setF({ ...f, abstractText: e.target.value })} maxLength={8000} /></Field>
            <div className="grid grid--3">
              <Field id="np-kw" label="Keywords"><input id="np-kw" className="ctl" value={f.keywords} onChange={(e) => setF({ ...f, keywords: e.target.value })} /></Field>
              <Field id="np-course" label="Project course code" hint="For undergraduates, e.g. CSC 499; links moderation to the score sheet"><input id="np-course" className="ctl tnum" value={f.courseCode} onChange={(e) => setF({ ...f, courseCode: e.target.value.toUpperCase() })} /></Field>
              <Field id="np-co" label="Co-supervisor"><input id="np-co" className="ctl" value={f.coSupervisor} onChange={(e) => setF({ ...f, coSupervisor: e.target.value })} /></Field>
            </div>
            <Field id="np-sup" label="Supervisor" hint="A lecturer on the register, or a name typed">
              {supervisor ? <div className="row row--base"><strong>{supervisor.name}</strong><span className="sub2">{supervisor.department ?? ""}</span><Btn kind="ghost" size="sm" onClick={() => setSupervisor(null)}>Change</Btn></div> : (
                <>
                  <div className="row"><input id="np-sup" className="ctl" style={{ flex: "1 1 200px" }} value={vq} onChange={(e) => { setVq(e.target.value); void search("supervisors", e.target.value); }} placeholder="Search the lecturers" autoComplete="off" /><input className="ctl" style={{ flex: "1 1 200px" }} value={f.supervisorName} onChange={(e) => setF({ ...f, supervisorName: e.target.value })} placeholder="Or type the supervisor's name" aria-label="Supervisor's name" /></div>
                  {supers.length ? <ul className="plain stack mt-2">{supers.map((s) => <li key={s.id}><button type="button" className="lnk" onClick={() => { setSupervisor(s); setSupers([]); }}>{s.name}</button> <span className="sub2">{s.staff_number ?? ""} {s.department ?? ""}</span></li>)}</ul> : null}
                </>
              )}
            </Field>
          </div>
        </Modal>
      ) : null}
      {assign ? (
        <Modal title={`Assign: ${assign.title}`} sub={`${assign.student} · ${assign.programme}`} onClose={() => setAssign(null)}
          foot={<><Btn kind="ghost" onClick={() => setAssign(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !a.examinerId || !a.deadline} onClick={() => void doAssign()}>Assign the Project</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="stack">
            <Field id="as-ex" label="External examiner" required hint="Active examiners only; a project may go to more than one">
              <select id="as-ex" className="ctl" value={a.examinerId} onChange={(e) => setA({ ...a, examinerId: e.target.value })}><option value="">Choose…</option>{examiners.map((e) => <option key={e.id} value={e.id}>{e.name} · {e.institution} · {Number(e.pending)} pending</option>)}</select>
            </Field>
            <Field id="as-rubric" label="Assessment form"><select id="as-rubric" className="ctl" value={a.rubricId} onChange={(e) => setA({ ...a, rubricId: e.target.value })}><option value="">The default for this kind of project</option>{rubrics.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}</select></Field>
            <div className="row">
              <Field id="as-deadline" label="Review deadline" required style={{ flex: "1 1 160px" }}><input id="as-deadline" className="ctl" type="date" value={a.deadline} onChange={(e) => setA({ ...a, deadline: e.target.value })} /></Field>
              <Field id="as-exam" label="Examination date" hint="Where a defence is held" style={{ flex: "1 1 160px" }}><input id="as-exam" className="ctl" type="date" value={a.examDate} onChange={(e) => setA({ ...a, examDate: e.target.value })} /></Field>
            </div>
            {!Number(assign.documents) ? <Note kind="bad" title="No document released yet">The examiner can be assigned now, but will find nothing to read until the report is released on the project&rsquo;s page.</Note> : null}
          </div>
        </Modal>
      ) : null}
    </>
  );
}
