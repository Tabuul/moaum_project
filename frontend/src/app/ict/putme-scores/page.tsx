import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PutmeScores } from "@/components/cbt/PutmeScores";
import type { PutmeScoresPage } from "@/lib/putme-cbt";

export const dynamic = "force-dynamic";

/** the Post-UTME session the desk opens on: the one applications are filed under today (the public door says which) */
export async function putmeSession(asked: string | string[] | undefined): Promise<string> {
  if (typeof asked === "string" && /^\d{4}\/\d{4}$/.test(asked)) return asked;
  const pub = await api<{ session: string }>("/api/v1/putme/cbt/public");
  return pub.ok ? pub.data.session : "";
}

/** t/putmescores — the Directorate of ICT's Post-UTME CBT scores (V385): every approved attempt, the official file, sent to the Academic Office */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const session = await putmeSession(q.session);
  const p = new URLSearchParams();
  for (const k of ["exam", "q", "status", "prog", "fac", "page"]) if (typeof q[k] === "string" && q[k]) p.set(k, q[k] as string);
  const [me, page] = await Promise.all([api<Me>("/api/v1/iam/me"), api<PutmeScoresPage>(`/api/v1/admissions/sessions/${session}/putme-scores${p.size ? `?${p.toString()}` : ""}`)]);
  return (
    <Shell route="t/putmescores" me={me.ok ? me.data : null}>
      {page.ok ? <PutmeScores page={page.data} mode="ict" acting={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={page.problem} />}
    </Shell>
  );
}
