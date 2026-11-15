import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { admissionLetterPdf, type LetterDoc } from "@/lib/admission-letter-pdf";
import { crestImage } from "@/lib/pdf-crest";
import { signatureImageOf } from "@/lib/letter-signature";
import { qrMatrix } from "@/lib/qr";
import { publicOrigin } from "@/lib/public-origin";

export const dynamic = "force-dynamic";

/** the offer / confirmation letter from the student's library (V282): the same document the applicant's dashboard opens, on its trail */
export async function GET(req: Request) {
  const url = new URL(req.url);
  const print = url.searchParams.get("print") === "1", download = url.searchParams.get("download") === "1";
  const doc = await api<LetterDoc>(`/api/v1/me/admission-documents/letter${print ? "?event=PRINTED" : ""}`);
  if (!doc.ok) return NextResponse.json(doc.problem, { status: doc.problem.status });
  const letter = doc.data;
  if (!letter.application) return NextResponse.json({ status: 500, title: "The letter's application could not be read" }, { status: 500 });
  // V759: the signature uploaded for the signatory the letter's template names comes with the letter; none, and the space is left.
  // The QR and the "verify at" line name the portal's public address, never the server's own (lib/public-origin)
  const origin = publicOrigin(req);
  const bytes = admissionLetterPdf(letter.application, letter, origin, { crest: crestImage(), signature: signatureImageOf(letter.signature), qr: qrMatrix(`${origin}${letter.verifyPath}`) });
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `${download ? "attachment" : "inline"}; filename="admission-letter-${letter.application.applicationNo.replace(/\//g, "-")}.pdf"` } });
}
