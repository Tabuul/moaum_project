import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { Receipt } from "@/lib/student-portal";
import { A4, Page, pdf } from "@/lib/pdf-write";

export const dynamic = "force-dynamic";

const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const naira = (n: number | string) => `NGN ${Number(n).toLocaleString("en-NG", { minimumFractionDigits: 2 })}`;

/** the official payment receipt as a PDF: the same facts as the screen, on one A4 page */
export async function GET(_: Request, { params }: { params: Promise<{ reference: string }> }) {
  const { reference } = await params;
  const r = await api<Receipt>(`/api/v1/me/fees/receipts/${encodeURIComponent(reference)}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const x = r.data;
  if (!x.confirmed_at) return NextResponse.json({ status: 409, title: "Not confirmed", detail: "A receipt is issued when the payment is confirmed." }, { status: 409 });
  const p = new Page();
  const L = 64;
  let y = A4.h - 70;
  p.text(L, y, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", 12, true);
  y -= 15;
  p.text(L, y, "Official Payment Receipt · Bursary Department", 9.5, false, [0.35, 0.35, 0.35]);
  y -= 10;
  p.rule(L, y, A4.w - L, y, 1, 0.2);
  y -= 26;
  p.text(L, y, "RECEIPT NUMBER", 7.5, false, [0.4, 0.4, 0.4]);
  p.text(L + 130, y, x.receipt_no ?? "", 12, true);
  p.text(A4.w - L - 170, y, "DATE", 7.5, false, [0.4, 0.4, 0.4]);
  p.text(A4.w - L - 130, y, day(x.confirmed_at), 10.5);
  y -= 28;
  for (const [k, v] of [["Received from", x.name], ["Matriculation number", x.matricNo ?? ""], ["Programme", `${x.programme} · ${x.level} Level`], ["Session", x.session]]) {
    p.text(L, y, k.toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 130, y, v, 10.5);
    y -= 18;
  }
  y -= 8;
  p.fill(L, y - 4, A4.w - 2 * L, 18, 0.2);
  p.text(L + 8, y, "BEING PAYMENT FOR", 8, true, [1, 1, 1]);
  p.text(A4.w - L - 100, y, "AMOUNT", 8, true, [1, 1, 1]);
  y -= 24;
  p.text(L + 8, y, x.purpose, 10.5);
  p.text(L + 8, y - 12, `Against reference ${x.reference}`, 8, false, [0.4, 0.4, 0.4]);
  p.text(A4.w - L - 140, y, naira(x.amount), 10.5, true);
  y -= 34;
  p.rule(L, y + 6, A4.w - L, y + 6);
  p.text(L + 8, y - 8, "TOTAL RECEIVED", 10.5, true);
  p.text(A4.w - L - 140, y - 8, naira(x.amount), 13, true);
  y -= 40;
  for (const [k, v] of [["Channel", x.channel ?? "—"], ["Gateway or teller reference", x.note ?? "—"]]) {
    p.text(L, y, k.toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 170, y, v, 10);
    y -= 18;
  }
  y -= 16;
  y = p.paragraph(L, y, "This receipt is valid without a signature. It is verified against the Bursary's ledger by its receipt number, not by its appearance. Nothing is released against a payment the bank has not confirmed.", A4.w - 2 * L, 9);
  p.text(L, 50, `Issued by the portal on ${day(new Date().toISOString())} · ${x.receipt_no}`, 7.5, false, [0.4, 0.4, 0.4]);
  const bytes = pdf([p], `Receipt ${x.receipt_no}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="receipt-${(x.receipt_no ?? "").replace(/\//g, "-")}.pdf"` } });
}
