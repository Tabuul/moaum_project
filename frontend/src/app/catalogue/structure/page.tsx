import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Structure, type ProgrammeOption, type StructureData } from "./Structure";

export const dynamic = "force-dynamic";

/** t/structure — what a programme offers at each level and semester, and the binding of a course into it */
export default async function StructurePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, programmes] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ProgrammeOption[]>("/api/v1/catalogue/programmes"),
  ]);
  const options = programmes.ok ? programmes.data.filter((x) => !x.archived) : [];
  const prog = typeof p.prog === "string" && p.prog ? p.prog : options[0]?.code ?? "";
  const data = prog ? await api<StructureData>(`/api/v1/catalogue/structure?prog=${encodeURIComponent(prog)}`) : null;
  const office = me.ok ? me.data.activeOffice : null;
  const may = office === "hod" || office === "dean" || office === "academic" || office === "dregistrar" || office === "registrar" || office === "admin" || office === "super";
  return (
    <Shell route="t/structure" me={me.ok ? me.data : null}>
      {!programmes.ok ? <ProblemNotice problem={programmes.problem} /> : (
        <Structure programmes={options} prog={prog} data={data && data.ok ? data.data : null} problem={data && !data.ok ? data.problem : null} may={may} />
      )}
    </Shell>
  );
}
