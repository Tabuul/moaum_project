import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { RosterPage } from "@/lib/gst-eps-permit";
import { GstPermits } from "@/app/gst/GstPermits";

export const dynamic = "force-dynamic";

/** t/epspermits — the EPS office's GST & EPS examination permits (V492): its students for a session and semester, each with their permit */
export default async function EPSPermitsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const one = (k: string) => (typeof p[k] === "string" && p[k] ? (p[k] as string) : undefined);
  const filters = { status: one("status"), course: one("course"), q: one("q") };
  const qs = new URLSearchParams();
  for (const k of ["session", "semester", "status", "course", "q", "page"]) { const v = one(k); if (v) qs.set(k, v); }
  qs.set("size", "50");
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<RosterPage>(`/api/v1/gst/EPS/permits?${qs.toString()}`)]);
  return (
    <Shell route="t/epspermits" me={me.ok ? me.data : null}>
      {data.ok ? <GstPermits data={data.data} base="/eps" filters={filters} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
