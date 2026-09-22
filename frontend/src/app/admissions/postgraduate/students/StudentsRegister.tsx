"use client";

/**
 * The postgraduate register (V211): every postgraduate student with their coursework CGPA, academic
 * standing (good / probation below 2.50, Policy 15.5) and research stage. Filterable by programme and
 * level. Read by the Dean, Secretary and the academic offices.
 */
import { useCallback, useEffect, useMemo, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Prog { code: string; name: string; faculty_name: string }
interface Row {
  id: string; surname: string; other_names: string; matric_no: string | null; admission_no: string | null;
  sex: string | null; entry_level: number; entry_session: string; status: string; programme_name: string; department_name: string;
  cgpa: number | null; research_stage: string | null; mode: string | null; standing: string;
}
export interface View { counts: { total: number; pgd: number; masters: number; doctoral: number }; rows: Row[] }

const LEVEL: Record<number, string> = { 700: "PGD", 800: "Master’s", 900: "Doctoral" };
const RESEARCH: Record<string, string> = {
  REGISTERED: "Registered", SUPERVISED: "Supervised", PROPOSAL_SUBMITTED: "Proposal", PROPOSAL_APPROVED: "Proposal approved",
  SEMINAR_HELD: "Seminar", TITLE_REGISTERED: "Title", PANEL_CONSTITUTED: "Panel", DRAFT_SUBMITTED: "Draft", VIVA_HELD: "Viva",
  CORRECTIONS: "Corrections", FINAL_SUBMITTED: "Final", CLEARED: "Cleared", AWARD_RECOMMENDED: "To Senate", AWARDED: "Awarded", WITHDRAWN: "Withdrawn",
};

export function StudentsRegister({ view, problem, mayEdit }: { view: View | null; problem: Problem | null; mayEdit: boolean }) {
  const [progs, setProgs] = useState<Prog[]>([]);
  const [programme, setProgramme] = useState("");
  const [level, setLevel] = useState("");
  const [gender, setGender] = useState("");
  const [session, setSession] = useState("");
  const [standing, setStanding] = useState("");
  const [data, setData] = useState<View | null>(view);
  const [err, setErr] = useState<Problem | null>(problem);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/pg/programmes").then((r) => (r.ok ? r.json() : [])).then((j) => { if (live) setProgs(Array.isArray(j) ? j : []); }).catch(() => {});
    return () => { live = false; };
  }, []);

  const load = useCallback(async (p: string, l: string) => {
    const q = [p ? `programme=${encodeURIComponent(p)}` : "", l ? `level=${l}` : ""].filter(Boolean).join("&");
    const r = await fetch(`/api/bff/api/v1/pg/students${q ? `?${q}` : ""}`, { cache: "no-store" });
    setErr(null);
    const j = await r.json().catch(() => null);
    if (!r.ok) { setErr(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
    setData(j as View);
  }, []);

  useEffect(() => {
    if (programme === "" && level === "") return;
    void (async () => { await load(programme, level); })();
  }, [programme, level, load]);

  const byFaculty = useMemo(() => {
    const m = new Map<string, Prog[]>();
    for (const p of progs) { const k = p.faculty_name; if (!m.has(k)) m.set(k, []); m.get(k)!.push(p); }
    return [...m.entries()];
  }, [progs]);

  async function changeStatus(id: string, action: string) {
    // "READMIT" returns a lapsed student (past their duration or probation) to ACTIVE to continue where
    // they stopped; it is a reinstatement carrying a readmission — the readmission fee is charged and paid
    // through the shared finance engine (the Bursary states a Readmission fee; the student pays on /student/fees).
    const to = action === "READMIT" ? "ACTIVE" : action;
    const label = action === "READMIT" ? "readmission" : action === "ACTIVE" ? "reinstate" : action.toLowerCase();
    const promptText = action === "READMIT"
      ? "Instrument for the readmission (Senate minute or decision). The student resumes at their current level and is charged the readmission fee:"
      : `Instrument for the ${label} (Senate minute, letter, or decision):`;
    const instrument = window.prompt(promptText, "");
    if (instrument === null || !instrument.trim()) return;
    setBusy(true); setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/pg/students/${id}/status`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`PG student ${label}`) },
        body: JSON.stringify({ to, instrument: instrument.trim(), reason: action === "READMIT" ? "Readmitted to continue" : "" }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      await load(programme, level);
    } finally { setBusy(false); }
  }

  if (!data) return <ProblemNotice problem={err ?? { status: 500, title: "The register could not be read." }} />;
  const c = data.counts;
  const onProbation = data.rows.filter((r) => r.standing === "PROBATION").length;
  const sessions = [...new Set(data.rows.map((r) => r.entry_session).filter(Boolean))].sort().reverse();
  const shown = data.rows.filter((r) =>
    (!gender || r.sex === gender) && (!session || r.entry_session === session) && (!standing || r.standing === standing));

  // the summary tiles double as filters — click one to scope the register to that segment
  const tiles: { label: string; value: string; color: string | null; sub: string; active: boolean; onClick: () => void }[] = [
    { label: "PG students", value: String(c.total), color: null, sub: "on the register", active: level === "" && standing === "", onClick: () => { setLevel(""); setStanding(""); } },
    { label: "PGD", value: String(c.pgd), color: null, sub: "level 700", active: level === "700", onClick: () => { setStanding(""); setLevel(level === "700" ? "" : "700"); } },
    { label: "Master’s", value: String(c.masters), color: null, sub: "level 800", active: level === "800", onClick: () => { setStanding(""); setLevel(level === "800" ? "" : "800"); } },
    { label: "Doctoral", value: String(c.doctoral), color: null, sub: "level 900", active: level === "900", onClick: () => { setStanding(""); setLevel(level === "900" ? "" : "900"); } },
    { label: "On probation", value: String(onProbation), color: onProbation ? "var(--red-deep)" : null, sub: "CGPA below 2.50", active: standing === "PROBATION", onClick: () => setStanding(standing === "PROBATION" ? "" : "PROBATION") },
  ];

  return (
    <>
      {err ? <ProblemNotice problem={err} /> : null}
      <div className="grid grid--4">
        {tiles.map((t, i) => (
          <button type="button" key={i} className="tile" onClick={t.onClick} aria-pressed={t.active}
            style={{ textAlign: "left", cursor: "pointer", ...(t.active ? { outline: "2px solid var(--chrome)", outlineOffset: "-2px" } : {}) }}>
            <span className="eyebrow">{t.label}</span>
            <span className="n tnum" style={t.color ? { color: t.color } : undefined}>{t.value}</span>
            <span className="c">{t.sub}</span>
          </button>
        ))}
      </div>
      <Panel title="Postgraduate register" right={
        <span style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          <select className="ctl" style={{ width: "auto", maxWidth: 220 }} value={programme} onChange={(e) => setProgramme(e.target.value)} aria-label="Programme">
            <option value="">All programmes</option>
            {byFaculty.map(([fac, list]) => <optgroup key={fac} label={fac}>{list.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}</optgroup>)}
          </select>
          <select className="ctl" style={{ width: "auto" }} value={level} onChange={(e) => setLevel(e.target.value)} aria-label="Level">
            <option value="">All levels</option><option value="700">700 · PGD</option><option value="800">800 · Master&rsquo;s</option><option value="900">900 · Doctoral</option>
          </select>
          <select className="ctl" style={{ width: "auto" }} value={gender} onChange={(e) => setGender(e.target.value)} aria-label="Gender">
            <option value="">All genders</option><option value="F">Female</option><option value="M">Male</option>
          </select>
          <select className="ctl" style={{ width: "auto" }} value={session} onChange={(e) => setSession(e.target.value)} aria-label="Entry session">
            <option value="">All sessions</option>{sessions.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
          <select className="ctl" style={{ width: "auto" }} value={standing} onChange={(e) => setStanding(e.target.value)} aria-label="Standing">
            <option value="">All standings</option><option value="GOOD">Good</option><option value="PROBATION">Probation</option><option value="NEW">New</option>
          </select>
        </span>
      }>
        {shown.length ? (
          <DTable cols={["Student", "Programme", "Level|mid", "Sex|mid", "Status|mid", "CGPA|num", "Standing|mid", "Research|mid", ...(mayEdit ? ["|mid"] : [])]}
            rows={shown.map((r) => [
              <span key="n"><span style={{ fontWeight: 600 }}>{r.surname}, {r.other_names}</span><div className="sub2 tnum">{r.matric_no ?? r.admission_no ?? ""}</div></span>,
              <span key="p"><span>{r.programme_name}</span><div className="sub2">{r.department_name}</div></span>,
              <span key="l" className="sub2">{LEVEL[r.entry_level] ?? r.entry_level}</span>,
              <span key="g" className="sub2">{r.sex === "F" ? "Female" : r.sex === "M" ? "Male" : "—"}</span>,
              <span key="st" className="sub2">{(r.status ?? "").charAt(0) + (r.status ?? "").slice(1).toLowerCase()}{r.mode ? ` · ${r.mode === "PART_TIME" ? "PT" : "FT"}` : ""}</span>,
              <span key="c" className="tnum">{r.cgpa == null ? "—" : Number(r.cgpa).toFixed(2)}</span>,
              r.standing === "PROBATION" ? <Pil key="s" kind="bad">Probation</Pil> : r.standing === "GOOD" ? <Pil key="s" kind="ok">Good</Pil> : <Pil key="s" kind="grey">New</Pil>,
              <span key="r" className="sub2">{r.research_stage ? (RESEARCH[r.research_stage] ?? r.research_stage) : "—"}</span>,
              ...(mayEdit ? [
                <select key="a" className="ctl" style={{ width: "auto", padding: "2px 6px" }} disabled={busy} value=""
                  onChange={(e) => { const to = e.target.value; e.currentTarget.value = ""; if (to) void changeStatus(r.id, to); }} aria-label="Change status">
                  <option value="">Action…</option>
                  {r.status !== "DEFERRED" ? <option value="DEFERRED">Defer</option> : null}
                  {r.status !== "WITHDRAWN" ? <option value="WITHDRAWN">Withdraw</option> : null}
                  {r.status !== "ACTIVE" ? <option value="ACTIVE">Reinstate (active)</option> : null}
                  {r.status !== "ACTIVE" ? <option value="READMIT">Readmit (continue)</option> : null}
                </select>,
              ] : []),
            ])} texts={shown.map((r) => `${r.surname} ${r.other_names} ${r.matric_no ?? ""} ${r.programme_name}`)} />
        ) : <PBody><div className="sub2">No postgraduate student matches these filters{data.rows.length ? ` (${data.rows.length} on the register).` : "."}</div></PBody>}
      </Panel>
      <Note kind="info" title="Academic standing (Policy 15.5 / 20)">A student whose CGPA falls below 2.50 is placed on probation for a semester and advised to withdraw if it does not improve.</Note>
    </>
  );
}
