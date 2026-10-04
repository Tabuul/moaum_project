/** The receipt of an admission fee — the admission checking fee or the acceptance fee — as a PDF (V282): the same facts as the
 *  screen, on one A4 page, under the University's crest. */
import { A4, Page, pdf } from "@/lib/pdf-write";
import { currentInstitution } from "./document/institution-cache.ts";
import { brandHeader } from "@/lib/pdf-crest";

export interface AdmissionReceipt {
  reference: string; kind: string; amount: number; confirmed_at: string; receipt_no: string | null; channel: string | null; generated_at: string;
  application_no: string; session: string; surname: string; other_names: string; jamb_reg_no: string; programme: string;
}

const when = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const naira = (n: number | string) => `NGN ${Number(n).toLocaleString("en-NG", { minimumFractionDigits: 2 })}`;
const PURPOSE: Record<string, string> = { CHECKING: "Admission checking fee", ACCEPTANCE: "Acceptance fee", APPLICATION: "Application fee" };

export function admissionReceiptPdf(r: AdmissionReceipt): Uint8Array {
  const p = new Page();
  const L = 64;
  let y = brandHeader(p, L, "Bursary · Official receipt");
  p.text(L, y, "OFFICIAL RECEIPT", 14, true);
  p.text(A4.w - L - 170, y, `Receipt no ${r.receipt_no ?? r.reference}`, 9.5);
  y -= 28;
  const rows: [string, string][] = [
    ["Received from", `${r.surname.toUpperCase()}, ${r.other_names}`],
    ["JAMB registration number", r.jamb_reg_no],
    ["Application number", r.application_no],
    ["Programme", r.programme],
    ["Session", r.session],
    ["Purpose", PURPOSE[r.kind] ?? r.kind],
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
  y -= 60;
  p.text(L, y, "This receipt is issued by the portal against a payment the University confirmed. It is verified against the Bursary's record, not by its appearance.", 8.5, false, [0.4, 0.4, 0.4]);
  y -= 30;
  p.text(L, y, "Bursar", 10.5, true);
  p.text(L, 50, `Reference ${r.reference} · generated ${when(r.generated_at)} · ${currentInstitution().name}`, 7.5, false, [0.4, 0.4, 0.4]);
  return pdf([p], `Receipt ${r.reference}`);
}
