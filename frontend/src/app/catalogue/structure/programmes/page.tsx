import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Directory } from "@/lib/catalogue";
import { Programmes, type ProgrammeFilters, type ProgrammeRow } from "./Programmes";

export const dynamic = "force-dynamic";

/** t/structureprogrammes — V471: every programme with its structure counted, each opened on its Programme Structure */
export default async function StructureProgrammesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const filters: ProgrammeFilters = { category: s("category"), fac: s("fac"), dept: s("dept"), q: s("q"), empty: s("empty") };
  const qs = new URLSearchParams();
  for (const [k, v] of Object.entries(filters)) if (v) qs.set(k, v);
  const [me, rows, directory] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ProgrammeRow[]>(`/api/v1/catalogue/structure/programmes?${qs.toString()}`),
    api<Directory>("/api/v1/catalogue/directory"),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  const pgOnly = office === "pgschool" || office === "pgsecretary";
  return (
    <Shell route="t/structureprogrammes" me={me.ok ? me.data : null}>
      {!rows.ok ? <ProblemNotice problem={rows.problem} /> : (
        <Programmes rows={rows.data} directory={directory.ok ? directory.data : null} filters={filters} pgOnly={pgOnly} />
      )}
    </Shell>
  );
}
