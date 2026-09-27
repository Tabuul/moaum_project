import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { ScreeningView } from "@/lib/screening";
import { buildScreeningForms, type IssuedForms } from "@/lib/screening-forms-build";

export const dynamic = "force-dynamic";

/** the screening forms from the student's library (V282): the same document the applicant's dashboard opens, on its trail */
export async function GET(req: Request) {
  const url = new URL(req.url);
  const print = url.searchParams.get("print") === "1", download = url.searchParams.get("download") === "1";
  const [v, doc] = await Promise.all([api<ScreeningView>("/api/v1/me/admission-documents/screening"), api<IssuedForms>(`/api/v1/me/admission-documents/forms${print ? "?event=PRINTED" : ""}`)]);
  if (!v.ok) return NextResponse.json(v.problem, { status: v.problem.status });
  if (!doc.ok) return NextResponse.json(doc.problem, { status: doc.problem.status });
  if (!v.data.form) return NextResponse.json({ status: 409, title: "No screening on your record", detail: "The forms exist only for an admission the University screened successfully." }, { status: 409 });
  const { bytes, file } = buildScreeningForms(v.data, doc.data, url.origin);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `${download ? "attachment" : "inline"}; filename="${file}"` } });
}
