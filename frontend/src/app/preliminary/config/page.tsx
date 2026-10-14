import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { PrelimConfig } from "./PrelimConfig";

export const dynamic = "force-dynamic";

/** prelim/config — the Preliminary Science programme's settings (V446): the Academic Office's rule, targets and documents, the
 *  Bursary's fees; the server decides who may change what */
export default async function PrelimConfigPage() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = (me.ok ? me.data.activeOffice : null) ?? "";
  return (
    <Shell route="prelim/config" me={me.ok ? me.data : null}>
      <PrelimConfig may={{ configure: ["academic", "super"].includes(office), fees: ["bursar", "super"].includes(office) }} />
    </Shell>
  );
}
