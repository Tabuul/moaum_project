import Link from "next/link";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Note, Panel, PBody } from "@/components/proto/ui";

export const dynamic = "force-dynamic";

/**
 * The College of Health Sciences dashboard — the landing the login gate routes the College officers to
 * (Provost, College Secretary, Finance Controller), who sign in through the University's one login.
 *
 * This is the seam handed to the College module developer: the route, the Shell, the menu (menus.ts →
 * provost / collegesecretary / financecontroller, home "r/college") and the office wiring are in place.
 * Build the dashboard functionalities here. The backend already offers /api/v1/provost/dashboard
 * (College-scoped Dean aggregate) and /api/v1/staff/college/{code}; ref.college + ref.faculty.college_code
 * model the College tier.
 */
export default async function CollegeDashboardPage() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const role = office === "provost" ? "Provost"
    : office === "collegesecretary" ? "College Secretary"
    : office === "financecontroller" ? "Finance Controller" : "College officer";
  return (
    <Shell route="r/college" me={me.ok ? me.data : null}>
      <Note kind="info" title={`Welcome${me.ok ? `, ${me.data.name}` : ""} — ${role}, College of Health Sciences`}>
        You are signed in to the University portal. The College of Health Sciences dashboard is being built here.
      </Note>

      <Panel title="College of Health Sciences">
        <PBody>
          <div className="sub2" style={{ marginBottom: 10 }}>
            This is the College module&rsquo;s dashboard area. The academic structure (Basic Medical Sciences,
            Basic Clinical Sciences and Clinical Sciences) sits under the College tier, and its officers — the
            Provost, the College Secretary and the Finance Controller — work here.
          </div>
          <Link href="/college" className="btn btn--primary btn--sm">Open the College overview</Link>
        </PBody>
      </Panel>
    </Shell>
  );
}
