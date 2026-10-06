import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebExamNumbers } from "../JupebOffice";

export const dynamic = "force-dynamic";

/** /jupeb/examination — the official JUPEB examination numbers, imported by application number (V339) */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canWrite = office === "jupeb" || office === "super";
  return (
    <Shell route="jupeb/examination" me={me.ok ? me.data : null}>
      <JupebExamNumbers canWrite={canWrite} />
    </Shell>
  );
}
