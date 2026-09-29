import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { DisciplineData, SwapRow } from "@/lib/hostel";
import { hostelSession } from "../page";
import { Discipline } from "./Discipline";

export const dynamic = "force-dynamic";

/** t/hostel-discipline — hostel incidents, the sanctions decided on them and their appeals; the room swaps two students have agreed (V291) */
export default async function DisciplinePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const g = (k: string) => (typeof p[k] === "string" ? (p[k] as string).slice(0, 40) : "");
  const { session, sessions } = await hostelSession(p);
  const state = g("state"), tab = g("tab") === "swaps" ? "swaps" : "incidents";
  const [me, data, swaps] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<DisciplineData>(`/api/v1/hostel/sessions/${session}/discipline${state ? `?state=${encodeURIComponent(state)}` : ""}`),
    api<SwapRow[]>(`/api/v1/hostel/sessions/${session}/swaps`),
  ]);
  return (
    <Shell route="t/hostel-discipline" me={me.ok ? me.data : null}>
      {data.ok ? <Discipline data={data.data} swaps={swaps.ok ? swaps.data : []} session={session} sessions={sessions} state={state} tab={tab} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
