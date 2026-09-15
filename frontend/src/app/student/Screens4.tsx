"use client";

/**
 * Results — proto/part29.html sResults and proto/part4.html studentSlip, as
 * drawn — from the published sheets and nothing else: a grade appears the
 * moment Senate approves that set, and until the minute exists there is
 * nothing to show but the desk the sheet is on.
 */
import Link from "next/link";
import type { Results, ResultRow } from "@/lib/student-portal";
import { GRADE_COLOUR, STAGE_LABEL, semesterName } from "@/lib/student-portal";
import { Btn, Note, Panel, Pil, Tick, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { onDay } from "./common";

function group(rows: ResultRow[]): { session: string; semester: number; rows: ResultRow[] }[] {
  const out: { session: string; semester: number; rows: ResultRow[] }[] = [];
  for (const r of rows) {
    let g = out.find((x) => x.session === r.session && x.semester === r.semester);
    if (!g) { g = { session: r.session, semester: r.semester, rows: [] }; out.push(g); }
    g.rows.push(r);
  }
  return out;
}

export function ResultsScreen({ r }: { r: Results }) {
  const groups = group(r.rows);
  const latest = groups[groups.length - 1];
  const live = latest ? latest.rows.filter((x) => x.published) : [];
  const waiting = latest ? latest.rows.filter((x) => !x.published) : [];
  const sem = latest ? r.semesters.find((s) => s.session === latest.session && s.semester === latest.semester) : undefined;
  return (
    <>
      {r.clearsResults === false ? (
        <Note kind="bad" title="Your results are withheld until your fees are settled">Under the scheme in force, a semester result is released on payment in full. Your grades stand on the record; they are shown the moment the Bursary&rsquo;s position releases them.</Note>
      ) : !latest ? (
        <Note kind="info" title="Nothing is registered against you yet">Results follow an approved course registration. Register your courses, sit the papers, and the sheets appear here on the desk they are on.</Note>
      ) : live.length === 0 ? (
        <Note kind="info" title={`Your ${latest.session} ${semesterName(latest.semester).toLowerCase()}-semester results are not published yet`}>
          Nothing here is missing or lost. Each course below shows the desk it is on and the office holding it, and a grade appears the moment Senate approves that set &mdash; not before, because a result without a Senate minute is not a result.
        </Note>
      ) : waiting.length ? (
        <Note kind="info" title={`${live.length} of your ${latest.rows.length} courses are published`}>
          The rest are still in the approval chain. Each one below says where it is and who is holding it. Your GPA is calculated on the {sem?.units ?? 0} units released so far and will change as the others arrive.
        </Note>
      ) : (
        <Note kind="ok" title={`All ${latest.rows.length} courses are published${live[0]?.senate_minute ? ` under minute ${live[0].senate_minute}` : ""}`}>
          Released {onDay(live[0]?.published_at)}. Your statement of results is available below.
        </Note>
      )}
      {r.clearsResults !== false ? (
        <>
          <Tiles items={[
            ["This semester", sem?.gpa != null ? String(sem.gpa) : "—", sem?.gpa != null ? "var(--green-ink)" : "var(--faint)", sem?.gpa != null ? `GPA on ${sem.units} units released` : "No course released yet"],
            ["Cumulative", r.cgpa != null ? String(r.cgpa) : "—", null, r.cgpa != null ? "On every published semester" : "Nothing published yet"],
            ["Standing", r.standing ?? "—", null, "On the CGPA so far"],
            ["Units this semester", latest ? String(latest.rows.reduce((n, x) => n + x.units, 0)) : "0", null, "Registered and approved"],
          ]} />
          {latest ? (
            <Panel title={`${latest.session} · ${semesterName(latest.semester)} semester`} right={live.length ? `Published${live[0]?.senate_minute ? ` under ${live[0].senate_minute}` : ""}` : "In the approval chain"}>
              <DTable cols={["Course", "Units|mid", "Score|mid", "Grade|mid", "Points|mid", "Where it is", "Held by"]} rows={latest.rows.map((c) => {
                const st = STAGE_LABEL[c.stage] ?? [c.stage, ""];
                if (!c.published) return [<Two key="c" a={<span className="tnum">{c.course_code}</span>} b={c.title} />, <span className="tnum" key="u">{c.units}</span>, <span className="sub2" key="s">—</span>, <span className="sub2" key="g">—</span>, <span className="sub2" key="p">—</span>, <Pil kind="info" key="w">{st[0]}</Pil>, <span className="sub2" key="h">{st[1]}</span>];
                if (c.outcome !== "GRADED") return [<Two key="c" a={<span className="tnum">{c.course_code}</span>} b={c.title} />, <span className="tnum" key="u">{c.units}</span>, <Pil kind="bad" key="s">{c.outcome === "ABSENT" ? "Absent" : c.outcome}</Pil>, <span className="sub2" key="g">—</span>, <span className="sub2" key="p">—</span>, <Pil kind="ok" key="w">Published</Pil>, <span className="sub2" key="h">Not counted in the GPA</span>];
                return [<Two key="c" a={<span className="tnum">{c.course_code}</span>} b={c.title} />, <span className="tnum" key="u">{c.units}</span>, <b className="tnum" key="s">{c.total}</b>, <b key="g" style={{ color: GRADE_COLOUR[c.grade ?? ""] ?? "var(--ink)" }}>{c.grade}</b>, <span className="tnum" key="p">{c.points}</span>, <Pil kind="ok" key="w">Published</Pil>, <span className="sub2" key="h">{c.senate_minute ?? "—"}</span>];
              })} />
              <div style={{ padding: "0 16px 16px", display: "flex", gap: 9, flexWrap: "wrap" }}>
                {live.length ? <Link href={`/student/results/${encodeURIComponent(latest.session)}/${latest.semester}`} className="btn btn--primary">Statement of results</Link> : null}
                <Btn kind="ghost" disabled title="Arrives with the results desk">Query a mark</Btn>
                <Btn kind="ghost" disabled title="Arrives with the credentials module">Official transcript</Btn>
              </div>
            </Panel>
          ) : null}
          {waiting.length ? (
            <Panel title="What is holding each one" right="The office, not a department name">
              <DTable cols={["Course", "On the desk of", "What that desk does"]} rows={waiting.map((c) => { const st = STAGE_LABEL[c.stage] ?? [c.stage, ""]; return [<b className="tnum" key="c">{c.course_code}</b>, <span className="sub2" key="d">{st[1]}</span>, <span className="sub2" key="w">{st[0]}</span>]; })} />
            </Panel>
          ) : null}
          <Panel title="Academic summary" right="Senate-approved results only · CUR·CUE·WGP·GPA per semester, TCR·TCE·TWGP·CGPA cumulative">
            <DTable cols={["Session · Semester", "CUR|mid", "CUE|mid", "WGP|mid", "GPA|mid", "TCR|mid", "TCE|mid", "TWGP|mid", "LCGPA|mid", "CGPA|mid", "|num"]} rows={r.semesters.map((h) => [
              <span key="s"><span className="tnum">{h.session}</span> · {semesterName(h.semester)}</span>,
              <span className="tnum" key="cur">{h.cur}</span>, <span className="tnum" key="cue">{h.cue}</span>, <span className="tnum" key="wgp">{h.wgp}</span>,
              <b className="tnum" key="g">{h.gpa ?? "—"}</b>,
              <span className="tnum" key="tcr">{h.tcr}</span>, <span className="tnum" key="tce">{h.tce}</span>, <span className="tnum" key="twgp">{h.twgp}</span>,
              <span className="tnum sub2" key="l">{h.lcgpa ?? "—"}</span>, <b className="tnum" key="c">{h.cgpa ?? "—"}</b>,
              h.published_count ? <Link key="a" href={`/student/results/${encodeURIComponent(h.session)}/${h.semester}`} className="btn btn--ghost btn--sm">Open</Link> : <span className="sub2" key="a">—</span>,
            ])} />
            {!r.semesters.length ? <div className="card__body"><div className="sub2">No semester has a published result yet.</div></div> : (
              <div className="card__body"><div className="sub2">CUR credit units registered · CUE earned · WGP weighted grade points · TCR/TCE/TWGP the running totals · LCGPA the previous semester&rsquo;s CGPA. A full semester-by-semester broadsheet is on <Link href="/student/broadsheet">Result broadsheet</Link>.</div></div>
            )}
          </Panel>
          {r.carryovers.length ? (
            <Note kind="bad" title={`${r.carryovers.length} carryover${r.carryovers.length === 1 ? "" : "s"}`}>
              {r.carryovers.map((c) => `${c.course_code} (${c.failed_in})`).join(", ")} will be added to your next registration automatically. You do not need to request {r.carryovers.length === 1 ? "it" : "them"}.
            </Note>
          ) : null}
        </>
      ) : null}
    </>
  );
}

export function Slip({ r, session, semester }: { r: Results; session: string; semester: number }) {
  const rows = r.rows.filter((x) => x.session === session && x.semester === semester && x.published);
  const sem = r.semesters.find((s) => s.session === session && s.semester === semester);
  if (!rows.length || r.clearsResults === false) {
    return <Note kind="info" title="No statement for this semester">{r.clearsResults === false ? "Results are withheld until your fees are settled." : "Nothing is published for this semester yet."}</Note>;
  }
  const passed = rows.filter((x) => x.outcome === "GRADED" && (x.points ?? 0) > 0).reduce((n, x) => n + x.units, 0);
  const registered = rows.reduce((n, x) => n + x.units, 0);
  const gp = rows.filter((x) => x.outcome === "GRADED").reduce((n, x) => n + x.units * Number(x.points ?? 0), 0);
  const failed = rows.filter((x) => x.outcome === "GRADED" && (x.points ?? 0) === 0);
  return (
    <>
      <div className="card" style={{ background: "var(--chrome)", borderColor: "var(--chrome)" }}><div className="card__body">
        <div style={{ display: "flex", gap: 26, flexWrap: "wrap" }}>
          <div><div style={{ fontSize: 11, letterSpacing: ".5px", textTransform: "uppercase", color: "var(--chrome-ink)" }}>Semester GPA</div><div className="tnum" style={{ fontSize: 30, fontWeight: 700, color: "#fff", letterSpacing: "-.8px" }}>{sem?.gpa ?? "—"}</div></div>
          <div><div style={{ fontSize: 11, letterSpacing: ".5px", textTransform: "uppercase", color: "var(--chrome-ink)" }}>Cumulative</div><div className="tnum" style={{ fontSize: 30, fontWeight: 700, color: "#fff", letterSpacing: "-.8px" }}>{sem?.cgpa ?? "—"}</div></div>
        </div>
        {r.standing ? <div style={{ display: "flex", alignItems: "center", gap: 9, background: "var(--green)", borderRadius: 6, padding: "10px 13px" }}><Tick size={15} colour="#fff" /><span style={{ color: "#fff", fontWeight: 600 }}>{r.standing}</span></div> : null}
      </div></div>
      <div className="card"><div className="tablewrap"><table>
        <thead><tr><th>Course</th><th className="mid">Unit</th><th className="mid">Score</th><th className="mid">Grade</th></tr></thead>
        <tbody>
          {rows.map((x) => <tr key={x.course_code}><td><strong className="tnum">{x.course_code}</strong><div className="sub2">{x.title}</div></td><td className="mid tnum">{x.units}</td><td className="mid tnum">{x.outcome === "GRADED" ? x.total : x.outcome}</td><td className="mid" style={{ fontWeight: 700, color: GRADE_COLOUR[x.grade ?? ""] ?? "var(--ink)" }}>{x.grade ?? "—"}</td></tr>)}
          <tr><td style={{ fontWeight: 700 }}>Units registered {registered} · passed {passed}</td><td colSpan={3} className="num" style={{ fontWeight: 700, color: "var(--muted)" }}>GP {gp.toFixed(1)}</td></tr>
        </tbody>
      </table></div></div>
      {failed.length ? (
        <Note kind="bad" title={`${failed.length} carryover${failed.length === 1 ? "" : "s"}`}>{failed.map((x) => x.course_code).join(", ")} will be added to your next registration automatically. You do not need to request {failed.length === 1 ? "it" : "them"}.</Note>
      ) : null}
      <div style={{ display: "flex", gap: 9, flexWrap: "wrap" }}>
        <a href={`/student/results/${encodeURIComponent(session)}/${semester}/pdf`} target="_blank" rel="noopener" className="btn btn--primary">Download result slip</a>
        <Link href="/student/results" className="btn btn--ghost">All results</Link>
      </div>
      <div className="sub2">Published {onDay(rows[0]?.published_at)} after Senate approval{rows[0]?.senate_minute ? ` · minute ${rows[0].senate_minute}` : ""}. The register is the thing; this slip is a view of it.</div>
    </>
  );
}

/** s/broadsheet — the student's own results as a broadsheet: each semester's courses, then its
 *  summary line (CUR·CUE·WGP·GPA this semester; TCR·TCE·TWGP·LCGPA·CGPA cumulative). */
export function Broadsheet({ r }: { r: Results }) {
  if (r.clearsResults === false) {
    return <Note kind="bad" title="Your results are withheld until your fees are settled"><Link href="/student/fees" className="btn btn--urgent btn--sm">Fees &amp; payments</Link></Note>;
  }
  const groups = group(r.rows.filter((x) => x.published));
  const semOf = (s: string, n: number) => r.semesters.find((x) => x.session === s && x.semester === n);
  return (
    <>
      <Tiles items={[
        ["Name", r.name, null, `${r.matricNo} · ${r.programme}`],
        ["Level", `${r.level} Level`, null, "Current"],
        ["CGPA", r.cgpa != null ? String(r.cgpa) : "—", null, "On every published semester"],
        ["Standing", r.standing ?? "—", null, "On the CGPA so far"],
      ]} />
      {groups.length ? groups.map((g) => {
        const sm = semOf(g.session, g.semester);
        return (
          <Panel key={`${g.session}-${g.semester}`} title={`${g.session} · ${semesterName(g.semester)} semester`}
            right={sm ? `GPA ${sm.gpa ?? "—"} · CGPA ${sm.cgpa ?? "—"}` : undefined}>
            <div className="tablewrap"><table style={{ minWidth: 520 }}>
              <thead><tr>
                <th>Course</th><th>Title</th><th className="mid">Unit</th><th className="mid">CA</th><th className="mid">Exam</th><th className="mid">Total</th><th className="mid">Grade</th><th className="mid">Point</th>
              </tr></thead>
              <tbody>
                {g.rows.map((c) => (
                  <tr key={c.course_code}>
                    <td className="tnum" style={{ fontWeight: 600 }}>{c.course_code}</td>
                    <td>{c.title}</td>
                    <td className="mid tnum">{c.units}</td>
                    <td className="mid tnum">{c.outcome === "GRADED" ? (c.ca ?? "—") : "—"}</td>
                    <td className="mid tnum">{c.outcome === "GRADED" ? (c.exam ?? "—") : "—"}</td>
                    <td className="mid tnum">{c.outcome === "GRADED" ? (c.total ?? "—") : (c.outcome ? c.outcome.charAt(0) + c.outcome.slice(1).toLowerCase() : "—")}</td>
                    <td className="mid tnum" style={{ fontWeight: 700, color: c.grade ? GRADE_COLOUR[c.grade] : undefined }}>{c.grade ?? "—"}</td>
                    <td className="mid tnum">{c.points ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table></div>
            {sm ? (
              <div className="card__body" style={{ borderTop: "1px solid var(--line-2)" }}>
                <div className="tnum" style={{ display: "flex", flexWrap: "wrap", gap: "4px 16px", fontSize: 12.5 }}>
                  <span><b>CUR</b> {sm.cur}</span><span><b>CUE</b> {sm.cue}</span><span><b>WGP</b> {sm.wgp}</span><span><b>GPA</b> {sm.gpa ?? "—"}</span>
                  <span style={{ color: "var(--faint)" }}>|</span>
                  <span><b>TCR</b> {sm.tcr}</span><span><b>TCE</b> {sm.tce}</span><span><b>TWGP</b> {sm.twgp}</span><span><b>LCGPA</b> {sm.lcgpa ?? "—"}</span><span><b>CGPA</b> {sm.cgpa ?? "—"}</span>
                </div>
              </div>
            ) : null}
          </Panel>
        );
      }) : <Panel title="No published results yet"><div className="card__body"><div className="sub2">A semester appears here once Senate approves its results. Nothing is shown before the minute exists.</div></div></Panel>}
      <p className="sub2" style={{ maxWidth: "80ch" }}>CUR credit units registered · CUE credit units earned · WGP weighted grade points · GPA the semester average · TCR/TCE/TWGP the running totals · LCGPA the previous semester&rsquo;s CGPA · CGPA the cumulative average. This is a view of the published record.</p>
      {groups.length ? (
        <div style={{ display: "flex", gap: 9, flexWrap: "wrap" }}>
          <a href="/student/broadsheet/pdf" target="_blank" rel="noopener" className="btn btn--primary">Print broadsheet</a>
        </div>
      ) : null}
    </>
  );
}
