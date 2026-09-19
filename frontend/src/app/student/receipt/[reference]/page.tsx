import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { headers } from "next/headers";
import { loadStudent } from "../../load";

export const dynamic = "force-dynamic";
import type { Receipt } from "@/lib/student-portal";
import { qrDataUrl, receiptToken, verifyPath } from "@/lib/qr";
import { ReceiptScreen } from "../../Screens2";

/** s/receipt — the receipt issued on confirmation, with a QR to the public verification page */
export default async function Page({ params }: { params: Promise<{ reference: string }> }) {
  const { reference } = await params;
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/receipt" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const r = await api<Receipt>(`/api/v1/me/fees/receipts/${encodeURIComponent(reference)}`);
  let qr: string | null = null, verifyUrl: string | null = null, token: string | null = null;
  if (r.ok && r.data.confirmed_at) {
    const h = await headers();
    const host = h.get("x-forwarded-host") ?? h.get("host");
    const proto = h.get("x-forwarded-proto") ?? "https";
    const origin = host ? `${proto}://${host}` : "";
    verifyUrl = origin + verifyPath(r.data.reference, r.data.receipt_no);
    token = receiptToken(r.data.reference, r.data.receipt_no);
    qr = await qrDataUrl(verifyUrl);
  }
  return (
    <Shell route="s/receipt" me={loaded.me}>
      {r.ok ? <ReceiptScreen r={r.data} qr={qr} verifyUrl={verifyUrl} token={token} photoSrc={loaded.student.hasPhoto ? `/api/bff/api/v1/me/passport?v=${encodeURIComponent(loaded.student.matricNo ?? loaded.student.admissionNo ?? loaded.student.id)}` : null} /> : <ProblemNotice problem={r.problem} />}
    </Shell>
  );
}
