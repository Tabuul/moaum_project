import { redirect } from "next/navigation";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PlatformDashboard } from "./dashboards/Platform";
import { AcademicDashboard } from "./dashboards/Academic";
import { RegistrarDashboard } from "./dashboards/Registrar";
import { OfficeDashboard } from "./dashboards/Office";
import { LecturerDashboard } from "./dashboards/Lecturer";
import type { MySheet } from "@/lib/results";

export const dynamic = "force-dynamic";

/* the platform's own dashboard is the platform's offices' */
const PLATFORM = new Set(["ict", "admin", "super"]);
/* Academic Affairs: the offices that work the register */
const ACADEMIC = new Set(["academic", "dregistrar", "records", "dvc", "vc"]);

export default async function DashboardPage() {
  const [me, sessions] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ name: string; state: string }[]>("/api/v1/ref/sessions")]);
  const office = me.ok ? me.data.activeOffice : null;
  /* an applicant's home is their application, not an office's dashboard */
  if (office === "applicant") redirect("/applicant");
  if (office === "student") redirect("/student");
  const session = sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name ?? "2026/2027" : "2026/2027";
  /* the lecturer's dashboard is the sheets they owe, read from the rolls (V013) */
  const mine = office === "lecturer" ? await api<MySheet[]>(`/api/v1/results/mine?session=${encodeURIComponent(session)}`) : null;
  /* the requests students put to this office (V036), for the offices that answer them */
  const asks = office && ["registrar", "dregistrar", "bursar", "library", "services", "academic", "hod", "housing"].includes(office) ? await api<{ state: string }[]>("/api/v1/support/requests") : null;
  const requestsOpen = asks && asks.ok ? asks.data.filter((r) => r.state === "OPEN" || r.state === "WITH_OFFICE").length : null;
  return (
    <Shell route="r/academic" me={me.ok ? me.data : null}>
      {!me.ok ? <ProblemNotice problem={me.problem} /> : null}
      {office && PLATFORM.has(office) ? (
        <PlatformDashboard me={me.ok ? me.data : null} />
      ) : office && ACADEMIC.has(office) ? (
        <AcademicDashboard session={session} />
      ) : office === "registrar" ? (
        <RegistrarDashboard session={session} />
      ) : office === "lecturer" ? (
        <LecturerDashboard me={me.ok ? me.data : null} sheets={mine && mine.ok ? mine.data : []} session={session} />
      ) : (
        <OfficeDashboard me={me.ok ? me.data : null} requestsOpen={requestsOpen} />
      )}
    </Shell>
  );
}
