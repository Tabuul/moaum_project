import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { publicOrigin } from "@/lib/public-origin";
import type { ScreeningView } from "@/lib/screening";
import { buildScreeningForms, type IssuedForms } from "@/lib/screening-forms-build";

export const dynamic = "force-dynamic";

/** the five screening forms of a successful screening (V280), from the applicant's dashboard; each opening is on the document's trail */
export async function GET(req: Request) {
  const url = new URL(req.url);
  const print = url.searchParams.get("print") === "1", download = url.searchParams.get("download") === "1";
  const [v, doc] = await Promise.all([api<ScreeningView>("/api/v1/applicant/me/screening"), api<IssuedForms>(`/api/v1/applicant/me/screening/forms${print ? "?event=PRINTED" : ""}`)]);
  if (!v.ok) return NextResponse.json(v.problem, { status: v.problem.status });
  if (!doc.ok) return NextResponse.json(doc.problem, { status: doc.problem.status });
  if (!v.data.form) {
    return NextResponse.json({ status: 409, title: "No screening yet", detail: "The forms are generated once the University's screening is successful." }, { status: 409 });
  }
  const { bytes, file } = buildScreeningForms(v.data, doc.data, publicOrigin(req));
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `${download ? "attachment" : "inline"}; filename="${file}"` } });
}
