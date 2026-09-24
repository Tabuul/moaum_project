"use client";

/** tAlumni — the alumni register: every student Senate has graduated, searchable and
 *  filterable by faculty and graduating session. Read-only; the source is the graduand
 *  list, so a name appears here only after Senate has approved the award. */
import { useMemo, useState } from "react";
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

interface Row { name: string; matric_no: string | null; programme: string | null; faculty: string | null; session: string; award: string; cgpa: number | null; class: string | null }
export interface AlumniData {
  rows: Row[];
  tiles: { total: number; sessions: number; latest_cohort: number };
  sessions: { session: string }[];
}

export function Alumni({ d }: { d: AlumniData }) {
  const [q, setQ] = useState("");
  const [faculty, setFaculty] = useState("");
  const [session, setSession] = useState("");
  const faculties = useMemo(() => Array.from(new Set(d.rows.map((r) => r.faculty).filter(Boolean))).sort() as string[], [d.rows]);

  const shown = d.rows.filter((r) =>
    (!faculty || r.faculty === faculty) &&
    (!session || r.session === session) &&
    (!q.trim() || `${r.name} ${r.matric_no ?? ""}`.toLowerCase().includes(q.trim().toLowerCase())));

  return (
    <>
      <Tiles items={[
        ["On the register", Number(d.tiles.total).toLocaleString(), null, "Graduated and approved by Senate"],
        ["Graduating sessions", String(d.tiles.sessions), null, "Cohorts on record"],
        ["Latest cohort", Number(d.tiles.latest_cohort).toLocaleString(), null, d.sessions[0]?.session ?? "—"],
        ["Showing", shown.length.toLocaleString(), null, "After filters"],
      ]} />
      <Panel title="Alumni" right="A name appears once Senate approves the award">
        <PBody>
          <div className="row row--end">
            <div className="field" style={{ minWidth: 220 }}><label htmlFor="al-q">Search</label><input id="al-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Name or matriculation number" /></div>
            <div className="field" style={{ minWidth: 180 }}><label htmlFor="al-f">Faculty</label><select id="al-f" className="ctl" value={faculty} onChange={(e) => setFaculty(e.target.value)}><option value="">All faculties</option>{faculties.map((f) => <option key={f} value={f}>{f}</option>)}</select></div>
            <div className="field" style={{ minWidth: 140 }}><label htmlFor="al-s">Session</label><select id="al-s" className="ctl" value={session} onChange={(e) => setSession(e.target.value)}><option value="">All sessions</option>{d.sessions.map((s) => <option key={s.session} value={s.session}>{s.session}</option>)}</select></div>
          </div>
        </PBody>
        {shown.length ? (
          <DTable cols={["Name", "Matric number|mid", "Programme", "Faculty|mid", "Class|mid", "Session|mid"]} rows={shown.map((r) => [
            <span key="n">{r.name}</span>,
            <span className="tnum sub2" key="m">{r.matric_no ?? "—"}</span>,
            <span className="sub2" key="p">{r.programme ?? "—"}<div className="sub2">{r.award}</div></span>,
            <span className="sub2" key="f">{r.faculty ?? "—"}</span>,
            r.class ? <Pil kind="ok" key="c">{r.class}</Pil> : <span className="sub2" key="c">—</span>,
            <span className="tnum sub2" key="s">{r.session}</span>,
          ])} texts={shown.map((r) => `${r.name} ${r.matric_no ?? ""} ${r.faculty ?? ""} ${r.session}`)} />
        ) : <PBody><div className="sub2">{d.rows.length ? "No alumnus matches these filters." : "No graduand has been approved by Senate yet. The register fills as cohorts graduate."}</div></PBody>}
      </Panel>
      <Note kind="info" title="The register is the record, not a mailing list">
        This is the University&rsquo;s record of who it has graduated. Contact details and alumni-relations activity are kept separately, under the data-protection rules that govern personal data after graduation.
      </Note>
    </>
  );
}
