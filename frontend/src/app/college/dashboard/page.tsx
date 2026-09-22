import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { DeanDashboard, type DeanHome } from "../../dashboards/Dean";

export const dynamic = "force-dynamic";

/**
 * The College of Health Sciences dashboard — the landing the login gate routes the College officers to
 * (Provost, College Secretary, Finance Controller), who sign in through the University's one login.
 *
 * `/api/v1/provost/dashboard` returns the same shape as the Dean's faculty dashboard, one scope higher
 * (ProvostController mirrors DeanController deliberately), so it renders through the same DeanDashboard
 * component the Dean and Faculty Officer use, labelled for the College. All three College offices share
 * this view — the registration, result-pipeline and at-risk picture across every department in the College.
 */
export default async function CollegeDashboardPage() {
  const [me, sessions] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ name: string; state: string }[]>("/api/v1/ref/sessions")]);
  const office = me.ok ? me.data.activeOffice : null;
  const role = office === "provost" ? "Provost"
    : office === "collegesecretary" ? "College Secretary"
    : office === "financecontroller" ? "Finance Controller" : "College officer";
  const session = sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name ?? "2026/2027" : "2026/2027";
  const home = await api<DeanHome>(`/api/v1/provost/dashboard?session=${encodeURIComponent(session)}`);
  return (
    <Shell route="r/college" me={me.ok ? me.data : null}>
      <DeanDashboard me={me.ok ? me.data : null} home={home.ok ? home.data : null} role={role} scopeNoun="college" desks={[]} />
    </Shell>
  );
}
