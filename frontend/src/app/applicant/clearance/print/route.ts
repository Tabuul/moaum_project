import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { Admission, ScreeningView } from "@/lib/screening";
import { jpegSize } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";
import { imageFromDataUrl, screeningFormsPdf } from "@/lib/screening-forms-pdf";

export const dynamic = "force-dynamic";

/** the five screening forms, filled from the applicant's own answers, as one printable PDF */
export async function GET() {
  const v = await api<ScreeningView>("/api/v1/applicant/me/screening");
  if (!v.ok) return NextResponse.json(v.problem, { status: v.problem.status });
  if (!v.data.form) {
    return NextResponse.json({ status: 409, title: "No screening form yet", detail: "The forms print once your screening form is open and filled on the portal." }, { status: 409 });
  }
  // the "Date Paid" the paper forms carry is the acceptance fee's confirmation
  const adm = await api<Admission>("/api/v1/applicant/me/admission");
  const paidOn = adm.ok ? adm.data.entitlement?.confirmed_at ?? null : null;
  const answers: Record<string, string> = {};
  for (const x of v.data.answers) answers[x.field] = x.value ?? "";
  const bytes = screeningFormsPdf({
    prefill: v.data.prefill,
    answers,
    institutions: v.data.institutions,
    olevel: v.data.olevel,
    form: v.data.form,
    acceptancePaidOn: paidOn,
    passport: imageFromDataUrl(v.data.prefill.jamb_passport, jpegSize),
    crest: crestImage(),
  });
  const file = `screening-forms-${v.data.form.screening_no.replace(/[^A-Za-z0-9]+/g, "-")}.pdf`;
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="${file}"` } });
}
