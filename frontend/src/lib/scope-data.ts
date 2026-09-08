import "server-only";
import { cookies } from "next/headers";
import { api } from "./api";
import { readScope, SCOPE_COOKIE, type Scope } from "./scope";
import type { ScopeStructure } from "@/components/proto/ScopeBar";

/** what every scoped page needs before it can draw the bar: the scope asked for, the structure and the sessions */
export async function loadScope(params: Record<string, string | string[] | undefined>): Promise<{
  scope: Scope;
  structure: ScopeStructure;
  sessions: string[];
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
  return {
    scope,
    structure: structure.ok ? structure.data : { faculties: [] },
    sessions: sessions.ok ? sessions.data.map((s) => s.name) : [scope.session],
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
