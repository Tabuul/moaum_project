"use client";

/**
 * The lectures due (V354): the timetable's lectures on each teaching day — from the day teaching starts by the JUPEB calendar
 * until the examinations — and what became of each: recorded, open, not held (with the reason), due today, missed, or still to
 * come. "Take attendance" opens the lecture's own register (a subject may have two lectures in a day, each its own); "Not held"
 * records why a lecture did not take place, so it is not counted missed. The server shows a lecturer only their own subjects.
 */
import { useEffect, useState } from "react";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { WEEKDAYS, day, jcall } from "@/lib/jupeb";

const BASE = "/api/v1/attendance/jupeb";

export interface Lecture {
  slot_id: string; held_on: string; weekday: number; semester: number; subject_id: string; subject_code: string; subject_title: string; course_code: string | null;
  unit_title: string | null; practical: boolean; class_id: string | null; class_name: string | null; venue: string | null; starts_at: string; ends_at: string;
  register_id: string | null; saved_at: string | null; locked_at: string | null; marked: number; not_held: string | null; state: string;
}
interface Data { session: string; from: string; to: string; today: string; teachingStarts: string | null; semesterStarts: string | null; counts: Record<string, number>; rows: Lecture[] }

export const STATE_WORD: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = {
  RECORDED: ["Recorded", "ok"], OPEN: ["Opened, not saved", "warn"], NOT_HELD: ["Not held", "grey"], DUE: ["Due today", "info"], MISSED: ["Not recorded", "bad"], UPCOMING: ["To come", "grey"],
};
export const lectureName = (x: { practical: boolean; course_code: string | null; unit_title: string | null; subject_title: string }) =>
  x.practical ? `${x.subject_title} practical` : x.course_code ? `${x.course_code}${x.unit_title ? ` ${x.unit_title}` : ""}` : x.subject_title;

const addDays = (iso: string, n: number) => { const d = new Date(`${iso}T12:00:00Z`); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const monday = (iso: string) => { const d = new Date(`${iso}T12:00:00Z`); const w = (d.getUTCDay() + 6) % 7; return addDays(iso, -w); };

/** the lectures due, with the register of each opened from it */
export function LecturesDue({ session, office, onOpen }: { session: string; office: boolean; onOpen: (registerId: string) => void }) {
  const [range, setRange] = useState<"day" | "week" | "semester">("day");
  const [pick, setPick] = useState("");
  const [d, setD] = useState<Data | null>(null);
  const [tick, setTick] = useState(0);
  const [busy, setBusy] = useState(false);
  const [why, setWhy] = useState<{ x: Lecture; reason: string } | null>(null);
  const [onlyMissed, setOnlyMissed] = useState(false);
  useEffect(() => {
    let live = true;
    const q = new URLSearchParams({ session });
    if (range === "semester") q.set("scope", "semester");
    else if (pick) {
      if (range === "day") { q.set("from", pick); q.set("to", pick); }
      else { q.set("from", monday(pick)); q.set("to", addDays(monday(pick), 6)); }
    }
    void jcall<Data>(`${BASE}/lectures?${q}`).then((r) => {
      if (!live) return;
      if (!r.ok) { notifyProblem(r.problem); return; }
      if (!pick) setPick(r.data.today);
      setD(r.data);
    });
    return () => { live = false; };
  }, [session, range, pick, tick]);
  async function take(x: Lecture) {
    setBusy(true);
    try {
      const r = await jcall<{ id: string }>(`${BASE}/slots/${x.slot_id}/register`, "POST", { day: x.held_on }, `Attendance register: ${lectureName(x)} on ${x.held_on}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      onOpen(r.data.id);
    } finally { setBusy(false); }
  }
  async function notHeld() {
    if (!why) return;
    setBusy(true);
    try {
      const r = await jcall(`${BASE}/slots/${why.x.slot_id}/not-held`, "POST", { day: why.x.held_on, reason: why.reason.trim() }, `Lecture not held: ${lectureName(why.x)} on ${why.x.held_on}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setWhy(null); setTick((t) => t + 1); notify("Recorded as not held.");
    } finally { setBusy(false); }
  }
  async function withdraw(x: Lecture) {
    if (!window.confirm(`Withdraw "not held" for ${lectureName(x)} on ${day(x.held_on)}?`)) return;
    const r = await jcall(`${BASE}/slots/${x.slot_id}/not-held/withdraw`, "POST", { day: x.held_on }, `Lecture not held withdrawn: ${lectureName(x)} on ${x.held_on}`);
    if (r.ok) { setTick((t) => t + 1); notify("Withdrawn."); } else notifyProblem(r.problem);
  }
  if (!d) return <Note kind="info" title="Loading the lectures…">One moment.</Note>;
  const rows = onlyMissed ? d.rows.filter((x) => x.state === "MISSED" || x.state === "OPEN") : d.rows;
  const c = d.counts;
  return (
    <Panel title="Lectures from the timetable" right={<span className="row" style={{ flexWrap: "wrap" }}>
      <select className="ctl" style={{ width: 170 }} aria-label="Range" value={range} onChange={(e) => setRange(e.target.value as typeof range)}>
        <option value="day">One day</option><option value="week">The week</option><option value="semester">The semester so far</option></select>
      {range !== "semester" ? <>
        <Btn kind="ghost" aria-label="Before" onClick={() => setPick(addDays(pick, range === "day" ? -1 : -7))}>‹</Btn>
        <input type="date" className="ctl" style={{ width: 160 }} aria-label="Day" value={pick} max={d.today} onChange={(e) => setPick(e.target.value)} />
        <Btn kind="ghost" aria-label="After" disabled={pick >= d.today} onClick={() => setPick(addDays(pick, range === "day" ? 1 : 7))}>›</Btn>
        <Btn kind="ghost" onClick={() => setPick(d.today)}>Today</Btn></> : null}
    </span>}>
      <PBody>
        <div className="row" style={{ gap: "var(--s-2)", flexWrap: "wrap", marginBottom: "var(--s-2)" }}>
          {Object.entries(STATE_WORD).filter(([k]) => c[k]).map(([k, [w, kind]]) => <Pil key={k} kind={kind}>{`${w}: ${c[k]}`}</Pil>)}
          <label className="row row--inline row--tight"><input type="checkbox" checked={onlyMissed} onChange={(e) => setOnlyMissed(e.target.checked)} /> only those not recorded</label>
        </div>
        {!d.teachingStarts ? <Note kind="info" title="Teaching's start is not on the calendar">The lectures are counted from the day the JUPEB calendar says teaching starts. Mark that event on the calendar.</Note> : null}
        {!rows.length ? <p className="sub2">{d.rows.length ? "Every lecture here is recorded." : `No lecture is on the timetable ${range === "day" ? `on ${day(d.from)}` : "in these days"}${d.teachingStarts && d.from < d.teachingStarts ? " (teaching starts " + day(d.teachingStarts) + ")" : ""}.`}</p> : (
          <DTable pageSize={50} cols={["Day", "Time", "Lecture", "Class", "Room", "State", "|mid"]} texts={rows.map((x) => `${x.subject_code} ${x.subject_title} ${x.course_code ?? ""}`)}
            rows={rows.map((x) => [`${WEEKDAYS[x.weekday]} ${day(x.held_on)}`, `${x.starts_at}–${x.ends_at}`, lectureName(x), x.class_name ?? "Every class", x.venue ?? "to confirm",
              <span key="s" title={x.not_held ?? undefined}><Pil kind={STATE_WORD[x.state]?.[1] ?? "grey"}>{STATE_WORD[x.state]?.[0] ?? x.state}</Pil>{x.state === "RECORDED" ? <span className="sub2">{` ${x.marked} marked`}</span> : null}{x.not_held ? <span className="sub2">{` ${x.not_held}`}</span> : null}</span>,
              <span key="a" className="row" style={{ gap: 4, flexWrap: "nowrap" }}>
                {x.state !== "NOT_HELD" && x.state !== "UPCOMING" ? <Btn kind={x.state === "DUE" || x.state === "MISSED" ? "primary" : "ghost"} disabled={busy} onClick={() => void take(x)}>{x.register_id ? "Open" : "Take attendance"}</Btn> : null}
                {x.state !== "NOT_HELD" && x.state !== "RECORDED" ? <Btn kind="ghost" onClick={() => setWhy({ x, reason: "" })}>Not held…</Btn> : null}
                {x.state === "NOT_HELD" && office ? <Btn kind="ghost" onClick={() => void withdraw(x)}>Withdraw</Btn> : null}
              </span>])} />
        )}
      </PBody>
      {why ? (
        <Modal title={`${lectureName(why.x)} on ${day(why.x.held_on)} was not held`} onClose={() => setWhy(null)}
          foot={<><Btn kind="ghost" onClick={() => setWhy(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || why.reason.trim().length < 5} onClick={() => void notHeld()}>{busy ? "Saving…" : "Record it"}</Btn></>}>
          <p>The lecture is then not counted as missed. It cannot be recorded as not held once its attendance is taken.</p>
          <Field id="nh-why" label="Why" required><input id="nh-why" className="ctl" maxLength={300} placeholder="e.g. public holiday; the lecturer at a conference" value={why.reason} onChange={(e) => setWhy({ ...why, reason: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </Panel>
  );
}
