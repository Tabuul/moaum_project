import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Checks, type IssuesData } from "./Checks";

export const dynamic = "force-dynamic";

/** t/structurecheck — V471: what is wrong with the programmes' structures, each problem opened where it is put right */
export default async function StructureChecksPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const kind = s("kind");
  const category = s("category");
  const qs = new URLSearchParams();
  if (kind) qs.set("kind", kind);
  if (category) qs.set("category", category);
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<IssuesData>(`/api/v1/catalogue/structure/issues?${qs.toString()}`),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/structurecheck" me={me.ok ? me.data : null}>
      <Checks data={data.ok ? data.data : null} problem={data.ok ? null : data.problem} kind={kind} category={category}
        pgOnly={office === "pgschool" || office === "pgsecretary"} />
    </Shell>
  );
}
