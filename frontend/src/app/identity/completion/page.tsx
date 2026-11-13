import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { STAFF_COUNTS, STUDENT_COUNTS, choicesOf, completionTab, completionTabs, countsOf, pageOf, staffRowOf, studentRowOf } from "@/lib/identity";
import { Completion, type CompletionFilters } from "./Completion";

export const dynamic = "force-dynamic";

/** rows a page of the list (the API holds a page to 200) */
const SIZE = 50;

/** t/identitycompletion — V749: where the identity information stands, for the offices that see to it: the students in study (the
 *  blood group confirmed, a photograph, a matriculation number — what the student identity card waits on) and the staff in service
 *  (the photograph enhanced and accepted, the e-mail verified, the blood group confirmed), counted under the filters and listed by
 *  what is missing, searched, paged and exported. One tab is read at a time; each office is shown only the tabs the API lets it read
 *  (Records and Student Affairs the students alone, the Director of HR the staff alone). */
export default async function IdentityCompletionPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const one = (k: string) => { const v = q[k]; return ((Array.isArray(v) ? v[0] : v) ?? "").trim(); };
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  // the tab asked for when the office reads it, else the first it reads: the Director of HR the staff alone, Records and Student
  // Affairs the students alone, every other reader opening on the students
  const tab = completionTab(one("tab"), office);
  const filters: CompletionFilters = {
    faculty: one("faculty"), department: one("department"), programme: one("programme"), level: one("level"),
    unit: one("unit"), category: one("category"), missing: one("missing").toUpperCase(), q: one("q"), page: Math.max(1, Math.floor(Number(one("page")) || 1)),
  };
  // the counts: the narrowing alone
  const scope = new URLSearchParams();
  const set = (k: string, v: string) => { if (v) scope.set(k, v); };
  set("faculty", filters.faculty);
  if (tab === "students") { set("department", filters.department); set("programme", filters.programme); set("level", filters.level); }
  else { set("unit", filters.unit); set("category", filters.category); }
  // the list: the same narrowing, and what is missing, the search and the page (the API counts its pages from 0)
  const list = new URLSearchParams(scope);
  if (filters.missing) list.set("missing", filters.missing);
  if (filters.q) list.set("q", filters.q);
  list.set("page", String(filters.page - 1));
  list.set("size", String(SIZE));
  const base = `/api/v1/identity/completion/${tab}`;
  const [counts, rows] = await Promise.all([
    api<unknown>(`${base}${scope.size ? `?${scope}` : ""}`),
    api<unknown>(`${base}/list?${list}`),
  ]);
  const raw = counts.ok ? counts.data : null;
  return (
    <Shell route="t/identitycompletion" me={me.ok ? me.data : null}>
      {!me.ok ? <ProblemNotice problem={me.problem} /> : null}
      {/* drawn afresh for each address, so the form shows the filters a count's link or the paging chose, not the last ones typed */}
      <Completion
        key={`${tab}?${list}`}
        tab={tab}
        tabs={completionTabs(office)}
        filters={filters}
        faculties={choicesOf(raw, "faculties")}
        departments={choicesOf(raw, "departments")}
        programmes={choicesOf(raw, "programmes")}
        units={choicesOf(raw, "units")}
        studentCounts={tab === "students" && raw ? countsOf(raw, STUDENT_COUNTS) : null}
        staffCounts={tab === "staff" && raw ? countsOf(raw, STAFF_COUNTS) : null}
        countsProblem={counts.ok ? null : counts.problem}
        students={tab === "students" && rows.ok ? pageOf(rows.data, studentRowOf, { page: filters.page, size: SIZE }) : null}
        staff={tab === "staff" && rows.ok ? pageOf(rows.data, staffRowOf, { page: filters.page, size: SIZE }) : null}
        listProblem={rows.ok ? null : rows.problem}
      />
    </Shell>
  );
}
