"use client";

/**
 * V651: a postgraduate student's academic history — the stage of the session (recorded or calculated, fresh or returning), every
 * cycle with the stage of each session, the restart requests, and the school-fees references with the stage they were raised under.
 * Read when shown; a cycle is never hidden.
 */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { Note, Panel, PBody, Pil, Spinner } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { CYCLE_WORDS, RECOMMENDATION_WORDS, RESTART_WORDS, stageText, type History } from "@/lib/pg-academic";

const when = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const naira = (n: number | string) => `₦${Number(n).toLocaleString("en-NG")}`;
const SOURCE: Record<string, string> = {
  RECONCILIATION: "Reconciliation", PROGRESSION: "Progression", EXTENSION: "Extension", RESTART: "Restart", CORRECTION: "Correction", ADMISSION: "Admission",
};

export function usePgHistory(studentId: string | null, session?: string | null) {
  const [data, setData] = useState<{ key: string; h: History | null; failed: string | null } | null>(null);
  const key = `${studentId}|${session ?? ""}`;
  useEffect(() => {
    if (!studentId) return;
    let alive = true;
    fetch(`/api/bff/api/v1/pg/academic/students/${studentId}/history${session ? `?session=${encodeURIComponent(session)}` : ""}`, { cache: "no-store" })
      .then(async (r) => {
        const j = await r.json().catch(() => null);
        if (!alive) return;
        setData({ key, h: r.ok ? (j as History) : null, failed: r.ok ? null : ((j as Problem | null)?.detail ?? r.statusText) });
      })
      .catch(() => { if (alive) setData({ key, h: null, failed: "The portal could not reach the server." }); });
    return () => { alive = false; };
  }, [studentId, session, key]);
  return data && data.key === key ? data : null;
}

export function PgHistoryBody({ h }: { h: History }) {
  const c = h.current;
  return (
    <>
      {c ? (
        <Note kind={c.beyond || c.recommendation === "RESTART_REQUIRED" ? "bad" : c.is_extension ? "info" : "ok"}
          title={`${h.session}: ${stageText(c)}${c.category ? ` · ${c.category === "FRESH" ? "Fresh" : "Returning"}` : ""}`}>
          Cycle {c.cycle_no} {c.cycle_id ? "" : "(not yet recorded) "}from {c.start_session ?? "—"} · {c.official ? "recorded by the PG School" : "calculated from the calendar"} ·{" "}
          <Pil kind={RECOMMENDATION_WORDS[c.recommendation]?.[1] ?? "grey"}>{RECOMMENDATION_WORDS[c.recommendation]?.[0] ?? c.recommendation}</Pil>
        </Note>
      ) : null}
      {h.cycles.length ? h.cycles.map((cy) => (
        <div key={cy.id} className="mt-3">
          <div className="row row--tight" style={{ flexWrap: "wrap" }}>
            <strong>Cycle {cy.cycle_no}</strong>
            <span className="sub2">{cy.qualification_label} · {cy.programme} · from {cy.start_session}{cy.source === "RESTART" ? " · a restart" : ""}</span>
            <Pil kind={CYCLE_WORDS[cy.status]?.[1] ?? "grey"}>{CYCLE_WORDS[cy.status]?.[0] ?? cy.status}</Pil>
          </div>
          {cy.status_reason ? <div className="sub2">{cy.status_reason} ({when(cy.status_at)})</div> : null}
          {cy.stages.length ? (
            <DTable cols={["Session", "Stage", "How", "By", "Reason"]} rows={cy.stages.map((s) => [
              <span key="s" className="tnum">{s.session}</span>,
              <span key="l">{s.label}{s.is_extension ? <> <Pil kind="warn">Extension</Pil></> : null}</span>,
              <span key="h" className="sub2">{SOURCE[s.source] ?? s.source}</span>,
              <span key="b" className="sub2">{s.decided_by_name ?? s.decided_office ?? "—"} · {when(s.at)}</span>,
              <span key="r" className="sub2">{s.reason ?? "—"}</span>,
            ])} />
          ) : <div className="sub2">No stage recorded in this cycle yet.</div>}
        </div>
      )) : <div className="sub2 mt-2">No cycle is recorded yet: the student is read as cycle 1 from the admission session until the PG School records it.</div>}
      {h.restarts.length ? (
        <div className="mt-3">
          <strong>Restart requests</strong>
          <DTable cols={["Reference", "State", "New cycle from", "Reason", "Notes"]} rows={h.restarts.map((r) => [
            <span key="r" className="tnum">{r.reference}</span>,
            <Pil key="s" kind={RESTART_WORDS[r.state][1]}>{RESTART_WORDS[r.state][0]}</Pil>,
            <span key="f" className="tnum">{r.start_session}{r.new_cycle_no ? ` (cycle ${r.new_cycle_no})` : ""}</span>,
            <span key="w" className="sub2">{r.reason}</span>,
            <span key="n" className="sub2">{[r.dept_note, r.decision_note].filter(Boolean).join(" · ") || "—"}</span>,
          ])} />
        </div>
      ) : null}
      {h.payments.length ? (
        <div className="mt-3">
          <strong>School fees by cycle and stage</strong>
          <DTable cols={["Reference", "Session", "Cycle", "Stage", "Category", "Amount|num", "Paid"]} rows={h.payments.map((p) => [
            <span key="r" className="tnum">{p.reference}</span>,
            <span key="s" className="tnum">{p.session}</span>,
            <span key="c" className="tnum">{p.cycle_no ?? "—"}</span>,
            <span key="g">{p.stage_label ?? "—"}{p.official ? "" : <span className="sub2"> (calculated)</span>}</span>,
            <span key="k" className="sub2">{p.category === "FRESH" ? "Fresh" : p.category === "RETURNING" ? "Returning" : "—"}</span>,
            <span key="a" className="tnum">{naira(p.amount)}</span>,
            <Pil key="p" kind={p.paid ? "ok" : "grey"}>{p.paid ? "Paid" : "Not paid"}</Pil>,
          ])} />
        </div>
      ) : null}
    </>
  );
}

/** the full record's panel: shown for a postgraduate student only */
export function PgHistoryPanel({ studentId }: { studentId: string }) {
  const d = usePgHistory(studentId, null);
  if (d && d.h && !d.h.pg) return null;
  if (d && !d.h && d.failed) return null;   // an office that reads no PG history sees no panel
  return (
    <Panel title="Postgraduate academic history" right={d?.h?.current ? stageText(d.h.current) : undefined}>
      <PBody>
        {!d ? <div className="row row--tight sub2" role="status" aria-live="polite"><Spinner /> Reading the postgraduate history…</div>
          : d.h ? <PgHistoryBody h={d.h} /> : null}
      </PBody>
    </Panel>
  );
}
