"use client";
import { notifyProblem } from "@/components/proto/Toast";

/**
 * The Secretary's thesis clearance desk (Policy 31–32), after the prototype's pgClear screen: the final
 * versions awaiting the Secretary's clearance before binding — with the plagiarism figure and the viva
 * outcome beside each — and "Clear for binding", which moves the record on through the research
 * lifecycle (V209). Cleared theses then go to the School Board.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Awaiting { id: string; degree_kind: string; topic: string | null; final_submitted_at: string | null; plagiarism_pct: number | null; viva_grade: string | null; viva_outcome: string | null; surname: string; other_names: string; matric_no: string | null; programme_name: string; pg_award: string | null }
interface Cleared { id: string; degree_kind: string; topic: string | null; cleared_at: string | null; stage: string; surname: string; other_names: string; matric_no: string | null; programme_name: string; pg_award: string | null }
export interface ClearView { awaiting: Awaiting[]; cleared: Cleared[] }

const KIND: Record<string, string> = { PROJECT: "Project report", DISSERTATION: "Dissertation", THESIS: "Thesis" };
const STAGE: Record<string, string> = { CLEARED: "Cleared", AWARD_RECOMMENDED: "With Senate", AWARDED: "Awarded" };
const VIVA: Record<string, string> = { PASS_CLEAN: "Pass", PASS_MINOR: "Pass · minor", PASS_MAJOR: "Pass · major", SECOND_ORAL: "Second oral", FAIL: "Fail" };
const fmt = (v: string | null) => { if (!v) return "—"; const d = new Date(v); return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }); };

export function Clearance({ view, problem, mayClear }: { view: ClearView | null; problem: Problem | null; mayClear: boolean }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<Problem | null>(null);

  async function clear(r: Awaiting) {
    setErr(null); setBusy(r.id);
    try {
      const res = await fetch(`/api/bff/api/v1/pg/research/${encodeURIComponent(r.id)}/action`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Thesis cleared for binding: ${r.surname}, ${r.other_names}`) },
        body: JSON.stringify({ action: "CLEAR", note: "Cleared by the Secretary before binding" }),
      });
      const j = await res.json().catch(() => null);
      if (!res.ok) { setErr(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: res.status, title: res.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: res.status, title: res.statusText }); return; }
      router.refresh();
    } finally { setBusy(null); }
  }

  const awaiting = view?.awaiting ?? [];
  const cleared = view?.cleared ?? [];
  return (
    <>
      <Note kind="info" title="Thesis clearance (Policy 31–32)">
        Clear the final version before binding; the candidate then submits five hard-bound copies with the prescribed cover. A cleared thesis goes to the School Board for recommendation to Senate.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <Tiles items={[
        ["Awaiting clearance", String(awaiting.length), awaiting.length ? "var(--chrome)" : null, "final versions submitted"],
        ["Cleared", String(cleared.length), cleared.length ? "var(--green-ink)" : null, "recently, for binding"],
      ]} cls="grid--2" />

      <Panel title="Awaiting clearance" right={`${awaiting.length} finally submitted`}>
        {awaiting.length ? (
          <DTable cols={["Candidate", "Programme", "Work", "Final submitted|mid", "Plagiarism|mid", "Viva|mid", "|num"]}
            rows={awaiting.map((r) => [
              <span key="n"><span className="b600">{r.surname}, {r.other_names}</span><div className="sub2 tnum">{r.matric_no ?? "—"}</div></span>,
              <span key="p"><span>{r.programme_name}</span><div className="sub2">{r.pg_award ?? ""}</div></span>,
              <span key="w"><span>{KIND[r.degree_kind] ?? r.degree_kind}</span><div className="sub2">{r.topic ?? "—"}</div></span>,
              <span key="d" className="tnum">{fmt(r.final_submitted_at)}</span>,
              r.plagiarism_pct == null ? <span key="pl" className="sub2">—</span> : <Pil key="pl" kind={Number(r.plagiarism_pct) <= 20 ? "ok" : "warn"}>{Number(r.plagiarism_pct)}%</Pil>,
              r.viva_outcome ? <Pil key="v" kind={r.viva_outcome === "FAIL" ? "bad" : "ok"}>{r.viva_grade ? `${r.viva_grade} · ` : ""}{VIVA[r.viva_outcome] ?? r.viva_outcome}</Pil> : <span key="v" className="sub2">—</span>,
              mayClear ? <Btn kind="primary" key="a" disabled={busy !== null} onClick={() => void clear(r)}>{busy === r.id ? "Clearing…" : "Clear for binding"}</Btn> : <span key="a" className="sub2">—</span>,
            ])}
            texts={awaiting.map((r) => `${r.surname} ${r.other_names} ${r.matric_no ?? ""} ${r.programme_name} ${r.topic ?? ""}`)} />
        ) : <PBody><div className="sub2">No thesis is awaiting clearance.</div></PBody>}
      </Panel>

      <Panel title="Cleared for binding" right="most recent first">
        {cleared.length ? (
          <DTable cols={["Candidate", "Programme", "Work", "Cleared|mid", "Now|mid"]}
            rows={cleared.map((r) => [
              <span key="n"><span className="b600">{r.surname}, {r.other_names}</span><div className="sub2 tnum">{r.matric_no ?? "—"}</div></span>,
              <span key="p"><span>{r.programme_name}</span><div className="sub2">{r.pg_award ?? ""}</div></span>,
              <span key="w"><span>{KIND[r.degree_kind] ?? r.degree_kind}</span><div className="sub2">{r.topic ?? "—"}</div></span>,
              <span key="d" className="tnum">{fmt(r.cleared_at)}</span>,
              <Pil key="s" kind={r.stage === "AWARDED" ? "ok" : "info"}>{STAGE[r.stage] ?? r.stage}</Pil>,
            ])}
            texts={cleared.map((r) => `${r.surname} ${r.other_names} ${r.matric_no ?? ""} ${r.programme_name}`)} />
        ) : <PBody><div className="sub2">No thesis has been cleared yet.</div></PBody>}
      </Panel>
    </>
  );
}
