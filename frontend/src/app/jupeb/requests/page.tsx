import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebRequests } from "../JupebOffice";

export const dynamic = "force-dynamic";

/** /jupeb/requests — the change requests made after submission (V343) */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canWrite = office === "jupeb" || office === "super";
  return (
    <Shell route="jupeb/requests" me={me.ok ? me.data : null}>
      <JupebRequests canWrite={canWrite} />
    </Shell>
  );
}
