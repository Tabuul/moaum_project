"use client";

/**
 * The School Board & awards desk (Policy 33–34), matching the prototype's pgBoard screen. Candidates the
 * Secretary has cleared await the Board's recommendation to Senate; recommended candidates await the
 * Senate award; and the awarded of the session are listed. It reads the research pipeline (V209) and
 * uses its recommend / award actions.
 */
import { useCallback, useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Row {
  id: string; stage: string; degree_kind: string; viva_grade: string | null;
  surname: string; other_names: string; matric_no: string | null; admission_no: string | null;
  programme_name: string; department_name: string; updated_at: string;
}
const KIND: Record<string, string> = { PROJECT: "Project report", DISSERTATION: "Dissertation", THESIS: "Thesis" };
function fmt(v: string | null): string {
  if (!v) return "—";
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" });
}
const name = (r: Row) => <span><span className="b600">{r.surname}, {r.other_names}</span><div className="sub2 tnum">{r.matric_no ?? r.admission_no ?? ""}</div></span>;

export function Board({ mayEdit }: { mayEdit: boolean }) {
  const [rows, setRows] = useState<Row[]>([]);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const r = await fetch("/api/bff/api/v1/pg/research", { cache: "no-store" });
      setProblem(null);
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); setLoading(false); return; }
      setRows(((j as { rows?: Row[] }).rows) ?? []);
    } finally { setLoading(false); }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function act(id: string, action: string, reason: string) {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/pg/research/${id}/action`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify({ action }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      await load();
    } finally { setBusy(false); }
  }

  if (loading) return <Note kind="info" title="Loading the Board…">One moment.</Note>;

  const cleared = rows.filter((r) => r.stage === "CLEARED");
  const recommended = rows.filter((r) => r.stage === "AWARD_RECOMMENDED");
  const awarded = rows.filter((r) => r.stage === "AWARDED");

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {cleared.length ? (
        <Note kind="ok" title={`${cleared.length} candidate${cleared.length === 1 ? "" : "s"} cleared, awaiting the Board's recommendation to Senate`}>
          The School submits a summary of graduating students to Senate for approval (Policy 34).
        </Note>
      ) : null}
      <Tiles items={[
        ["Awaiting the Board", String(cleared.length), cleared.length ? "var(--chrome)" : null, "cleared, to recommend"],
        ["With Senate", String(recommended.length), recommended.length ? "var(--chrome)" : null, "recommended"],
        ["Awarded", String(awarded.length), awarded.length ? "var(--green-ink)" : null, "this session"],
      ]} />

      <Panel title="Cleared — recommend to Senate">
        {cleared.length ? (
          <DTable cols={["Candidate", "Programme", "Kind|mid", "Viva|mid", "Cleared|num", "|mid"]}
            rows={cleared.map((r) => [
              name(r), <span key="p"><span>{r.programme_name}</span><div className="sub2">{r.department_name}</div></span>,
              <span key="k" className="sub2">{KIND[r.degree_kind] ?? r.degree_kind}</span>,
              r.viva_grade ? <Pil key="g" kind="ok">{r.viva_grade}</Pil> : <span key="g" className="sub2">—</span>,
              <span key="d" className="tnum sub2">{fmt(r.updated_at)}</span>,
              mayEdit ? <button key="a" className="btn btn--primary btn--sm" disabled={busy} onClick={() => void act(r.id, "RECOMMEND", `Recommended ${r.surname} to Senate`)}>Recommend</button> : null,
            ])} texts={cleared.map((r) => `${r.surname} ${r.other_names} ${r.programme_name}`)} />
        ) : <PBody><div className="sub2">No cleared candidate awaiting the Board.</div></PBody>}
      </Panel>

      <Panel title="Recommended — record the Senate award">
        {recommended.length ? (
          <DTable cols={["Candidate", "Programme", "Kind|mid", "|mid"]}
            rows={recommended.map((r) => [
              name(r), <span key="p">{r.programme_name}</span>, <span key="k" className="sub2">{KIND[r.degree_kind] ?? r.degree_kind}</span>,
              mayEdit ? <button key="a" className="btn btn--go btn--sm" disabled={busy} onClick={() => void act(r.id, "AWARD", `Recorded Senate award for ${r.surname}`)}>Record award</button> : null,
            ])} texts={recommended.map((r) => `${r.surname} ${r.other_names} ${r.programme_name}`)} />
        ) : <PBody><div className="sub2">Nothing with Senate at the moment.</div></PBody>}
      </Panel>

      <Panel title="Awarded this session" right={`${awarded.length} graduand${awarded.length === 1 ? "" : "s"}`}>
        {awarded.length ? (
          <DTable cols={["Candidate", "Programme", "Kind|mid", "Awarded|num"]}
            rows={awarded.map((r) => [
              name(r), <span key="p">{r.programme_name}</span>, <span key="k" className="sub2">{KIND[r.degree_kind] ?? r.degree_kind}</span>,
              <span key="d" className="tnum sub2">{fmt(r.updated_at)}</span>,
            ])} texts={awarded.map((r) => `${r.surname} ${r.other_names} ${r.programme_name}`)} />
        ) : <PBody><div className="sub2">No award recorded yet this session.</div></PBody>}
      </Panel>
    </>
  );
}
