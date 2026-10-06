import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebFees } from "./JupebFees";

export const dynamic = "force-dynamic";

/** /finance/jupeb-fees — the Bursary's JUPEB fees (V339): the Bursar sets them; the JUPEB Office and the auditors read them */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="f/jupebfees" me={me.ok ? me.data : null}>
      <JupebFees canWrite={office === "bursar" || office === "super"} />
    </Shell>
  );
}
