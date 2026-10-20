"use client";

/** the placement to move to: faculty, then its departments, then the department's programmes on the register, then the programme's
 *  own levels — searchable, cascading, nothing typed in (V578) */
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import type { Faculty } from "@/lib/programme-swap";

export interface Target { faculty: string; dept: string; programme: string; level: string }

export function TargetPicker({ faculties, value, onChange, idPrefix = "tp" }: { faculties: Faculty[]; value: Target; onChange: (t: Target) => void; idPrefix?: string }) {
  const faculty = faculties.find((f) => f.code === value.faculty);
  const dept = faculty?.departments.find((d) => d.code === value.dept);
  const programme = dept?.programmes.find((p) => p.code === value.programme);
  return (
    <div className="grid grid--2">
      <Field id={`${idPrefix}-fac`} label="Faculty">
        <SearchSelect id={`${idPrefix}-fac`} value={value.faculty} onChange={(v) => onChange({ faculty: v, dept: "", programme: "", level: "" })} placeholder="Search a faculty…"
          options={faculties.map((f) => ({ value: f.code, label: f.name }))} />
      </Field>
      <Field id={`${idPrefix}-dept`} label="Department">
        <SearchSelect id={`${idPrefix}-dept`} value={value.dept} disabled={!faculty} onChange={(v) => onChange({ ...value, dept: v, programme: "", level: "" })} placeholder="Search a department…"
          options={(faculty?.departments ?? []).map((d) => ({ value: d.code, label: d.name }))} />
      </Field>
      <Field id={`${idPrefix}-prog`} label="Programme">
        <SearchSelect id={`${idPrefix}-prog`} value={value.programme} disabled={!dept} onChange={(v) => onChange({ ...value, programme: v, level: "" })} placeholder="Search a programme…"
          options={(dept?.programmes ?? []).map((p) => ({ value: p.code, label: p.name }))} />
      </Field>
      <Field id={`${idPrefix}-level`} label="Level" hint={programme ? `${programme.name} has the levels ${programme.levels.join(", ")}` : "Choose the programme first"}>
        <select id={`${idPrefix}-level`} className="ctl" disabled={!programme} value={value.level} onChange={(e) => onChange({ ...value, level: e.target.value })}>
          <option value="">Choose…</option>
          {(programme?.levels ?? []).map((l) => <option key={l} value={l}>{l} Level</option>)}
        </select>
      </Field>
    </div>
  );
}
