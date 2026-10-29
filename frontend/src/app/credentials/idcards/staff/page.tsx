import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { StaffIdCards, type StaffRoster } from "./StaffIdCards";

export const dynamic = "force-dynamic";

/** t/staffidcards — V698: the Security Unit's staff identity cards: every member of staff in service, the card in force, issued and
 *  printed one at a time or all at once (a faculty's, a unit's, the ones a search finds) */
export default async function StaffIdCardsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const one = (k: string) => (typeof p[k] === "string" && (p[k] as string).trim() ? (p[k] as string).trim() : null);
  const filters = { faculty: one("faculty"), unit: one("unit"), q: one("q"), card: one("card") };
  const qs = new URLSearchParams();
  for (const [k, v] of Object.entries(filters)) if (v) qs.set(k, v);
  const [me, roster] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<StaffRoster>(`/api/v1/credentials/identity-cards/staff/roster${qs.size ? `?${qs.toString()}` : ""}`),
  ]);
  return (
    <Shell route="t/staffidcards" me={me.ok ? me.data : null}>
      {roster.ok
        ? <StaffIdCards roster={roster.data} filters={filters} actingOffice={me.ok ? me.data.activeOffice : null} />
        : <ProblemNotice problem={roster.problem} />}
    </Shell>
  );
}
