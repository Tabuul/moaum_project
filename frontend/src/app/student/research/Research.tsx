"use client";

import { notifyProblem } from "@/components/proto/Toast";
/**
 * The postgraduate student's own research & thesis view (V209). It reads their research record — created
 * on first view — and drives the student-side steps: stating the topic and submitting the proposal. The
 * School runs the rest from its desk; the stage, supervisors and milestone log show here so the candidate
 * always sees where the work stands.
 */
import { useCallback, useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody } from "@/components/proto/ui";
import { Field, Steps } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Supervisor { name: string; role: string; is_external: boolean }
interface Event { stage: string; note: string | null; at: string }
interface Research {
  degree_kind: string; stage: string; topic: string | null;
  proposal_submitted_at: string | null; proposal_approved_at: string | null;
  seminar_held_at: string | null; pgsr: string | null; title_registered_at: string | null; plagiarism_pct: number | null;
  draft_submitted_at: string | null; viva_held_at: string | null; viva_grade: string | null; viva_outcome: string | null;
  corrections_due: string | null; final_submitted_at: string | null; cleared_at: string | null;
  award_recommended_at: string | null; awarded_at: string | null;
  programme_name: string; department_name: string; faculty_name: string;
  supervisors: Supervisor[]; panel: PanelMember[]; events: Event[]; documents?: ResearchDoc[];
}
interface PanelMember { name: string; role: string; is_external: boolean }
interface ResearchDoc { id: string; kind: string; version: number; filename: string; content_type: string; size_bytes: number; note: string | null; status: string; reviewer_note: string | null; reviewed_at: string | null; by_candidate: boolean; uploaded_at: string }
const DOC_KIND: Record<string, string> = { PROPOSAL: "Research proposal", SEMINAR_PAPER: "Seminar paper", PLAGIARISM_REPORT: "Plagiarism report", DRAFT: "Draft for examination", CORRECTED: "Corrected copy", FINAL: "Final copy", OTHER: "Other document" };
const DOC_STATUS: Record<string, ["grey" | "ok" | "bad", string]> = { SUBMITTED: ["grey", "Submitted"], ACCEPTED: ["ok", "Accepted"], RETURNED: ["bad", "Returned"] };
/** which document the stage calls for next, so the right one is offered first */
function docKindFor(stage: string): string {
  if (["REGISTERED", "SUPERVISED", "PROPOSAL_SUBMITTED"].includes(stage)) return "PROPOSAL";
  if (stage === "PROPOSAL_APPROVED") return "SEMINAR_PAPER";
  if (stage === "SEMINAR_HELD") return "PLAGIARISM_REPORT";
  if (["TITLE_REGISTERED", "PANEL_CONSTITUTED"].includes(stage)) return "DRAFT";
  if (stage === "CORRECTIONS") return "CORRECTED";
  if (stage === "VIVA_HELD") return "FINAL";
  return "OTHER";
}
const DOC_MIME = ["application/pdf", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"];
function readBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(",")[1] ?? "");
    reader.onerror = () => reject(new Error("read failed"));
    reader.readAsDataURL(file);
  });
}
const PANEL_ROLE: Record<string, string> = {
  CHAIR: "chair / HOD", EXTERNAL: "external examiner", SUPERVISOR: "supervisor", CO_SUPERVISOR: "co-supervisor",
  INTERNAL: "internal examiner", PGSR: "PGSR", COORDINATOR: "PG coordinator",
};
const VIVA_OUTCOME: Record<string, string> = {
  PASS_CLEAN: "Passed, no corrections", PASS_MINOR: "Passed, minor corrections", PASS_MAJOR: "Passed, major corrections",
  SECOND_ORAL: "Second oral required", FAIL: "Failed",
};
const KIND: Record<string, string> = { PROJECT: "Project report", DISSERTATION: "Dissertation", THESIS: "Thesis" };
const STAGE_LABEL: Record<string, string> = {
  REGISTERED: "Registered", SUPERVISED: "Supervisor assigned", PROPOSAL_SUBMITTED: "Proposal submitted",
  PROPOSAL_APPROVED: "Proposal approved", SEMINAR_HELD: "Seminar held", TITLE_REGISTERED: "Title registered",
  PANEL_CONSTITUTED: "Panel constituted", DRAFT_SUBMITTED: "Draft submitted", VIVA_HELD: "Viva held",
  CORRECTIONS: "Corrections", FINAL_SUBMITTED: "Final submitted", CLEARED: "Cleared", AWARD_RECOMMENDED: "Recommended to Senate",
  AWARDED: "Awarded", WITHDRAWN: "Withdrawn",
};
function fmt(v: string | null): string {
  if (!v) return "—";
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" });
}

export function Research() {
  const [r, setR] = useState<Research | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [loading, setLoading] = useState(true);
  const [topic, setTopic] = useState("");
  const [busy, setBusy] = useState(false);
  const [docKind, setDocKind] = useState<string | null>(null);
  const [docFile, setDocFile] = useState<File | null>(null);
  const [docNote, setDocNote] = useState("");
  const [docKey, setDocKey] = useState(0);

  async function submitDocument() {
    if (!docFile || !r) return;
    const kind = docKind ?? docKindFor(r.stage);
    const mime = docFile.type || (docFile.name.toLowerCase().endsWith(".docx") ? DOC_MIME[1] : "application/pdf");
    if (!DOC_MIME.includes(mime) || docFile.size > 25 * 1024 * 1024) {
      const pr: Problem = { status: 422, title: "A research document is a PDF or a Word (.docx) file of at most 25 MB." }; setProblem(pr); notifyProblem(pr); return;
    }
    const b64 = await readBase64(docFile);
    await act("/documents", { kind, filename: docFile.name, contentType: mime, contentBase64: b64, note: docNote.trim() || null }, `${DOC_KIND[kind] ?? kind} submitted`);
    setDocFile(null); setDocNote(""); setDocKey((k) => k + 1);
  }

  const load = useCallback(async () => {
    try {
      const res = await fetch("/api/bff/api/v1/pg/research/me", { cache: "no-store" });
      setProblem(null);
      const j = await res.json().catch(() => null);
      if (!res.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: res.status, title: res.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: res.status, title: res.statusText }); setLoading(false); return; }
      const data = j as Research;
      setR(data);
      setTopic(data.topic ?? "");
    } finally { setLoading(false); }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function act(path: string, body: unknown, reason: string) {
    setBusy(true); setProblem(null);
    try {
      const res = await fetch(`/api/bff/api/v1/pg/research/me${path}`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body),
      });
      const j = await res.json().catch(() => null);
      if (!res.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: res.status, title: res.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: res.status, title: res.statusText }); return; }
      setR(j as Research);
      setTopic((j as Research).topic ?? "");
    } finally { setBusy(false); }
  }

  if (loading) return <Note kind="info" title="Loading your research record…">One moment.</Note>;
  if (!r) return <ProblemNotice problem={problem ?? { status: 500, title: "The research record could not be read." }} />;

  const proposalDone = !!r.proposal_submitted_at;
  const canEditTopic = !["PROPOSAL_APPROVED", "SEMINAR_HELD", "TITLE_REGISTERED", "PANEL_CONSTITUTED", "DRAFT_SUBMITTED", "VIVA_HELD", "CORRECTIONS", "FINAL_SUBMITTED", "CLEARED", "AWARD_RECOMMENDED", "AWARDED"].includes(r.stage);
  const steps: { label: string; done: boolean; when: string | null }[] = [
    { label: "Supervisor assigned", done: r.supervisors.length > 0 || ["SUPERVISED", "PROPOSAL_SUBMITTED", "PROPOSAL_APPROVED", "SEMINAR_HELD", "TITLE_REGISTERED", "PANEL_CONSTITUTED", "DRAFT_SUBMITTED", "VIVA_HELD", "CORRECTIONS", "FINAL_SUBMITTED", "CLEARED", "AWARD_RECOMMENDED", "AWARDED"].includes(r.stage), when: null },
    { label: "Proposal submitted", done: proposalDone, when: r.proposal_submitted_at },
    { label: "Proposal approved", done: !!r.proposal_approved_at, when: r.proposal_approved_at },
    { label: "Research seminar", done: !!r.seminar_held_at, when: r.seminar_held_at },
    { label: "Title registered", done: !!r.title_registered_at, when: r.title_registered_at },
    { label: "Draft & viva", done: !!r.viva_held_at, when: r.viva_held_at },
    { label: "Corrections", done: !!r.corrections_due || !!r.final_submitted_at, when: r.corrections_due },
    { label: "Final submission & clearance", done: !!r.cleared_at, when: r.cleared_at },
    { label: "Award", done: !!r.awarded_at, when: r.awarded_at },
  ];

  return (
    <>
      <Note kind={r.awarded_at ? "ok" : "info"} title={`${KIND[r.degree_kind] ?? r.degree_kind} — ${STAGE_LABEL[r.stage] ?? r.stage}`}>
        {r.programme_name} · {r.department_name}. Your research runs from supervision through the proposal, seminar, title, panel and viva to the award; the School records each step.
      </Note>

      <Panel title="Progress">
        <PBody>
          <Steps list={steps.map((s) => [s.done ? "done" : "todo", s.label, s.when ? fmt(s.when) : (s.done ? "" : "pending")])} />
        </PBody>
      </Panel>

      <Panel title="Supervision">
        <PBody>
          {r.supervisors.length ? r.supervisors.map((s, i) => (
            <div key={i} className="sub2">{s.name} — {s.role.toLowerCase()}{s.is_external ? " (external)" : ""}</div>
          )) : <div className="sub2">No supervisor has been assigned yet. The department assigns supervisors after registration (Policy 14).</div>}
        </PBody>
      </Panel>

      {(r.panel?.length ?? 0) > 0 ? (
        <Panel title="Panel of examiners">
          <PBody>
            {r.panel.map((p, i) => (
              <div key={i} className="sub2">{p.name} — {PANEL_ROLE[p.role] ?? p.role.toLowerCase()}{p.is_external ? " (external)" : ""}</div>
            ))}
          </PBody>
        </Panel>
      ) : null}

      {r.viva_held_at ? (
        <Note kind={r.viva_outcome === "FAIL" ? "bad" : "ok"} title={`Viva — ${VIVA_OUTCOME[r.viva_outcome ?? ""] ?? r.viva_outcome ?? ""}`}>
          Held {fmt(r.viva_held_at)}{r.viva_grade ? ` · grade ${r.viva_grade}` : ""}.
          {r.corrections_due ? ` Corrections are due by ${fmt(r.corrections_due)}.` : ""}
          {r.cleared_at ? ` Cleared for binding on ${fmt(r.cleared_at)}.` : ""}
          {r.awarded_at ? ` Awarded by Senate on ${fmt(r.awarded_at)}.` : ""}
        </Note>
      ) : null}

      <Panel title="Topic & proposal">
        <PBody>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <Field id="topic" label="Research topic">
            <input id="topic" className="ctl" value={topic} onChange={(e) => setTopic(e.target.value)} disabled={!canEditTopic || busy} placeholder="State your working topic" />
          </Field>
          <div className="row mt-2">
            {canEditTopic ? (
              <Btn kind="ghost" disabled={busy || !topic.trim()} onClick={() => void act("/topic", { topic: topic.trim() }, "Set research topic")}>Save topic</Btn>
            ) : null}
            {!proposalDone ? (
              <Btn kind="primary" disabled={busy || !topic.trim()} onClick={() => void act("/proposal", {}, "Submit research proposal")}>Submit proposal</Btn>
            ) : (
              <span className="sub2">Proposal submitted {fmt(r.proposal_submitted_at)}{r.proposal_approved_at ? ` · approved ${fmt(r.proposal_approved_at)}` : " · awaiting the School"}.</span>
            )}
          </div>
          {canEditTopic ? <div className="sub2 mt-2">A Master&rsquo;s proposal is due within 6 months, a PhD within 12 months, of first registration (Policy 21).</div> : null}
        </PBody>
      </Panel>

      <Panel title="Documents" right={r.documents?.length ? `${r.documents.length} on record · every version kept` : "Nothing submitted yet"}>
        <PBody>
          {r.documents && r.documents.length ? (
            <div className="stack" style={{ gap: "var(--s-1)" }}>
              {r.documents.map((d) => {
                const [kind, word] = DOC_STATUS[d.status] ?? ["grey", d.status];
                return (
                  <div key={d.id} className="row row--between" style={{ gap: "var(--s-3)", padding: "8px 0", borderBottom: "1px solid var(--line)" }}>
                    <span style={{ minWidth: 0 }}>
                      <a className="lnk b600" href={`/api/bff/api/v1/pg/research/me/documents/${d.id}/content`} target="_blank" rel="noopener">{DOC_KIND[d.kind] ?? d.kind} · version {d.version}</a>
                      <div className="sub2">{d.filename} · {fmt(d.uploaded_at)}{d.note ? ` · ${d.note}` : ""}</div>
                      {d.reviewer_note ? <div className="sub2">The School: {d.reviewer_note}</div> : null}
                    </span>
                    <span className={`pill pill--${kind}`}>{word}</span>
                  </div>
                );
              })}
            </div>
          ) : null}
          {!["AWARDED", "WITHDRAWN"].includes(r.stage) ? (
            <div className="row row--end mt-3">
              <Field id="rd-kind" label="Document" style={{ flex: "1 1 200px" }}>
                <select id="rd-kind" className="ctl" value={docKind ?? docKindFor(r.stage)} onChange={(e) => setDocKind(e.target.value)}>
                  {Object.entries(DOC_KIND).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </Field>
              <Field id="rd-file" label="File" hint="PDF or Word (.docx), at most 25 MB" style={{ flex: "2 1 240px" }}>
                <input key={docKey} id="rd-file" type="file" className="ctl" accept=".pdf,.docx" onChange={(e) => setDocFile(e.target.files?.[0] ?? null)} />
              </Field>
              <Field id="rd-note" label="Note" style={{ flex: "2 1 200px" }}>
                <input id="rd-note" className="ctl" value={docNote} onChange={(e) => setDocNote(e.target.value)} placeholder="Optional — what changed in this version" />
              </Field>
              <Btn kind="primary" disabled={busy || !docFile} onClick={() => void submitDocument()}>Submit Document</Btn>
            </div>
          ) : null}
          <div className="sub2 mt-2">A new version never replaces an earlier one. A draft submitted once your title is registered moves your record to draft submitted; a final copy after the oral examination moves it to final submitted.</div>
        </PBody>
      </Panel>

      <Panel title="Milestones">
        <PBody>
          {r.events.length ? (
            <div style={{ display: "grid", gap: "var(--s-1)" }}>
              {r.events.map((e, i) => (
                <div key={i} className="sub2"><span className="tnum">{fmt(e.at)}</span> — {e.note ?? STAGE_LABEL[e.stage] ?? e.stage}</div>
              ))}
            </div>
          ) : <div className="sub2">No milestone recorded yet.</div>}
        </PBody>
      </Panel>
    </>
  );
}
