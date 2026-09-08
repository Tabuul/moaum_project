"use client";

/**
 * The three record forms of the calendar, as proto/part36.html defines them
 * (REC.session, REC.semester, REC.level) and proto/part35.html lays them out:
 * the lead note, the grid of fields with their hints, the rule note under
 * them, and a footer that offers to end the record rather than delete it.
 * Every date is an ISO date control, because the API takes ISO dates.
 */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import type { LevelLimitRow, SemesterRow, SessionRow } from "@/lib/calendar";
import { semesterName } from "@/lib/calendar";
import { Note } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export type Draft = Record<string, string>;

const LOCKED = <span className="bio__t bio__t--locked">not editable</span>;

function Txt({ k, draft, set, num, ph, ro }: { k: string; draft: Draft; set: (k: string, v: string) => void; num?: boolean; ph?: string; ro?: boolean }) {
  return (
    <input
      id={"rf_" + k}
      className={`ctl${num ? " tnum" : ""}${ro ? " ctl--ro" : ""}`}
      value={draft[k] ?? ""}
      placeholder={ph}
      readOnly={ro}
      autoComplete="off"
      onChange={(e) => set(k, e.target.value)}
    />
  );
}

function Day({ k, draft, set }: { k: string; draft: Draft; set: (k: string, v: string) => void }) {
  return <input id={"rf_" + k} type="date" className="ctl" value={draft[k] ?? ""} onChange={(e) => set(k, e.target.value)} />;
}

function Sel({ k, draft, set, options }: { k: string; draft: Draft; set: (k: string, v: string) => void; options: string[] }) {
  return (
    <select id={"rf_" + k} className="ctl" value={draft[k] ?? ""} onChange={(e) => set(k, e.target.value)}>
      {options.map((o) => (
        <option key={o} value={o}>
          {o}
        </option>
      ))}
    </select>
  );
}

function Foot({ onClose, onEnd, endLabel, save, busy }: { onClose: () => void; onEnd?: () => void; endLabel?: string; save: () => void; busy: boolean }) {
  return (
    <>
      <button className="btn btn--ghost btn--sm" onClick={onClose}>
        Cancel
      </button>
      {onEnd ? (
        <button className="btn btn--ghost btn--sm" onClick={onEnd}>
          {endLabel}
        </button>
      ) : null}
      <span style={{ flexGrow: 1 }} />
      <button className="btn btn--primary btn--sm" onClick={save} disabled={busy}>
        {busy ? "Saving…" : "Save the change"}
      </button>
    </>
  );
}

const STATES = ["Planned", "Current", "Closed"];
const SEMS = ["2", "3 (with a long vacation semester)"];

export function SessionModal({
  row,
  onClose,
  onSave,
  onEnd,
  busy,
  problem,
}: {
  row: SessionRow | null;
  onClose: () => void;
  onSave: (draft: Draft) => void;
  onEnd: (reason: string) => void;
  busy: boolean;
  problem: Problem | null;
}) {
  const isNew = row === null;
  const [draft, setDraft] = useState<Draft>({
    n: row?.name ?? "",
    opens: row?.startsOn ?? "",
    closes: row?.endsOn ?? "",
    sems: row && row.semesters === 3 ? SEMS[1] : SEMS[0],
    minute: row?.senateMinute ?? "",
    state: row?.state === "CURRENT" ? "Current" : row?.state === "CLOSED" ? "Closed" : "Planned",
  });
  const [ending, setEnding] = useState(false);
  const [reason, setReason] = useState("");
  const set = (k: string, v: string) => setDraft((d) => ({ ...d, [k]: v }));

  if (ending) {
    return (
      <Modal
        title={`End ${row?.name ?? "the session"}`}
        sub="It stays on the record"
        onClose={onClose}
        wide
        foot={
          <>
            <button className="btn btn--ghost btn--sm" onClick={() => setEnding(false)}>
              &larr; Back to the form
            </button>
            <span style={{ flexGrow: 1 }} />
            <button className="btn btn--urgent btn--sm" onClick={() => onEnd(reason)} disabled={busy}>
              {busy ? "Closing…" : "End it"}
            </button>
          </>
        }
      >
        {problem ? <ProblemNotice problem={problem} /> : null}
        <Note kind="bad" title="Ending is not deleting, and the difference is the whole point">
          Ending a session closes it: it stops being the session anything new is recorded against, and every registration,
          score sheet and result already bound to it stays exactly where it is and keeps resolving. No application role in
          this system holds a DELETE grant on any table, this screen included.
        </Note>
        <div className="grid grid--2 rfgrid">
          <Field id="rf_endwhy" label="Reason, as it will read in the log" full>
            <input
              id="rf_endwhy"
              className="ctl"
              value={reason}
              autoComplete="off"
              placeholder="Closed at the end of the academic year"
              onChange={(e) => setReason(e.target.value)}
            />
          </Field>
        </div>
      </Modal>
    );
  }

  return (
    <Modal
      title={isNew ? "New session" : `Edit ${row.name}`}
      sub={
        isNew
          ? ""
          : `${row.state === "CURRENT" ? "Current" : row.state === "CLOSED" ? "Closed" : "Planned"} · ${row.senateMinute ?? "no minute recorded"}`
      }
      onClose={onClose}
      wide
      foot={<Foot onClose={onClose} onEnd={isNew ? undefined : () => setEnding(true)} endLabel="End this session" save={() => onSave(draft)} busy={busy} />}
    >
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Note kind="info" title="The session is the spine everything else hangs on">
        Registration windows, fee schedules, grading schemes, examination sessions, result sets and the publication embargo
        are all bounded by a session and a semester.
      </Note>
      <div className="grid grid--3 rfgrid">
        <Field id="rf_n" label={isNew ? "Session" : <>Session {LOCKED}</>}>
          <Txt k="n" draft={draft} set={set} num ph="2027/2028" ro={!isNew} />
        </Field>
        <Field id="rf_opens" label="Opens">
          <Day k="opens" draft={draft} set={set} />
        </Field>
        <Field id="rf_closes" label="Closes">
          <Day k="closes" draft={draft} set={set} />
        </Field>
        <Field id="rf_sems" label="Semesters">
          <Sel k="sems" draft={draft} set={set} options={SEMS} />
        </Field>
        <Field
          id="rf_scheme"
          label={<>Grading scheme {LOCKED}</>}
          hint="The scheme in force is effective-dated policy, recorded with its instrument where policy is versioned — not chosen on this form."
        >
          <input id="rf_scheme" className="ctl ctl--ro" value="The scheme in force on the day" readOnly />
        </Field>
        <Field id="rf_minute" label="Senate minute">
          <Txt k="minute" draft={draft} set={set} num ph="SEN/2027/…" />
        </Field>
        <Field id="rf_state" label="State" full hint="A session stays Planned until its Senate minute is recorded against it.">
          <Sel k="state" draft={draft} set={set} options={STATES} />
        </Field>
      </div>
      <Note kind="bad" title="A session cannot open without its Senate minute, and two may never overlap">
        The academic calendar is approved by Senate. Opening one early would let students register into a session the
        University has not resolved to run. The no-overlap rule is an exclusion constraint in the database, not a check on
        this form &mdash; a script cannot get around it either.
      </Note>
    </Modal>
  );
}

export function semesterDraft(row: SemesterRow | null, next: number): Draft {
  return {
    n: semesterName(row?.number ?? next),
    state: row?.state === "OPEN" ? "Open" : row?.state === "CLOSED" ? "Closed" : "Not yet open",
    lectFrom: row?.lecturesFrom ?? "",
    lectTo: row?.lecturesTo ?? "",
    ropen: row?.registrationOpens ?? "",
    rclose: row?.registrationCloses ?? "",
    late: row?.lateRegistrationCloses ?? "",
    examsFrom: row?.examsFrom ?? "",
    examsTo: row?.examsTo ?? "",
    due: row?.resultsDue ?? "",
    query: row?.queryWindow ?? "",
  };
}

export function levelDraft(row: LevelLimitRow | null): Draft {
  return {
    n: row ? String(row.level) : "100",
    who: row?.appliesTo ?? "All programmes",
    min: row ? String(row.minUnits) : "",
    max: row ? String(row.maxUnits) : "",
    carry: row ? (row.carryoverCounts ? "Yes" : "No") : "Yes",
    instrument: row?.instrument ?? "",
  };
}

export { Txt as RecText, Day as RecDay, Sel as RecSelect, Foot as RecFoot };
