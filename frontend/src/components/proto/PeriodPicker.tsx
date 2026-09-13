"use client";

/** A session + semester selector for the institutional screens. Navigates the page to
 *  ?session=&sem=, so the server re-fetches and every chart, tile and table redraws for the
 *  chosen period. Mirrors the session <select className="ctl"> pattern used across admissions. */
import { useRouter } from "next/navigation";

export function PeriodPicker({ base, sessions, session, semester }: { base: string; sessions: string[]; session: string; semester: number }) {
  const router = useRouter();
  const opts = sessions.includes(session) ? sessions : [session, ...sessions];
  const go = (s: string, sem: number) => router.push(`${base}?session=${encodeURIComponent(s)}&sem=${sem}`);
  return (
    <div className="card"><div className="card__body" style={{ display: "flex", gap: 10, alignItems: "flex-end", flexWrap: "wrap" }}>
      <div className="field" style={{ minWidth: 170, margin: 0 }}>
        <label htmlFor="pp-session">Session</label>
        <select id="pp-session" className="ctl" value={session} onChange={(e) => go(e.target.value, semester)}>
          {opts.map((x) => <option key={x} value={x}>{x}</option>)}
        </select>
      </div>
      <div className="field" style={{ minWidth: 170, margin: 0 }}>
        <label htmlFor="pp-sem">Semester</label>
        <select id="pp-sem" className="ctl" value={String(semester)} onChange={(e) => go(session, Number(e.target.value))}>
          <option value="1">First semester</option>
          <option value="2">Second semester</option>
        </select>
      </div>
      <div className="sub2" style={{ marginLeft: "auto", alignSelf: "center" }}>Every figure below is for the session and semester chosen here.</div>
    </div></div>
  );
}
