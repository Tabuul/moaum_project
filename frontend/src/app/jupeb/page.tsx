import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebDashboard } from "./JupebOffice";

export const dynamic = "force-dynamic";

/** /jupeb — the JUPEB Office's dashboard (V339) */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="jupeb/dashboard" me={me.ok ? me.data : null}>
      <JupebDashboard />
    </Shell>
  );
}
