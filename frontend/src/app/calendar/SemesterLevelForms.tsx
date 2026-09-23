"use client";

/**
 * REC.semester and REC.level of proto/part36.html, with the prototype's
 * hints and rule notes. The prototype's single "Lectures" and "Examinations"
 * text fields are two ISO date controls each here, because that is what the
 * database holds and what the registration and examination gates read.
 */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import type { LevelLimitRow, SemesterRow } from "@/lib/calendar";
import { SEMESTER_NAMES } from "@/lib/calendar";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { RecDay, RecFoot, RecSelect, RecText, semesterDraft, levelDraft, type Draft } from "./CalendarForms";

const SEM_STATES = ["Open", "Not yet open", "Closed"];
const LEVELS = ["100", "200", "300", "400", "500", "600"];
const APPLIES = ["All programmes", "MBBS, LL.B and other five-year programmes", "One programme"];
const YESNO = ["Yes", "No"];

export function SemesterModal({
  session,
  row,
  next,
  onClose,
  onSave,
  busy,
  problem,
}: {
  session: string;
  row: SemesterRow | null;
  next: number;
  onClose: () => void;
  onSave: (draft: Draft) => void;
  busy: boolean;
  problem: Problem | null;
}) {
  const [draft, setDraft] = useState<Draft>(semesterDraft(row, next));
  const set = (k: string, v: string) => setDraft((d) => ({ ...d, [k]: v }));

  return (
    <Modal
      title={row ? `Windows for the ${draft.n} semester` : "New semester"}
      sub={`${session} · every date here changes what a student can do today`}
      onClose={onClose}
      wide
      foot={<RecFoot onClose={onClose} save={() => onSave(draft)} busy={busy} />}
    >
      {problem ? <ProblemNotice problem={problem} /> : null}
      <div className="grid grid--2 rfgrid">
        <Field id="rf_n" label="Semester">
          <RecSelect k="n" draft={draft} set={set} options={SEMESTER_NAMES} />
        </Field>
        <Field id="rf_state" label="State">
          <RecSelect k="state" draft={draft} set={set} options={SEM_STATES} />
        </Field>
        <Field id="rf_lectFrom" label="Lectures from">
          <RecDay k="lectFrom" draft={draft} set={set} />
        </Field>
        <Field id="rf_lectTo" label="Lectures to">
          <RecDay k="lectTo" draft={draft} set={set} />
        </Field>
        <Field id="rf_ropen" label="Registration opens" hint="Makes the course form writable for cleared students.">
          <RecDay k="ropen" draft={draft} set={set} />
        </Field>
        <Field
          id="rf_rclose"
          label="Registration closes"
          hint="Freezes the register — and the register is what every score sheet is generated over."
        >
          <RecDay k="rclose" draft={draft} set={set} />
        </Field>
        <Field id="rf_late" label="Late registration closes">
          <RecDay k="late" draft={draft} set={set} />
        </Field>
        <Field id="rf_examsFrom" label="Examinations from" hint="Locks the examination roll.">
          <RecDay k="examsFrom" draft={draft} set={set} />
        </Field>
        <Field id="rf_examsTo" label="Examinations to">
          <RecDay k="examsTo" draft={draft} set={set} />
        </Field>
        <Field id="rf_due" label="Score sheets due" hint="What the escalation clock counts from.">
          <RecDay k="due" draft={draft} set={set} />
        </Field>
        <Field id="rf_query" label="Result query window" full>
          <RecText k="query" draft={draft} set={set} ph="seven days from release" />
        </Field>
      </div>
    </Modal>
  );
}

export function LevelModal({
  row,
  onClose,
  onSave,
  busy,
  problem,
}: {
  row: LevelLimitRow | null;
  onClose: () => void;
  onSave: (draft: Draft) => void;
  busy: boolean;
  problem: Problem | null;
}) {
  const [draft, setDraft] = useState<Draft>(levelDraft(row));
  const set = (k: string, v: string) => setDraft((d) => ({ ...d, [k]: v }));

  return (
    <Modal
      title={row ? `Edit level ${row.level}` : "New level"}
      onClose={onClose}
      wide
      foot={<RecFoot onClose={onClose} save={() => onSave(draft)} busy={busy} />}
    >
      {problem ? <ProblemNotice problem={problem} /> : null}
      <div className="grid grid--2 rfgrid">
        <Field id="rf_n" label="Level">
          <RecSelect k="n" draft={draft} set={set} options={LEVELS} />
        </Field>
        <Field id="rf_who" label="Applies to">
          <RecSelect k="who" draft={draft} set={set} options={APPLIES} />
        </Field>
        <Field id="rf_min" label="Minimum units per semester">
          <RecText k="min" draft={draft} set={set} num />
        </Field>
        <Field id="rf_max" label="Maximum units per semester">
          <RecText k="max" draft={draft} set={set} num />
        </Field>
        <Field
          id="rf_carry"
          label="Carryover counts toward the maximum"
          full
          hint="It does, and it has to: a student repeating three courses has three courses’ worth of examinations to sit."
        >
          <RecSelect k="carry" draft={draft} set={set} options={YESNO} />
        </Field>
        <Field id="rf_instrument" label="Senate minute" full hint="The minute that fixed these limits, as it will read in the log.">
          <RecText k="instrument" draft={draft} set={set} num ph="SEN/2026/…" />
        </Field>
      </div>
    </Modal>
  );
}
