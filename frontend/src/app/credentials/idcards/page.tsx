import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { IdCards, type CardDesk } from "./IdCards";

export const dynamic = "force-dynamic";

/** t/idcards — the Library's card desk: printed by the Library, handed over by Security */
export default async function IdCardsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const q = typeof params.q === "string" ? params.q : "";
  const [me, desk] = await Promise.all([api<Me>("/api/v1/iam/me"), api<CardDesk>(`/api/v1/credentials/identity-cards${q ? `?q=${encodeURIComponent(q)}` : ""}`)]);
  return (
    <Shell route="t/idcards" me={me.ok ? me.data : null}>
      {desk.ok ? <IdCards desk={desk.data} q={q} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={desk.problem} />}
    </Shell>
  );
}
