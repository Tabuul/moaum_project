import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { admissionReceiptPdf } from "@/lib/admission-receipt-pdf";
import { publicOrigin } from "@/lib/public-origin";
import { loadInstitution } from "@/lib/document/institution-server";
import type { IutMe } from "@/lib/transfer-application";

export const dynamic = "force-dynamic";

/** what GET /api/v1/transfer-applications/me/receipts/{reference} answers: a confirmed reference of the applicant's own */
interface IutReceipt {
  receiptNo?: string | null; reference: string; amount: number; paidAt?: string | null; channel?: string | null; purpose?: string | null;
  applicationNo: string; name?: string | null; session: string; checkCode?: string | null;
}

/** V766: the receipt of the inter-university transfer application fee as a PDF, from the transfer applicant's portal: the applicants'
 *  receipt (lib/admission-receipt-pdf), titled for this fee, with the QR to its verification page and the code the API signed */
export async function GET(req: Request, { params }: { params: Promise<{ reference: string }> }) {
  await loadInstitution();
  const { reference } = await params;
  const download = new URL(req.url).searchParams.get("download") === "1";
  const [r, me] = await Promise.all([
    api<IutReceipt>(`/api/v1/transfer-applications/me/receipts/${encodeURIComponent(reference)}`),
    api<IutMe>("/api/v1/transfer-applications/me"),
  ]);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const x = r.data;
  const name = x.name ?? (me.ok ? `${me.data.applicant?.surname ?? ""}, ${me.data.applicant?.otherNames ?? ""}` : "");
  const cut = name.indexOf(",");
  const bytes = admissionReceiptPdf({
    reference: x.reference, kind: "IUT_APPLICATION", amount: x.amount, confirmed_at: x.paidAt ?? "", receipt_no: x.receiptNo ?? null, channel: x.channel ?? null,
    generated_at: new Date().toISOString(), application_no: x.applicationNo, session: x.session,
    surname: cut >= 0 ? name.slice(0, cut).trim() : name.trim(), other_names: cut >= 0 ? name.slice(cut + 1).trim() : "",
    jamb_reg_no: me.ok ? me.data.applicant?.jambRegNo ?? null : null,
    programme: me.ok ? me.data.applied?.programmeName ?? me.data.applied?.programme ?? "" : "", check_code: x.checkCode ?? null,
  }, publicOrigin(req));
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: {
    "content-type": "application/pdf", "cache-control": "no-store",
    "content-disposition": `${download ? "attachment" : "inline"}; filename="receipt-${x.reference.replace(/[^A-Za-z0-9]+/g, "-")}.pdf"`,
  } });
}
