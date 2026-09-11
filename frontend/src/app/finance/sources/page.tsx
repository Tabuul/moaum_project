import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { FundingSource } from "@/lib/wallet";
import { Sources } from "./Sources";

export const dynamic = "force-dynamic";

/** t/fundsources — settings: the sources of income a wallet is funded from, kept in the database. */
export default async function FundingSourcesPage() {
  const [me, list] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ sources: FundingSource[] }>("/api/v1/funding/sources"),
  ]);
  return (
    <Shell route="t/fundsources" me={me.ok ? me.data : null}>
      {list.ok ? <Sources sources={list.data.sources} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
