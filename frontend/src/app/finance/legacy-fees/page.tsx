import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { LegacyFees } from "./LegacyFees";

export const dynamic = "force-dynamic";

/** t/legacyfees — import old students' school-fees history from the old portal (V087). */
export default async function LegacyFeesPage() {
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/legacyfees" me={me.ok ? me.data : null}>
      <LegacyFees actingOffice={me.ok ? me.data.activeOffice : null} />
    </Shell>
  );
}
