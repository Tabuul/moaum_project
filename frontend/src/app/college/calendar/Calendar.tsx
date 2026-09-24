"use client";
/** The College's calendar (V249): each level's semesters dated for a session. The prospectus gives lengths, never dates;
 *  the College enters them here. The dates tell the student where their year is and when it ends, and hold the
 *  examinations desk to the end of the year: results are entered once the cohort's final semester has begun. The
 *  University's own semesters for the session stand beside, since the College's years are staggered against them. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { SemesterRow } from "@/lib/calendar";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface CalendarRow { level: number; phase: string; ordinal: number; name: string; length_weeks: number | null; starts_on: string | null; ends_on: string | null; subjects: string | null; open_years?: number }

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const plusYear = (iso: string | null) => { if (!iso) return ""; const d = new Date(iso); d.setFullYear(d.getFullYear() + 1); return d.toISOString().slice(0, 10); };
const weeksBetween = (a: string | null, b: string | null) => (a && b ? Math.round((new Date(b).getTime() - new Date(a).getTime()) / (7 * 86400000)) : null);

export function Calendar({ sessions, session, rows, previous, university, mayEdit, problem }: {
  sessions: string[]; session: string; rows: CalendarRow[]; previous: CalendarRow[]; university: SemesterRow[]; mayEdit: boolean; problem: Problem | null;
}) {
  const router = useRouter();
  const go = useQueryNav();
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  const [draft, setDraft] = useState<Record<string, { starts: string; ends: string }>>({});
  const key = (r: CalendarRow) => `${r.level}-${r.ordinal}`;
  const value = (r: CalendarRow) => draft[key(r)] ?? { starts: r.starts_on ?? "", ends: r.ends_on ?? "" };
  const changed = (r: CalendarRow) => { const v = value(r); return v.starts !== (r.starts_on ?? "") || v.ends !== (r.ends_on ?? ""); };
  const today = new Date().toISOString().slice(0, 10);
  const prevSession = sessions[sessions.indexOf(session) + 1] ?? null;

  async function saveOne(r: CalendarRow): Promise<boolean> {
    const v = value(r);
    const res = await fetch("/api/bff/api/v1/college/calendar", {
      method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${r.level} Level semester ${r.ordinal} dated for ${session}`) },
      body: JSON.stringify({ session, level: r.level, ordinal: r.ordinal, startsOn: v.starts || null, endsOn: v.ends || null, lengthWeeks: r.length_weeks }),
    });
    if (!res.ok) { const j = (await res.json().catch(() => null)) as Problem | null; const p = j ?? { status: res.status, title: res.statusText }; setErr(p); notifyProblem(p); return false; }
    return true;
  }
  async function save(r: CalendarRow) {
    setBusy(key(r)); setErr(null);
    try {
      if (await saveOne(r)) { const v = value(r); notify(v.starts || v.ends ? `${r.level} Level semester ${r.ordinal} dated` : `${r.level} Level semester ${r.ordinal} cleared`); router.refresh(); }
    } finally { setBusy(null); }
  }
  async function saveAll() {
    const todo = rows.filter(changed);
    if (!todo.length) return;
    setBusy("all"); setErr(null);
    try {
      let n = 0;
      for (const r of todo) { if (!(await saveOne(r))) break; n++; }
      if (n) { notify(`${n} semester${n === 1 ? "" : "s"} dated for ${session}`); setDraft({}); router.refresh(); }
    } finally { setBusy(null); }
  }
  function copyPrevious() {
    if (!previous.length) return;
    const next: typeof draft = { ...draft };
    for (const r of rows) {
      const p = previous.find((x) => x.level === r.level && x.ordinal === r.ordinal);
      if (p && (p.starts_on || p.ends_on)) next[key(r)] = { starts: plusYear(p.starts_on), ends: plusYear(p.ends_on) };
    }
    setDraft(next);
    notify(`${prevSession}'s dates copied a year on; check them and save`, "info");
  }

  const levels = Array.from(new Set(rows.map((r) => r.level)));
  const summary = levels.map((L) => {
    const rs = rows.filter((r) => r.level === L);
    const dated = rs.filter((r) => r.starts_on);
    const starts = dated.map((r) => r.starts_on!).sort()[0] ?? null;
    const ends = rs.filter((r) => r.ends_on).map((r) => r.ends_on!).sort().reverse()[0] ?? null;
    const last = rs.slice().sort((a, b) => b.ordinal - a.ordinal).find((r) => r.starts_on);
    const reached = !last || last.starts_on! <= today;
    const standing = !dated.length ? "Undated" : starts && starts > today ? "Ahead" : ends && ends < today ? "Ended" : "Running";
    return { level: L, phase: rs[0]?.phase, dated: dated.length, of: rs.length, starts, ends, weeks: weeksBetween(starts, ends), open: rs[0]?.open_years ?? 0, reached, standing };
  });
  const undated = summary.filter((s) => s.open > 0 && !s.dated).length;
  const pending = rows.filter(changed).length;

  return (
    <>
      <div className="scope">
        <div className="scope__f"><label htmlFor="cal-session">Session</label>
          <select id="cal-session" className="ws__select" value={session} onChange={(e) => go(`/college/calendar?session=${encodeURIComponent(e.target.value)}`)}>{sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></div>
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      <Tiles items={[
        ["Levels dated", `${summary.filter((s) => s.dated).length} of ${summary.length}`, null, session],
        ["Years open, undated", String(undated), undated ? "var(--red-ink)" : null, undated ? "Their end and the results guard stay unknown" : "Every level with years open is dated"],
        ["Running now", String(summary.filter((s) => s.standing === "Running").length), null, `${summary.filter((s) => s.standing === "Ahead").length} ahead · ${summary.filter((s) => s.standing === "Ended").length} ended`],
        ["Unsaved changes", String(pending), pending ? "var(--amber-ink)" : null, pending ? "Save each row, or all at once" : "Nothing pending"],
      ]} />
      <Note kind="info" title="The College's years run on their own dates" action={mayEdit ? <span className="row row--tight">
        {previous.some((p) => p.starts_on) ? <Btn kind="secondary" disabled={busy !== null} onClick={copyPrevious}>Copy {prevSession}&rsquo;s dates, a year on</Btn> : null}
        <Btn kind="go" disabled={busy !== null || !pending} onClick={() => void saveAll()}>{busy === "all" ? "Saving…" : `Save all ${pending || ""}`.trim()}</Btn>
      </span> : undefined}>
        A cohort&rsquo;s year at a level begins in the session named here and runs by these dates, whatever the University&rsquo;s semesters do. The 100 Level year is the University&rsquo;s and is shorter, so a cohort promoted from 100 opens its 200 Level year while the cohort before it is still in its second semester. The examinations desk enters results for a cohort once its final semester has begun; a level left undated blocks nothing.
      </Note>

      <Panel title={`The year at each level · ${session}`} right="The span of its semesters, and what stands on it">
        <DTable cols={["Level|mid", "Phase", "Semesters dated|mid", "Begins|mid", "Ends|mid", "Weeks|mid", "Years open|mid", "Standing|mid", "Results|mid"]} rows={summary.map((s) => [
          <strong className="tnum" key="l">{s.level}</strong>,
          <span className="sub2" key="p">{s.phase === "CLINICAL" ? "Clinical" : "Pre-clinical"}</span>,
          <span className="tnum" key="d">{s.dated} of {s.of}</span>,
          <span className="tnum" key="b">{day(s.starts)}</span>,
          <span className="tnum" key="e">{day(s.ends)}</span>,
          <span className="tnum" key="w">{s.weeks ?? "—"}</span>,
          <span className="tnum" key="o" style={{ color: s.open && !s.dated ? "var(--red-ink)" : undefined }}>{s.open}</span>,
          <Pil key="s" kind={s.standing === "Running" ? "ok" : s.standing === "Ahead" ? "info" : s.standing === "Ended" ? "grey" : s.open ? "bad" : "grey"}>{s.standing}</Pil>,
          <span key="r" className="sub2">{s.dated ? (s.reached ? "Open" : `From ${day(rows.filter((r) => r.level === s.level).slice().sort((a, b) => b.ordinal - a.ordinal).find((r) => r.starts_on)?.starts_on ?? null)}`) : "Open (undated)"}</span>,
        ])} />
      </Panel>

      {levels.map((L) => (
        <Panel key={L} title={`${L} Level · ${session}`} right={rows.find((r) => r.level === L)?.phase === "CLINICAL" ? "Clinical year: block and posting enrolment" : "Pre-clinical: the prospectus's semesters"}>
          <div className="tablewrap"><table className="tbl--data">
            <thead><tr><th>Semester</th><th className="mid">Weeks</th><th>Subjects</th><th className="mid">Starts</th><th className="mid">Ends</th><th className="mid">Standing</th><th></th></tr></thead>
            <tbody>
              {rows.filter((r) => r.level === L).map((r) => {
                const v = value(r);
                const standing = !r.starts_on ? "Undated" : r.starts_on > today ? "Ahead" : r.ends_on && r.ends_on < today ? "Ended" : "Running";
                const w = weeksBetween(v.starts || null, v.ends || null);
                return (
                  <tr key={key(r)}>
                    <td><strong>{r.name}</strong></td>
                    <td className="mid tnum">{r.length_weeks ?? "—"}{w != null && r.length_weeks != null && w !== r.length_weeks ? <div className="sub2" style={{ color: "var(--amber-ink)" }}>{w} dated</div> : null}</td>
                    <td className="sub2">{r.subjects ?? "—"}</td>
                    <td className="mid"><input type="date" className={`ctl${changed(r) ? " is-changed" : ""}`} value={v.starts} disabled={!mayEdit} onChange={(e) => setDraft({ ...draft, [key(r)]: { ...v, starts: e.target.value } })} /></td>
                    <td className="mid"><input type="date" className="ctl" value={v.ends} disabled={!mayEdit} onChange={(e) => setDraft({ ...draft, [key(r)]: { ...v, ends: e.target.value } })} /></td>
                    <td className="mid"><Pil kind={standing === "Running" ? "ok" : standing === "Ahead" ? "info" : "grey"}>{standing}</Pil></td>
                    <td>{mayEdit ? <Btn kind={changed(r) ? "primary" : "ghost"} disabled={busy !== null || !changed(r)} onClick={() => void save(r)}>{busy === key(r) ? "Saving…" : "Save"}</Btn> : null}</td>
                  </tr>
                );
              })}
            </tbody>
          </table></div>
          <PBody><div className="sub2">Blank both dates and save to clear a semester. A dated span that differs from the prospectus&rsquo;s weeks is shown in amber, not refused.</div></PBody>
        </Panel>
      ))}

      <Panel title={`The University's semesters · ${session}`} right="For comparison: the 100 Level year, and the fee semesters the College's registration reads">
        {university.length ? (
          <DTable cols={["Semester|mid", "Lectures", "Registration", "Late registration closes|mid", "Examinations", "Results due|mid", "State|mid"]} rows={university.map((u) => [
            <strong className="tnum" key="n">{u.number}</strong>,
            <span className="tnum" key="l">{day(u.lecturesFrom)} to {day(u.lecturesTo)}</span>,
            <span className="tnum" key="r">{day(u.registrationOpens)} to {day(u.registrationCloses)}</span>,
            <span className="tnum" key="lr">{day(u.lateRegistrationCloses)}</span>,
            <span className="tnum" key="x">{day(u.examsFrom)} to {day(u.examsTo)}</span>,
            <span className="tnum" key="d">{day(u.resultsDue)}</span>,
            <Pil key="s" kind={u.state === "OPEN" ? "ok" : u.state === "CLOSED" ? "grey" : "info"}>{u.state === "NOT_YET_OPEN" ? "Not yet open" : u.state === "OPEN" ? "Open" : "Closed"}</Pil>,
          ])} />
        ) : <PBody><div className="sub2">The Registry has not dated the University&rsquo;s semesters for {session} yet.</div></PBody>}
      </Panel>
    </>
  );
}
