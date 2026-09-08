/**
 * The scope every list in the estate is a list within (proto/part21.html):
 * faculty, department, programme, level, course, session and semester. It is
 * carried in the URL so a link says what it is a list of, and remembered in
 * a cookie so it holds as an officer moves between screens.
 */
export interface Scope {
  fac: string;
  dept: string;
  prog: string;
  level: string;
  course: string;
  session: string;
  sem: string;
}

export const SCOPE_COOKIE = "moaum_scope";
export const SCOPE_KEYS: (keyof Scope)[] = ["fac", "dept", "prog", "level", "course", "session", "sem"];
export const DEFAULT_SESSION = "2026/2027";

export const EMPTY_SCOPE: Scope = { fac: "", dept: "", prog: "", level: "", course: "", session: DEFAULT_SESSION, sem: "" };

type Params = Record<string, string | string[] | undefined>;

/** the scope a page was asked for: the URL wins, the cookie fills in, the default session last */
export function readScope(params: Params, cookie: string | null | undefined): Scope {
  let remembered: Partial<Scope> = {};
  if (cookie) {
    try {
      const parsed = JSON.parse(decodeURIComponent(cookie)) as Partial<Scope>;
      if (parsed && typeof parsed === "object") remembered = parsed;
    } catch {
      remembered = {};
    }
  }
  const out: Scope = { ...EMPTY_SCOPE };
  const inUrl = SCOPE_KEYS.some((k) => typeof params[k] === "string");
  for (const k of SCOPE_KEYS) {
    const v = params[k];
    if (typeof v === "string") out[k] = v;
    else if (!inUrl && typeof remembered[k] === "string") out[k] = remembered[k] as string;
  }
  if (!/^\d{4}\/\d{4}$/.test(out.session)) out.session = DEFAULT_SESSION;
  if (out.level && !/^(100|200|300|400|500|600)$/.test(out.level)) out.level = "";
  if (out.sem && !/^[123]$/.test(out.sem)) out.sem = "";
  return out;
}

/** the scope as query-string parameters for an API call or a link */
export function scopeQuery(s: Partial<Scope>): string {
  const q = new URLSearchParams();
  for (const k of SCOPE_KEYS) {
    const v = s[k];
    if (v) q.set(k, v);
  }
  return q.toString();
}
