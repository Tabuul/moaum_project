import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../../load";

export const dynamic = "force-dynamic";
import type { Receipt } from "@/lib/student-portal";
import { ReceiptScreen } from "../../Screens2";

/** s/receipt — the receipt issued on confirmation */
export default async function Page({ params }: { params: Promise<{ reference: string }> }) {
  const { reference } = await params;
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/receipt" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const r = await api<Receipt>(`/api/v1/me/fees/receipts/${encodeURIComponent(reference)}`);
  return (
    <Shell route="s/receipt" me={loaded.me}>
      {r.ok ? <ReceiptScreen r={r.data} /> : <ProblemNotice problem={r.problem} />}
    </Shell>
  );
}
