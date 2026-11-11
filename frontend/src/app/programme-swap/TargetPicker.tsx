"use client";

/** the placement to move to: faculty, then its departments, then the department's programmes on the register, then the programme's
 *  own levels — searchable, cascading, nothing typed in (V578). For a postgraduate student (V719) the postgraduate programmes alone,
 *  each named with its degree type, and the programme chosen read out in full: faculty, department, degree type, code, levels. */
import { useMemo } from "react";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { KvGrid } from "@/components/proto/ui";
import { postgraduateStructure, programmeFacts, programmeLabel, type Faculty } from "@/lib/programme-swap";

export interface Target { faculty: string; dept: string; programme: string; level: string }

export function TargetPicker({ faculties, value, onChange, idPrefix = "tp", postgraduate = false, facts = postgraduate }:
  { faculties: Faculty[]; value: Target; onChange: (t: Target) => void; idPrefix?: string; postgraduate?: boolean; facts?: boolean }) {
  const list = useMemo(() => (postgraduate ? postgraduateStructure(faculties) : faculties), [faculties, postgraduate]);
  const faculty = list.find((f) => f.code === value.faculty);
  const dept = faculty?.departments.find((d) => d.code === value.dept);
  const programme = dept?.programmes.find((p) => p.code === value.programme);
  const chosen = programme ? programmeFacts(list, programme.code) : null;
  return (
    <>
      <div className="grid grid--2">
        <Field id={`${idPrefix}-fac`} label="Faculty">
          <SearchSelect id={`${idPrefix}-fac`} value={value.faculty} onChange={(v) => onChange({ faculty: v, dept: "", programme: "", level: "" })} placeholder="Search a faculty…"
            options={list.map((f) => ({ value: f.code, label: f.name }))} />
        </Field>
        <Field id={`${idPrefix}-dept`} label="Department">
          <SearchSelect id={`${idPrefix}-dept`} value={value.dept} disabled={!faculty} onChange={(v) => onChange({ ...value, dept: v, programme: "", level: "" })} placeholder="Search a department…"
            options={(faculty?.departments ?? []).map((d) => ({ value: d.code, label: d.name }))} />
        </Field>
        <Field id={`${idPrefix}-prog`} label={postgraduate ? "Postgraduate programme" : "Programme"} hint={postgraduate ? "The approved postgraduate programmes of the department, with the degree type" : undefined}>
          <SearchSelect id={`${idPrefix}-prog`} value={value.programme} disabled={!dept} onChange={(v) => onChange({ ...value, programme: v, level: "" })} placeholder="Search a programme…"
            options={(dept?.programmes ?? []).map((p) => ({ value: p.code, label: programmeLabel(p) }))} />
        </Field>
        <Field id={`${idPrefix}-level`} label={postgraduate ? "Level (the stage)" : "Level"} hint={programme ? `${programme.name} has the levels ${programme.levels.join(", ")}` : "Choose the programme first"}>
          <select id={`${idPrefix}-level`} className="ctl" disabled={!programme} value={value.level} onChange={(e) => onChange({ ...value, level: e.target.value })}>
            <option value="">Choose…</option>
            {(programme?.levels ?? []).map((l) => <option key={l} value={l}>{l} Level</option>)}
          </select>
        </Field>
      </div>
      {facts && chosen ? (
        <div className="mt-2" data-testid={`${idPrefix}-facts`}>
          <div className="eyebrow">The programme chosen</div>
          <KvGrid pairs={[["Faculty", chosen.faculty], ["Department", chosen.department], ["Degree type", chosen.award ?? (chosen.category === "POST GRADUATE" ? "—" : "Undergraduate")], ["Programme code", <span className="tnum" key="c">{chosen.code}</span>]]} />
        </div>
      ) : null}
    </>
  );
}
