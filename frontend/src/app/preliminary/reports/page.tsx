import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { PrelimDeskRoute } from "@/lib/preliminary";
import type { PrelimSummary } from "../PrelimDesk";
import { PrelimReports } from "./PrelimReports";

export const dynamic = "force-dynamic";

/** prelim/reports — a preliminary or proficiency programme's reports (V446; V701 every route, chosen with ?route=), within the reader's scope */
export default async function PrelimReportsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const route = typeof sp.route === "string" ? sp.route : "";
  const [me, summary, routes] = await Promise.all([api<Me>("/api/v1/iam/me"),
    api<PrelimSummary>(`/api/v1/admissions/preliminary/summary${route ? `?route=${encodeURIComponent(route)}` : ""}`),
    api<PrelimDeskRoute[]>("/api/v1/admissions/preliminary/routes")]);
  const office = (me.ok ? me.data.activeOffice : null) ?? "";
  return (
    <Shell route="prelim/reports" me={me.ok ? me.data : null}>
      {!summary.ok ? <ProblemNotice problem={summary.problem} /> : (
        <PrelimReports key={summary.data.route} session={summary.data.session} sessions={summary.data.sessions} generatedBy={me.ok ? me.data.name ?? null : null}
          route={summary.data.route} routes={routes.ok ? routes.data : []}
          payments={["prelim", "prelimtech", "academic", "registrar", "dregistrar", "super", "admin"].includes(office)} />
      )}
    </Shell>
  );
}
