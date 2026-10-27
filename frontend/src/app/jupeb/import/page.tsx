import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Note } from "@/components/proto/ui";
import { JupebOldPortalImport } from "../JupebOffice";
import { OldPortalMove } from "./OldPortalMove";

export const dynamic = "force-dynamic";

/** /jupeb/import — the JUPEB students already registered on the old portal, uploaded with their logins (V345); an upload filed under the
 *  wrong session moved to the session its students belong to (V659) */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  // V680: the Director of ICT and the Database Operators too (an operator over the whole University; the server holds the scope)
  const canWrite = office === "jupeb" || office === "ict" || office === "dbops" || office === "super";
  return (
    <Shell route="jupeb/import" me={me.ok ? me.data : null}>
      {canWrite ? <><JupebOldPortalImport office={office} /><OldPortalMove /></> : <Note kind="info" title="The JUPEB Office, the Director of ICT or a Database Operator uploads the old portal's students">Act in one of those offices to upload them.</Note>}
    </Shell>
  );
}
