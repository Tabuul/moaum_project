import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebSearch } from "./JupebSearch";

export const dynamic = "force-dynamic";

/** /helpdesk/jupeb — ICT Support's search of the JUPEB programme's records (V347); what an agent reaches is the API's to decide */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/supportjupeb" me={me.ok ? me.data : null}>
      <JupebSearch />
    </Shell>
  );
}
