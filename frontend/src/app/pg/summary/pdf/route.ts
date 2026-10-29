import { NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { jpegSize } from "@/lib/pdf-write";
import { pgApplicationPdf, type PgMe, type PgPhoto } from "@/lib/pg-application-pdf";
import { loadInstitution } from "@/lib/document/institution-server";

export const dynamic = "force-dynamic";

/** the applicant's application summary as a PDF — printable and downloadable once they are signed in */
export async function GET() {
  await loadInstitution();
  const me = await api<PgMe>("/api/v1/pg/me");
  if (!me.ok) return NextResponse.json(me.problem, { status: me.problem.status });
  const s = me.data;

  // the applicant's passport, so it shows on the printed summary (JPEG can be embedded directly)
  let photo: PgPhoto | null = null;
  try {
    const tok = await sessionToken();
    const res = await fetch(`${API_URL}/api/v1/pg/passport/image?format=jpeg`, { headers: tok ? { Authorization: `Bearer ${tok}` } : {}, cache: "no-store" });
    if (res.ok && (res.headers.get("content-type") ?? "").includes("jpeg")) {
      const buf = new Uint8Array(await res.arrayBuffer());
      const dim = jpegSize(buf);
      if (dim) photo = { width: dim.width, height: dim.height, data: buf };
    }
  } catch { /* no passport, or not a JPEG — the summary prints without it */ }

  const bytes = pgApplicationPdf(s, photo, "APPLICATION SUMMARY");
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: {
      "content-type": "application/pdf",
      "content-disposition": `inline; filename="pg-application-${s.applicationNo.replace(/\//g, "-")}.pdf"`,
    },
  });
}
