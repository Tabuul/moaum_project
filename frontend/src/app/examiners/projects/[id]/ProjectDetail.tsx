"use client";
/** One project on the desk (V254): the documents released for external examination (and withheld again), the examiners
 *  it is with and each one's standing, an examiner assigned, the history. */
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { DOC_KIND, DOC_MAX, DOC_MIME, Documents, History, RecommendationPil, StatusPil, dayOf, daysWords, mimeOf, readBase64, type AssignmentRow, type Doc, type Event, type ExaminerRow, type ProjectRow, type Rubric } from "@/lib/examiners";

export interface ProjectFull extends Omit<ProjectRow, "documents"> { documents: Doc[]; assignments: AssignmentRow[]; history: Event[] }

export function ProjectDetail({ p, examiners, rubrics }: { p: ProjectFull; examiners: ExaminerRow[]; rubrics: Rubric[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [kind, setKind] = useState("REPORT");
  const [file, setFile] = useState<File | null>(null);
  const [fileKey, setFileKey] = useState(0);
  const [assign, setAssign] = useState(false);
  const [a, setA] = useState({ examinerId: "", rubricId: rubrics.find((r) => r.kind === p.kind)?.id ?? "", deadline: "", examDate: "" });
  const live = p.assignments.filter((x) => !x.ended_at);

  async function call(path: string, method: "POST" | "PUT", body: unknown, reason: string): Promise<boolean> {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/examiners${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      if (!r.ok) { const pr = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return false; }
      notify(reason); router.refresh(); return true;
    } finally { setBusy(false); }
  }
  async function release() {
    if (!file) return;
    const mime = mimeOf(file);
    if (!DOC_MIME.includes(mime) || file.size > DOC_MAX) { const pr = { status: 422, title: "A project document is a PDF, a Word or PowerPoint file, or a ZIP, of at most 25 MB." }; setProblem(pr); notifyProblem(pr); return; }
    const b64 = await readBase64(file);
    if (await call(`/projects/${p.id}/documents`, "POST", { kind, filename: file.name, contentType: mime, contentBase64: b64 }, `${DOC_KIND[kind]} released: ${file.name}`)) { setFile(null); setFileKey((k) => k + 1); }
  }

  return (
    <>
      <PageHead eyebrow={`${p.kind === "POSTGRADUATE" ? "Postgraduate" : "Undergraduate"} project · ${p.session}`} title={p.title} description={`${p.student} (${p.number}) · ${p.programme}, ${p.department}`}
        actions={<><Btn kind="primary" onClick={() => { setProblem(null); setAssign(true); }}>Assign an Examiner</Btn><LinkBtn href="/examiners/projects">All Projects</LinkBtn></>} />
      {problem && !assign ? <ProblemNotice problem={problem} /> : null}
      <div className="grid grid--2">
        <Panel title="The project" right={p.project_type ?? "—"}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[["Candidate", <strong key="c">{p.student}</strong>], ["Student ID", <span key="n" className="tnum">{p.number}</span>], ["Programme", p.programme], ["Faculty", p.faculty], ["Supervisor", p.supervisor ?? "—"], ["Co-supervisor", p.co_supervisor ?? "—"], ["Submitted", dayOf(p.submitted_on)], ["Project course", p.course_code ?? "—"], ["Keywords", p.keywords ?? "—"], ["Registered", dayOf(p.created_at)]]} />
            {p.abstract ? <><div className="hr" /><div className="eyebrow mb-1">Abstract</div><div style={{ whiteSpace: "pre-wrap" }}>{p.abstract}</div></> : null}
            {p.pg_research_id ? <div className="mt-2"><Pil kind="info">On the postgraduate research record</Pil></div> : null}
          </PBody>
        </Panel>
        <Panel title="Documents for external examination" right={`${p.documents.filter((d) => d.released !== false).length} released`}>
          <PBody>
            <Documents items={p.documents} href={(d) => `/api/bff/api/v1/examiners/projects/${p.id}/documents/${d.id}/content`}
              extra={(d) => <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void call(`/projects/${p.id}/documents/${d.id}`, "PUT", { released: d.released === false }, d.released === false ? `${d.filename} released` : `${d.filename} withheld`)}>{d.released === false ? "Release" : "Withhold"}</Btn>} />
            <div className="row row--end mt-3">
              <Field id="pd-kind" label="Kind" style={{ flex: "1 1 160px" }}><select id="pd-kind" className="ctl" value={kind} onChange={(e) => setKind(e.target.value)}>{Object.entries(DOC_KIND).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
              <Field id="pd-file" label="File" hint="PDF, Word, PowerPoint or ZIP, at most 25 MB" style={{ flex: "2 1 220px" }}><input key={fileKey} id="pd-file" type="file" className="ctl" accept=".pdf,.docx,.pptx,.zip" onChange={(e) => setFile(e.target.files?.[0] ?? null)} /></Field>
              <Btn kind="primary" disabled={busy || !file} onClick={() => void release()}>Release</Btn>
            </div>
            <div className="sub2 mt-1">Only what is released here reaches an examiner; nothing internal is ever shown to them.</div>
          </PBody>
        </Panel>
      </div>

      <Panel title="Examiners" right={`${live.length} current${p.assignments.length > live.length ? ` · ${p.assignments.length - live.length} ended` : ""}`}>
        {p.assignments.length ? (
          <DTable pageSize={0} cols={["Examiner", "Assigned|mid", "Deadline|mid", "Status|mid", "Assessment", "|num"]} rows={p.assignments.map((x) => [
            <span key="e"><Link className="lnk b600" href={`/examiners/${x.examiner_id}`}>{x.examiner}</Link><div className="sub2">{x.institution}</div></span>,
            <span key="a" className="tnum sub2">{dayOf(x.assigned_at)}{x.assigned_by ? <div>by {x.assigned_by}</div> : null}</span>,
            <span key="d" className={`tnum${x.overdue ? " ink-red b600" : ""}`}>{dayOf(x.deadline)}<div className="sub2">{daysWords(x.days_left, x.status)}</div></span>,
            <span key="s"><StatusPil status={x.status} />{x.ended_reason ? <div className="sub2">{x.ended_reason}</div> : null}</span>,
            <span key="as">{x.total != null ? <><span className="tnum b600">{x.total} / {x.max_total}</span> <span className="sub2 tnum">{x.percentage}% · {x.grade}</span><div><RecommendationPil value={x.final_recommendation} /></div></> : <span className="sub2">—</span>}</span>,
            <LinkBtn key="o" href={`/examiners/assignments/${x.id}`} size="sm">Open</LinkBtn>,
          ])} />
        ) : <PBody><Note kind="info" title="Not yet assigned">Assign an active examiner by a review deadline. A project may go to more than one examiner; each assessment stands on its own.</Note></PBody>}
      </Panel>

      <Panel title="History" right="Every act on this project"><PBody><History events={p.history} /></PBody></Panel>

      {assign ? (
        <Modal title={`Assign: ${p.title}`} sub={`${p.student} · ${p.programme}`} onClose={() => setAssign(false)}
          foot={<><Btn kind="ghost" onClick={() => setAssign(false)}>Cancel</Btn><Btn kind="primary" disabled={busy || !a.examinerId || !a.deadline} onClick={async () => { if (await call("/assignments", "POST", { projectId: p.id, examinerId: a.examinerId, rubricId: a.rubricId || null, deadline: a.deadline, examDate: a.examDate || null }, `Assigned to ${examiners.find((e) => e.id === a.examinerId)?.name ?? "the examiner"}`)) setAssign(false); }}>Assign the Project</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="stack">
            <Field id="pa-ex" label="External examiner" required><select id="pa-ex" className="ctl" value={a.examinerId} onChange={(e) => setA({ ...a, examinerId: e.target.value })}><option value="">Choose…</option>{examiners.filter((e) => !live.some((x) => x.examiner_id === e.id)).map((e) => <option key={e.id} value={e.id}>{e.name} · {e.institution} · {Number(e.pending)} pending</option>)}</select></Field>
            <Field id="pa-rubric" label="Assessment form"><select id="pa-rubric" className="ctl" value={a.rubricId} onChange={(e) => setA({ ...a, rubricId: e.target.value })}><option value="">The default for this kind of project</option>{rubrics.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}</select></Field>
            <div className="row">
              <Field id="pa-deadline" label="Review deadline" required style={{ flex: "1 1 160px" }}><input id="pa-deadline" className="ctl" type="date" value={a.deadline} onChange={(e) => setA({ ...a, deadline: e.target.value })} /></Field>
              <Field id="pa-exam" label="Examination date" style={{ flex: "1 1 160px" }}><input id="pa-exam" className="ctl" type="date" value={a.examDate} onChange={(e) => setA({ ...a, examDate: e.target.value })} /></Field>
            </div>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
