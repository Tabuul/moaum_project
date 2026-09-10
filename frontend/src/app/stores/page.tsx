import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Stores, type StoreItem, type Asset } from "./Stores";

export const dynamic = "force-dynamic";

/** t/stores — stores (inventory) and the fixed-asset register. */
export default async function StoresPage() {
  const [me, items, assets] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ rows: StoreItem[] }>("/api/v1/stores/items"),
    api<{ rows: Asset[] }>("/api/v1/stores/assets"),
  ]);
  return (
    <Shell route="t/stores" me={me.ok ? me.data : null}>
      {items.ok ? (
        <Stores items={items.data.rows} assets={assets.ok ? assets.data.rows : []} actingOffice={me.ok ? me.data.activeOffice : null} />
      ) : <ProblemNotice problem={items.problem} />}
    </Shell>
  );
}
