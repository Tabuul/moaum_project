import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { admissionLetterPdf, type LetterDoc } from "@/lib/admission-letter-pdf";
import { crestImage, signatureImage } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";

export const dynamic = "force-dynamic";

/** the offer / confirmation letter from the student's library (V282): the same document the applicant's dashboard opens, on its trail */
export async function GET(req: Request) {
  const url = new URL(req.url);
  const print = url.searchParams.get("print") === "1", download = url.searchParams.get("download") === "1";
  const doc = await api<LetterDoc>(`/api/v1/me/admission-documents/letter${print ? "?event=PRINTED" : ""}`);
  if (!doc.ok) return NextResponse.json(doc.problem, { status: doc.problem.status });
  const letter = doc.data;
  if (!letter.application) return NextResponse.json({ status: 500, title: "The letter's application could not be read" }, { status: 500 });
  const bytes = admissionLetterPdf(letter.application, letter, url.origin, { crest: crestImage(), signature: signatureImage("registrar"), qr: qrMatrix(`${url.origin}${letter.verifyPath}`) });
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `${download ? "attachment" : "inline"}; filename="admission-letter-${letter.application.applicationNo.replace(/\//g, "-")}.pdf"` } });
}
