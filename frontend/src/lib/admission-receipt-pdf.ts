/** The receipt of an applicant's fee — the Post-UTME (or CCE) application fee, the admission checking fee or the acceptance
 *  fee, and a postgraduate applicant's — as a PDF (V282): the same facts as the screen, on one A4 page, under the University's crest, titled for what was paid, with a QR
 *  to the public verification page and the check code the API signed over the reference. */
import { A4, Page, pdf } from "@/lib/pdf-write";
import { currentInstitution } from "./document/institution-cache.ts";
import { brandHeader } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";
import { applicantFeeName, applicantReceiptTitle, applicantReceiptVerifyPath } from "@/lib/applicant-receipt";

export interface AdmissionReceipt {
  reference: string; kind: string; amount: number; confirmed_at: string; receipt_no: string | null; channel: string | null; generated_at: string;
  /** a postgraduate applicant has no JAMB number: the row is left out */
  application_no: string; session: string; surname: string; other_names: string; jamb_reg_no: string | null; programme: string;
  /** V412: the admission route (entry mode); a CCE applicant's receipt names the CCE fee */
  route?: string | null;
  /** the code the API signed over the reference, which the QR's verification address carries */
  check_code?: string | null;
}

const when = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const naira = (n: number | string) => `NGN ${Number(n).toLocaleString("en-NG", { minimumFractionDigits: 2 })}`;

/** origin: the portal's public address, so the QR opens a real page */
export function admissionReceiptPdf(r: AdmissionReceipt, origin: string): Uint8Array {
  const p = new Page();
  const L = 64;
  const title = applicantReceiptTitle(r.kind, r.route);
  let y = brandHeader(p, L, "Bursary · Official receipt");
  p.textCenter(A4.w / 2, y, title.toUpperCase(), 15, true);
  y -= 16;
  p.textCenter(A4.w / 2, y, `Receipt no ${r.receipt_no ?? r.reference}`, 9.5, false, [0.35, 0.35, 0.35]);
  y -= 30;
  const rows: [string, string][] = [
    ["Received from", `${r.surname.toUpperCase()}, ${r.other_names}`],
    ...(r.jamb_reg_no ? [["JAMB registration number", r.jamb_reg_no] as [string, string]] : []),
    ["Application number", r.application_no],
    ["Programme applied for", r.programme ?? "—"],
    ["Session", r.session],
    ["Being payment for", applicantFeeName(r.kind, r.route)],
    ["Payment reference", r.reference],
    ["Channel", r.channel ?? "—"],
    ["Confirmed on", when(r.confirmed_at)],
  ];
  for (const [k, v] of rows) {
    p.text(L, y, k, 9.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 190, y, v, 10.5);
    y -= 18;
  }
  y -= 6;
  p.fill(L, y - 30, A4.w - 2 * L, 40);
  p.text(L + 10, y - 6, "Amount received", 9.5, true);
  p.text(L + 190, y - 8, naira(r.amount), 15, true);
  y -= 64;

  // ── verify: a QR to the public verification page, drawn as module squares, beside the check code ──
  const code = r.check_code ?? "";
  if (code) {
    const { size, dark } = qrMatrix(origin + applicantReceiptVerifyPath(r.reference, code));
    const cell = 2.7, dim = size * cell, qx = A4.w - L - dim, qy = y;
    p.fill(qx - 11, qy - dim - 11, dim + 22, dim + 22, 1);   // a quiet white margin keeps it scannable
    for (let rr = 0; rr < size; rr++) {
      for (let cc = 0; cc < size; cc++) if (dark[rr * size + cc]) p.fill(qx + cc * cell, qy - (rr + 1) * cell, cell, cell, 0);
    }
    p.text(L, qy, "SCAN TO VERIFY", 8, true, [0.4, 0.4, 0.4]);
    let ty = p.paragraph(L, qy - 14, `Scan the QR code, or enter the payment reference and the check code at ${origin.replace(/^https?:\/\//, "")}/verify. The payer, the fee and the amount shown there are the Bursary's record, and prevail over this paper.`, qx - L - 24, 9);
    ty -= 6;
    p.text(L, ty, `Check code  ${code}`, 9, true);
    y = Math.min(ty, qy - dim) - 30;
  } else {
    p.text(L, y, "Issued against a payment the University confirmed; verified against the Bursary's record.", 8.5, false, [0.4, 0.4, 0.4]);
    y -= 30;
  }
  p.text(L, y, "Bursar", 10.5, true);
  p.text(L, 50, `Reference ${r.reference} · generated ${when(r.generated_at)} · ${currentInstitution().name}`, 7.5, false, [0.4, 0.4, 0.4]);
  return pdf([p], `${title} ${r.reference}`);
}
