import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebIdCards } from "./JupebIdCards";

export const dynamic = "force-dynamic";

/** /jupeb/idcards — the JUPEB students' identity cards, issued, printed and replaced by the JUPEB Office (V349) */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canWrite = office === "jupeb" || office === "super";
  return (
    <Shell route="jupeb/idcards" me={me.ok ? me.data : null}>
      <JupebIdCards canWrite={canWrite} />
    </Shell>
  );
}
