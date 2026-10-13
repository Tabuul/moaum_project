import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

/** t/biodatastudents — V434: Biodata compliance is one screen, at /biodata/compliance; this address sends there with the filters it carried. */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const one = (k: string) => { const v = q[k]; return (Array.isArray(v) ? v[0] : v) ?? ""; };
  const p = new URLSearchParams();
  for (const [from, to] of [["status", "status"], ["missing", "missing"], ["fac", "faculty"], ["dept", "department"], ["prog", "programme"], ["level", "level"],
    ["session", "session"], ["sex", "sex"], ["q", "q"]] as [string, string][]) {
    const v = one(from);
    if (v && !(from === "status" && v === "COMPLETE")) p.set(to, v);
  }
  redirect(`/biodata/compliance${p.toString() ? `?${p}` : ""}`);
}
