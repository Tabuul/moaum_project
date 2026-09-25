import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { ApplicationRow, Window } from "@/lib/hostel";
import { hostelSession } from "../page";
import { Applications } from "./Applications";

export const dynamic = "force-dynamic";

export interface AppFilters { state: string; review: string; fac: string; dept: string; prog: string; level: string; hall: string; q: string; page: string }
export interface AppList { session: string; total: number; page: number; size: number; rows: ApplicationRow[]; options: { faculty_code: string; faculty: string; dept_code: string; department: string; programme_code: string; programme: string }[]; setting: Window | null }

/** t/hostel › applications — every application of the session: reviewed, approved, waitlisted, rejected, seated by hand */
export default async function HostelApplicationsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const g = (k: string) => (typeof p[k] === "string" ? (p[k] as string).slice(0, 80) : "");
  const { session } = await hostelSession(p);
  const filters: AppFilters = { state: g("state"), review: g("review"), fac: g("fac"), dept: g("dept"), prog: g("prog"), level: g("level"), hall: g("hall"), q: g("q"), page: g("page") };
  const qs = new URLSearchParams(); for (const [k, v] of Object.entries(filters)) if (v) qs.set(k, v);
  qs.set("size", "500");
  const [me, view] = await Promise.all([api<Me>("/api/v1/iam/me"), api<AppList>(`/api/v1/hostel/sessions/${session}/applications?${qs}`)]);
  return (
    <Shell route="t/hostel" me={me.ok ? me.data : null}>
      {view.ok ? <Applications list={view.data} filters={filters} session={session} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
