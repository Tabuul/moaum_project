import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { HallList, type HallListData } from "./HallList";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

/** the hall list of one screening batch: every seat in order, with the photograph on file, for the invigilator at the door */
export default async function HallListPage({ params, searchParams }: { params: Promise<{ batch: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { batch } = await params;
  const q = await searchParams;
  const requested = typeof q.session === "string" ? q.session : "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : "2026/2027";
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<HallListData>(`/api/v1/admissions/sessions/${session}/screening-batches/${batch}/hall-list`)]);
  return (
    <Shell route="t/admissions" me={me.ok ? me.data : null}>
      {list.ok ? <HallList data={list.data} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
