import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { HostelImport } from "./Import";

export const dynamic = "force-dynamic";

/** t/hostel-import — the University's hostel workbook read, previewed and imported without duplicates (V290) */
export default async function HostelImportPage() {
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/hostel-import" me={me.ok ? me.data : null}>
      <HostelImport office={me.ok ? me.data.activeOffice ?? null : null} />
    </Shell>
  );
}
