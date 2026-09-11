import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Migration } from "./Migration";

export const dynamic = "force-dynamic";

/** t/migration — the Examinations Officer's desk for bringing students, registrations and past results
 *  over from the old portal. */
export default async function MigrationPage() {
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/legacy" me={me.ok ? me.data : null}>
      <Migration actingOffice={me.ok ? me.data.activeOffice : null} />
    </Shell>
  );
}
