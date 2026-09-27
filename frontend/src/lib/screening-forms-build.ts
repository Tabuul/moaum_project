/** The five screening forms of a successful screening (V280), drawn from the issued document's record: numbered and verifiable, the
 *  fields the University does not hold left blank to be filled by hand. Built the same from the applicant's dashboard and from the
 *  student's library (V282). */
import type { Facts, ScreeningView } from "@/lib/screening";
import { jpegSize } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";
import { imageFromDataUrl, screeningFormsPdf } from "@/lib/screening-forms-pdf";

export interface IssuedForms { number: string; version: number; verification_code: string; statement: string; issued_on: string; verifyPath: string }

export function buildScreeningForms(view: ScreeningView, doc: IssuedForms, origin: string): { bytes: Uint8Array; file: string } {
  if (!view.form) throw new Error("no screening record");
  const st = JSON.parse(doc.statement) as { facts: Facts; decidedOn?: string | null; decidedOffice?: string | null; remarks?: string | null };
  const facts = st.facts;
  const answers: Record<string, string> = {};
  for (const [k, x] of Object.entries(facts.biodata ?? {})) if (x != null && String(x).trim()) answers[k] = String(x);
  for (const [k, x] of Object.entries(facts.answers ?? {})) if (x != null && String(x).trim()) answers[k] = String(x);
  // what the University holds fills the paper's own fields; anything not held prints blank
  if (!answers.state_of_origin && facts.identity.state_of_origin) answers.state_of_origin = String(facts.identity.state_of_origin);
  if (!answers.lga && facts.identity.lga) answers.lga = String(facts.identity.lga);
  if (!answers.date_of_birth && facts.identity.date_of_birth) answers.date_of_birth = String(facts.identity.date_of_birth);
  if (!answers.nationality && facts.identity.nationality) answers.nationality = String(facts.identity.nationality);   // JAMB's state implies it (V282)
  if (!answers.mobile && facts.identity.phone) answers.mobile = String(facts.identity.phone);
  if (!answers.personal_email && facts.identity.email) answers.personal_email = String(facts.identity.email);
  if (!answers.kin_name && facts.identity.next_of_kin) answers.kin_name = String(facts.identity.next_of_kin);
  const verifyUrl = `${origin}${doc.verifyPath}`;
  const p = view.prefill;
  const form = view.form;
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
    document: { number: doc.number, version: doc.version, code: doc.verification_code, issuedOn: doc.issued_on, verifyUrl, verifyPage: `${origin}/verify/document`, qr: qrMatrix(verifyUrl) },
  });
  const file = `screening-forms-${doc.number.replace(/[^A-Za-z0-9]+/g, "-")}-v${doc.version}.pdf`;
  return { bytes, file };
}

function numOrNull(x: unknown): number | null {
  if (x == null || x === "") return null;
  const n = Number(x);
  return isNaN(n) ? null : n;
}
