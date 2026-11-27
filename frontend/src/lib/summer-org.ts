/** The Summer desk's faculty, department and programme options. A plain module (no "use client"): the server page builds the options from the University's
 *  structure, and the client components (OrgFilters and the lists) read them. They must not live in a client module: a server component cannot call a
 *  function a client module exports ("Attempted to call orgFromStructure() from the server but orgFromStructure is on the client"). */
import type { ScopeStructure } from "@/components/proto/ScopeBar";

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
