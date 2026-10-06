import { api } from "@/lib/api";
import type { Directory } from "@/lib/catalogue";
import { Shell, type Me } from "@/components/proto/Shell";
import { CatalogueManage, type ImportRow, type ResetRow } from "./CatalogueManage";

export const dynamic = "force-dynamic";

/** t/coursecatalogue — the course catalogue's reset and its upload with owners and offerings (V338). */
export default async function CatalogueManagePage() {
  const [me, dir, resets, imports] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Directory>("/api/v1/catalogue/directory"),
    api<ResetRow[]>("/api/v1/catalogue/reset/history"),
    api<ImportRow[]>("/api/v1/catalogue/catalogue-import/history"),
  ]);
  return (
    <Shell route="t/coursecatalogue" me={me.ok ? me.data : null}>
      <CatalogueManage directory={dir.ok ? dir.data : null} resets={resets.ok ? resets.data : []} imports={imports.ok ? imports.data : []}
        actingOffice={me.ok ? me.data.activeOffice : null} />
    </Shell>
  );
}
