import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Note } from "@/components/proto/ui";
import { JupebOldPortalImport } from "../JupebOffice";

export const dynamic = "force-dynamic";

/** /jupeb/import — the JUPEB students already registered on the old portal, uploaded with their logins (V345) */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canWrite = office === "jupeb" || office === "super";
  return (
    <Shell route="jupeb/import" me={me.ok ? me.data : null}>
      {canWrite ? <JupebOldPortalImport /> : <Note kind="info" title="The JUPEB Office uploads the old portal's students">Sign in as the JUPEB Office to upload them.</Note>}
    </Shell>
  );
}
