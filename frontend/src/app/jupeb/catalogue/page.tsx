import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebCatalogue } from "../JupebOffice";

export const dynamic = "force-dynamic";

/** /jupeb/catalogue — the JUPEB subjects and the approved combinations (V339) */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canWrite = office === "jupeb" || office === "super";
  return (
    <Shell route="jupeb/catalogue" me={me.ok ? me.data : null}>
      <JupebCatalogue canWrite={canWrite} />
    </Shell>
  );
}
