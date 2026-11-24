import { NextRequest, NextResponse } from "next/server";
import { api } from "@/lib/api";
import { publicOrigin } from "@/lib/public-origin";
import { qrMatrix, regVerifyPath, studentCheckCodeResult } from "@/lib/qr";
import { loadInstitution } from "@/lib/document/institution-server";
import type { SummerConfirmation } from "@/lib/summer";
import { summerConfirmationPdf } from "@/lib/summer-confirmation";

export const dynamic = "force-dynamic";

/** The Summer Semester registration confirmation as a PDF (V779): the student's selections with the Academic Office's verification of
 *  each, the itemised fees, the payments with their receipt numbers and the notice, on the University's document writer. Titled a
 *  registration confirmation once the registration stands, a selection summary before (payment outstanding; or, once a course is paid
 *  that the registration has not yet taken, registration pending). The QR opens the public
 *  check of the student's semester-3 registration, whose code the API signed, and is printed only when the registration stands: the
 *  check answers genuine only for an approved registration. A student with no selection in the session has nothing to print (404). */
export async function GET(request: NextRequest) {
  const inst = await loadInstitution();
  const asked = request.nextUrl.searchParams.get("session") ?? "";
  const session = /^\d{4}\/\d{4}$/.test(asked) ? asked : null;
  const r = await api<SummerConfirmation>(`/api/v1/me/summer/confirmation${session ? `?session=${encodeURIComponent(session)}` : ""}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const c = r.data;
  let qr: { matrix: { size: number; dark: boolean[] }; caption: string } | null = null;
  if (c.status === "REGISTERED") {
    const check = await studentCheckCodeResult("REG", c.session, 3);
    if (!check.ok) return NextResponse.json(check.problem, { status: check.problem.status });
    qr = { matrix: qrMatrix(publicOrigin(request) + regVerifyPath(check.number, c.session, 3, check.code)), caption: `Summer Semester registration ${check.number} - check code ${check.code}` };
  }
  const bytes = summerConfirmationPdf(c, inst, qr).finish();
  const kind = c.status === "REGISTERED" ? "confirmation" : "selection-summary";
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "cache-control": "no-store", "content-disposition": `inline; filename="summer-semester-${kind}-${c.session.replace("/", "-")}.pdf"` },
  });
}
