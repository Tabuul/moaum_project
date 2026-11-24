"use client";

/** V779 · "Select your courses": the courses of the student's programme (every level up to the final one, both semesters together),
 *  the ones the results show failed and the ones the Academic Office named, to be searched and ticked. The student selects the
 *  courses they believe they still owe, even where their earlier results are not on the portal; the Academic Office verifies each
 *  against the record. Several courses at once, both semesters in one call, at most 30 a call. Selecting is the server's act
 *  alone: a course it refuses is said with its reason, and nothing here decides who may take what. */
import { useMemo, useState } from "react";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { useAct } from "../common";
import {
  SELECT_LIMIT, asTakenWord, courseReasonWord, courseSemesterWord, courseStatusWords, evidenceTone, evidenceWord, filterPool, groupByLevel, naira, plural, poolCounts,
  poolLevels, selectionCost, selectionFormula, type MySummer, type PoolFilter, type SummerCourse,
} from "@/lib/summer";

interface Origin { session: string; semester: string }

export function Picker({ d, sessions }: { d: MySummer; sessions: string[] }) {
  const { act, busy, problem } = useAct();
  const courses = useMemo(() => d.courses ?? [], [d.courses]);
  const canSelect = !!d.period?.open_now && !!d.fee && !!d.eligibility?.eligible;
  const [q, setQ] = useState("");
  const [level, setLevel] = useState("all");
  const [semester, setSemester] = useState("all");
  const [scope, setScope] = useState<NonNullable<PoolFilter["scope"]>>("all");
  const [picked, setPicked] = useState<string[]>([]);
  const [origins, setOrigins] = useState<Record<string, Origin>>({});

  const counts = useMemo(() => poolCounts(courses), [courses]);
  const levels = useMemo(() => poolLevels(courses), [courses]);
  const shown = useMemo(() => filterPool(courses, { q, level: level === "all" ? "all" : Number(level), semester: semester === "all" ? "all" : (Number(semester) as 1 | 2), scope }), [courses, q, level, semester, scope]);
  const groups = useMemo(() => groupByLevel(shown), [shown]);
  const byCode = useMemo(() => new Map(courses.map((c) => [c.course_code, c])), [courses]);

  // a course the page no longer offers (selected, then the page read again) leaves the ticks
  const live = picked.filter((code) => byCode.get(code)?.selectable);
  const batch = live.slice(0, SELECT_LIMIT);
  const units = live.reduce((s, code) => s + (byCode.get(code)?.units ?? 0), 0);
  const cost = selectionCost(live.length, d.account, d.fee);
  // an origin is given whole (the session and the semester) or not at all
  const half = live.some((code) => { const o = origins[code]; return !!o && (!!o.session !== !!o.semester); });

  function toggle(c: SummerCourse) {
    setPicked((x) => (x.includes(c.course_code) ? x.filter((k) => k !== c.course_code) : [...x, c.course_code]));
  }
  function setOrigin(code: string, patch: Partial<Origin>) {
    setOrigins((o) => {
      const cur: Origin = o[code] ?? { session: "", semester: "" };
      return { ...o, [code]: { ...cur, ...patch } };
    });
  }
  async function select() {
    const body = {
      session: d.session,
      courses: batch,
      origins: batch.filter((code) => origins[code]?.session && origins[code]?.semester)
        .map((code) => ({ course: code, session: origins[code].session, semester: Number(origins[code].semester) })),
    };
    const r = await act("select", "POST", "/me/summer/select", body, "Summer Semester courses selected", `${plural(batch.length, "course")} selected — pay to register`);
    if (r) setPicked((x) => x.filter((code) => !batch.includes(code)));
  }

  if (!courses.length) {
    return <Note kind="info" title="No course to select">No course of your programme or your record can be selected in the Summer Semester now. If you believe this is wrong, ask your department or the Academic Office.</Note>;
  }
  return (
    <Panel title="Select your courses" right={`${plural(counts.total, "course")} · first and second semester together`}>
      <PBody>
        <div className="sub2 mb-2">Search your programme&rsquo;s courses and tick the ones you believe you still owe. You may select courses even where your earlier results are not on the portal; the Academic Office verifies each against your record.</div>
        <div className="filterbar" role="search">
          <div className="field" style={{ flex: "2 1 220px" }}>
            <label htmlFor="sp-q">Search</label>
            <input id="sp-q" className="ctl" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Code or title" autoComplete="off" />
          </div>
          <div className="field" style={{ flex: "0 1 120px" }}>
            <label htmlFor="sp-level">Level</label>
            <select id="sp-level" className="ctl" value={level} onChange={(e) => setLevel(e.target.value)}>
              <option value="all">All</option>
              {levels.map((l) => <option key={l} value={String(l)}>{l}</option>)}
            </select>
          </div>
          <div className="field" style={{ flex: "0 1 130px" }}>
            <label htmlFor="sp-sem">Semester</label>
            <select id="sp-sem" className="ctl" value={semester} onChange={(e) => setSemester(e.target.value)}>
              <option value="all">Both</option><option value="1">First</option><option value="2">Second</option>
            </select>
          </div>
          <div className="field" style={{ flex: "0 1 190px" }}>
            <label htmlFor="sp-show">Show</label>
            <select id="sp-show" className="ctl" value={scope} onChange={(e) => setScope(e.target.value as NonNullable<PoolFilter["scope"]>)}>
              <option value="all">All courses ({counts.total})</option>
              <option value="outstanding">My outstanding ({counts.outstanding})</option>
              <option value="selected">Selected ({counts.inSelected})</option>
            </select>
          </div>
        </div>
        <div className="sub2 mt-1" role="status" aria-live="polite">{plural(shown.length, "course")} shown{shown.length !== counts.total ? ` of ${counts.total}` : ""}.</div>
      </PBody>

      {groups.length === 0 ? <PBody><div className="sub2">No course matches these filters.</div></PBody> : groups.map((g) => (
        <section key={g.label} aria-label={g.label}>
          <PBody><div className="eyebrow">{g.label} · {plural(g.courses.length, "course")}</div></PBody>
          <DTable pageSize={0} noPrint title={g.label}
            cols={["|mid", "Course", "Title", "Units|num", "Level|num", "Semester", "Result evidence", "Status", "Fee|num"]}
            rows={g.courses.map((c) => {
              const ticked = live.includes(c.course_code);
              const taken = asTakenWord(c);
              const status = courseStatusWords(c);
              const o = origins[c.course_code] ?? { session: "", semester: "" };
              return [
                c.selectable && canSelect
                  ? <input key={`t${c.course_code}`} type="checkbox" aria-label={`Select ${c.course_code}, ${c.title ?? ""}`} checked={ticked} onChange={() => toggle(c)} />
                  : <span key={`t${c.course_code}`} />,
                <b key={`c${c.course_code}`} className="tnum">{c.course_code}</b>,
                <span key={`n${c.course_code}`}>{c.title ?? "—"}
                  {taken ? <span className="blk sub2">{taken}</span> : null}
                  {ticked ? (
                    <span className="blk" style={{ marginTop: "var(--s-1)" }}>
                      <span className="sub2 blk">Where did you owe it? (optional)</span>
                      <span className="row row--tight">
                        <select className="ctl" style={{ width: "auto" }} aria-label={`Session in which you owed ${c.course_code}`} value={o.session} onChange={(e) => setOrigin(c.course_code, { session: e.target.value })}>
                          <option value="">Session: not sure</option>
                          {sessions.map((s) => <option key={s} value={s}>{s}</option>)}
                        </select>
                        <select className="ctl" style={{ width: "auto" }} aria-label={`Semester in which you owed ${c.course_code}`} value={o.semester} onChange={(e) => setOrigin(c.course_code, { semester: e.target.value })}>
                          <option value="">Semester: not sure</option>
                          <option value="1">First</option><option value="2">Second</option>
                        </select>
                      </span>
                    </span>
                  ) : null}
                </span>,
                <span key={`u${c.course_code}`} className="tnum">{c.units ?? "—"}</span>,
                <span key={`l${c.course_code}`} className="tnum">{c.level ?? "—"}</span>,
                <span key={`s${c.course_code}`}>{courseSemesterWord(c)}</span>,
                c.evidence ? <Pil key={`e${c.course_code}`} kind={evidenceTone(c.evidence)}>{evidenceWord(c.evidence)}</Pil> : <span key={`e${c.course_code}`} className="sub2">—</span>,
                <span key={`p${c.course_code}`}>
                  {status ? <Pil kind={status[1]}>{status[0].toUpperCase()}</Pil> : null}
                  {!c.selectable && c.reason && !(status && (c.reason === "ALREADY_REGISTERED" || c.reason === "ALREADY_SELECTED")) ? <span className="blk sub2">{courseReasonWord(c.reason)}</span> : null}
                  {(c.verification === "NOT_OUTSTANDING" || c.verification === "REJECTED") && c.decision_reason ? <span className="blk sub2">{c.decision_reason}</span> : null}
                </span>,
                <span key={`f${c.course_code}`} className="tnum">{naira(c.course_fee)}</span>,
              ];
            })} />
        </section>
      ))}

      {live.length > 0 ? (
        <div className="row" role="region" aria-label="Your selection"
          style={{ position: "sticky", bottom: 0, zIndex: 5, background: "var(--surface)", borderTop: "1px solid var(--line)", boxShadow: "var(--sh-2)", padding: "var(--s-3) var(--s-4)", gap: "var(--s-3)", justifyContent: "space-between" }}>
          <div>
            <b className="tnum">{live.length} selected · {units} unit{units === 1 ? "" : "s"} · {selectionFormula(live.length, d.account, d.fee)}</b>
            {live.length > SELECT_LIMIT ? <div className="sub2">Select up to {SELECT_LIMIT} at a time; select the rest afterwards.</div> : null}
            {half ? <div className="sub2 ink-red">Say both the session and the semester where you owed a course, or neither.</div> : null}
            {!d.account?.programmeFeeState ? <div className="sub2">The programme fee ({naira(d.fee?.programme_fee)}) is charged once, with your first course; you pay after selecting.</div> : <div className="sub2">The programme fee is already charged; each course adds its course fee ({naira(cost)} for these).</div>}
          </div>
          <div className="row row--tight">
            <Btn kind="ghost" size="md" disabled={busy !== null} onClick={() => setPicked([])}>Clear</Btn>
            <Btn kind="primary" size="md" busy={busy === "select"} busyLabel="Selecting…" disabled={busy !== null || half || batch.length === 0} onClick={() => void select()}>
              Select {plural(batch.length, "course")}
            </Btn>
          </div>
        </div>
      ) : null}
      {problem ? <PBody><ProblemNotice problem={problem} /></PBody> : null}
      {!canSelect ? <PBody><div className="sub2">{!d.period?.open_now ? "Registration is not open, so no course can be selected now." : !d.fee ? "You can select courses once the Bursary publishes the fees." : ""}</div></PBody> : null}
    </Panel>
  );
}
