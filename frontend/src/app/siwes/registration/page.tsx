import { api, type ApiResult } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { ScopeStructure } from "@/components/proto/ScopeBar";
import { apiStatus, readSiwesFilters, siwesQuery, unpaidEntries, unpaidTotal, type SiwesConfig, type SiwesStats, type SiwesStudentPage, type SiwesUnpaidEntry } from "@/lib/siwes";
import { SiwesDesk, type SiwesTab } from "./SiwesDesk";

export const dynamic = "force-dynamic";

/** V777: every row of the session's SIWES courses held without the SIWES fee — the API pages the list (500 a page, as the desk's students
 *  are read for an export); the pages that follow the first are read until the total it states is reached (at most 40 pages) */
async function unpaidRows(session: string): Promise<ApiResult<SiwesUnpaidEntry[]>> {
  const SIZE = 500;
  const read = (page: number) => api<unknown>(`/api/v1/siwes/admin/unpaid-entries?${siwesQuery({}, { session, page, size: SIZE })}`);
  const first = await read(0);
  if (!first.ok) return first;
  let rows = unpaidEntries(first.data);
  const total = unpaidTotal(first.data) ?? rows.length;
  for (let page = 1; rows.length < total && page < 40; page++) {
    const next = await read(page);
    if (!next.ok) return next;
    const more = unpaidEntries(next.data);
    if (!more.length) break;
    rows = rows.concat(more);
  }
  return { ok: true, data: rows, status: first.status };
}

/** t/siwesreg — V752: SIWES registration at 300 Level, Second Semester (the University's master prompt of 12 November 2026). The
 *  Academic Office (and the Registrar, the Deputy Registrar, the Super Administrator) set a session's SIWES — the registration window,
 *  the training period and its length, the programmes taking it and each programme's SIWES course (a course of the catalogue, never a
 *  new one); everyone who reads it — a Head of Department or SIWES Coordinator their department, a Dean or Faculty Officer their faculty,
 *  the Bursary the University — sees the students (eligible, paid, registered), each one's detail, the figures, and exports them. The API
 *  bounds every list to the acting office; a tab the API refuses is not shown.
 *  V777 (every SIWES course carries the SIWES fee): the session's SIWES courses held on a registration with no SIWES fee paid are a tab of
 *  their own (GET /siwes/admin/unpaid-entries) — those who registered one before the rule and are asked to pay it now. */
export default async function SiwesRegistrationPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const filters = readSiwesFilters(sp);
  const page = typeof sp.page === "string" && /^\d{1,5}$/.test(sp.page) ? Number(sp.page) : 0;
  const tab = (["config", "students", "stats", "unpaid"] as const).find((t) => t === sp.tab) ?? null;
  // the session the address names, else the API's own (the University's current session): read first, then the lists of that session
  const [me, config, structure] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SiwesConfig>(`/api/v1/siwes/admin/config${filters.session ? `?session=${encodeURIComponent(filters.session)}` : ""}`),
    api<ScopeStructure>("/api/v1/ref/structure"),
  ]);
  const session = filters.session ?? (config.ok ? config.data.session : undefined);
  const unit = { session, faculty: filters.faculty, department: filters.department, programme: filters.programme };
  const [students, stats, unpaid] = await Promise.all([
    // the eligible students unless the address asks for another list (ALL: no status, every student of the programmes taking SIWES)
    api<SiwesStudentPage>(`/api/v1/siwes/admin/students?${siwesQuery({ ...unit, status: apiStatus(filters.status), q: filters.q }, { page, size: 50 })}`),
    api<SiwesStats>(`/api/v1/siwes/admin/stats?${siwesQuery(unit)}`),
    // V777: the courses held without the SIWES fee — the session only, every page of it (the API bounds the list to the office)
    session ? unpaidRows(session) : Promise.resolve(null),
  ]);
  const shell = me.ok ? me.data : null;
  if (!config.ok && !students.ok && !stats.ok && !(unpaid?.ok)) {
    return <Shell route="t/siwesreg" me={shell}><ProblemNotice problem={config.problem} /></Shell>;
  }
  return (
    // V777: the desk covers every SIWES course, whatever the level and semester: the bound cohort's own "300 Level, Second Semester" is on its tabs
    <Shell route="t/siwesreg" me={shell} sub={session ?? undefined}>
      <SiwesDesk
        key={`${session ?? ""}|${tab ?? ""}`}
        session={session ?? null}
        filters={{ ...filters, session }}
        tab={tab as SiwesTab | null}
        config={config.ok ? config.data : null}
        configProblem={config.ok ? null : config.problem}
        students={students.ok ? students.data : null}
        studentsProblem={students.ok ? null : students.problem}
        stats={stats.ok ? stats.data : null}
        statsProblem={stats.ok ? null : stats.problem}
        unpaid={unpaid?.ok ? unpaid.data : null}
        unpaidProblem={unpaid && !unpaid.ok ? unpaid.problem : null}
        structure={structure.ok ? structure.data : { faculties: [] }}
        actingOffice={shell?.activeOffice ?? null}
      />
    </Shell>
  );
}
