import "server-only";
import { createHash } from "crypto";
import QRCode from "qrcode";

/**
 * Receipt verification. A receipt is not trusted by its appearance — it is
 * verified against the Bursary's ledger. Every receipt carries a QR that opens
 * a public page showing the authoritative record, plus a short check token so a
 * scanned reference cannot simply be enumerated. The token is a stateless
 * digest of the reference and the receipt number (both printed on the receipt),
 * so no secret has to be kept in step across services; the API recomputes it.
 */
export function receiptToken(reference: string, receiptNo: string | null): string {
  return createHash("sha256").update(`${reference}|${receiptNo ?? ""}`).digest("hex").slice(0, 12).toUpperCase();
}

/** the path (no origin) the QR opens: the public verification page for this receipt */
export function verifyPath(reference: string, receiptNo: string | null): string {
  return `/verify/receipt/${encodeURIComponent(reference)}?c=${receiptToken(reference, receiptNo)}`;
}

/** the QR as a monochrome module grid, for drawing into a PDF as filled squares */
export function qrMatrix(text: string): { size: number; dark: boolean[] } {
  const qr = QRCode.create(text, { errorCorrectionLevel: "M" });
  const size = qr.modules.size;
  const src = qr.modules.data;
  const dark: boolean[] = new Array(size * size);
  for (let i = 0; i < size * size; i++) dark[i] = !!src[i];
  return { size, dark };
}

/** the QR as a PNG data URL, for an <img> on the on-screen receipt */
export function qrDataUrl(text: string): Promise<string> {
  return QRCode.toDataURL(text, { errorCorrectionLevel: "M", margin: 1, width: 220 });
}
