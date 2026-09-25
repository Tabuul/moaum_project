"use client";

/**
 * The research & thesis desk (V209): the School of Postgraduate Studies runs each candidate's research
 * from supervision through the proposal, seminar, title, panel, viva, corrections, final submission,
 * clearance and the Board's recommendation to Senate — following the Postgraduate Policy. One record per
 * candidate, a stage, the supervisors, and the milestone log. The desk shows the pipeline and advances it.
 */
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { Btn, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface ResearchRow {
  id: string; stage: string; degree_kind: string; topic: string | null; updated_at: string;
  viva_grade: string | null; viva_outcome: string | null;
  matric_no: string | null; admission_no: string | null; surname: string; other_names: string;
  programme_name: string; pg_award: string | null; faculty_name: string; department_name: string;
  supervisors: string | null;
}
export interface ResearchList {
  counts: { total: number; supervision: number; proposal: number; seminar: number; examination: number; finishing: number; awarded: number };
  rows: ResearchRow[];
}
interface Supervisor { name: string; role: string; is_external: boolean; assigned_at: string }
interface PanelMember { name: string; role: string; is_external: boolean }
interface Event { stage: string; note: string | null; at: string }
const PANEL_ROLE: Record<string, string> = {
  CHAIR: "chair / HOD", EXTERNAL: "external examiner", SUPERVISOR: "supervisor", CO_SUPERVISOR: "co-supervisor",
  INTERNAL: "internal examiner", PGSR: "PGSR", COORDINATOR: "PG coordinator",
};
interface ResearchDoc { id: string; kind: string; version: number; filename: string; content_type: string; size_bytes: number; note: string | null; status: string; reviewer_note: string | null; reviewed_at: string | null; by_candidate: boolean; uploaded_at: string }
const DOC_KIND: Record<string, string> = { PROPOSAL: "Proposal", SEMINAR_PAPER: "Seminar paper", PLAGIARISM_REPORT: "Plagiarism report", DRAFT: "Draft", CORRECTED: "Corrected copy", FINAL: "Final copy", OTHER: "Other" };
const DOC_STATUS: Record<string, "grey" | "ok" | "bad"> = { SUBMITTED: "grey", ACCEPTED: "ok", RETURNED: "bad" };
interface Detail extends Omit<ResearchRow, "supervisors"> {
  name: string; entry_session: string; entry_level: number;
  documents?: ResearchDoc[];
  proposal_submitted_at: string | null; proposal_approved_at: string | null;
  seminar_held_at: string | null; pgsr: string | null; title_registered_at: string | null; plagiarism_pct: number | null;
  panel_constituted_at: string | null; draft_submitted_at: string | null;
  viva_held_at: string | null; viva_score: number | null; corrections_due: string | null;
  final_submitted_at: string | null; cleared_at: string | null; award_recommended_at: string | null; awarded_at: string | null;
  supervisors: Supervisor[]; panel: PanelMember[]; events: Event[];
}

const STAGES: [string, string][] = [
  ["", "All stages"],
  ["REGISTERED", "Registered — awaiting supervisor"],
  ["SUPERVISED", "Supervised"],
  ["PROPOSAL_SUBMITTED", "Proposal submitted"],
  ["PROPOSAL_APPROVED", "Proposal approved"],
  ["SEMINAR_HELD", "Seminar held"],
  ["TITLE_REGISTERED", "Title registered"],
  ["PANEL_CONSTITUTED", "Panel constituted"],
  ["DRAFT_SUBMITTED", "Draft submitted"],
  ["VIVA_HELD", "Viva held"],
  ["CORRECTIONS", "Corrections"],
  ["FINAL_SUBMITTED", "Final submitted"],
  ["CLEARED", "Cleared"],
  ["AWARD_RECOMMENDED", "Recommended to Senate"],
  ["AWARDED", "Awarded"],
  ["WITHDRAWN", "Withdrawn"],
];
const STAGE_LABEL: Record<string, string> = Object.fromEntries(STAGES);
const KIND: Record<string, string> = { PROJECT: "Project report", DISSERTATION: "Dissertation", THESIS: "Thesis" };

// what the desk can do next from a given stage
const NEXT: Record<string, { action: string; label: string; needs?: ("pgsr" | "plagiarism" | "viva" | "due")[] }[]> = {
  SUPERVISED: [{ action: "SUBMIT_PROPOSAL", label: "Record proposal submitted" }],
  PROPOSAL_SUBMITTED: [{ action: "APPROVE_PROPOSAL", label: "Approve proposal" }],
  PROPOSAL_APPROVED: [{ action: "SEMINAR", label: "Record seminar", needs: ["pgsr"] }],
  SEMINAR_HELD: [{ action: "REGISTER_TITLE", label: "Register title", needs: ["plagiarism"] }],
  TITLE_REGISTERED: [{ action: "PANEL", label: "Constitute panel" }],
  PANEL_CONSTITUTED: [{ action: "DRAFT", label: "Record draft submission" }],
  DRAFT_SUBMITTED: [{ action: "VIVA", label: "Record viva", needs: ["viva"] }],
  VIVA_HELD: [{ action: "CORRECTIONS", label: "Corrections required", needs: ["due"] }, { action: "FINAL", label: "Record final submission" }],
  CORRECTIONS: [{ action: "FINAL", label: "Record final submission" }],
  FINAL_SUBMITTED: [{ action: "CLEAR", label: "Clear for binding" }],
  CLEARED: [{ action: "RECOMMEND", label: "Recommend to Senate" }],
  AWARD_RECOMMENDED: [{ action: "AWARD", label: "Record Senate award" }],
};

function fmt(v: string | null | undefined): string {
  if (!v) return "—";
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" });
}

export function PgResearch({ initialStage, view, problem, actingOffice }: { initialStage: string; view: ResearchList | null; problem: Problem | null; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["pgschool", "pgsecretary", "super"].includes(actingOffice ?? "");
  const [stage, setStage] = useState(initialStage);
  const [selected, setSelected] = useState<string | null>(null);
  const [detail, setDetail] = useState<Detail | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(problem);
  // inline action inputs
  const [sup, setSup] = useState({ name: "", role: "FIRST", external: false });
  const [pan, setPan] = useState({ name: "", role: "EXTERNAL", external: false });
  const [pgsr, setPgsr] = useState("");
  const [plag, setPlag] = useState("");
  const [viva, setViva] = useState({ score: "", outcome: "PASS_MINOR" });
  const [due, setDue] = useState("");

  function onStage(s: string) {
    setStage(s);
    router.push(s ? `/admissions/postgraduate/research?stage=${encodeURIComponent(s)}` : "/admissions/postgraduate/research");
  }

  const loadDetail = useCallback(async (id: string) => {
    const r = await fetch(`/api/bff/api/v1/pg/research/${id}`, { cache: "no-store" });
    setErr(null);
    const j = await r.json().catch(() => null);
    if (!r.ok) { setErr(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
    setDetail(j as Detail);
  }, []);

  useEffect(() => {
    if (!selected) return;
    void (async () => { await loadDetail(selected); })();
  }, [selected, loadDetail]);

  async function post(path: string, body: unknown, reason: string) {
    if (!selected) return;
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/pg/research/${selected}${path}`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setDetail(j as Detail);
      notify(reason);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  async function doAction(action: string, needs?: string[]) {
    const body: Record<string, unknown> = { action };
    if (needs?.includes("pgsr")) body.pgsr = pgsr.trim();
    if (needs?.includes("plagiarism")) body.plagiarismPct = Number(plag) || 0;
    if (needs?.includes("viva")) { body.vivaScore = Number(viva.score) || 0; body.vivaOutcome = viva.outcome; }
    if (needs?.includes("due")) body.correctionsDue = due.trim();
    await post("/action", body, `Research: ${action.replace(/_/g, " ").toLowerCase()}`);
    setPgsr(""); setPlag(""); setViva({ score: "", outcome: "PASS_MINOR" }); setDue("");
  }

  const rows = view?.rows ?? [];
  const c = view?.counts;
  const nexts = detail ? (NEXT[detail.stage] ?? []) : [];
  const sups = detail?.supervisors ?? [];
  const panel = detail?.panel ?? [];

  return (
    <>
      {err ? <ProblemNotice problem={err} /> : null}
      {c ? (
        <Tiles items={[
          ["In the pipeline", String(c.total), null, "All research candidates"],
          ["Supervision", String(c.supervision), c.supervision ? "var(--chrome)" : null, "Registered / supervised"],
          ["Proposal", String(c.proposal), null, "Submitted / approved"],
          ["Seminar & title", String(c.seminar), null, "Seminar / title registered"],
          ["Examination", String(c.examination), c.examination ? "var(--chrome)" : null, "Panel · draft · viva · corrections"],
          ["Awarded", String(c.awarded), c.awarded ? "var(--green-ink)" : null, "Approved by Senate"],
        ]} />
      ) : null}

      <Panel title="Research pipeline" right={
        <select className="ctl" value={stage} onChange={(e) => onStage(e.target.value)} style={{ maxWidth: 260 }}>
          {STAGES.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
        </select>
      }>
        {rows.length ? (
          <DTable
            cols={["Candidate", "Programme", "Kind|mid", "Stage|mid", "Supervisors", "Updated|num"]}
            rows={rows.map((r) => [
              <button key="n" className="linklike" onClick={() => setSelected(r.id)} style={{ textAlign: "left" }}>
                <span className="b600">{r.surname}, {r.other_names}</span>
                <div className="sub2 tnum">{r.matric_no ?? r.admission_no ?? ""}</div>
              </button>,
              <span key="p"><span>{r.programme_name}</span><div className="sub2">{r.department_name}</div></span>,
              <span key="k" className="sub2">{KIND[r.degree_kind] ?? r.degree_kind}</span>,
              <Pil key="s" kind={r.stage === "AWARDED" ? "ok" : "info"}>{STAGE_LABEL[r.stage] ?? r.stage}</Pil>,
              <span key="v" className="sub2">{r.supervisors ?? "—"}</span>,
              <span key="u" className="tnum sub2">{fmt(r.updated_at)}</span>,
            ])}
            texts={rows.map((r) => `${r.surname} ${r.other_names} ${r.matric_no ?? ""} ${r.programme_name} ${r.stage}`)}
          />
        ) : <PBody><div className="sub2">No research candidate at this stage.</div></PBody>}
      </Panel>

      {detail ? (
        <Panel title={`${detail.name} · ${STAGE_LABEL[detail.stage] ?? detail.stage}`} right={<button className="linklike" onClick={() => { setSelected(null); setDetail(null); }}>Close</button>}>
          <PBody>
            <div className="grid grid--2" style={{ alignItems: "start", gap: "var(--s-4)" }}>
              <div className="stack" style={{ gap: "var(--s-1)" }}>
                <Two a="Programme" b={`${detail.programme_name} · ${KIND[detail.degree_kind] ?? detail.degree_kind}`} />
                <Two a="Department" b={`${detail.department_name} · ${detail.faculty_name}`} />
                <Two a="Number" b={detail.matric_no ?? detail.admission_no ?? "—"} />
                <Two a="Topic" b={detail.topic ?? "— not stated yet"} />
                <Two a="Proposal" b={detail.proposal_approved_at ? `Approved ${fmt(detail.proposal_approved_at)}` : detail.proposal_submitted_at ? `Submitted ${fmt(detail.proposal_submitted_at)}` : "—"} />
                <Two a="Seminar" b={detail.seminar_held_at ? `${fmt(detail.seminar_held_at)}${detail.pgsr ? ` · PGSR ${detail.pgsr}` : ""}` : "—"} />
                <Two a="Title / plagiarism" b={detail.title_registered_at ? `${fmt(detail.title_registered_at)} · ${detail.plagiarism_pct ?? "—"}% originality` : "—"} />
                <Two a="Viva" b={detail.viva_held_at ? `${fmt(detail.viva_held_at)} · ${detail.viva_score ?? "—"}% (${detail.viva_grade ?? "—"}) · ${detail.viva_outcome ?? ""}` : "—"} />
                <Two a="Final / cleared" b={`${detail.final_submitted_at ? fmt(detail.final_submitted_at) : "—"}${detail.cleared_at ? ` · cleared ${fmt(detail.cleared_at)}` : ""}`} />
                <Two a="Award" b={detail.awarded_at ? `Awarded ${fmt(detail.awarded_at)}` : detail.award_recommended_at ? `Recommended ${fmt(detail.award_recommended_at)}` : "—"} />
              </div>

              <div className="stack" style={{ gap: "var(--s-3)" }}>
                <div>
                  <div className="b600 mb-2">Supervisors</div>
                  {sups.length ? sups.map((s, i) => (
                    <div key={i} className="sub2">{s.name} — {s.role.toLowerCase()}{s.is_external ? " (external)" : ""}</div>
                  )) : <div className="sub2">None assigned yet.</div>}
                  {may && !["AWARDED", "WITHDRAWN"].includes(detail.stage) ? (
                    <div className="row row--tight mt-2">
                      <input className="ctl" placeholder="Supervisor name" value={sup.name} onChange={(e) => setSup({ ...sup, name: e.target.value })} style={{ maxWidth: 200 }} />
                      <select className="ctl" value={sup.role} onChange={(e) => setSup({ ...sup, role: e.target.value })} style={{ maxWidth: 120 }}>
                        <option value="FIRST">First</option><option value="SECOND">Second</option><option value="CO">Co</option>
                      </select>
                      <label className="sub2 row" style={{ gap: "var(--s-1)" }}>
                        <input type="checkbox" checked={sup.external} onChange={(e) => setSup({ ...sup, external: e.target.checked })} /> external
                      </label>
                      <Btn kind="ghost" disabled={busy || !sup.name.trim()} onClick={() => { void post("/supervisor", { name: sup.name.trim(), role: sup.role, external: sup.external }, `Assigned supervisor ${sup.name.trim()}`); setSup({ name: "", role: "FIRST", external: false }); }}>Add</Btn>
                    </div>
                  ) : null}
                </div>

                <div>
                  <div className="b600 mb-2">Panel of examiners</div>
                  {panel.length ? panel.map((p, i) => (
                    <div key={i} className="sub2">{p.name} — {PANEL_ROLE[p.role] ?? p.role.toLowerCase()}{p.is_external ? " (external)" : ""}</div>
                  )) : <div className="sub2">Not constituted yet — six for a Master&rsquo;s, seven for a PhD (Policy 24.3).</div>}
                  {may && !["AWARDED", "WITHDRAWN"].includes(detail.stage) ? (
                    <div className="row row--tight mt-2">
                      <input className="ctl" placeholder="Member name" value={pan.name} onChange={(e) => setPan({ ...pan, name: e.target.value })} style={{ maxWidth: 190 }} />
                      <select className="ctl" value={pan.role} onChange={(e) => setPan({ ...pan, role: e.target.value })} style={{ maxWidth: 150 }}>
                        <option value="CHAIR">Chair / HOD</option><option value="EXTERNAL">External examiner</option>
                        <option value="SUPERVISOR">Supervisor</option><option value="CO_SUPERVISOR">Co-supervisor</option>
                        <option value="INTERNAL">Internal examiner</option><option value="PGSR">PGSR</option><option value="COORDINATOR">PG Coordinator</option>
                      </select>
                      <label className="sub2 row" style={{ gap: "var(--s-1)" }}>
                        <input type="checkbox" checked={pan.external} onChange={(e) => setPan({ ...pan, external: e.target.checked })} /> external
                      </label>
                      <Btn kind="ghost" disabled={busy || !pan.name.trim()} onClick={() => { void post("/panel-member", { name: pan.name.trim(), role: pan.role, external: pan.external }, `Added ${pan.name.trim()} to the panel`); setPan({ name: "", role: "EXTERNAL", external: false }); }}>Add</Btn>
                    </div>
                  ) : null}
                </div>

                {may && nexts.length ? (
                  <div>
                    <div className="b600 mb-2">Advance</div>
                    <div className="stack">
                      {nexts.map((n) => (
                        <div key={n.action} className="row row--tight">
                          {n.needs?.includes("pgsr") ? <input className="ctl" placeholder="PGSR (representative)" value={pgsr} onChange={(e) => setPgsr(e.target.value)} style={{ maxWidth: 200 }} /> : null}
                          {n.needs?.includes("plagiarism") ? <input className="ctl tnum" placeholder="Originality %" value={plag} onChange={(e) => setPlag(e.target.value.replace(/[^0-9.]/g, ""))} style={{ maxWidth: 120 }} /> : null}
                          {n.needs?.includes("viva") ? (
                            <>
                              <input className="ctl tnum" placeholder="Score %" value={viva.score} onChange={(e) => setViva({ ...viva, score: e.target.value.replace(/[^0-9.]/g, "") })} style={{ maxWidth: 110 }} />
                              <select className="ctl" value={viva.outcome} onChange={(e) => setViva({ ...viva, outcome: e.target.value })} style={{ maxWidth: 170 }}>
                                <option value="PASS_CLEAN">Pass, no corrections</option>
                                <option value="PASS_MINOR">Pass, minor corrections</option>
                                <option value="PASS_MAJOR">Pass, major corrections</option>
                                <option value="SECOND_ORAL">Second oral</option>
                                <option value="FAIL">Fail</option>
                              </select>
                            </>
                          ) : null}
                          {n.needs?.includes("due") ? <input className="ctl" type="date" value={due} onChange={(e) => setDue(e.target.value)} style={{ maxWidth: 160 }} /> : null}
                          <Btn kind="primary" disabled={busy} onClick={() => void doAction(n.action, n.needs)}>{n.label}</Btn>
                        </div>
                      ))}
                      {!["AWARDED", "WITHDRAWN"].includes(detail.stage) ? (
                        <Btn kind="ghost" disabled={busy} onClick={() => { if (window.confirm("Withdraw this candidate from the programme?")) void doAction("WITHDRAW"); }}>Withdraw candidate</Btn>
                      ) : null}
                    </div>
                  </div>
                ) : null}

                <div>
                  <div className="b600 mb-2">Documents submitted by the candidate</div>
                  {detail.documents && detail.documents.length ? (
                    <DTable pageSize={0} cols={["Document", "Version|mid", "Submitted|mid", "Status|mid", "|num"]}
                      rows={detail.documents.map((d) => [
                        <span key="d"><a className="lnk b600" href={`/api/bff/api/v1/pg/research/${detail.id}/documents/${d.id}/content`} target="_blank" rel="noopener">{DOC_KIND[d.kind] ?? d.kind}</a><div className="sub2">{d.filename} · {(d.size_bytes / 1048576).toFixed(1)} MB{d.note ? ` · ${d.note}` : ""}</div>{d.reviewer_note ? <div className="sub2">Desk: {d.reviewer_note}</div> : null}</span>,
                        <span key="v" className="tnum">v{d.version}</span>,
                        <span key="w" className="tnum sub2">{fmt(d.uploaded_at)}</span>,
                        <Pil key="s" kind={DOC_STATUS[d.status] ?? "grey"}>{d.status.charAt(0) + d.status.slice(1).toLowerCase()}</Pil>,
                        may && d.status === "SUBMITTED" ? <span key="a" className="row row--inline row--tight" style={{ justifyContent: "flex-end" }}>
                          <Btn kind="primary" size="sm" disabled={busy} onClick={() => void post(`/documents/${d.id}/review`, { status: "ACCEPTED" }, `${DOC_KIND[d.kind] ?? d.kind} v${d.version} accepted`)}>Accept</Btn>
                          <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { const n = window.prompt("What must the candidate correct?"); if (n !== null) void post(`/documents/${d.id}/review`, { status: "RETURNED", note: n }, `${DOC_KIND[d.kind] ?? d.kind} v${d.version} returned`); }}>Return</Btn>
                        </span> : <span key="a" />,
                      ])} />
                  ) : <div className="sub2">Nothing submitted yet. The candidate submits the proposal, seminar paper, plagiarism report, draft, corrected copy and final copy on their research desk; each is kept by version.</div>}
                </div>

                <div>
                  <div className="b600 mb-2">Milestones</div>
                  {detail.events.length ? (
                    <div className="stack" style={{ gap: "var(--s-1)" }}>
                      {detail.events.map((e, i) => (
                        <div key={i} className="sub2"><span className="tnum">{fmt(e.at)}</span> — {e.note ?? STAGE_LABEL[e.stage] ?? e.stage}</div>
                      ))}
                    </div>
                  ) : <div className="sub2">No milestone recorded yet.</div>}
                </div>
              </div>
            </div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
