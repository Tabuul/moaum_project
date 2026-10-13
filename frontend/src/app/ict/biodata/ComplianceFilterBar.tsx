"use client";

/** V423 — the filter bar of Biodata compliance: faculty, department, programme, level, session of entry and gender,
 *  each change carried in the address; a selector the office's scope fixes (a Dean's faculty, a Head's department) is
 *  disabled and says so — the API holds the bound whatever the address says. */
import { usePathname, useSearchParams } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { Field } from "@/components/proto/blocks";
import type { Ceiling, ScopeStructure } from "@/components/proto/ScopeBar";

export interface ComplianceFilters { fac: string; dept: string; prog: string; level: string; session: string; sex: string }

export function ComplianceFilterBar({ filters, structure, sessions, ceiling, children }: {
  filters: ComplianceFilters; structure: ScopeStructure; sessions: string[]; ceiling: Ceiling; children?: React.ReactNode;
}) {
  const queryNav = useQueryNav();
  const pathname = usePathname();
  const params = useSearchParams();
  const f = filters;

  function go(patch: Partial<ComplianceFilters> & Record<string, string>) {
    const p = new URLSearchParams(params.toString());
    for (const [k, v] of Object.entries(patch)) { if (v) p.set(k, v); else p.delete(k); }
    if ("fac" in patch) { p.delete("dept"); p.delete("prog"); }
    if ("dept" in patch) p.delete("prog");
    p.delete("page");
    queryNav(`${pathname}?${p.toString()}`);
  }

  const faculties = structure.faculties;
  const depts = faculties.filter((x) => !f.fac || x.code === f.fac).flatMap((x) => x.departments);
  const progs = depts.filter((d) => !f.dept || d.code === f.dept).flatMap((d) => d.programmes).filter((p) => !p.archived);
  return (
    <div className="scope">
      <div className="scope__f"><Field id="bc-fac" label="Faculty">
        <select id="bc-fac" className="ctl" value={f.fac} disabled={!!ceiling.fac} title={ceiling.fac ? ceiling.why : undefined} onChange={(e) => go({ fac: e.target.value })}>
          <option value="">All faculties</option>{faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
        </select>
      </Field></div>
      <div className="scope__f"><Field id="bc-dept" label="Department">
        <select id="bc-dept" className="ctl" value={f.dept} disabled={!!ceiling.dept} title={ceiling.dept ? ceiling.why : undefined} onChange={(e) => go({ dept: e.target.value })}>
          <option value="">All departments</option>{depts.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
        </select>
      </Field></div>
      <div className="scope__f"><Field id="bc-prog" label="Programme">
        <select id="bc-prog" className="ctl" value={f.prog} disabled={!!ceiling.prog} onChange={(e) => go({ prog: e.target.value })}>
          <option value="">All programmes</option>{progs.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
        </select>
      </Field></div>
      <div className="scope__f"><Field id="bc-level" label="Level">
        <select id="bc-level" className="ctl" value={f.level} onChange={(e) => go({ level: e.target.value })}>
          <option value="">All levels</option>{["100", "200", "300", "400", "500", "600", "700", "800"].map((l) => <option key={l} value={l}>{l} Level</option>)}
        </select>
      </Field></div>
      <div className="scope__f"><Field id="bc-session" label="Session of entry">
        <select id="bc-session" className="ctl" value={f.session} onChange={(e) => go({ session: e.target.value })}>
          <option value="">All sessions</option>{sessions.map((x) => <option key={x} value={x}>{x}</option>)}
        </select>
      </Field></div>
      <div className="scope__f"><Field id="bc-sex" label="Gender">
        <select id="bc-sex" className="ctl" value={f.sex} onChange={(e) => go({ sex: e.target.value })}>
          <option value="">All</option><option value="F">Female</option><option value="M">Male</option>
        </select>
      </Field></div>
      {children}
    </div>
  );
}

/** the filters as an address's query, for links between the overview and the list */
export function filterQuery(f: ComplianceFilters, more: Record<string, string> = {}): string {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries({ ...f, ...more })) if (v) q.set(k, v);
  return q.toString();
}
