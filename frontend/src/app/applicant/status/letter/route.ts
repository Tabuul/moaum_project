import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { Application } from "@/lib/applicant";
import { admissionLetterPdf, type LetterDoc } from "@/lib/admission-letter-pdf";
import { crestImage, signatureImage } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";

export const dynamic = "force-dynamic";

/** the letter of provisional admission as a PDF: the released offer, the programme, the terms, on one A4 page (V275, V282) */
export async function GET(req: Request) {
  const me = await api<Application>("/api/v1/applicant/me");
  if (!me.ok) return NextResponse.json(me.problem, { status: me.problem.status });
  const a = me.data;
  if (!a.decisionReleasedAt || a.decision !== "OFFERED") {
    return NextResponse.json({ status: 409, title: "No offer to print", detail: "The letter is issued when the Admissions Board's offer is released." }, { status: 409 });
  }
  if (!a.acceptedAt) {
    return NextResponse.json({ status: 409, title: "Accept your offer first", detail: "The admission letter is issued once you have accepted the offer and the acceptance fee is confirmed. Sign the undertaking and pay the acceptance fee, then print the letter." }, { status: 409 });
  }
  const url = new URL(req.url);
  const print = url.searchParams.get("print") === "1", download = url.searchParams.get("download") === "1";
  // the letter as a digital document (V275): its number, its code, the QR that opens the public verifier; each opening on its trail
  const doc = await api<LetterDoc>(`/api/v1/applicant/me/letter${print ? "?event=PRINTED" : ""}`);
  if (!doc.ok) return NextResponse.json(doc.problem, { status: doc.problem.status });
  const letter = doc.data;
  const app = letter.application ?? { applicationNo: a.applicationNo, session: a.session, name: a.name, jambKey: a.jambKey, entryLevel: a.entryLevel, programme: a.programme, faculty: a.faculty, decision: a.decision, decisionReleasedAt: a.decisionReleasedAt, decisionBasis: a.decisionBasis, acceptedAt: a.acceptedAt };
  const bytes = admissionLetterPdf({ ...app, result: a.result }, letter, url.origin, { crest: crestImage(), signature: signatureImage("registrar"), qr: qrMatrix(`${url.origin}${letter.verifyPath}`) });
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `${download ? "attachment" : "inline"}; filename="admission-letter-${a.applicationNo.replace(/\//g, "-")}.pdf"` } });
}
