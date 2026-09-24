"use client";

/**
 * The Postgraduate School's own session and semester calendar (V224), apart from the University's
 * undergraduate one. The School lists its sessions, marks the one it is currently running, and sets the
 * registration/lecture/exam windows for each semester (a session may run a third, Summer, semester).
 * Everything the PG module reads for "the current session" resolves from here.
 */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { Modal, Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

interface SessionRow { name: string; starts_on: string | null; ends_on: string | null; semesters: number; state: string; note: string | null }
interface SemesterRow { number: number; registration_opens: string | null; registration_closes: string | null; lectures_from: string | null; lectures_to: string | null; exams_from: string | null; exams_to: string | null; results_due: string | null; state: string }
interface CalData { sessions: SessionRow[]; current: string | null; looking: string | null; semesters: SemesterRow[] }

const SEM_NAME: Record<number, string> = { 1: "First semester", 2: "Second semester", 3: "Summer semester" };
const STATE_PILL: Record<string, string> = { PLANNED: "var(--chrome)", CURRENT: "var(--green-ink)", CLOSED: "var(--ink-3, var(--faint))" };
const SEM_STATE: Record<string, string> = { NOT_YET_OPEN: "var(--chrome)", OPEN: "var(--green-ink)", CLOSED: "var(--ink-3, var(--faint))" };

const day = (v: string | null) => {
  if (!v) return "—";
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" });
};
const parts = (name: string): [string, string] => { const [s, y] = name.split("/"); return [s, y]; };

type Draft = Record<string, string>;

export function PgCalendar({ initial }: { initial: CalData }) {
  const [data, setData] = useState<CalData>(initial);
  const [looking, setLooking] = useState<string>(initial.looking ?? initial.current ?? initial.sessions[0]?.name ?? "");
  const [problem, setProblem] = useState<Problem | null>(null);
  const [sessionModal, setSessionModal] = useState<SessionRow | "new" | null>(null);
  const [semesterModal, setSemesterModal] = useState<SemesterRow | number | null>(null);

  // switch which session's semesters are shown (a read; nothing is written)
  async function pick(session: string) {
    setLooking(session);
    setProblem(null);
    const r = await fetch(`/api/bff/api/v1/pg/calendar?session=${encodeURIComponent(session)}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (r.ok && j) setData(j as CalData);
    else setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText });
  }

  async function send(url: string, method: string, body?: unknown): Promise<boolean> {
    setProblem(null);
    const r = await fetch(url, { method, headers: { "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined });
    const j = await r.json().catch(() => null);
    if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return false; }
    if (j && typeof j === "object" && "sessions" in j) { const cd = j as CalData; setData(cd); if (cd.looking) setLooking(cd.looking); }
    return true;
  }

  const current = data.sessions.find((s) => s.state === "CURRENT") ?? null;
  const openSem = data.semesters.find((s) => s.state === "OPEN") ?? null;
  const lookingRow = data.sessions.find((s) => s.name === looking) ?? null;

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Note kind="info" title="The Postgraduate School's own calendar">
        These sessions and semesters are the School&rsquo;s own, kept apart from the undergraduate calendar. The one you mark <b>Current</b> is the session new applications open under and the School&rsquo;s desks default to.
      </Note>

      <Tiles items={[
        ["Current session", current ? current.name : "None set", current ? "var(--green-ink)" : "var(--chrome)", current ? `${current.semesters} semesters` : "mark one current"],
        ["Current semester", openSem ? SEM_NAME[openSem.number] : "None open", openSem ? "var(--green-ink)" : "var(--chrome)", looking],
        ["Sessions on record", String(data.sessions.length), null, "PG calendar"],
      ]} cls="grid--3" />

      <Panel title="Sessions" right={<Btn kind="primary" onClick={() => setSessionModal("new")}>Setup new session</Btn>}>
        <PBody>
          <div className="tablewrap">
            <table className="tbl tbl--data">
              <thead>
                <tr>
                  <th>Session</th><th>Opens</th>
                  <th>Closes</th><th>Semesters</th>
                  <th>State</th><th />
                </tr>
              </thead>
              <tbody>
                {data.sessions.map((s) => (
                  <tr key={s.name} className={s.name === looking ? "is-on" : ""} style={{ background: s.name === looking ? "var(--sunk)" : undefined }}>
                    <td><button type="button" className="lnk b600" style={{ background: "none", border: "none", cursor: "pointer", color: "inherit", padding: 0 }} onClick={() => void pick(s.name)}>{s.name}</button></td>
                    <td className="tnum">{day(s.starts_on)}</td>
                    <td className="tnum">{day(s.ends_on)}</td>
                    <td>{s.semesters}{s.semesters === 3 ? " (Summer)" : ""}</td>
                    <td><span className="b600" style={{ color: STATE_PILL[s.state] ?? "inherit" }}>{s.state[0] + s.state.slice(1).toLowerCase()}</span></td>
                    <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>
                      <Btn kind="ghost" onClick={() => setSessionModal(s)}>Edit</Btn>{" "}
                      {s.state !== "CURRENT" ? <Btn kind="go" onClick={() => { const [a, b] = parts(s.name); void send(`/api/bff/api/v1/pg/calendar/sessions/${a}/${b}/make-current`, "POST"); }}>Make current</Btn> : null}
                    </td>
                  </tr>
                ))}
                {data.sessions.length === 0 ? <tr><td colSpan={6} className="ink-chrome">No sessions yet. Set one up to start the PG calendar.</td></tr> : null}
              </tbody>
            </table>
          </div>
        </PBody>
      </Panel>

      <Panel title={`Semesters — ${looking || "select a session"}`} right={lookingRow ? <span className="sub2">{lookingRow.semesters} semester{lookingRow.semesters === 1 ? "" : "s"} this session</span> : null}>
        <PBody>
          {!lookingRow ? <Note kind="info" title="Select a session">Click a session above to set its semester windows.</Note> : (
            <div style={{ display: "grid", gap: 2 }}>
              {Array.from({ length: lookingRow.semesters }, (_, i) => i + 1).map((n) => {
                const row = data.semesters.find((s) => s.number === n) ?? null;
                return (
                  <div key={n} className="row" style={{ gap: "var(--s-3)", padding: "var(--s-2) 0", borderBottom: "1px solid var(--line-2)" }}>
                    <div style={{ flex: "1 1 260px", minWidth: 0 }}>
                      <div className="b600">{SEM_NAME[n]} {row ? <span className="b600 t-sm" style={{ color: SEM_STATE[row.state] ?? "inherit" }}>· {row.state.replace(/_/g, " ").toLowerCase()}</span> : <span className="sub2" style={{ fontWeight: 400 }}>· not set</span>}</div>
                      <div className="sub2">{row ? <>Registration {day(row.registration_opens)} – {day(row.registration_closes)} · Exams {day(row.exams_from)} – {day(row.exams_to)}</> : "No windows set yet"}</div>
                    </div>
                    <Btn kind="primary" onClick={() => setSemesterModal(row ?? n)}>{row ? "Edit windows" : "Set windows"}</Btn>
                  </div>
                );
              })}
            </div>
          )}
        </PBody>
      </Panel>

      {sessionModal ? (
        <SessionForm
          row={sessionModal === "new" ? null : sessionModal}
          onClose={() => setSessionModal(null)}
          onSaved={(name) => { setSessionModal(null); void pick(name); }}
          send={send}
        />
      ) : null}

      {semesterModal !== null && lookingRow ? (
        <SemesterForm
          session={lookingRow.name}
          row={typeof semesterModal === "number" ? null : semesterModal}
          number={typeof semesterModal === "number" ? semesterModal : semesterModal.number}
          onClose={() => setSemesterModal(null)}
          onSaved={() => setSemesterModal(null)}
          send={send}
        />
      ) : null}
    </>
  );
}

function SessionForm({ row, onClose, onSaved, send }: { row: SessionRow | null; onClose: () => void; onSaved: (name: string) => void; send: (u: string, m: string, b?: unknown) => Promise<boolean> }) {
  const [d, setD] = useState<Draft>({
    name: row?.name ?? "", startsOn: row?.starts_on?.slice(0, 10) ?? "", endsOn: row?.ends_on?.slice(0, 10) ?? "",
    semesters: String(row?.semesters ?? 2), state: row?.state ?? "PLANNED", note: row?.note ?? "",
  });
  const [busy, setBusy] = useState(false);
  const set = (k: string, v: string) => setD((p) => ({ ...p, [k]: v }));

  async function save() {
    if (!/^[0-9]{4}\/[0-9]{4}$/.test(d.name)) { alert("The session name reads like 2026/2027."); return; }
    const [a, b] = parts(d.name);
    setBusy(true);
    const ok = await send(`/api/bff/api/v1/pg/calendar/sessions/${a}/${b}`, "PUT", {
      startsOn: d.startsOn || null, endsOn: d.endsOn || null, semesters: Number(d.semesters), state: d.state, note: d.note || null,
    });
    setBusy(false);
    if (ok) onSaved(d.name);
  }

  return (
    <Modal title={row ? `Edit ${row.name}` : "Setup new session"} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Save session"}</Btn></>}>
      <div className="rf">
        <Field id="rf_name" label="Session" hint="Two academic years, as 2026/2027.">
          <input id="rf_name" className="ctl tnum" value={d.name} readOnly={!!row} placeholder="2026/2027" onChange={(e) => set("name", e.target.value)} />
        </Field>
        <Field id="rf_semesters" label="Semesters" hint="Two, or three when the School runs a Summer semester.">
          <select id="rf_semesters" className="ctl" value={d.semesters} onChange={(e) => set("semesters", e.target.value)}>
            <option value="2">2</option><option value="3">3 (Summer semester)</option>
          </select>
        </Field>
        <Field id="rf_startsOn" label="Opens"><input id="rf_startsOn" type="date" className="ctl" value={d.startsOn} onChange={(e) => set("startsOn", e.target.value)} /></Field>
        <Field id="rf_endsOn" label="Closes"><input id="rf_endsOn" type="date" className="ctl" value={d.endsOn} onChange={(e) => set("endsOn", e.target.value)} /></Field>
        <Field id="rf_state" label="State" hint="Only one session is Current at a time; marking this one Current closes the other.">
          <select id="rf_state" className="ctl" value={d.state} onChange={(e) => set("state", e.target.value)}>
            <option value="PLANNED">Planned</option><option value="CURRENT">Current</option><option value="CLOSED">Closed</option>
          </select>
        </Field>
        <Field id="rf_note" label="Note" full hint="Optional — a Senate minute or a remark for the record."><input id="rf_note" className="ctl" value={d.note} onChange={(e) => set("note", e.target.value)} /></Field>
      </div>
    </Modal>
  );
}

function SemesterForm({ session, row, number, onClose, onSaved, send }: { session: string; row: SemesterRow | null; number: number; onClose: () => void; onSaved: () => void; send: (u: string, m: string, b?: unknown) => Promise<boolean> }) {
  const [d, setD] = useState<Draft>({
    registrationOpens: row?.registration_opens?.slice(0, 10) ?? "", registrationCloses: row?.registration_closes?.slice(0, 10) ?? "",
    lecturesFrom: row?.lectures_from?.slice(0, 10) ?? "", lecturesTo: row?.lectures_to?.slice(0, 10) ?? "",
    examsFrom: row?.exams_from?.slice(0, 10) ?? "", examsTo: row?.exams_to?.slice(0, 10) ?? "",
    resultsDue: row?.results_due?.slice(0, 10) ?? "", state: row?.state ?? "NOT_YET_OPEN",
  });
  const [busy, setBusy] = useState(false);
  const set = (k: string, v: string) => setD((p) => ({ ...p, [k]: v }));

  async function save() {
    const [a, b] = parts(session);
    setBusy(true);
    const ok = await send(`/api/bff/api/v1/pg/calendar/sessions/${a}/${b}/semesters/${number}`, "PUT", {
      registrationOpens: d.registrationOpens || null, registrationCloses: d.registrationCloses || null,
      lecturesFrom: d.lecturesFrom || null, lecturesTo: d.lecturesTo || null,
      examsFrom: d.examsFrom || null, examsTo: d.examsTo || null, resultsDue: d.resultsDue || null, state: d.state,
    });
    setBusy(false);
    if (ok) onSaved();
  }

  const dayField = (k: string, label: string) => (
    <Field key={k} id={`rf_${k}`} label={label}><input id={`rf_${k}`} type="date" className="ctl" value={d[k]} onChange={(e) => set(k, e.target.value)} /></Field>
  );

  return (
    <Modal title={`${SEM_NAME[number]} — ${session}`} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Save windows"}</Btn></>}>
      <div className="rf">
        {dayField("registrationOpens", "Registration opens")}
        {dayField("registrationCloses", "Registration closes")}
        {dayField("lecturesFrom", "Lectures from")}
        {dayField("lecturesTo", "Lectures to")}
        {dayField("examsFrom", "Exams from")}
        {dayField("examsTo", "Exams to")}
        {dayField("resultsDue", "Results due")}
        <Field id="rf_state" label="State" hint="Open marks this as the current semester.">
          <select id="rf_state" className="ctl" value={d.state} onChange={(e) => set("state", e.target.value)}>
            <option value="NOT_YET_OPEN">Not yet open</option><option value="OPEN">Open</option><option value="CLOSED">Closed</option>
          </select>
        </Field>
      </div>
    </Modal>
  );
}
