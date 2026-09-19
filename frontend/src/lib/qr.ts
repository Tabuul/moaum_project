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

/** the examination card's check token and the public path its QR opens */
export function examToken(matricNo: string, session: string, semester: number): string {
  return createHash("sha256").update(`EXAM|${matricNo}|${session}|${semester}`).digest("hex").slice(0, 12).toUpperCase();
}
export function examVerifyPath(matricNo: string, session: string, semester: number): string {
  const c = examToken(matricNo, session, semester);
  return `/verify/exam?m=${encodeURIComponent(matricNo)}&s=${encodeURIComponent(session)}&sem=${semester}&c=${c}`;
}

/** the course registration form's check token and the public path its QR opens */
export function regToken(matricNo: string, session: string, semester: number): string {
  return createHash("sha256").update(`REG|${matricNo}|${session}|${semester}`).digest("hex").slice(0, 12).toUpperCase();
}
export function regVerifyPath(matricNo: string, session: string, semester: number): string {
  const c = regToken(matricNo, session, semester);
  return `/verify/registration?m=${encodeURIComponent(matricNo)}&s=${encodeURIComponent(session)}&sem=${semester}&c=${c}`;
}

/** the semester results statement's check token and the public path its QR opens */
export function resultToken(matricNo: string, session: string, semester: number): string {
  return createHash("sha256").update(`RESULT|${matricNo}|${session}|${semester}`).digest("hex").slice(0, 12).toUpperCase();
}
export function resultVerifyPath(matricNo: string, session: string, semester: number): string {
  const c = resultToken(matricNo, session, semester);
  return `/verify/results?m=${encodeURIComponent(matricNo)}&s=${encodeURIComponent(session)}&sem=${semester}&c=${c}`;
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
