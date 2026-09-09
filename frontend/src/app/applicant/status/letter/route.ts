import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { Application } from "@/lib/applicant";
import { A4, Page, pdf } from "@/lib/pdf-write";
import { brandHeader } from "@/lib/pdf-crest";

export const dynamic = "force-dynamic";

const when = (iso: string) => new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });

/** the letter of provisional admission as a PDF: the released offer, the programme, the terms, on one A4 page */
export async function GET() {
  const me = await api<Application>("/api/v1/applicant/me");
  if (!me.ok) return NextResponse.json(me.problem, { status: me.problem.status });
  const a = me.data;
  if (!a.decisionReleasedAt || a.decision !== "OFFERED") {
    return NextResponse.json({ status: 409, title: "No offer to print", detail: "The letter is issued when the Admissions Board's offer is released." }, { status: 409 });
  }
  if (!a.acceptedAt) {
    return NextResponse.json({ status: 409, title: "Accept your offer first", detail: "The admission letter is issued once you have accepted the offer and the acceptance fee is confirmed. Sign the undertaking and pay the acceptance fee, then print the letter." }, { status: 409 });
  }
  const p = new Page();
  const L = 64;
  let y = brandHeader(p, L, "Office of the Registrar · Academic Affairs");
  p.text(L, y, `Our ref: ${a.applicationNo}`, 9.5);
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
  y = p.paragraph(L, y, `You accepted this offer on ${when(a.acceptedAt)} and the acceptance fee is confirmed${a.admissionNo ? `; your admission number is ${a.admissionNo}` : ""}. Nothing is paid to any person; every naira you owe is paid on the portal, to a reference the portal generates.`, A4.w - 2 * L, 10.5, 1.45);
  y -= 8;
  y = p.paragraph(L, y, "After acceptance, present your original documents at the Registry for clearance. You then pay your fees and register your courses under your admission number; your matriculation number is issued afterwards, over the confirmed register.", A4.w - 2 * L, 10.5, 1.45);
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
  p.text(L, 50, `Issued by the portal on ${when(new Date().toISOString())} · ${a.applicationNo} · this letter is verified against the register, not by its appearance`, 7.5, false, [0.4, 0.4, 0.4]);

  const bytes = pdf([p], `Admission letter ${a.applicationNo}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="admission-letter-${a.applicationNo.replace(/\//g, "-")}.pdf"` } });
}

function basisName(code: string): string {
  return ({ NM: "National Merit", SM: "State Merit", ELG: "Equality of Local Government", LOCALITY: "Locality", PLWD: "Persons Living With Disability", OTHER: "the Board's decision" } as Record<string, string>)[code] ?? code;
}
