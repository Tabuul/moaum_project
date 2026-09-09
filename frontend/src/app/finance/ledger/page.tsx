import { api } from "@/lib/api";
import type { DayBookRow } from "@/lib/bursary";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Ledger } from "./Ledger";

export const dynamic = "force-dynamic";

/** t/ledger — every confirmation, whoever paid, however it came */
export default async function LedgerPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const from = typeof params.from === "string" ? params.from : "";
  const to = typeof params.to === "string" ? params.to : "";
  const q = new URLSearchParams();
  if (from) q.set("from", from);
  if (to) q.set("to", to);
  const [me, l] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ from: string; to: string; rows: DayBookRow[] }>(`/api/v1/finance/ledger${q.toString() ? `?${q}` : ""}`)]);
  return (
    <Shell route="t/ledger" me={me.ok ? me.data : null}>
      {l.ok ? <Ledger from={l.data.from} to={l.data.to} rows={l.data.rows} /> : <ProblemNotice problem={l.problem} />}
    </Shell>
  );
}
