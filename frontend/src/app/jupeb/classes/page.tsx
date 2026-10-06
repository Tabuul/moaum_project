import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebClasses } from "../JupebOffice";

export const dynamic = "force-dynamic";

/** /jupeb/classes — the JUPEB classes of a session (V339) */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canWrite = office === "jupeb" || office === "super";
  return (
    <Shell route="jupeb/classes" me={me.ok ? me.data : null}>
      <JupebClasses canWrite={canWrite} />
    </Shell>
  );
}
