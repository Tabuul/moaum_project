import { redirect } from "next/navigation";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PlatformDashboard } from "./dashboards/Platform";
import { AcademicDashboard } from "./dashboards/Academic";
import { RegistrarDashboard } from "./dashboards/Registrar";
import { OfficeDashboard } from "./dashboards/Office";
import { LecturerDashboard } from "./dashboards/Lecturer";
import { BursarDashboard } from "./dashboards/Bursar";
import { HodDashboard, type HodHome } from "./dashboards/Hod";
import { ClinicDashboard } from "./dashboards/Clinic";
import { LibraryDashboard } from "./dashboards/Library";
import { ExamsDashboard } from "./dashboards/Exams";
import { HrDashboard, type HrHome } from "./dashboards/Hr";
import { DeanDashboard, type DeanHome } from "./dashboards/Dean";
import { SecurityDashboard } from "./dashboards/Security";
import { HousingDashboard } from "./dashboards/Housing";
import { SiwesDashboard, type SiwesOffering } from "./dashboards/Siwes";
import { AuditDashboard, type AuditEntry } from "./dashboards/Audit";
import type { Posture } from "./security/Security";
import type { HostelDeskData } from "@/lib/hostel";
import type { MySheet, SheetListing } from "@/lib/results";
import type { ClinicDesk } from "@/lib/health";
import type { LibraryDeskData } from "@/lib/library";

export const dynamic = "force-dynamic";

/* the platform's own dashboard is the technical desks'; the administrator's home is the
   whole-institution view (r/admin, /admin), so it is not in this set */
const PLATFORM = new Set(["ict", "super"]);
/* Academic Affairs: the offices that work the register (the VC's home is the
   institutional overview, so it redirects there rather than to this dashboard) */
const ACADEMIC = new Set(["academic", "dregistrar", "records", "dvc"]);

export default async function DashboardPage() {
  const [me, sessions] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ name: string; state: string }[]>("/api/v1/ref/sessions")]);
  const office = me.ok ? me.data.activeOffice : null;
  /* an applicant's home is their application, not an office's dashboard */
  if (office === "applicant") redirect("/applicant");
  if (office === "student") redirect("/student");
  /* the administrator's home is the whole institution at one desk (proto part18) */
  if (office === "admin") redirect("/admin");
  /* the Vice-Chancellor's home is the institutional overview (menus.ts home t/overview) */
  if (office === "vc") redirect("/overview");
  const session = sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name ?? "2026/2027" : "2026/2027";
  /* the lecturer's dashboard is the sheets they owe, read from the rolls (V013) */
  const mine = office === "lecturer" ? await api<MySheet[]>(`/api/v1/results/mine?session=${encodeURIComponent(session)}`) : null;
  /* the requests students put to this office (V036), for the offices that answer them */
  const asks = office && ["registrar", "dregistrar", "bursar", "library", "services", "academic", "hod", "housing"].includes(office) ? await api<{ state: string }[]>("/api/v1/support/requests") : null;
  const requestsOpen = asks && asks.ok ? asks.data.filter((r) => r.state === "OPEN" || r.state === "WITH_OFFICE").length : null;
  /* open result queries for the Exams Officer's desk (the HOD gets its own count on the HOD dashboard) */
  const rq = office && ["exams", "facultyexams"].includes(office) ? await api<unknown[]>("/api/v1/results/queries?state=open") : null;
  const openQueries = rq && rq.ok ? rq.data.length : null;
  /* the Head of Department's dashboard, scoped to their own department */
  const hodHome = office === "hod" ? await api<HodHome>(`/api/v1/hod/dashboard?session=${encodeURIComponent(session)}`) : null;
  /* the Support Services office's home is the clinic: its figures and the queue (V032) */
  const clinic = office === "services" ? await api<ClinicDesk>("/api/v1/health/desk") : null;
  /* the Librarian's home is the circulation desk (V033) */
  const library = office === "library" ? await api<LibraryDeskData>("/api/v1/library/desk") : null;
  /* the Exams Officer's home is the result-sheet pipeline in their scope (V013) */
  const examSheets = office && ["exams", "facultyexams"].includes(office) ? await api<SheetListing>(`/api/v1/results/sheets?session=${encodeURIComponent(session)}`) : null;
  /* the Director of HR's home is the establishment and what waits on the directorate (V071-V076) */
  const hr = office === "hrm" ? await api<HrHome>("/api/v1/hr/dashboard") : null;
  /* the Dean's home is their faculty: registration, pipeline and at-risk by department */
  const dean = office === "dean" ? await api<DeanHome>(`/api/v1/dean/dashboard?session=${encodeURIComponent(session)}`) : null;
  /* the Chief Security Officer and Internal Audit read the same posture (V002) */
  const posture = office && ["security", "audit"].includes(office) ? await api<Posture>("/api/v1/governance/security") : null;
  const auditFeed = office === "audit" ? await api<{ entries: AuditEntry[] }>("/api/v1/audit/entries?limit=12") : null;
  /* Housing/Welfare: the accommodation draw (V038) */
  const hostel = office === "housing" ? await api<HostelDeskData>(`/api/v1/hostel/sessions/${encodeURIComponent(session)}`) : null;
  /* the SIWES Coordinator's department offerings this second semester (V156) */
  const siwes = office === "siwes" ? await api<SiwesOffering[]>(`/api/v1/siwes/offerings?session=${encodeURIComponent(session)}&semester=2`) : null;
  /* a live subtitle for the lecturer/HOD header — real name and counts, not a fixed prototype line */
  let sub: string | undefined;
  if (office === "lecturer" && mine && mine.ok) {
    const n = mine.data.length;
    sub = `${me.ok ? me.data.name : "Lecturer"} · ${n} course${n === 1 ? "" : "s"} this session`;
  } else if (office === "hod" && hodHome && hodHome.ok && hodHome.data.resolved) {
    const h = hodHome.data;
    sub = `${h.deptName} · ${h.approvals ?? 0} to approve · ${h.deptStudents ?? 0} students`;
  }
  return (
    <Shell route="r/academic" me={me.ok ? me.data : null} sub={sub}>
      {!me.ok ? <ProblemNotice problem={me.problem} /> : null}
      {office && PLATFORM.has(office) ? (
        <PlatformDashboard me={me.ok ? me.data : null} />
      ) : office && ACADEMIC.has(office) ? (
        <AcademicDashboard session={session} />
      ) : office === "registrar" ? (
        <RegistrarDashboard session={session} />
      ) : office === "bursar" ? (
        <BursarDashboard session={session} />
      ) : office === "lecturer" ? (
        <LecturerDashboard me={me.ok ? me.data : null} sheets={mine && mine.ok ? mine.data : []} session={session} />
      ) : office === "hod" ? (
        <HodDashboard me={me.ok ? me.data : null} home={hodHome && hodHome.ok ? hodHome.data : null} requestsOpen={requestsOpen} />
      ) : office === "services" ? (
        <ClinicDashboard me={me.ok ? me.data : null} desk={clinic && clinic.ok ? clinic.data : null} />
      ) : office === "library" ? (
        <LibraryDashboard me={me.ok ? me.data : null} desk={library && library.ok ? library.data : null} />
      ) : (office === "exams" || office === "facultyexams") ? (
        <ExamsDashboard me={me.ok ? me.data : null} listing={examSheets && examSheets.ok ? examSheets.data : null} openQueries={openQueries} session={session} />
      ) : office === "hrm" ? (
        <HrDashboard me={me.ok ? me.data : null} home={hr && hr.ok ? hr.data : null} />
      ) : office === "dean" ? (
        <DeanDashboard me={me.ok ? me.data : null} home={dean && dean.ok ? dean.data : null} />
      ) : office === "security" ? (
        <SecurityDashboard me={me.ok ? me.data : null} posture={posture && posture.ok ? posture.data : null} />
      ) : office === "audit" ? (
        <AuditDashboard me={me.ok ? me.data : null} posture={posture && posture.ok ? posture.data : null} feed={auditFeed && auditFeed.ok ? auditFeed.data.entries : []} />
      ) : office === "housing" ? (
        <HousingDashboard me={me.ok ? me.data : null} desk={hostel && hostel.ok ? hostel.data : null} />
      ) : office === "siwes" ? (
        <SiwesDashboard me={me.ok ? me.data : null} offerings={siwes && siwes.ok ? siwes.data : []} semester={2} />
      ) : (
        <OfficeDashboard me={me.ok ? me.data : null} requestsOpen={requestsOpen} openQueries={openQueries} />
      )}
    </Shell>
  );
}
