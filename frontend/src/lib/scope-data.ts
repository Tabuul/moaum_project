import "server-only";
import { cookies } from "next/headers";
import { api } from "./api";
import { readScope, SCOPE_COOKIE, type Scope } from "./scope";
import type { Ceiling, ScopeStructure } from "@/components/proto/ScopeBar";

/**
 * What every scoped page needs before it can draw the bar: the scope asked for, the structure,
 * the sessions, and the ceiling the office is bound to. The API scopes /ref/structure to the
 * office — a Head of Department gets back only their own faculty and department — so when the
 * structure carries a single faculty (and a single department under it) the office is bound to
 * it: the scope is fixed there and the bar locks those selectors, leaving only programme, level
 * and course to choose. For any office that sees the whole University this does nothing.
 */
export async function loadScope(params: Record<string, string | string[] | undefined>): Promise<{
  scope: Scope;
  structure: ScopeStructure;
  sessions: string[];
  ceiling: Ceiling;
}> {
  let cookie: string | null = null;
  try {
    cookie = (await cookies()).get(SCOPE_COOKIE)?.value ?? null;
  } catch {
    cookie = null;
  }
  const scope = readScope(params, cookie);
  const [structure, sessions] = await Promise.all([
    api<ScopeStructure>("/api/v1/ref/structure"),
    api<{ name: string }[]>("/api/v1/ref/sessions"),
  ]);
  const struct: ScopeStructure = structure.ok ? structure.data : { faculties: [] };

  const ceiling: Ceiling = {};
  if (struct.faculties.length === 1) {
    const fac = struct.faculties[0];
    ceiling.fac = fac.code;
    scope.fac = fac.code;
    if (fac.departments.length === 1) {
      ceiling.dept = fac.departments[0].code;
      scope.dept = fac.departments[0].code;
      ceiling.why = "Your department bounds this scope.";
      // a lecturer whose courses serve one programme, or a one-programme department: the programme is fixed too
      const progs = fac.departments[0].programmes.filter((p) => !p.archived);
      if (progs.length === 1) {
        ceiling.prog = progs[0].code;
        scope.prog = progs[0].code;
        ceiling.why = "Your programme bounds this scope.";
      }
    } else {
      ceiling.why = "Your faculty bounds this scope.";
    }
  }

  return {
    scope,
    structure: struct,
    sessions: sessions.ok ? sessions.data.map((s) => s.name) : [scope.session],
    ceiling,
  };
}

/** the scope as the API wants it */
export function scopeParams(s: Scope, extra: Record<string, string | undefined> = {}): string {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries({ fac: s.fac, dept: s.dept, prog: s.prog, level: s.level, course: s.course, session: s.session, sem: s.sem, ...extra })) {
    if (v) q.set(k, v);
  }
  return q.toString();
}
