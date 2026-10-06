import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebSettings } from "../JupebOffice";

export const dynamic = "force-dynamic";

/** /jupeb/settings — numbering, screening and the documents asked for (V339) */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canWrite = office === "jupeb" || office === "super";
  return (
    <Shell route="jupeb/settings" me={me.ok ? me.data : null}>
      <JupebSettings canWrite={canWrite} />
    </Shell>
  );
}
