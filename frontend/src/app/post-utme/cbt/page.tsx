import { api } from "@/lib/api";
import { ApplicationClosed } from "@/components/ApplicationClosed";
import type { PutmePublic } from "@/lib/putme-cbt";
import { PutmeGate } from "./PutmeGate";

export const dynamic = "force-dynamic";

/** /post-utme/cbt — the Post-UTME CBT door (V385), open to the world while the Director of ICT's window is open; the closure message otherwise */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const asked = typeof params.session === "string" && /^\d{4}\/\d{4}$/.test(params.session) ? params.session : null;
  const state = await api<PutmePublic>(`/api/v1/putme/cbt/public${asked ? `?session=${encodeURIComponent(asked)}` : ""}`);
  if (!state.ok || !state.data.cbt.open) {
    const w = state.ok ? state.data : null;
    return <ApplicationClosed title="Post-UTME CBT examination" eyebrow="Admissions" window={w ? { type: "POST_UTME_CBT", label: "The Post-UTME CBT examination", session: w.session, status: w.cbt.state, open: false, opensAt: w.cbt.opensAt, closesAt: w.cbt.closesAt, message: w.cbt.message, applicationPath: "/post-utme/cbt", applicationUrl: "" } : null} />;
  }
  return <PutmeGate state={state.data} />;
}
