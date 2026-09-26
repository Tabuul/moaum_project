/** The official Deferment Approval Letter (V259), drawn with the portal's PDF writer: the crest, the reference, the
 *  student and their programme, the period deferred, the expected return, the approving officer, and a QR that
 *  names the reference. One function, used by the student's copy and the desk's. */
import { A4, Page, pdf } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";
import type { DefermentFull } from "@/lib/deferments";
import { SEM, stepsOf } from "@/lib/deferments";

const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" }) : "");

export function defermentLetter(d: DefermentFull, verifyUrl: string): Uint8Array {
  const p = new Page();
  const L = 64;
  const cx = A4.w / 2;
  const crest = crestImage();
  let y = A4.h - 46;
  if (crest) p.jpeg(cx - 24, y - 46, 48, 48, crest);
  p.textCenter(cx, y - 60, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", 13, true);
  p.textCenter(cx, y - 74, "P.M.B 102119, Makurdi, Nigeria", 9.5, false, [0.35, 0.35, 0.35]);
  p.textCenter(cx, y - 87, "(Office of the Registrar)", 9.5, false, [0.35, 0.35, 0.35]);
  y -= 108;
  p.text(A4.w - L - 170, y, "DATE: " + day(d.decided_at ?? new Date().toISOString()), 10, true);
  p.text(L, y, "REF: " + clean(d.reference), 10, true);
  y -= 30;
  p.textCenter(cx, y, "DEFERMENT APPROVAL LETTER", 12.5, true); y -= 16;
  p.textCenter(cx, y, d.kind === "SESSION" ? `${clean(d.session)} ACADEMIC SESSION` : `${clean(d.session)} ACADEMIC SESSION - ${SEM(d.semester).toUpperCase()}`, 10.5, true); y -= 26;

  const line = (k: string, v: string) => { p.text(L, y, k, 10.5, true); p.text(L + 150, y, clean(v), 10.5, false); y -= 17; };
  line("STUDENT:", `${d.surname}, ${d.other_names}`);
  line("STUDENT ID:", d.number);
  line("PROGRAMME:", d.programme);
  line("DEPARTMENT:", d.department);
  line("FACULTY:", d.faculty);
  line("LEVEL:", `${d.level} Level`);
  y -= 8;
  y = p.paragraph(L, y, `The University has considered your request to defer ${d.kind === "SESSION" ? `the ${d.session} academic session` : `the ${SEM(d.semester).toLowerCase()} of the ${d.session} academic session`} on ${d.reason.toLowerCase()} grounds, verified by the Bursary, approved by your department, your faculty and the Deputy Vice-Chancellor (Academic), and approved by the Senate Business Committee as follows:`, A4.w - 2 * L, 10, 1.45) - 8;
  line("DEFERMENT TYPE:", d.kind === "SESSION" ? "Academic session" : "Semester");
  line("PERIOD DEFERRED:", d.kind === "SESSION" ? `${d.session} academic session` : `${d.session}, ${SEM(d.semester)}`);
  line("EFFECTIVE FROM:", day(d.period_from) || d.session);
  line("EXPECTED RETURN:", `${d.return_session ?? ""}, ${SEM(d.return_semester)}${d.return_on ? ` (${day(d.return_on)})` : ""}`);
  line("APPROVED ON:", day(d.decided_at));
  line("APPROVED BY:", "Senate Business Committee" + (d.decided_officer ? ` (recorded by ${d.decided_officer})` : ""));
  if (d.decision_note) line("REMARKS:", d.decision_note);
  y -= 8;
  const notes = [
    "During the deferred period you are not academically active and may not register courses, sit examinations or be assessed for that period.",
    "Your registrations, payments, results and academic history for other periods remain on your record unchanged.",
    "Present yourself at your department at the start of your return period; the department confirms your return and your record is reactivated for registration and fees as usual.",
    "The University may verify this letter by its reference on the portal.",
  ];
  notes.forEach((n, i) => { y = p.paragraph(L, y, `${i + 1}. ${n}`, A4.w - 2 * L, 9.5, 1.4) - 4; });
  y -= 24;
  p.text(L, y, "______________________________", 10); y -= 14;
  p.text(L, y, "Registrar", 10, true); y -= 13;
  p.text(L, y, "For: Rev. Fr. Moses Orshio Adasu University, Makurdi", 9.5, false, [0.35, 0.35, 0.35]);

  const qr = qrMatrix(verifyUrl);
  const cell = 2.2, size = qr.size * cell, qx = A4.w - L - size, qy = 60;
  for (let r = 0; r < qr.size; r++) for (let c = 0; c < qr.size; c++) if (qr.dark[r * qr.size + c]) p.fill(qx + c * cell, qy + (qr.size - 1 - r) * cell, cell, cell, 0);
  p.text(L, 46, `Verify: ${clean(verifyUrl)}`, 8, false, [0.4, 0.4, 0.4]);
  p.text(L, 36, `Deferment ${clean(d.reference)} · generated ${day(new Date().toISOString())}`, 8, false, [0.4, 0.4, 0.4]);
  return pdf([p], `Deferment ${d.reference}`);
}

/** The deferment application, whole, for the desk's copy (V264): the student, the request, the fee, the financial
 *  verification, each desk's word and the approval timeline. Drawn only for a desk the API allows to download it. */
export function defermentApplication(d: DefermentFull): Uint8Array {
  const pages: Page[] = [];
  let p = new Page();
  const L = 56;
  const cx = A4.w / 2;
  const crest = crestImage();
  let y = A4.h - 46;
  const newPage = () => { pages.push(p); p = new Page(); y = A4.h - 60; };
  const need = (h: number) => { if (y - h < 60) newPage(); };
  if (crest) p.jpeg(cx - 24, y - 46, 48, 48, crest);
  p.textCenter(cx, y - 60, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", 13, true);
  p.textCenter(cx, y - 74, "Office of the Registrar · Student Deferment Application", 9.5, false, [0.35, 0.35, 0.35]);
  y -= 100;
  p.text(L, y, "APPLICATION NO: " + clean(d.reference), 10.5, true);
  p.text(A4.w - L - 220, y, "STATUS: " + clean(d.stage_label), 10.5, true);
  y -= 24;
  const head = (t: string) => { need(40); y -= 6; p.text(L, y, t.toUpperCase(), 10, true, [0.06, 0.25, 0.33]); y -= 6; p.fill(L, y, A4.w - 2 * L, 0.8, 0.75); y -= 14; };
  const line = (k: string, v: string | null | undefined) => { need(18); p.text(L, y, k, 9.5, true); p.text(L + 170, y, clean(v ?? "—") || "—", 9.5, false); y -= 15; };
  head("Student information");
  line("Name", `${d.surname}, ${d.other_names}`); line("Student ID", d.number); line("Faculty", d.faculty); line("Department", d.department); line("Programme", d.programme); line("Level", `${d.level} Level`);
  line("Entry session", d.entry_session); line("Status", d.student_status);
  head("Deferment information");
  line("Deferment type", d.kind === "SESSION" ? "Academic session" : "Semester"); line("Academic session", d.session); line("Semester", d.kind === "SESSION" ? "Whole session" : SEM(d.semester));
  line("Reason", d.reason); line("Requested period from", day(d.period_from)); line("Expected return", `${d.return_session ?? ""} ${SEM(d.return_semester)}${d.return_on ? ` (${day(d.return_on)})` : ""}`);
  if (d.explanation) { need(60); y = p.paragraph(L, y, "Additional explanation: " + clean(d.explanation), A4.w - 2 * L, 9.5, 1.4) - 6; }
  line("Declaration", d.declared ? "Confirmed by the student" : "Not confirmed"); line("Supporting documents", `${d.documents.length} on file${d.documents.length ? ": " + d.documents.map((x) => x.filename).join(", ") : ""}`);
  head("Financial information");
  line("Deferment application fee", d.fee_amount != null ? `NGN ${Number(d.fee_amount).toLocaleString("en-NG")} · ${d.fee_state ?? ""}` : "—");
  line("Fee reference / receipt", `${d.fee_reference ?? "—"}${d.fee_receipt_no ? ` · ${d.fee_receipt_no}` : ""}`);
  const f = d.financials;
  line("Last school-fee payment", d.bursary_last_fee_amount != null ? `NGN ${Number(d.bursary_last_fee_amount).toLocaleString("en-NG")} on ${day(d.bursary_last_fee_at)} (${d.bursary_last_fee_session ?? ""})` : f?.found ? `NGN ${Number(f.last_fee_amount).toLocaleString("en-NG")} on ${day(f.last_fee_at)} (${f.last_fee_session ?? ""})` : "No qualifying school-fee payment found");
  line("Payment reference", d.bursary_last_fee_ref ?? f?.last_fee_ref ?? "—");
  line("Outstanding balance", d.bursary_balance != null ? `NGN ${Number(d.bursary_balance).toLocaleString("en-NG")} (${d.bursary_balance_session ?? ""})` : f?.balance != null ? `NGN ${Number(f.balance).toLocaleString("en-NG")} (${f.balance_session ?? ""})` : "—");
  head("Approval history");
  const steps = stepsOf(d);
  for (const s of steps) {
    need(30);
    p.text(L, y, (s.failed ? "x " : s.done ? "v " : s.current ? "> " : "- ") + s.label, 9.5, s.done || s.current);
    p.text(L + 300, y, s.when ? day(s.when) : s.current ? "Current stage" : "", 9.5, false, [0.35, 0.35, 0.35]);
    y -= 13;
    if (s.who) { p.text(L + 14, y, clean(s.who), 8.5, false, [0.35, 0.35, 0.35]); y -= 12; }
    if (s.note) { y = p.paragraph(L + 14, y, clean(s.note), A4.w - 2 * L - 14, 8.5, 1.35) - 2; }
  }
  if (d.effect && d.effect.applied) {
    head("Academic effect of the deferment");
    line("Duration deferred", `${d.effect.duration_semesters} semester(s)`); line("Courses affected", String(d.effect.courses_affected)); line("CGPA effect", "No negative effect");
    line("Programme duration", `${d.effect.original_semesters} -> ${d.effect.adjusted_semesters} semesters (+${d.effect.extension_semesters})`);
    line("Expected completion", `${d.effect.original_completion} -> ${d.effect.adjusted_completion}`);
  }
  p.text(L, 36, `Deferment ${clean(d.reference)} · printed ${day(new Date().toISOString())} · for official use`, 8, false, [0.4, 0.4, 0.4]);
  pages.push(p);
  return pdf(pages, `Deferment application ${d.reference}`);
}
