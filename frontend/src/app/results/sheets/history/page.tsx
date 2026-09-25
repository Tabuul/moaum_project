import { api } from "@/lib/api";
import type { MySheet } from "@/lib/results";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { SheetHistory } from "./SheetHistory";

export const dynamic = "force-dynamic";

/** t/sheethistory — every score sheet the lecturer has ever carried, across sessions, read from the register */
export default async function SheetHistoryPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, sheets, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<MySheet[]>("/api/v1/results/mine"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  const current = sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name ?? null : null;
  return (
    <Shell route="t/sheethistory" me={me.ok ? me.data : null}>
      {sheets.ok ? <SheetHistory sheets={sheets.data} current={current} initial={{ session: typeof p.session === "string" ? p.session : "", sem: typeof p.sem === "string" ? p.sem : "", standing: typeof p.standing === "string" ? p.standing : "" }} /> : <ProblemNotice problem={sheets.problem} />}
    </Shell>
  );
}
