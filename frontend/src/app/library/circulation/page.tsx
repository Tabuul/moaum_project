import { api } from "@/lib/api";
import type { LibraryDeskData } from "@/lib/library";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Circulation } from "./Circulation";

export const dynamic = "force-dynamic";

/** t/circulation — issue, return, renew; the overdue; the fines; the clearance position */
export default async function CirculationPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const patron = typeof params.patron === "string" ? params.patron : "";
  const q = typeof params.q === "string" ? params.q : "";
  const query = new URLSearchParams();
  if (patron) query.set("patron", patron);
  if (q) query.set("q", q);
  const [me, desk] = await Promise.all([api<Me>("/api/v1/iam/me"), api<LibraryDeskData>(`/api/v1/library/desk${query.toString() ? `?${query}` : ""}`)]);
  return (
    <Shell route="t/circulation" me={me.ok ? me.data : null}>
      {desk.ok ? <Circulation d={desk.data} patron={patron} q={q} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={desk.problem} />}
    </Shell>
  );
}
