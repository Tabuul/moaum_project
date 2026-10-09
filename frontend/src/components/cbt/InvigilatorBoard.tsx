"use client";
/** V374: the invigilator's screen for one sitting — seat by seat, who has not come, who is writing (and when the server last heard from
 *  them), who has submitted. The invigilator marks a candidate absent once the sitting has begun, or admits one who came late with up to
 *  the minutes they lost given back; a mark is undone while the candidate has not started. Every rule is the server's: who may mark
 *  (an invigilator of this sitting, or the office running the examination), when, and how many minutes. The screen reads the board
 *  again every fifteen seconds while it is in view. No candidate's answers or score are shown here. */
import { useCallback, useEffect, useMemo, useState } from "react";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedPrint, docSerial } from "@/lib/exportbrand";
import { num, whenAt } from "@/lib/cbt";
import { cbtSend } from "./CbtExam";

export type SeatState = "NOT_COME" | "ABSENT" | "ADMITTED" | "WRITING" | "DISCONNECTED" | "TIME_UP" | "SUBMITTED" | "TIME_EXPIRED" | "TERMINATED";
export interface BoardRow {
  seat_no: number; candidate_id: string; number: string; surname: string; other_names: string; level: number | null; programme: string | null; state: SeatState;
  attempt_id: string | null; started_at: string | null; ends_at: string | null; submitted_at: string | null; last_activity_at: string | null;
  answered: number | null; questions: number | null; violations: number | null; extra_minutes: number | null;
  mark: "ABSENT" | "LATE" | null; minutes_late: number | null; minutes_given: number | null; mark_note: string | null; marked_at: string | null; marked_by: string | null;
}
export interface Board {
  sitting: { id: string; exam_id: string; label: string; venue: string; starts_at: string; ends_at: string; capacity: number };
  exam: { id: string; reference: string; title: string; course_code: string; office: string; state: string; live_state: string; duration_minutes: number; late_entry_minutes: number | null };
  now: string; role: "INVIGILATOR" | "OFFICE" | "READER"; canMark: boolean;
  invigilators: { person_id: string; name: string; staff_number: string | null; chief: boolean }[];
  rows: BoardRow[]; marked?: number;
}

const STATE: Record<SeatState, [string, "grey" | "info" | "ok" | "bad" | "warn", string]> = {
  NOT_COME: ["Not come", "grey", "var(--line, #d0d5dd)"],
  ABSENT: ["Absent", "bad", "var(--red-line)"],
  ADMITTED: ["Admitted late", "info", "var(--amber-line)"],
  WRITING: ["Writing", "info", "var(--green-line)"],
  DISCONNECTED: ["Not heard from", "warn", "var(--amber-line)"],
  TIME_UP: ["Time up", "warn", "var(--amber-line)"],
  SUBMITTED: ["Submitted", "ok", "var(--green-line)"],
  TIME_EXPIRED: ["Time expired", "warn", "var(--amber-line)"],
  TERMINATED: ["Terminated", "bad", "var(--red-line)"],
};
const FILTERS: [string, string, SeatState[]][] = [
  ["all", "Every seat", []], ["notcome", "Not come", ["NOT_COME", "ADMITTED"]], ["writing", "Writing", ["WRITING"]], ["silent", "Not heard from", ["DISCONNECTED", "TIME_UP"]],
  ["done", "Finished", ["SUBMITTED", "TIME_EXPIRED", "TERMINATED"]], ["absent", "Absent", ["ABSENT"]],
];
const hhmm = (iso: string | null) => (iso ? new Date(iso).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" }) : "—");
const nameOf = (r: BoardRow) => `${r.surname.toUpperCase()}, ${r.other_names}`;
const initials = (r: BoardRow) => `${r.surname.charAt(0)}${r.other_names.charAt(0)}`.toUpperCase();

export function InvigilatorBoard({ initial }: { initial: Board }) {
  const [board, setBoard] = useState<Board>(initial);
  const [skew] = useState(() => new Date(initial.now).getTime() - Date.now());
  const [tick, setTick] = useState(() => Date.now());
  const [filter, setFilter] = useState("all");
  const [q, setQ] = useState("");
  const [open, setOpen] = useState<BoardRow | null>(null);
  const [note, setNote] = useState("");
  const [minutes, setMinutes] = useState("");
  const [busy, setBusy] = useState(false);
  const [stale, setStale] = useState(false);
  const id = initial.sitting.id;

  const load = useCallback(async () => {
    try {
      const r = await fetch(`/api/bff/api/v1/cbt/sittings/${id}/board`, { cache: "no-store" });
      if (!r.ok) { setStale(true); return; }
      setBoard((await r.json()) as Board);
      setStale(false);
    } catch { setStale(true); }
  }, [id]);
  useEffect(() => {
    const every = window.setInterval(() => { if (document.visibilityState === "visible") void load(); }, 15000);
    const clock = window.setInterval(() => setTick(Date.now()), 1000);
    const back = () => { if (document.visibilityState === "visible") void load(); };
    document.addEventListener("visibilitychange", back);
    return () => { window.clearInterval(every); window.clearInterval(clock); document.removeEventListener("visibilitychange", back); };
  }, [load]);

  const now = tick + skew;
  const s = board.sitting;
  const begun = now >= new Date(s.starts_at).getTime();
  const over = now >= new Date(s.ends_at).getTime();
  const lostMinutes = begun ? Math.ceil((now - new Date(s.starts_at).getTime()) / 60000) : 0;
  const count = (states: SeatState[]) => board.rows.filter((r) => states.includes(r.state)).length;
  const shown = useMemo(() => {
    const want = FILTERS.find((f) => f[0] === filter)?.[2] ?? [];
    const t = q.trim().toLowerCase();
    return board.rows.filter((r) => (!want.length || want.includes(r.state)) && (!t || `${r.number} ${r.surname} ${r.other_names} ${r.seat_no}`.toLowerCase().includes(t)));
  }, [board.rows, filter, q]);
  // the row in the side panel, kept current as the board is read again
  const current = open ? board.rows.find((r) => r.candidate_id === open.candidate_id) ?? open : null;

  async function act(path: string, body: unknown, reason: string) {
    setBusy(true);
    try {
      const j = await cbtSend(`/sittings/${id}${path}`, "POST", body, reason);
      if (j) { setBoard(j as unknown as Board); setOpen(null); }
    } finally { setBusy(false); }
  }
  const openSeat = (r: BoardRow) => { setOpen(r); setNote(""); setMinutes(String(lostMinutes)); };

  const left = Math.max(0, new Date(s.ends_at).getTime() - now);
  const leftText = over ? "ended" : begun ? `${Math.floor(left / 3600000) ? `${Math.floor(left / 3600000)} h ` : ""}${Math.floor((left % 3600000) / 60000)} min left` : `begins ${whenAt(s.starts_at)}`;
  const printRows = board.rows.map((r) => [r.seat_no, r.number, nameOf(r), r.level ?? "", r.programme ?? "", STATE[r.state][0] + (r.mark === "LATE" ? ` (${r.minutes_late} min late)` : ""), hhmm(r.started_at), hhmm(r.submitted_at), ""]);

  return (
    <>
      <Note kind={over ? "info" : begun ? "ok" : "info"} title={`${board.exam.course_code} · ${s.label} · ${s.venue}`}>
        {board.exam.title} ({board.exam.reference}) · {whenAt(s.starts_at)} to {hhmm(s.ends_at)} · {board.exam.duration_minutes} minutes once a candidate starts · <b>{leftText}</b>.
        {board.exam.late_entry_minutes != null ? <> A candidate may start on their own until <b>{hhmm(new Date(new Date(s.starts_at).getTime() + board.exam.late_entry_minutes * 60000).toISOString())}</b>; after that, admit them here.</> : <> There is no late-entry limit: a candidate may start at any time in the sitting.</>}
        {board.invigilators.length ? <> Invigilating: {board.invigilators.map((p) => `${p.name}${p.chief ? " (chief)" : ""}`).join("; ")}.</> : null}
      </Note>
      {stale ? <Note kind="bad" title="The board could not be read again">It shows the seats as they were last read; it tries again every fifteen seconds.</Note> : null}
      {board.role === "READER" ? <Note kind="info" title="Read only">Your office reads the board; the invigilators and the office running the examination mark it.</Note> : null}
      <Tiles cls="grid--5" items={[
        ["SEATED", num(board.rows.length), null, `of ${num(s.capacity)} seats`],
        ["NOT COME", num(count(["NOT_COME", "ADMITTED"])), null, `${num(count(["ADMITTED"]))} admitted late, not yet started`],
        ["WRITING", num(count(["WRITING"])), count(["WRITING"]) ? "var(--green-ink)" : null, `${num(count(["DISCONNECTED", "TIME_UP"]))} not heard from`],
        ["FINISHED", num(count(["SUBMITTED", "TIME_EXPIRED", "TERMINATED"])), null, `${num(count(["TIME_EXPIRED"]))} time expired · ${num(count(["TERMINATED"]))} terminated`],
        ["ABSENT", num(count(["ABSENT"])), count(["ABSENT"]) ? "var(--red-ink)" : null, "Marked by an invigilator"],
      ]} />

      <Panel title="Seats" right={<span className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
        <input className="ctl" aria-label="Find a candidate" placeholder="Name, matric number or seat" value={q} onChange={(e) => setQ(e.target.value)} />
        <Btn kind="ghost" size="sm" onClick={() => void load()}>Read again</Btn>
        <Btn kind="ghost" size="sm" disabled={!board.rows.length} onClick={() => brandedPrint(`${board.exam.course_code} CBT attendance`, `${board.exam.title} · ${s.label} · ${s.venue} · ${whenAt(s.starts_at)} to ${hhmm(s.ends_at)}`,
          ["Seat", "Matric No.", "Name", "Level", "Programme", "Attendance", "Started", "Finished", "Signature"], printRows, docSerial("CBT"))}>Print</Btn>
        {board.canMark && begun && count(["NOT_COME"]) ? <Btn kind="urgent" size="sm" disabled={busy} onClick={() => {
          if (window.confirm(`Mark the ${count(["NOT_COME"])} candidate${count(["NOT_COME"]) === 1 ? "" : "s"} who have not come and have no mark as absent? A candidate marked absent cannot start until an invigilator undoes the mark or admits them.`)) void act("/rest-absent", { note: "did not come" }, `Everyone not come in ${s.label} marked absent`);
        }}>Mark everyone not come absent</Btn> : null}
      </span>}>
        <PBody>
          <div className="row row--inline row--tight mb-2" style={{ flexWrap: "wrap" }} role="group" aria-label="Show">
            {FILTERS.map(([key, label, states]) => (
              <Btn key={key} kind={filter === key ? "primary" : "ghost"} size="sm" onClick={() => setFilter(key)}>{label}{states.length ? ` · ${count(states)}` : ""}</Btn>
            ))}
          </div>
          {shown.length ? (
            <div style={{ display: "grid", gap: 8, gridTemplateColumns: "repeat(auto-fill, minmax(190px, 1fr))" }}>
              {shown.map((r) => {
                const heard = r.last_activity_at ? Math.max(0, Math.round((now - new Date(r.last_activity_at).getTime()) / 1000)) : null;
                const minsLeft = r.ends_at ? Math.max(0, Math.ceil((new Date(r.ends_at).getTime() - now) / 60000)) : null;
                return (
                  <button key={r.candidate_id} type="button" onClick={() => openSeat(r)} aria-label={`Seat ${r.seat_no}: ${nameOf(r)}, ${STATE[r.state][0]}`}
                    style={{ textAlign: "left", border: `2px solid ${STATE[r.state][2]}`, borderRadius: 10, padding: "8px 10px", background: "var(--card, #fff)", cursor: "pointer", display: "grid", gap: 3, font: "inherit", color: "inherit" }}>
                    <span className="row row--inline row--tight" style={{ justifyContent: "space-between" }}>
                      <b className="tnum" style={{ fontSize: 18 }}>{r.seat_no}</b>
                      <Pil kind={STATE[r.state][1]}>{STATE[r.state][0]}</Pil>
                    </span>
                    <span className="row row--inline row--tight" style={{ alignItems: "center", gap: 8 }}>
                      <span aria-hidden style={{ width: 30, height: 30, borderRadius: "50%", background: "var(--wash, #eef1f5)", display: "inline-grid", placeItems: "center", fontSize: 12, fontWeight: 600, flex: "none" }}>{initials(r)}</span>
                      <span style={{ minWidth: 0 }}><b style={{ display: "block", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{nameOf(r)}</b><span className="sub2 tnum">{r.number}{r.level ? ` · ${r.level}L` : ""}</span></span>
                    </span>
                    {r.attempt_id ? (
                      <span className="sub2 tnum">
                        {r.answered ?? 0}/{r.questions ?? 0} answered
                        {r.state === "WRITING" || r.state === "DISCONNECTED" ? ` · ${minsLeft} min left` : r.submitted_at ? ` · done ${hhmm(r.submitted_at)}` : ""}
                        {r.state === "DISCONNECTED" && heard != null ? ` · last heard ${heard >= 120 ? `${Math.round(heard / 60)} min` : `${heard} s`} ago` : ""}
                        {r.violations ? ` · ${r.violations} flag${r.violations === 1 ? "" : "s"}` : ""}
                      </span>
                    ) : <span className="sub2">{r.mark === "LATE" ? `Admitted ${r.minutes_late} min late${r.minutes_given ? `, +${r.minutes_given} min` : ""}` : r.mark === "ABSENT" ? (r.mark_note ?? "Marked absent") : begun ? "Has not started" : "Sitting not begun"}</span>}
                  </button>
                );
              })}
            </div>
          ) : <div className="sub2">{board.rows.length ? "No seat matches." : "Nobody is seated in this sitting."}</div>}
          <div className="sub2 mt-2">A seat is &ldquo;not heard from&rdquo; when the candidate&rsquo;s screen has been silent for a minute: walk to the seat. The board is read again every fifteen seconds. Answers and scores are never shown here.</div>
        </PBody>
      </Panel>

      {current ? (
        <Modal title={`Seat ${current.seat_no} · ${nameOf(current)}`} sub={`${current.number}${current.level ? ` · ${current.level} level` : ""}${current.programme ? ` · ${current.programme}` : ""}`} onClose={() => setOpen(null)}
          foot={<Btn kind="ghost" onClick={() => setOpen(null)}>Close</Btn>}>
          <p><Pil kind={STATE[current.state][1]}>{STATE[current.state][0]}</Pil></p>
          {current.attempt_id ? (
            <div className="sub2 mb-2">
              Started {hhmm(current.started_at)}{current.ends_at ? ` · ends ${hhmm(current.ends_at)}` : ""}{current.submitted_at ? ` · finished ${hhmm(current.submitted_at)}` : ""} · {current.answered ?? 0} of {current.questions ?? 0} answered
              {current.violations ? ` · ${current.violations} integrity flag${current.violations === 1 ? "" : "s"} (see the live monitor)` : ""}{current.extra_minutes ? ` · ${current.extra_minutes} minutes' extra time from the office` : ""}.
            </div>
          ) : null}
          {current.mark ? <div className="sub2 mb-2">{current.mark === "ABSENT" ? "Marked absent" : `Admitted ${current.minutes_late} minutes late, ${current.minutes_given} minutes given back`}{current.mark_note ? ` — “${current.mark_note}”` : ""}{current.marked_by ? ` · ${current.marked_by}` : ""}{current.marked_at ? `, ${hhmm(current.marked_at)}` : ""}.</div> : null}
          {board.canMark && !current.attempt_id ? (
            <>
              {!begun ? <div className="sub2">The sitting has not begun: a candidate is marked absent, or admitted late, once it has.</div> : null}
              {begun && !over ? (
                <div className="row row--inline row--tight mt-2" style={{ flexWrap: "wrap", alignItems: "flex-end" }}>
                  <Field id="late-min" label="Minutes to give back" hint={`0 to ${lostMinutes}: the time lost since the sitting began`}><input id="late-min" className="ctl tnum" inputMode="numeric" style={{ maxWidth: 100 }} value={minutes} onChange={(e) => setMinutes(e.target.value.replace(/[^0-9]/g, ""))} /></Field>
                  <Btn kind="primary" disabled={busy || minutes === "" || Number(minutes) > lostMinutes} onClick={() => void act(`/candidates/${current.candidate_id}/late`, { minutes: Number(minutes), note: note.trim() || null }, `${nameOf(current)} admitted late with ${minutes} minutes given back`)}>{current.mark === "LATE" ? "Admit again" : "Admit late"}</Btn>
                </div>
              ) : null}
              <Field id="mark-note" label="Note" hint="Optional: why, as you would write it on the attendance sheet"><input id="mark-note" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} /></Field>
              <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
                {begun && current.mark !== "ABSENT" ? <Btn kind="urgent" disabled={busy} onClick={() => void act(`/candidates/${current.candidate_id}/absent`, { note: note.trim() || null }, `${nameOf(current)} marked absent`)}>Mark absent</Btn> : null}
                {current.mark ? <Btn kind="ghost" disabled={busy} onClick={() => void act(`/candidates/${current.candidate_id}/clear`, {}, `The mark on ${nameOf(current)} undone`)}>Undo the mark</Btn> : null}
              </div>
              <div className="sub2 mt-2">A candidate marked absent cannot start. Admitting a late candidate lets them start past the late-entry limit; the minutes given back are added to their clock, never more than the time they lost — more than that is extra time, given by the examination office with its reason.</div>
            </>
          ) : null}
          {board.canMark && current.attempt_id ? <div className="sub2">The candidate has started: they are present, and the mark{current.mark ? " stays on the record" : " is not needed"}.</div> : null}
        </Modal>
      ) : null}
    </>
  );
}
