"use client";

/**
 * The School's external examiners (Policy 18), matching the prototype's pgExaminers screen. The Board
 * approves external examiners on a department's recommendation; a Master's examiner normally serves
 * three years, PhD examiners by specialization. This is the institution-level roster (distinct from a
 * candidate's panel, which the research desk holds).
 */
import { useCallback, useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Examiner { id: string; name: string; institution: string; field: string | null; tenure_from: string | null; tenure_to: string | null; active: boolean }
const yr = (v: string | null) => (v ? new Date(v).getFullYear() : null);
const tenure = (a: string | null, b: string | null) => { const f = yr(a), t = yr(b); return f && t ? `${f}–${t}` : f ? `${f}–` : "—"; };

export function Examiners({ mayEdit }: { mayEdit: boolean }) {
  const [rows, setRows] = useState<Examiner[]>([]);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [f, setF] = useState({ name: "", institution: "", field: "", tenureFrom: "", tenureTo: "" });

  const load = useCallback(async () => {
    try {
      const r = await fetch("/api/bff/api/v1/pg/examiners", { cache: "no-store" });
      setProblem(null);
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); setLoading(false); return; }
      setRows(Array.isArray(j) ? (j as Examiner[]) : []);
    } finally { setLoading(false); }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function add() {
    if (!f.name.trim() || !f.institution.trim()) { setProblem({ status: 400, title: "Name and institution are required." }); return; }
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/pg/examiners", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Appointed external examiner ${f.name.trim()}`) },
        body: JSON.stringify({ name: f.name.trim(), institution: f.institution.trim(), field: f.field.trim(), tenureFrom: f.tenureFrom, tenureTo: f.tenureTo }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setF({ name: "", institution: "", field: "", tenureFrom: "", tenureTo: "" });
      await load();
    } finally { setBusy(false); }
  }

  if (loading) return <Note kind="info" title="Loading external examiners…">One moment.</Note>;

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Note kind="info" title="External examiners (Policy 18)">
        The Board approves external examiners on a department&rsquo;s recommendation through the Faculty Postgraduate Committee; the Secretary issues the appointment letters. A Master&rsquo;s examiner normally serves three years; PhD examiners are approved by specialization.
      </Note>
      <Panel title="External examiners" right={`${rows.filter((r) => r.active).length} active`}>
        {rows.length ? (
          <DTable cols={["Name", "Institution", "Field", "Tenure|mid", "Status|mid"]}
            rows={rows.map((r) => [
              r.name, <span key="i" className="sub2">{r.institution}</span>, r.field ?? "—",
              <span key="t" className="tnum sub2">{tenure(r.tenure_from, r.tenure_to)}</span>,
              r.active ? <Pil key="s" kind="ok">Active</Pil> : <span key="s" className="sub2">Ended</span>,
            ])} texts={rows.map((r) => `${r.name} ${r.institution} ${r.field ?? ""}`)} />
        ) : <PBody><div className="sub2">No external examiner appointed yet.</div></PBody>}
      </Panel>

      {mayEdit ? (
        <Panel title="Appoint an examiner">
          <PBody>
            <div className="grid grid--2">
              <div className="field"><label htmlFor="e-name">Name</label><input id="e-name" className="ctl" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} placeholder="Prof. B. Okonkwo" /></div>
              <div className="field"><label htmlFor="e-inst">Institution</label><input id="e-inst" className="ctl" value={f.institution} onChange={(e) => setF({ ...f, institution: e.target.value })} placeholder="University of Ibadan" /></div>
              <div className="field"><label htmlFor="e-field">Field / specialization</label><input id="e-field" className="ctl" value={f.field} onChange={(e) => setF({ ...f, field: e.target.value })} placeholder="Economics" /></div>
              <div className="field"><label htmlFor="e-tf">Tenure from</label><input id="e-tf" className="ctl" type="date" value={f.tenureFrom} onChange={(e) => setF({ ...f, tenureFrom: e.target.value })} /></div>
              <div className="field"><label htmlFor="e-tt">Tenure to</label><input id="e-tt" className="ctl" type="date" value={f.tenureTo} onChange={(e) => setF({ ...f, tenureTo: e.target.value })} /></div>
            </div>
            <div className="mt-3"><button type="button" className="btn btn--primary btn--sm" disabled={busy} onClick={() => void add()}>{busy ? "Saving…" : "Appoint examiner"}</button></div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
