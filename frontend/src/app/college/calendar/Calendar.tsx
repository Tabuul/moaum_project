"use client";
/** The College's calendar (V249): each level's semesters dated for a session. The prospectus gives lengths, never dates;
 *  the College enters them here. The dates tell the student where their year is and when it ends, and hold the
 *  examinations desk to the end of the year: results are entered once the cohort's final semester has begun. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface CalendarRow { level: number; phase: string; ordinal: number; name: string; length_weeks: number | null; starts_on: string | null; ends_on: string | null; subjects: string | null }

export function Calendar({ sessions, session, rows, mayEdit, problem }: { sessions: string[]; session: string; rows: CalendarRow[]; mayEdit: boolean; problem: Problem | null }) {
  const router = useRouter();
  const go = useQueryNav();
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  const [draft, setDraft] = useState<Record<string, { starts: string; ends: string }>>({});
  const key = (r: CalendarRow) => `${r.level}-${r.ordinal}`;
  const value = (r: CalendarRow) => draft[key(r)] ?? { starts: r.starts_on ?? "", ends: r.ends_on ?? "" };

  async function save(r: CalendarRow) {
    const v = value(r);
    setBusy(key(r)); setErr(null);
    try {
      const res = await fetch("/api/bff/api/v1/college/calendar", {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${r.level} Level semester ${r.ordinal} dated for ${session}`) },
        body: JSON.stringify({ session, level: r.level, ordinal: r.ordinal, startsOn: v.starts || null, endsOn: v.ends || null, lengthWeeks: r.length_weeks }),
      });
      const j = (await res.json().catch(() => null)) as Problem | null;
      if (!res.ok) { setErr(j ?? { status: res.status, title: res.statusText }); return; }
      notify(v.starts || v.ends ? `${r.level} Level semester ${r.ordinal} dated` : `${r.level} Level semester ${r.ordinal} cleared`);
      router.refresh();
    } finally { setBusy(null); }
  }

  const levels = Array.from(new Set(rows.map((r) => r.level)));
  const today = new Date().toISOString().slice(0, 10);
  return (
    <>
      <div className="scope">
        <div className="scope__f"><label htmlFor="cal-session">Session</label>
          <select id="cal-session" className="ws__select" value={session} onChange={(e) => go(`/college/calendar?session=${encodeURIComponent(e.target.value)}`)}>{sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></div>
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      <Note kind="info" title="The College's years run on their own dates">
        A cohort&rsquo;s year at a level begins in the session named here and runs by these dates, whatever the University&rsquo;s semesters do. The 100 Level year is the University&rsquo;s and is shorter, so a cohort promoted from 100 opens its 200 Level year while the cohort before it is still in its second semester. The examinations desk enters results for a cohort once its final semester has begun; a level left undated blocks nothing.
      </Note>
      {levels.map((L) => (
        <Panel key={L} title={`${L} Level · ${session}`} right={rows.find((r) => r.level === L)?.phase === "CLINICAL" ? "Clinical year: block and posting enrolment" : "Pre-clinical: the prospectus's semesters"}>
          <div className="tablewrap"><table className="tbl--data">
            <thead><tr><th>Semester</th><th className="mid">Weeks</th><th>Subjects</th><th className="mid">Starts</th><th className="mid">Ends</th><th className="mid">Standing</th><th></th></tr></thead>
            <tbody>
              {rows.filter((r) => r.level === L).map((r) => {
                const v = value(r);
                const standing = !r.starts_on ? "Undated" : r.starts_on > today ? "Ahead" : r.ends_on && r.ends_on < today ? "Ended" : "Running";
                return (
                  <tr key={key(r)}>
                    <td><strong>{r.name}</strong></td>
                    <td className="mid tnum">{r.length_weeks ?? "—"}</td>
                    <td className="sub2">{r.subjects ?? "—"}</td>
                    <td className="mid"><input type="date" className="ctl" value={v.starts} disabled={!mayEdit} onChange={(e) => setDraft({ ...draft, [key(r)]: { ...v, starts: e.target.value } })} /></td>
                    <td className="mid"><input type="date" className="ctl" value={v.ends} disabled={!mayEdit} onChange={(e) => setDraft({ ...draft, [key(r)]: { ...v, ends: e.target.value } })} /></td>
                    <td className="mid"><span className="sub2">{standing}</span></td>
                    <td>{mayEdit ? <Btn kind="primary" disabled={busy !== null} onClick={() => void save(r)}>{busy === key(r) ? "Saving…" : "Save"}</Btn> : null}</td>
                  </tr>
                );
              })}
            </tbody>
          </table></div>
          <PBody><div className="sub2">Blank both dates and save to clear a semester.</div></PBody>
        </Panel>
      ))}
    </>
  );
}
