import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Desk, Figures } from "@/lib/historical-fees";
import { HistoricalFees, type Filters } from "./HistoricalFees";

export const dynamic = "force-dynamic";

const TABS = ["overview", "students", "approvals", "waivers", "evidence", "recon", "cohort", "reports", "quality", "setting"] as const;

/** t/historicalfees — V654: historical school fees and the graduate's financial clearance (the Bursary, the Students Account Officer;
 *  Audit and the Registry read). ?tab= opens a tab; ?financial= / ?filter= / ?q= a list of graduates. */
export default async function HistoricalFeesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const tab = (TABS as readonly string[]).includes(s("tab")) ? (s("tab") as (typeof TABS)[number]) : s("financial") || s("filter") || s("q") ? "students" : "overview";
  const filters: Filters = { q: s("q"), faculty: s("faculty"), programme: s("programme"), admission: s("admission"), graduation: s("graduation"), financial: s("financial"), filter: s("filter"),
    scope: s("scope"), type: s("type"), level: s("level") };   // V720
  const [me, desk, figures, faculties, programmes] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Desk>("/api/v1/finance/historical/permissions"),
    api<Figures>("/api/v1/finance/historical/figures"),
    api<{ faculties: { code: string; name: string }[] }>("/api/v1/ref/structure"),
    api<{ code: string; name: string; faculty_code: string }[]>("/api/v1/finance/programmes"),
  ]);
  return (
    <Shell route="t/historicalfees" me={me.ok ? me.data : null}>
      {desk.ok
        ? <HistoricalFees desk={desk.data} figures={figures.ok ? figures.data : null} initialTab={tab} initialFilters={filters}
            faculties={faculties.ok ? faculties.data.faculties : []} programmes={programmes.ok ? programmes.data : []} />
        : <ProblemNotice problem={desk.problem} />}
    </Shell>
  );
}
