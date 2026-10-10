import { api } from "@/lib/api";
import { ApplicationClosed } from "@/components/ApplicationClosed";
import type { PutmePublic } from "@/lib/putme-cbt";
import { ResultCheck } from "./ResultCheck";

export const dynamic = "force-dynamic";

/** /post-utme/results — Post-UTME result checking (V385), open while the Director of ICT's window is open; the closure message otherwise */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const asked = typeof params.session === "string" && /^\d{4}\/\d{4}$/.test(params.session) ? params.session : null;
  const state = await api<PutmePublic>(`/api/v1/putme/cbt/public${asked ? `?session=${encodeURIComponent(asked)}` : ""}`);
  if (!state.ok || !state.data.results.open) {
    const w = state.ok ? state.data : null;
    return <ApplicationClosed title="Post-UTME result checking" eyebrow="Admissions" window={w ? { type: "POST_UTME_RESULT_CHECKING", label: "Post-UTME result checking", session: w.session, status: w.results.state, open: false, opensAt: w.results.opensAt, closesAt: w.results.closesAt, message: w.results.message, applicationPath: "/post-utme/results", applicationUrl: "" } : null} />;
  }
  return <ResultCheck state={state.data} />;
}
