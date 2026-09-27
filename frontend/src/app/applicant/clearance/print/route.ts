import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { Facts, ScreeningView } from "@/lib/screening";
import { jpegSize } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";
import { imageFromDataUrl, screeningFormsPdf } from "@/lib/screening-forms-pdf";

export const dynamic = "force-dynamic";

interface Issued { number: string; version: number; verification_code: string; statement: string; issued_on: string; verifyPath: string }

/** the five screening forms of a successful screening (V280): drawn from the issued document's record, numbered and verifiable,
 *  the fields the University does not hold left blank to be filled by hand */
export async function GET(req: Request) {
  const [v, doc] = await Promise.all([api<ScreeningView>("/api/v1/applicant/me/screening"), api<Issued>("/api/v1/applicant/me/screening/forms")]);
  if (!v.ok) return NextResponse.json(v.problem, { status: v.problem.status });
  if (!doc.ok) return NextResponse.json(doc.problem, { status: doc.problem.status });
  if (!v.data.form) {
    return NextResponse.json({ status: 409, title: "No screening yet", detail: "The forms are generated once the University's screening is successful." }, { status: 409 });
  }
  const st = JSON.parse(doc.data.statement) as { facts: Facts; decidedOn?: string | null; decidedOffice?: string | null; remarks?: string | null };
  const facts = st.facts;
  const answers: Record<string, string> = {};
  for (const [k, x] of Object.entries(facts.biodata ?? {})) if (x != null && String(x).trim()) answers[k] = String(x);
  for (const [k, x] of Object.entries(facts.answers ?? {})) if (x != null && String(x).trim()) answers[k] = String(x);
  // what the University holds fills the paper's own fields; anything not held prints blank
  if (!answers.state_of_origin && facts.identity.state_of_origin) answers.state_of_origin = String(facts.identity.state_of_origin);
  if (!answers.lga && facts.identity.lga) answers.lga = String(facts.identity.lga);
  if (!answers.date_of_birth && facts.identity.date_of_birth) answers.date_of_birth = String(facts.identity.date_of_birth);
  if (!answers.mobile && facts.identity.phone) answers.mobile = String(facts.identity.phone);
  if (!answers.personal_email && facts.identity.email) answers.personal_email = String(facts.identity.email);
  if (!answers.kin_name && facts.identity.next_of_kin) answers.kin_name = String(facts.identity.next_of_kin);
  const origin = new URL(req.url).origin;
  const verifyUrl = `${origin}${doc.data.verifyPath}`;
  const p = v.data.prefill;
  const form = v.data.form;
  const bytes = screeningFormsPdf({
    prefill: {
      surname: p.surname, other_names: p.other_names, jamb_reg_no: p.jamb_reg_no, programme: String(facts.admission.programme ?? p.programme), entry_mode: p.entry_mode, session: p.session, application_no: p.application_no,
      sex: (facts.identity.sex as string | null) ?? p.sex, state_of_origin: p.state_of_origin, lga: p.lga, faculty: (facts.admission.faculty as string | null) ?? p.faculty, department: (facts.admission.department as string | null) ?? p.department,
      date_of_birth: (facts.identity.date_of_birth as string | null) ?? p.date_of_birth, email: p.email, phone: p.phone, next_of_kin: p.next_of_kin,
    },
    answers,
    institutions: (facts.institutions ?? []).map((i) => ({ name: String(i.name ?? ""), from_year: numOrNull(i.from_year), to_year: numOrNull(i.to_year), certificate: i.certificate == null ? null : String(i.certificate), award_year: numOrNull(i.award_year) })),
    olevel: (facts.olevel ?? []).map((r) => ({ exam_body: String(r.exam_body ?? ""), exam_number: r.exam_number == null ? null : String(r.exam_number), exam_year: numOrNull(r.exam_year), subject: String(r.subject ?? ""), grade: String(r.grade ?? "") })),
    form: { screening_no: form.screening_no, state: form.state, submitted_at: form.submitted_at, declaration_at: form.declaration_at, membership: form.membership, decided_at: form.decided_at, decided_office: form.decided_office, decision_reason: form.decision_reason },
    acceptancePaidOn: (facts.admission.acceptance_confirmed_at as string | null) ?? null,
    passport: imageFromDataUrl(p.jamb_passport, jpegSize),
    crest: crestImage(),
    document: { number: doc.data.number, version: doc.data.version, code: doc.data.verification_code, issuedOn: doc.data.issued_on, verifyUrl, verifyPage: `${origin}/verify/document`, qr: qrMatrix(verifyUrl) },
  });
  const download = new URL(req.url).searchParams.get("download") === "1";
  const file = `screening-forms-${doc.data.number.replace(/[^A-Za-z0-9]+/g, "-")}-v${doc.data.version}.pdf`;
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `${download ? "attachment" : "inline"}; filename="${file}"` } });
}

function numOrNull(x: unknown): number | null {
  if (x == null || x === "") return null;
  const n = Number(x);
  return isNaN(n) ? null : n;
}
