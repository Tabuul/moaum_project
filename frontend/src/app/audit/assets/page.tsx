import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AuditAssets, type Asset } from "./AuditAssets";

export const dynamic = "force-dynamic";

/** t/auditassets — the audit directorate's read of the fixed-asset register. */
export default async function AuditAssetsPage() {
  const [me, assets] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ rows: Asset[] }>("/api/v1/stores/assets")]);
  return (
    <Shell route="t/auditassets" me={me.ok ? me.data : null}>
      {assets.ok ? <AuditAssets rows={assets.data.rows} /> : <ProblemNotice problem={assets.problem} />}
    </Shell>
  );
}
