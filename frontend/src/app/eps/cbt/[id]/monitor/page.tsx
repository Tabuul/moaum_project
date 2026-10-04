import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { LiveMonitor } from "@/components/cbt/LiveMonitor";

export const dynamic = "force-dynamic";

/** t/epscbt — the live monitor of one EPS CBT examination (V322) */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const me = await api<Me>("/api/v1/iam/me");
  const acting = me.ok ? me.data.activeOffice ?? "" : "";
  return (
    <Shell route="t/epscbt" me={me.ok ? me.data : null} sub="Live monitor">
      <LiveMonitor examId={id} base="/eps" canManage={["eps", "super"].includes(acting)} />
    </Shell>
  );
}
