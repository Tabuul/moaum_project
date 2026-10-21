import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import { Shell, type Me } from "@/components/proto/Shell";
import { IdCardReport } from "./IdCardReport";

export const dynamic = "force-dynamic";

/** V605: Security Unit → ID card report — the cards printed and issued, filtered, as Excel and PDF on the University's standards */
export default async function IdCardReportPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions } = await loadScope(params);
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/idcardreport" me={me.ok ? me.data : null}>
      <IdCardReport scope={scope} structure={structure} sessions={sessions} />
    </Shell>
  );
}
