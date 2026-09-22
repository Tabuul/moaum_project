"use client";

/**
 * The Secretary's results-to-Senate desk (Policy 33–34), after the prototype's pgSecResults screen: the
 * computed results the School Board has recommended and that now sit with Senate, and the candidates
 * Senate has awarded this session — beside the coursework results recorded and those still with the
 * departments. The recommendation and the award themselves are acted on the School Board desk.
 */
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface SenateView {
  session: string;
  counts: { to_senate: number; awarded: number; coursework_results: number; pending_computation: number };
  toSenate: { id: string; degree_kind: string; topic: string | null; award_recommended_at: string | null; viva_grade: string | null; viva_outcome: string | null; cgpa: number | null; surname: string; other_names: string; matric_no: string | null; programme_name: string; pg_award: string | null }[];
  awarded: { id: string; degree_kind: string; awarded_at: string | null; surname: string; other_names: string; matric_no: string | null; programme_name: string; pg_award: string | null }[];
}

const VIVA: Record<string, string> = { PASS_CLEAN: "Pass", PASS_MINOR: "Pass · minor", PASS_MAJOR: "Pass · major", SECOND_ORAL: "Second oral", FAIL: "Fail" };
const fmt = (v: string | null) => { if (!v) return "—"; const d = new Date(v); return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }); };

export function Senate({ session, sessions, view, problem }: { session: string; sessions: { name: string; state: string }[]; view: SenateView | null; problem: Problem | null }) {
  const router = useRouter();
  const options = sessions.some((s) => s.name === session) ? sessions : [{ name: session, state: "" }, ...sessions];
  const c = view?.counts;
  return (
    <>
      <Note kind="info" title="Award of degrees (Policy 33–34)">
        The Head of Department submits computed results through the Faculty PG Committee. The School considers them and submits a summary of graduating students to Senate; a candidate is awarded from the date Senate approves, and the Dean issues the notification of award.
      </Note>

      <Panel title="Session" right={<span className="sub2">Awards are read for the session you choose</span>}>
        <PBody>
          <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
            <label htmlFor="sen-session" className="sub2" style={{ fontWeight: 600 }}>Session</label>
            <select id="sen-session" className="ctl" style={{ maxWidth: 260 }} value={session}
              onChange={(e) => router.push(`/admissions/postgraduate/senate?session=${encodeURIComponent(e.target.value)}`)}>
              {options.map((s) => <option key={s.name} value={s.name}>{s.name}{s.state === "CURRENT" ? " · current" : ""}</option>)}
            </select>
          </div>
        </PBody>
      </Panel>

      {problem ? <ProblemNotice problem={problem} /> : null}

      {view ? (
        <>
          <Tiles items={[
            ["To Senate", String(c?.to_senate ?? 0), Number(c?.to_senate) ? "var(--chrome)" : null, "recommended by the Board"],
            ["Awarded", String(c?.awarded ?? 0), Number(c?.awarded) ? "var(--green-ink)" : null, "this session"],
            ["Coursework results", String(c?.coursework_results ?? 0), null, "recorded this session"],
            ["Pending computation", String(c?.pending_computation ?? 0), Number(c?.pending_computation) ? "var(--chrome)" : null, "with the departments"],
          ]} />

          <Panel title="Computed results to Senate" right={<span className="sub2">{session} · <Link href="/admissions/postgraduate/board">School Board</Link></span>}>
            {view.toSenate.length ? (
              <DTable cols={["Candidate", "Programme", "Coursework CGPA|num", "Viva|mid", "Outcome|mid", "Status|mid"]}
                rows={view.toSenate.map((r) => [
                  <span key="n"><span style={{ fontWeight: 600 }}>{r.surname}, {r.other_names}</span><div className="sub2 tnum">{r.matric_no ?? "—"}</div></span>,
                  <span key="p"><span>{r.programme_name}</span><div className="sub2">{r.pg_award ?? ""}{r.topic ? ` · ${r.topic}` : ""}</div></span>,
                  <span key="g" className="tnum">{r.cgpa == null ? "—" : Number(r.cgpa).toFixed(2)}</span>,
                  r.viva_grade ? <Pil key="v" kind="ok">{r.viva_grade}{r.viva_outcome === "PASS_MINOR" ? " · minor" : r.viva_outcome === "PASS_MAJOR" ? " · major" : ""}</Pil> : <span key="v" className="sub2">—</span>,
                  r.viva_outcome ? <Pil key="o" kind={r.viva_outcome === "FAIL" ? "bad" : "ok"}>{VIVA[r.viva_outcome] ?? r.viva_outcome}</Pil> : <span key="o" className="sub2">—</span>,
                  <Pil key="s" kind="info">With Senate</Pil>,
                ])}
                texts={view.toSenate.map((r) => `${r.surname} ${r.other_names} ${r.matric_no ?? ""} ${r.programme_name}`)} />
            ) : <PBody><div className="sub2">No computed result is with Senate at the moment.</div></PBody>}
          </Panel>

          <Panel title="Awarded this session" right="Senate-approved">
            {view.awarded.length ? (
              <DTable cols={["Candidate", "Programme", "Award|mid", "Senate date|num"]}
                rows={view.awarded.map((r) => [
                  <span key="n"><span style={{ fontWeight: 600 }}>{r.surname}, {r.other_names}</span><div className="sub2 tnum">{r.matric_no ?? "—"}</div></span>,
                  <span key="p"><span>{r.programme_name}</span><div className="sub2">{r.pg_award ?? ""}</div></span>,
                  <Pil key="a" kind="ok">Awarded</Pil>,
                  <span key="d" className="tnum">{fmt(r.awarded_at)}</span>,
                ])}
                texts={view.awarded.map((r) => `${r.surname} ${r.other_names} ${r.matric_no ?? ""} ${r.programme_name}`)} />
            ) : <PBody><div className="sub2">Senate has not awarded a postgraduate degree for {session} yet.</div></PBody>}
          </Panel>
        </>
      ) : null}
    </>
  );
}
