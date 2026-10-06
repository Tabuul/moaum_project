import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebResults } from "../JupebOffice";

export const dynamic = "force-dynamic";

/** /jupeb/results — the Board's results, imported, reviewed and published (V339) */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canWrite = office === "jupeb" || office === "super";
  return (
    <Shell route="jupeb/results" me={me.ok ? me.data : null}>
      <JupebResults canWrite={canWrite} />
    </Shell>
  );
}
