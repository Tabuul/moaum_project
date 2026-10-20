import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { LegacyWalletFigures, LegacyWalletRow } from "@/lib/legacy-wallet";
import { LegacyWallet } from "./LegacyWallet";

export const dynamic = "force-dynamic";

/** t/legacywallet — the old portal's e-wallet reconciled (V583): what each student topped up and paid from the old wallet, the balance
 *  left, verified by one Bursary officer and posted to the wallet by another; the report; the batches */
export default async function LegacyWalletPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const qs = new URLSearchParams();
  for (const k of ["status", "q", "fac", "dept"]) if (s(k)) qs.set(k, s(k));
  const [me, figures, rows, structure] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<LegacyWalletFigures>("/api/v1/finance/legacy-wallet/figures"),
    api<LegacyWalletRow[]>(`/api/v1/finance/legacy-wallet/rows?${qs.toString()}`),
    api<{ faculty_code: string; faculty: string; dept_code: string; department: string }[]>("/api/v1/finance/fee-report/structure"),
  ]);
  const filters: Record<string, string> = {};
  for (const k of ["status", "q", "fac", "dept"]) if (s(k)) filters[k] = s(k);
  return (
    <Shell route="t/legacywallet" me={me.ok ? me.data : null}>
      {figures.ok ? (
        <LegacyWallet figures={figures.data} rows={rows.ok ? rows.data : []} rowsProblem={rows.ok ? null : rows.problem} structure={structure.ok ? structure.data : []}
          filters={filters} actingOffice={me.ok ? me.data.activeOffice ?? null : null} generatedBy={me.ok ? me.data.name ?? null : null} />
      ) : <ProblemNotice problem={figures.problem} />}
    </Shell>
  );
}
