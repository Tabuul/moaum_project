import { NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { type Receipt, receiptPurpose } from "@/lib/student-portal";
import { A4, Page, pdf, jpegSize } from "@/lib/pdf-write";
import { brandHeader } from "@/lib/pdf-crest";
import { qrMatrix, receiptToken, verifyPath } from "@/lib/qr";

export const dynamic = "force-dynamic";

/** the public origin, honouring the proxy so the QR opens a real address */
function originOf(req: Request): string {
  const h = req.headers;
  const host = h.get("x-forwarded-host") ?? h.get("host");
  const proto = h.get("x-forwarded-proto") ?? "https";
  try { return host ? `${proto}://${host}` : new URL(req.url).origin; } catch { return new URL(req.url).origin; }
}

const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const naira = (n: number | string) => `NGN ${Number(n).toLocaleString("en-NG", { minimumFractionDigits: 2 })}`;

/** the official payment receipt as a PDF: the same facts as the screen, on one A4 page */
export async function GET(req: Request, { params }: { params: Promise<{ reference: string }> }) {
  const { reference } = await params;
  const r = await api<Receipt>(`/api/v1/me/fees/receipts/${encodeURIComponent(reference)}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const x = r.data;
  if (!x.confirmed_at) return NextResponse.json({ status: 409, title: "Not confirmed", detail: "A receipt is issued when the payment is confirmed." }, { status: 409 });
  // the student's passport, embedded as JPEG (blank box when none) — from /me/passport, which resolves
  // the document store OR the JAMB/attachment store, so a migrated / JAMB-loaded photo also prints
  let photo: { width: number; height: number; data: Uint8Array } | null = null;
  try {
    const tok = await sessionToken();
    const res = await fetch(`${API_URL}/api/v1/me/passport`, { headers: tok ? { Authorization: `Bearer ${tok}` } : {}, cache: "no-store" });
    if (res.ok) {
      const buf = new Uint8Array(await res.arrayBuffer());
      const dim = jpegSize(buf);
      if (dim) photo = { width: dim.width, height: dim.height, data: buf };
    }
  } catch { /* leave the box blank */ }

  const p = new Page();
  const L = 64;
  let y = brandHeader(p, L, "Official Payment Receipt · Bursary Department");
  // passport at the top-right, aligned with the header
  const pw = 58, ph = 71, px = A4.w - L - pw, ptop = y + 4;
  if (photo) p.jpeg(px, ptop - ph, pw, ph, photo);
  else { p.rule(px, ptop, px + pw, ptop, 0.6, 0.7); p.rule(px, ptop - ph, px + pw, ptop - ph, 0.6, 0.7); p.rule(px, ptop, px, ptop - ph, 0.6, 0.7); p.rule(px + pw, ptop, px + pw, ptop - ph, 0.6, 0.7); p.text(px + 10, ptop - ph / 2, "PHOTO", 7.5, false, [0.6, 0.6, 0.6]); }
  // receipt numbers can be long (legacy ones especially), so keep them small and on their own line
  for (const [k, v, sz] of [["Receipt number", x.receipt_no ?? "", 9], ["Date", day(x.confirmed_at), 10.5]] as [string, string, number][]) {
    p.text(L, y, k.toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 130, y, v, sz, true);
    y -= 17;
  }
  y -= 6;
  const semLabel = x.term;
  const bio: [string, string][] = [["Received from", x.name], ["Matriculation number", x.matricNo ?? ""], ["Programme", `${x.programme} · ${x.level} Level`], ["Session", x.session]];
  if (semLabel) bio.push(["Semester", semLabel]);
  for (const [k, v] of bio) {
    p.text(L, y, k.toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 130, y, v, 10.5);
    y -= 18;
  }
  y -= 8;
  p.fill(L, y - 4, A4.w - 2 * L, 18, 0.2);
  p.text(L + 8, y, "BEING PAYMENT FOR", 8, true, [1, 1, 1]);
  p.text(A4.w - L - 100, y, "AMOUNT", 8, true, [1, 1, 1]);
  y -= 24;
  p.text(L + 8, y, receiptPurpose(x.purpose), 10.5);
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

  // ── verify: a QR to the public verification page, drawn as module squares ──
  const url = originOf(req) + verifyPath(x.reference, x.receipt_no);
  const token = receiptToken(x.reference, x.receipt_no);
  const { size, dark } = qrMatrix(url);
  const cell = 2.7;
  const qDim = size * cell;
  const qx = A4.w - L - qDim;
  const qy = y;                         // top edge of the QR
  // a quiet white margin (quiet zone) behind the code keeps it scannable over any shading
  p.fill(qx - 11, qy - qDim - 11, qDim + 22, qDim + 22, 1);
  for (let rr = 0; rr < size; rr++) {
    for (let cc = 0; cc < size; cc++) {
      if (dark[rr * size + cc]) p.fill(qx + cc * cell, qy - (rr + 1) * cell, cell, cell, 0);
    }
  }
  p.text(L, qy, "SCAN TO VERIFY", 8, true, [0.4, 0.4, 0.4]);
  const textW = qx - L - 16;
  let ty = p.paragraph(L, qy - 14, "Scan the QR code to verify this payment, or use the check code to confirm the authenticity of this receipt against the Bursary's ledger.", textW, 9);
  ty -= 6;
  // just the host, small — the QR carries the full address, so the long path is not printed
  p.text(L, ty, `Verify at ${url.replace(/^https?:\/\//, "").split("/")[0]}`, 7, false, [0.4, 0.4, 0.4]); ty -= 12;
  p.text(L, ty, `Check code  ${token}`, 8.5, true);
  y = Math.min(ty, qy - qDim) - 22;

  // ── a faint microtext band: legible here, it breaks up on a photocopy ──
  const strip = ` REV. FR. MOSES ORSHIO ADASU UNIVERSITY · OFFICIAL RECEIPT ${x.receipt_no ?? ""} · VERIFY ONLINE ·`;
  const band = strip.repeat(6);
  for (const my of [y + 6, 64]) p.text(L, my, band, 3.2, false, [0.82, 0.82, 0.82]);

  p.text(L, 50, `Issued by the portal on ${day(new Date().toISOString())} · ${x.receipt_no}`, 7.5, false, [0.4, 0.4, 0.4]);
  const bytes = pdf([p], `Receipt ${x.receipt_no}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="receipt-${(x.receipt_no ?? "").replace(/\//g, "-")}.pdf"` } });
}
