"use client";

/** The faculty, department, programme and level a Summer list is narrowed to — one control for the verification queue, the students
 *  and the reports. A Head of Department or a Dean is shown only their own unit (the API scopes what it offers, and refuses a value
 *  outside the office's bound); an office that sees the whole University chooses. */
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import type { ScopeStructure } from "@/components/proto/ScopeBar";
import { STUDENT_LEVELS } from "@/lib/levels";

export interface OrgOption { code: string; name: string; faculty?: string; dept?: string }
export interface OrgOptions { faculties: OrgOption[]; departments: OrgOption[]; programmes: OrgOption[] }

/** the options the University's structure offers the office (the API scopes it to the office's own unit) */
export function orgFromStructure(s: ScopeStructure | null | undefined): OrgOptions {
  const out: OrgOptions = { faculties: [], departments: [], programmes: [] };
  for (const f of s?.faculties ?? []) {
    out.faculties.push({ code: f.code, name: f.name });
    for (const d of f.departments ?? []) {
      out.departments.push({ code: d.code, name: d.name, faculty: f.code });
      for (const p of d.programmes ?? []) if (!p.archived) out.programmes.push({ code: p.code, name: p.name, faculty: f.code, dept: d.code });
    }
  }
  return out;
}

/** the options a response carries (the queue's facets), none of them knowing its parent */
export function orgFromFacets(f: { faculties: { code: string; name: string }[]; departments: { code: string; name: string }[]; programmes: { code: string; name: string }[] }): OrgOptions {
  return { faculties: f.faculties, departments: f.departments, programmes: f.programmes };
}

export function OrgFilters({ idp, filters, onChange, org, levels }: {
  idp: string; filters: Record<string, string>; onChange: (patch: Record<string, string>) => void; org: OrgOptions; levels?: number[];
}) {
  const depts = org.departments.filter((d) => !filters.faculty || !d.faculty || d.faculty === filters.faculty);
  const progs = org.programmes.filter((p) => (!filters.dept || !p.dept || p.dept === filters.dept) && (!filters.faculty || !p.faculty || p.faculty === filters.faculty));
  const levelList = levels && levels.length ? levels.map(String) : [...STUDENT_LEVELS].filter((l) => Number(l) <= 600);
  return (
    <>
      {org.faculties.length > 1 ? (
        <Field id={`${idp}-fac`} label="Faculty" style={{ flex: "1 1 170px" }}>
          <SearchSelect id={`${idp}-fac`} value={filters.faculty ?? ""} onChange={(v) => onChange({ faculty: v, dept: "", programme: "" })} allLabel="Any faculty" options={org.faculties.map((f) => ({ value: f.code, label: f.name }))} />
        </Field>
      ) : null}
      {depts.length > 1 ? (
        <Field id={`${idp}-dept`} label="Department" style={{ flex: "1 1 190px" }}>
          <SearchSelect id={`${idp}-dept`} value={filters.dept ?? ""} onChange={(v) => onChange({ dept: v, programme: "" })} allLabel="Any department" options={depts.map((d) => ({ value: d.code, label: d.name }))} />
        </Field>
      ) : null}
      {progs.length > 1 ? (
        <Field id={`${idp}-prog`} label="Programme" style={{ flex: "1 1 220px" }}>
          <SearchSelect id={`${idp}-prog`} value={filters.programme ?? ""} onChange={(v) => onChange({ programme: v })} allLabel="Any programme" options={progs.map((p) => ({ value: p.code, label: p.name }))} />
        </Field>
      ) : null}
      <Field id={`${idp}-level`} label="Level" style={{ flex: "0 1 100px" }}>
        <select id={`${idp}-level`} className="ctl" value={filters.level ?? ""} onChange={(e) => onChange({ level: e.target.value })}>
          <option value="">Any</option>
          {levelList.map((l) => <option key={l} value={l}>{l}</option>)}
        </select>
      </Field>
    </>
  );
}
