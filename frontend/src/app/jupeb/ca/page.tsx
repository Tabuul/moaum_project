import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebCa } from "./JupebCa";

export const dynamic = "force-dynamic";

/** /jupeb/ca — the JUPEB continuous assessment (V355); the API decides who reads and who writes */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canWrite = office === "jupeb" || office === "super";
  return (
    <Shell route="jupeb/ca" me={me.ok ? me.data : null}>
      <JupebCa canWrite={canWrite} />
    </Shell>
  );
}
