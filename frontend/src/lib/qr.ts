import "server-only";
import QRCode from "qrcode";
import { api } from "./api";

/**
 * Verification by QR. A printed document is not trusted by its appearance — it is checked against the University's
 * record: every receipt, examination card, course form and results statement carries a QR that opens a public page
 * showing the record, with a short check code so the page cannot simply be run through a list of numbers.
 *
 * V360: the check code is signed by the API with a key the portal never holds (it was a plain digest of what the
 * document already shows, which anyone could compute). The receipt's comes with the receipt (`checkCode`); a student's
 * examination card, course form and results statement get theirs from `/api/v1/me/check-code`.
 */

/** the path (no origin) the QR opens: the public verification page for this receipt */
export function verifyPath(reference: string, code: string): string {
  return `/verify/receipt/${encodeURIComponent(reference)}?c=${encodeURIComponent(code)}`;
}

/** the public paths the examination card's, the course form's and the results statement's QRs open */
export function examVerifyPath(number: string, session: string, semester: number, code: string): string {
  return `/verify/exam?m=${encodeURIComponent(number)}&s=${encodeURIComponent(session)}&sem=${semester}&c=${encodeURIComponent(code)}`;
}
export function regVerifyPath(number: string, session: string, semester: number, code: string): string {
  return `/verify/registration?m=${encodeURIComponent(number)}&s=${encodeURIComponent(session)}&sem=${semester}&c=${encodeURIComponent(code)}`;
}
export function resultVerifyPath(number: string, session: string, semester: number, code: string): string {
  return `/verify/results?m=${encodeURIComponent(number)}&s=${encodeURIComponent(session)}&sem=${semester}&c=${encodeURIComponent(code)}`;
}

/** V360: the signed check code for the signed-in student's own document, and the number it is made over */
export async function studentCheckCode(kind: "EXAM" | "REG" | "RESULT", session: string, semester: number): Promise<{ number: string; code: string } | null> {
  const r = await api<{ number: string; code: string }>(`/api/v1/me/check-code?kind=${kind}&session=${encodeURIComponent(session)}&semester=${semester}`);
  return r.ok ? { number: r.data.number, code: r.data.code } : null;
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
