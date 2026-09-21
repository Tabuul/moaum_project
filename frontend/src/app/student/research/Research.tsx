"use client";

/**
 * The postgraduate student's own research & thesis view (V209). It reads their research record — created
 * on first view — and drives the student-side steps: stating the topic and submitting the proposal. The
 * School runs the rest from its desk; the stage, supervisors and milestone log show here so the candidate
 * always sees where the work stands.
 */
import { useCallback, useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Note, Panel, PBody } from "@/components/proto/ui";
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
  supervisors: Supervisor[]; events: Event[];
}
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

  const load = useCallback(async () => {
    try {
      const res = await fetch("/api/bff/api/v1/pg/research/me", { cache: "no-store" });
      setProblem(null);
      const j = await res.json().catch(() => null);
      if (!res.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: res.status, title: res.statusText }); setLoading(false); return; }
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
      if (!res.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: res.status, title: res.statusText }); return; }
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
          <ol className="pg-steps">
            {steps.map((s) => (
              <li key={s.label} className={s.done ? "pg-step pg-step--done" : "pg-step"}>
                <span className="pg-step__dot" aria-hidden />
                <span className="pg-step__label">{s.label}</span>
                <span className="sub2">{s.when ? fmt(s.when) : (s.done ? "" : "pending")}</span>
              </li>
            ))}
          </ol>
        </PBody>
      </Panel>

      <Panel title="Supervision">
        <PBody>
          {r.supervisors.length ? r.supervisors.map((s, i) => (
            <div key={i} className="sub2">{s.name} — {s.role.toLowerCase()}{s.is_external ? " (external)" : ""}</div>
          )) : <div className="sub2">No supervisor has been assigned yet. The department assigns supervisors after registration (Policy 14).</div>}
        </PBody>
      </Panel>

      <Panel title="Topic & proposal">
        <PBody>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="field"><label htmlFor="topic">Research topic</label>
            <input id="topic" className="ctl" value={topic} onChange={(e) => setTopic(e.target.value)} disabled={!canEditTopic || busy} placeholder="State your working topic" />
          </div>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 8 }}>
            {canEditTopic ? (
              <button type="button" className="btn btn--ghost btn--sm" disabled={busy || !topic.trim()} onClick={() => void act("/topic", { topic: topic.trim() }, "Set research topic")}>Save topic</button>
            ) : null}
            {!proposalDone ? (
              <button type="button" className="btn btn--primary btn--sm" disabled={busy || !topic.trim()} onClick={() => void act("/proposal", {}, "Submit research proposal")}>Submit proposal</button>
            ) : (
              <span className="sub2">Proposal submitted {fmt(r.proposal_submitted_at)}{r.proposal_approved_at ? ` · approved ${fmt(r.proposal_approved_at)}` : " · awaiting the School"}.</span>
            )}
          </div>
          {canEditTopic ? <div className="sub2" style={{ marginTop: 6 }}>A Master&rsquo;s proposal is due within 6 months, a PhD within 12 months, of first registration (Policy 21).</div> : null}
        </PBody>
      </Panel>

      <Panel title="Milestones">
        <PBody>
          {r.events.length ? (
            <div style={{ display: "grid", gap: 4 }}>
              {r.events.map((e, i) => (
                <div key={i} className="sub2"><span className="tnum">{fmt(e.at)}</span> — {e.note ?? STAGE_LABEL[e.stage] ?? e.stage}</div>
              ))}
            </div>
          ) : <div className="sub2">No milestone recorded yet.</div>}
        </PBody>
      </Panel>

      <style>{`
        .pg-steps { list-style: none; margin: 0; padding: 0; display: grid; gap: 2px; }
        .pg-step { display: grid; grid-template-columns: 20px 1fr auto; align-items: center; gap: 10px; padding: 7px 0; }
        .pg-step__dot { width: 12px; height: 12px; border-radius: 50%; border: 2px solid var(--line-2); background: transparent; margin-left: 2px; }
        .pg-step--done .pg-step__dot { background: var(--green-ink); border-color: var(--green-ink); }
        .pg-step--done .pg-step__label { font-weight: 600; }
      `}</style>
    </>
  );
}
