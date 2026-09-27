/** The offer / confirmation letter as a PDF (V275): the released offer, the programme, the terms, on one A4 page, with the document's
 *  number, code and QR. Drawn the same from the applicant's dashboard and from the student's library (V282). */
import type { ScreeningResult } from "@/lib/applicant";
import { A4, Page, pdf } from "@/lib/pdf-write";
import { brandHeader } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";

export interface LetterApplication {
  applicationNo: string; session: string; name: string; jambKey: string; entryLevel: number; programme: string | null; faculty: string | null;
  decision: string | null; decisionReleasedAt: string | null; decisionBasis: string | null; acceptedAt: string | null; result?: ScreeningResult | null;
}
export interface LetterDoc { number: string; version: number; verification_code: string; statement: string; issued_on: string; verifyPath: string; application?: LetterApplication }

function qr(p: Page, x: number, y: number, side: number, text: string) {
  const { size, dark } = qrMatrix(text);
  const cell = side / size;
  for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) if (dark[r * size + c]) p.fill(x + c * cell, y + (size - 1 - r) * cell, cell, cell, 0);
}

const when = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "");

export function admissionLetterPdf(a: LetterApplication, letter: LetterDoc, origin: string): Uint8Array {
  const st = JSON.parse(letter.statement) as { changedFrom?: string | null; changedTo?: string | null; changedOn?: string | null };
  const verifyUrl = `${origin}${letter.verifyPath}`;
  const p = new Page();
  const L = 64;
  let y = brandHeader(p, L, "Office of the Registrar · Academic Affairs");
  p.text(L, y, `Our ref: ${a.applicationNo} · Document no ${letter.number}${letter.version > 1 ? ` (version ${letter.version})` : ""}`, 9.5);
  p.text(A4.w - L - 150, y, when(a.decisionReleasedAt), 9.5);
  y -= 26;
  p.text(L, y, a.name, 11, true);
  y -= 14;
  p.text(L, y, `JAMB registration number ${a.jambKey}`, 9.5);
  y -= 30;
  p.text(L, y, "OFFER OF PROVISIONAL ADMISSION", 13, true);
  y -= 22;
  y = p.paragraph(L, y, `I am pleased to inform you that the Admissions Board of the University has offered you provisional admission into the ${a.entryLevel} Level of the ${a.programme ?? "programme"} degree programme${a.faculty ? ` in the Faculty of ${a.faculty}` : ""} for the ${a.session} academic session${a.decisionBasis ? `, on the basis of ${basisName(a.decisionBasis)}` : ""}.`, A4.w - 2 * L, 10.5, 1.45);
  y -= 8;
  y = p.paragraph(L, y, "This offer is provisional. It stands on the results JAMB sent and the documents you declared, every one of which the Registry verifies with the examination bodies before clearance. A result that does not verify voids the admission at any point afterwards, including after the award of a degree.", A4.w - 2 * L, 10.5, 1.45);
  y -= 8;
  y = p.paragraph(L, y, `You accepted this offer on ${when(a.acceptedAt)} and the acceptance fee is confirmed. Nothing is paid to any person; every naira you owe is paid on the portal, to a reference the portal generates.`, A4.w - 2 * L, 10.5, 1.45);
  if (st.changedTo) {
    y -= 8;
    y = p.paragraph(L, y, `Your change of programme from ${st.changedFrom ?? "the programme first offered"} to ${st.changedTo} was approved by the Admissions Office${st.changedOn ? ` on ${when(st.changedOn)}` : ""}; this letter, version ${letter.version} under the same document number, states the admission as it now stands. Your acceptance fee remains valid.`, A4.w - 2 * L, 10.5, 1.45);
  }
  y -= 8;
  y = p.paragraph(L, y, "After acceptance, complete the online screening on the portal, then pay your school fees and register your courses. Your matriculation number is issued once your fees are paid and your courses registered; it is not issued with this letter.", A4.w - 2 * L, 10.5, 1.45);
  y -= 30;
  if (a.result) {
    p.fill(L, y - 58, A4.w - 2 * L, 66);
    p.text(L + 10, y - 4, "As screened", 9, true);
    p.text(L + 10, y - 22, `UTME ${a.result.utme ?? "—"} of 400 · screening ${a.result.screening ?? "—"} of 100 · aggregate ${a.result.aggregate ?? "—"} · weighted ${a.result.weightUtme}/${a.result.weightPutme}`, 9);
    p.text(L + 10, y - 40, `Departmental cut-off ${a.result.cutoff ?? "not stated"}${a.result.meritPosition ? ` · merit position ${a.result.meritPosition}${a.result.applied ? ` of ${a.result.applied}` : ""}` : ""}`, 9);
    y -= 90;
  }
  p.text(L, y, "Registrar", 10.5, true);
  y -= 14;
  p.text(L, y, "For: Vice-Chancellor", 9.5);
  // the verification block: the QR opens the public verifier; the code and the number are typed where it cannot be scanned
  qr(p, A4.w - L - 84, 62, 84, verifyUrl);
  p.text(L, 92, `Document no ${letter.number} · version ${letter.version} · issued ${when(letter.issued_on)}`, 8.5, true);
  p.text(L, 80, `Verification code ${letter.verification_code}`, 8.5);
  p.text(L, 68, `Verify at ${origin}/verify/document by the code or the document number. Only what the University discloses publicly is shown.`, 7.5, false, [0.4, 0.4, 0.4]);
  p.text(L, 50, `Issued by the portal · ${a.applicationNo} · this letter is verified against the register, not by its appearance`, 7.5, false, [0.4, 0.4, 0.4]);

  return pdf([p], `Admission letter ${a.applicationNo}`);
}

function basisName(code: string): string {
  return ({ NM: "National Merit", SM: "State Merit", ELG: "Equality of Local Government", LOCALITY: "Locality", PLWD: "Persons Living With Disability", OTHER: "the Board's decision" } as Record<string, string>)[code] ?? code;
}
