import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { jpegSize } from "@/lib/pdf-write";
import { pgApplicationPdf, type Deg, type PgMe, type PgPhoto, type Ref } from "@/lib/pg-application-pdf";
import { loadInstitution } from "@/lib/document/institution-server";

export const dynamic = "force-dynamic";

/** what the desk reads of one application (GET /api/v1/pg/applications/{id}) that the form prints */
interface Detail {
  found: boolean;
  application?: {
    application_no: string; session: string; surname: string; other_names: string; email: string; phone: string | null; entry_level: number;
    programme_name: string; pg_award: string | null; faculty_name: string | null; department_name: string | null;
    applied_at: string | null; submitted_at: string | null; fee_confirmed_at: string | null;
    sex: string | null; date_of_birth: string | null; state_of_origin: string | null; lga: string | null; nationality?: string | null; contact_address?: string | null;
    prior_institution: string | null; prior_award: string | null; prior_class: string | null; prior_cgpa: number | null; prior_year: number | null;
    proposal_title: string | null; proposal_text: string | null;
  };
  referees?: Ref[]; priorDegrees?: Deg[]; documents?: { kind: string; filename: string }[];
}

/** V694: an applicant's application form, for the School to download or print — the same document the applicant prints as their
 *  summary, read through the desk (READERS, a department or faculty office held to its own applications by the API) */
export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  await loadInstitution();
  const r = await api<Detail>(`/api/v1/pg/applications/${encodeURIComponent(id)}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const a = r.data.application;
  if (!r.data.found || !a) return NextResponse.json({ status: 404, title: "No such postgraduate application" }, { status: 404 });

  const s: PgMe = {
    applicationNo: a.application_no, session: a.session, name: `${a.surname}, ${a.other_names}`, surname: a.surname, otherNames: a.other_names,
    email: a.email, phone: a.phone, entryLevel: a.entry_level, programme: a.programme_name, award: a.pg_award,
    faculty: a.faculty_name ?? "", department: a.department_name ?? "", submittedAt: a.applied_at ?? a.submitted_at, feeConfirmedAt: a.fee_confirmed_at,
    biodata: { sex: a.sex, dateOfBirth: a.date_of_birth, stateOfOrigin: a.state_of_origin, lga: a.lga, nationality: a.nationality ?? null, contactAddress: a.contact_address ?? null },
    prior: { institution: a.prior_institution, award: a.prior_award, classOfDegree: a.prior_class, cgpa: a.prior_cgpa, year: a.prior_year },
    proposal: { title: a.proposal_title, text: a.proposal_text },
    referees: r.data.referees ?? [], priorDegrees: r.data.priorDegrees ?? [], documents: r.data.documents ?? [],
  };

  // the passport photograph, as a JPEG the PDF can embed; the form prints without it when there is none
  let photo: PgPhoto | null = null;
  try {
    const tok = await sessionToken();
    const office = (await cookies()).get("moaum_office")?.value ?? process.env.PORTAL_ACTIVE_OFFICE;
    const headers: Record<string, string> = tok ? { Authorization: `Bearer ${tok}` } : {};
    if (office) headers["X-Active-Office"] = office;
    const res = await fetch(`${API_URL}/api/v1/pg/applications/${encodeURIComponent(id)}/passport.jpg`, { headers, cache: "no-store" });
    if (res.ok && (res.headers.get("content-type") ?? "").includes("jpeg")) {
      const buf = new Uint8Array(await res.arrayBuffer());
      const dim = jpegSize(buf);
      if (dim) photo = { width: dim.width, height: dim.height, data: buf };
    }
  } catch { /* no passport — the form prints without it */ }

  const bytes = pgApplicationPdf(s, photo, "APPLICATION FORM");
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: {
      "content-type": "application/pdf",
      "content-disposition": `inline; filename="pg-application-form-${a.application_no.replace(/\//g, "-")}.pdf"`,
    },
  });
}
