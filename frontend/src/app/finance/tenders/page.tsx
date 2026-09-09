import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Tenders, type Tender, type Bid } from "./Tenders";

export const dynamic = "force-dynamic";

/** t/tenders — tenders: evaluation and award. */
export default async function TendersPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const selected = typeof p.t === "string" ? p.t : "";
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Tender[]>("/api/v1/expenditure/tenders")]);
  const bids = selected ? await api<Bid[]>(`/api/v1/expenditure/tenders/${encodeURIComponent(selected)}`) : null;
  return (
    <Shell route="t/tenders" me={me.ok ? me.data : null}>
      {list.ok ? (
        <Tenders tenders={list.data} selected={selected} bids={bids && bids.ok ? bids.data : []} actingOffice={me.ok ? me.data.activeOffice : null} />
      ) : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
